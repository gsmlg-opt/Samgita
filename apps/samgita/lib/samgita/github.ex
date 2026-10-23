defmodule Samgita.GitHub do
  @moduledoc "Verified GitHub facts and explicit Project associations; never Task acceptance or GitHub writes."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Error, Events, Params, Principal, Projection, Repo}
  alias Samgita.GitHub.{Client, Failure, Payload, Secrets, Signature}
  alias Samgita.Workers.GitHubReconcileWorker

  alias Samgita.Domain.{
    DomainEvent,
    GitHubConnection,
    GitHubDelivery,
    GitHubObject,
    GitHubObservation,
    GitHubProjectMapping,
    GitHubRepository,
    GitHubSync,
    Project,
    ProjectRepository,
    Repository
  }

  @read_roles ~w(observer worker manager reviewer)
  @feeds ~w(issues pulls workflow_runs check_runs)

  defp configure_command!(principal, attrs) do
    Commands.operator!(principal)
    previous = if attrs["id"], do: connection!(attrs["id"])
    if previous, do: Commands.expect!(previous, attrs)
    connection = previous || %GitHubConnection{}

    if previous && identity_changed?(previous, attrs),
      do: Commands.fail!(:invalid, %{reason: "identity_is_immutable"})

    changeset =
      connection
      |> cast(attrs, [
        :host,
        :app_id,
        :installation_id,
        :private_key_ref,
        :webhook_secret_ref,
        :enabled
      ])
      |> validate_required([
        :host,
        :app_id,
        :installation_id,
        :private_key_ref,
        :webhook_secret_ref
      ])
      |> validate_format(:host, ~r/\A[a-z0-9.-]+\z/)
      |> validate_format(:app_id, ~r/\A[1-9][0-9]{0,19}\z/)
      |> validate_format(:installation_id, ~r/\A[1-9][0-9]{0,19}\z/)
      |> validate_format(:private_key_ref, ~r/\A[A-Za-z0-9_.:\/-]{1,200}\z/)
      |> validate_format(:webhook_secret_ref, ~r/\A[A-Za-z0-9_.:\/-]{1,200}\z/)
      |> put_change(:state, "configured")
      |> put_change(:version, if(previous, do: previous.version + 1, else: 1))
      |> put_change(:rate_limited_until, nil)

    record = if previous, do: Commands.update!(changeset), else: Commands.insert!(changeset)
    connection_projection(record)
  end

  defp identity_changed?(previous, attrs) do
    Enum.any?(~w(host app_id installation_id), fn field ->
      Map.has_key?(attrs, field) &&
        attrs[field] != Map.get(previous, String.to_existing_atom(field))
    end)
  end

  defp associate_command!(ctx, current, project_id, attrs, opts, verified) do
    Commands.expect!(ctx.project, attrs)
    if ctx.project.state not in ~w(active paused), do: Commands.fail!(:invalid_transition)
    if verified.external_id != attrs["external_id"], do: Commands.fail!(:invalid)
    repository = repository!(current, verified, attrs)

    github = verified_binding!(current, repository, verified)

    association =
      Repo.get_by(ProjectRepository, project_id: project_id, repository_id: repository.id)

    association =
      association ||
        Commands.insert!(
          change(%ProjectRepository{}, project_id: project_id, repository_id: repository.id)
        )

    mapping =
      Repo.get_by(GitHubProjectMapping,
        github_repository_id: github.id,
        project_id: project_id
      )

    ensure_mapping_limit!(mapping, github)

    mapping =
      save!(mapping, %GitHubProjectMapping{},
        github_repository_id: github.id,
        project_id: project_id,
        project_repository_id: association.id,
        enabled: true,
        version: if(mapping, do: mapping.version + 1, else: 1)
      )

    project = ctx.project |> change(version: ctx.project.version + 1) |> Commands.update!()

    Events.append!(
      project_id,
      "github.repository_verified",
      ctx,
      "repository",
      repository.id,
      %{
        "connection_id" => current.id,
        "github_repository_id" => github.id,
        "external_id" => github.external_id
      },
      previous: ctx.project,
      current: project
    )

    for kind <- @feeds, do: request_sync!(github, kind, "", opts)
    mapping_projection(mapping, github) |> Map.put("project_version", project.version)
  end

  defp verified_binding!(current, repository, verified) do
    github =
      Repo.get_by(GitHubRepository,
        connection_id: current.id,
        external_id: verified.external_id
      )

    if github && github.repository_id != repository.id, do: Commands.fail!(:conflict)

    values = [
      connection_id: current.id,
      repository_id: repository.id,
      external_id: verified.external_id,
      full_name: verified.full_name,
      default_branch: verified.default_branch,
      permissions: verified.permissions,
      state: "verified",
      verified_at: DateTime.utc_now(),
      connection_version: current.version,
      version: if(github, do: github.version + 1, else: 1)
    ]

    save!(github, %GitHubRepository{}, values)
  end

  defp ensure_mapping_limit!(mapping, github) do
    if !mapping &&
         Repo.aggregate(
           from(m in GitHubProjectMapping, where: m.github_repository_id == ^github.id),
           :count
         ) >= 100,
       do: Commands.fail!(:conflict, %{reason: "mapping_limit"})
  end

  defp disable_mapping!(principal, project_id, id, attrs, ctx) do
    Commands.operator!(principal)
    mapping = mapping!(project_id, id)
    Commands.expect!(mapping, attrs)

    if attrs["enabled"] != false,
      do: Commands.fail!(:invalid, %{reason: "use_verified_association_to_enable"})

    mapping =
      mapping |> change(enabled: false, version: mapping.version + 1) |> Commands.update!()

    Events.append!(
      project_id,
      "github.mapping_disabled",
      Map.put(ctx, :notify, false),
      "github_mapping",
      id
    )

    mapping_projection(mapping, Repo.get!(GitHubRepository, mapping.github_repository_id))
  end

  defp reconcile_mapping!(principal, project_id, mapping_id, attrs) do
    Commands.operator!(principal)

    mapping = mapping!(project_id, mapping_id)
    Commands.expect!(mapping, attrs)
    github = Repo.get!(GitHubRepository, mapping.github_repository_id)
    connection = connection!(github.connection_id)

    if !mapping.enabled || usable(connection) != :ok || github.state != "verified" ||
         github.connection_version != connection.version,
       do: Commands.fail!(:forbidden)

    syncs = for kind <- @feeds, do: request_sync!(github, kind, "")
    %{"syncs" => Enum.map(syncs, &sync_projection/1)}
  end

  def configure(principal, attrs) do
    attrs = Params.strings(attrs)

    transaction(fn ->
      Commands.run(principal, nil, attrs, [operation: "github.configure"], fn _ ->
        configure_command!(principal, attrs)
      end)
      |> unwrap!()
    end)
  end

  def connections(principal, params \\ %{}) do
    Commands.read(principal, nil, [], fn _ ->
      Commands.operator!(principal)
      {limit, offset} = Params.page(params)

      %{
        "data" =>
          Repo.all(from c in GitHubConnection, order_by: c.id, limit: ^limit, offset: ^offset)
          |> Enum.map(&connection_projection/1),
        "limit" => limit,
        "offset" => offset
      }
    end)
  end

  @doc "Verify immutable repository scope remotely, then associate under ordered local locks."
  def associate(principal, project_id, attrs, opts \\ []) do
    attrs = Params.strings(attrs)

    with :ok <- operator(principal),
         {:ok, :missing} <-
           Commands.replay(principal, project_id, attrs, operation: "github.associate"),
         {:ok, connection} <- connection(attrs["connection_id"]),
         :ok <- usable(connection),
         :ok <- quota(connection, Keyword.get(opts, :now, DateTime.utc_now())),
         true <- numeric_id?(attrs["external_id"]),
         {:ok, verified} <-
           verify_association(connection, attrs["external_id"], opts) do
      transaction(fn ->
        associate_verified!(principal, project_id, attrs, opts, connection, verified)
      end)
    else
      {:ok, result} when is_map(result) -> {:ok, result}
      false -> {:error, Error.new(:invalid, %{field: "external_id"})}
      error -> error
    end
  end

  defp associate_verified!(principal, project_id, attrs, opts, connection, verified) do
    current = connection!(connection.id)

    if current.version != connection.version || usable(current) != :ok,
      do: Commands.fail!(:stale_version)

    Commands.run(principal, project_id, attrs, [operation: "github.associate"], fn ctx ->
      associate_command!(ctx, current, project_id, attrs, opts, verified)
    end)
    |> unwrap!()
  end

  def set_mapping(principal, project_id, id, attrs) do
    attrs = Params.strings(attrs)

    transaction(fn ->
      Commands.run(principal, project_id, attrs, [operation: "github.mapping:#{id}"], fn ctx ->
        disable_mapping!(principal, project_id, id, attrs, ctx)
      end)
      |> unwrap!()
    end)
  end

  def mappings(principal, project_id, params \\ %{}) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      {limit, offset} = Params.page(params)

      data =
        Repo.all(
          from m in GitHubProjectMapping,
            join: r in GitHubRepository,
            on: r.id == m.github_repository_id,
            where: m.project_id == ^project_id,
            order_by: m.id,
            limit: ^limit,
            offset: ^offset,
            select: {m, r}
        )

      %{
        "data" => Enum.map(data, fn {m, r} -> mapping_projection(m, r) end),
        "limit" => limit,
        "offset" => offset
      }
    end)
  end

  def facts(principal, project_id, mapping_id, params \\ %{}) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      mapping = readable_mapping!(project_id, mapping_id)
      {limit, offset} = Params.page(params)

      objects =
        Repo.all(
          from o in GitHubObject,
            where: o.github_repository_id == ^mapping.github_repository_id,
            order_by: [desc: o.observed_at, asc: o.id],
            limit: ^limit,
            offset: ^offset
        )

      syncs =
        Repo.all(
          from s in GitHubSync,
            where: s.github_repository_id == ^mapping.github_repository_id,
            order_by: [asc: s.next_attempt_at, asc: s.id],
            limit: 100
        )

      %{
        "data" => Enum.map(objects, &object_projection/1),
        "syncs" => Enum.map(syncs, &sync_projection/1),
        "limit" => limit,
        "offset" => offset,
        "input_trust" => "untrusted"
      }
    end)
  end

  def observation(principal, project_id, mapping_id, id) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      mapping = readable_mapping!(project_id, mapping_id)
      if !Params.uuid?(id), do: Commands.fail!(:not_found)

      row =
        Repo.one(
          from v in GitHubObservation,
            join: o in GitHubObject,
            on: o.id == v.object_id,
            where: v.id == ^id and o.github_repository_id == ^mapping.github_repository_id,
            select: v
        ) || Commands.fail!(:not_found)

      if !Repo.exists?(
           from e in DomainEvent,
             where:
               e.project_id == ^project_id and e.type == "github.reconciled" and
                 fragment("?->>'observation_id' = ?", e.data, ^id)
         ),
         do: Commands.fail!(:not_found)

      Projection.fields(
        row,
        ~w(id object_id version facts untrusted_input external_updated_at observed_at source_id)a
      )
      |> Map.put("input_trust", "untrusted")
    end)
  end

  def delivery(principal, project_id, mapping_id, id) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      mapping = readable_mapping!(project_id, mapping_id)
      if !Params.uuid?(id), do: Commands.fail!(:not_found)
      github = Repo.get!(GitHubRepository, mapping.github_repository_id)

      row =
        Repo.get_by(GitHubDelivery,
          id: id,
          connection_id: github.connection_id,
          repository_external_id: github.external_id
        ) || Commands.fail!(:not_found)

      if !Repo.exists?(
           from e in DomainEvent,
             where: e.id in ^row.event_ids and e.project_id == ^project_id
         ),
         do: Commands.fail!(:not_found)

      Projection.fields(
        row,
        ~w(id delivery_id event_name action installation_id repository_external_id body_digest payload received_at)a
      )
      |> Map.put("input_trust", "untrusted")
    end)
  end

  def reconcile(principal, project_id, mapping_id, attrs) do
    attrs = Params.strings(attrs)

    transaction(fn ->
      Commands.run(
        principal,
        project_id,
        attrs,
        [operation: "github.reconcile:#{mapping_id}"],
        fn _ ->
          reconcile_mapping!(principal, project_id, mapping_id, attrs)
        end
      )
      |> unwrap!()
    end)
  end

  @doc "Verify exact raw bytes and commit inbox, source facts, delivery intents and jobs before ACK."
  def ingest(connection_id, event_name, delivery_id, raw, signature, opts \\ []) do
    with true <- is_binary(raw) && byte_size(raw) <= 1_048_576,
         true <-
           is_binary(event_name) && Regex.match?(~r/\A[a-z_]{1,64}\z/, event_name) &&
             Params.uuid?(delivery_id),
         {:ok, initial} <- connection(connection_id),
         :ok <- usable(initial),
         {:ok, secret} <- Secrets.resolve(initial.webhook_secret_ref),
         :ok <- Signature.verify(raw, signature, secret),
         {:ok, body} when is_map(body) <- Jason.decode(raw) do
      transaction(fn ->
        ingest_verified!(connection_id, initial, event_name, delivery_id, raw, body, opts)
      end)
    else
      false ->
        {:error, Error.new(:invalid)}

      {:error, :invalid_signature} ->
        {:error, Error.new(:unauthorized)}

      {:error, %Samgita.GitHub.Failure{code: :secret_unavailable}} ->
        {:error, Error.new(:secret_unavailable)}

      {:error, %Error{}} = error ->
        error

      _ ->
        {:error, Error.new(:invalid)}
    end
  end

  defp ingest_verified!(connection_id, initial, event_name, delivery_id, raw, body, opts) do
    current = connection!(connection_id)

    if current.version != initial.version || usable(current) != :ok,
      do: Commands.fail!(:forbidden)

    digest = :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)

    existing =
      Repo.get_by(GitHubDelivery, connection_id: connection_id, delivery_id: delivery_id)

    if existing do
      replay_delivery!(existing, digest, event_name)
    else
      ingest_new!(current, event_name, delivery_id, digest, body, opts)
    end
  end

  defp replay_delivery!(existing, digest, event_name) do
    if existing.body_digest != digest || existing.event_name != event_name,
      do: Commands.fail!(:conflict, %{reason: "delivery_id_reused"})

    Map.put(delivery_projection(existing), "duplicate", true)
  end

  defp ingest_new!(current, event_name, delivery_id, digest, body, opts) do
    if nested_id(body["installation"]) != current.installation_id,
      do: Commands.fail!(:forbidden)

    case event_name do
      "installation" ->
        lifecycle!(current, delivery_id, digest, body, opts)

      "installation_repositories" ->
        removed_repositories!(current, delivery_id, digest, body, opts)

      _ ->
        ingest_fact!(current, event_name, delivery_id, digest, body, opts)
    end
  end

  defp ingest_fact!(connection, event_name, delivery_id, digest, body, opts) do
    repository_id = nested_id(body["repository"])
    if !repository_id, do: Commands.fail!(:forbidden)

    github =
      Repo.get_by(GitHubRepository, connection_id: connection.id, external_id: repository_id)

    if !verified_repository?(github, connection),
      do: Commands.fail!(:forbidden)

    mappings = mappings_locked(github.id)
    if mappings == [], do: Commands.fail!(:forbidden)

    case Payload.normalize(event_name, body) do
      {:ok, payload} ->
        receipt =
          insert_delivery!(
            connection,
            delivery_id,
            digest,
            event_name,
            payload.action,
            repository_id,
            state: "accepted",
            reason: nil,
            payload: %{"facts" => payload.facts, "untrusted_input" => payload.untrusted_input}
          )

        events =
          emit!(
            mappings,
            connection,
            receipt.id,
            delivery_id,
            "github.#{event_name}",
            "github_delivery",
            receipt.id,
            %{
              "github_repository_id" => github.id,
              "repository_id" => github.repository_id,
              "delivery_id" => delivery_id,
              "event" => event_name,
              "action" => payload.action,
              "facts" => payload.facts,
              "untrusted_input_ref" => receipt.id,
              "input_trust" => "untrusted",
              "occurred_at" =>
                if(payload.occurred_at, do: DateTime.to_iso8601(payload.occurred_at))
            }
          )

        request_sync!(github, payload.kind, payload.resource_id, opts)

        receipt
        |> change(event_ids: Enum.map(events, & &1.id))
        |> Commands.update!()
        |> delivery_projection()

      {:unsupported, reason} ->
        insert_delivery!(
          connection,
          delivery_id,
          digest,
          event_name,
          safe_action(body["action"]),
          repository_id,
          state: "unsupported",
          reason: to_string(reason),
          payload: %{}
        )
        |> delivery_projection()

      _ ->
        Commands.fail!(:invalid)
    end
  end

  defp lifecycle!(connection, delivery_id, digest, body, _opts) do
    action = body["action"]

    if action not in ~w(suspend deleted unsuspend new_permissions_accepted),
      do: Commands.fail!(:invalid)

    state = if action == "deleted", do: "revoked", else: "suspended"
    # Unsuspension/permission changes require an operator's explicit re-verification.
    connection |> change(state: state, version: connection.version + 1) |> Commands.update!()

    insert_delivery!(
      connection,
      delivery_id,
      digest,
      "installation",
      action,
      nil,
      state: "accepted",
      reason: "verification_required",
      payload: %{}
    )
    |> delivery_projection()
  end

  defp removed_repositories!(connection, delivery_id, digest, body, _opts) do
    if body["action"] not in ~w(added removed), do: Commands.fail!(:invalid)
    removed = body["repositories_removed"] || []
    if !is_list(removed) || length(removed) > 1000, do: Commands.fail!(:invalid)

    for item <- removed do
      external_id = if is_map(item), do: id(item["id"])
      if !external_id, do: Commands.fail!(:invalid)

      if repo =
           Repo.get_by(GitHubRepository, connection_id: connection.id, external_id: external_id) do
        repo |> change(state: "removed", version: repo.version + 1) |> Commands.update!()
      end
    end

    insert_delivery!(
      connection,
      delivery_id,
      digest,
      "installation_repositories",
      body["action"],
      nil,
      state: "accepted",
      reason: "new_repositories_require_operator_mapping",
      payload: %{}
    )
    |> delivery_projection()
  end

  defp insert_delivery!(
         connection,
         delivery_id,
         digest,
         event,
         action,
         repository_id,
         opts
       ) do
    change(%GitHubDelivery{},
      connection_id: connection.id,
      delivery_id: delivery_id,
      body_digest: digest,
      event_name: event,
      action: action,
      installation_id: connection.installation_id,
      repository_external_id: repository_id,
      state: Keyword.fetch!(opts, :state),
      reason: Keyword.fetch!(opts, :reason),
      payload: Keyword.fetch!(opts, :payload),
      received_at: DateTime.utc_now()
    )
    |> Commands.insert!()
  end

  @doc false
  def mappings_locked(github_id) do
    mappings =
      Repo.all(
        from m in GitHubProjectMapping,
          join: a in ProjectRepository,
          on: a.id == m.project_repository_id and a.project_id == m.project_id,
          join: r in GitHubRepository,
          on: r.id == m.github_repository_id and r.repository_id == a.repository_id,
          where: m.github_repository_id == ^github_id and m.enabled,
          order_by: m.project_id,
          limit: 101,
          select: m
      )

    if length(mappings) > 100, do: Commands.fail!(:conflict, %{reason: "mapping_limit"})
    ids = Enum.map(mappings, & &1.project_id)
    # All GitHub transactions hold the integration lock first; Projects follow in UUID order.
    Repo.all(from p in Project, where: p.id in ^ids, order_by: p.id, lock: "FOR UPDATE")
    mappings
  end

  @doc false
  def emit!(mappings, connection, command_id, source_id, type, resource_type, resource_id, data) do
    ctx = %{
      principal: Principal.operator(),
      command_id: command_id,
      source: "github",
      source_actor: "github:" <> connection.id,
      source_id: source_id
    }

    Enum.map(
      mappings,
      &Events.append!(
        &1.project_id,
        type,
        ctx,
        resource_type,
        resource_id,
        Map.merge(data, %{
          "connection_id" => connection.id,
          "installation_id" => connection.installation_id,
          "host" => connection.host
        })
      )
    )
  end

  @doc false
  def request_sync!(github, kind, resource_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    previous =
      Repo.get_by(GitHubSync,
        github_repository_id: github.id,
        kind: kind,
        resource_id: resource_id
      )

    sync =
      save!(previous, %GitHubSync{},
        github_repository_id: github.id,
        kind: kind,
        resource_id: resource_id,
        state: "pending",
        page: 1,
        since: nil,
        next_attempt_at: now,
        generation: if(previous, do: previous.generation + 1, else: 1),
        fence: if(previous, do: previous.fence + 1, else: 0),
        lease_id: nil,
        lease_expires_at: nil,
        attempt_count: 0,
        last_error_class: nil,
        last_error_code: nil,
        scan_started_at: nil
      )

    enqueue_sync!(sync, opts)
    sync
  end

  @doc false
  def enqueue_sync!(sync, opts \\ []) do
    enqueue = Keyword.get(opts, :enqueue, &Oban.insert/1)

    case enqueue.(GitHubReconcileWorker.new(%{"sync_id" => sync.id})) do
      {:ok, job} -> job
      {:error, _} -> Commands.fail!(:enqueue_failed)
    end
  end

  @doc false
  def transaction(callback) do
    Commands.system(nil, [], fn _ ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["samgita.github"])
      callback.()
    end)
  end

  @doc false
  def connection!(id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)
    Repo.get(GitHubConnection, id) || Commands.fail!(:not_found)
  end

  defp connection(id) do
    if Params.uuid?(id) do
      case Repo.get(GitHubConnection, id) do
        nil -> {:error, Error.new(:not_found)}
        connection -> {:ok, connection}
      end
    else
      {:error, Error.new(:not_found)}
    end
  end

  @doc false
  def usable(%{enabled: true, state: state}) when state in ~w(configured active), do: :ok
  def usable(_), do: {:error, Error.new(:forbidden)}

  defp quota(%{rate_limited_until: nil}, _), do: :ok

  defp quota(connection, now) do
    if DateTime.compare(connection.rate_limited_until, now) == :gt,
      do:
        {:error,
         Failure.new(
           :rate_limited,
           :rate_limited,
           DateTime.diff(connection.rate_limited_until, now)
         )},
      else: :ok
  end

  defp verify_association(connection, external_id, opts) do
    case Keyword.get(opts, :client, Client).verify(connection, external_id, opts) do
      {:error, %Failure{} = failure} = error ->
        persist_association_failure(connection, failure, error, opts)

      result ->
        result
    end
  end

  defp persist_association_failure(connection, failure, error, opts) do
    with {:ok, _} <-
           transaction(fn -> record_association_failure!(connection, failure, opts) end),
         do: error
  end

  defp record_association_failure!(connection, failure, opts) do
    current = connection!(connection.id)

    if current.version == connection.version,
      do:
        connection_failure!(
          current,
          failure,
          Keyword.get(opts, :now, DateTime.utc_now())
        )

    %{}
  end

  defp verified_repository?(nil, _), do: false

  defp verified_repository?(github, connection),
    do: github.state == "verified" && github.connection_version == connection.version

  defp invalid_retry_delay?(nil), do: false
  defp invalid_retry_delay?(delay), do: !is_integer(delay) || delay < 0 || delay > 604_800

  defp conflicting_repository?(nil, _), do: false
  defp conflicting_repository?(_, nil), do: false
  defp conflicting_repository?(requested, canonical), do: requested.id != canonical.id

  defp incompatible_repository?(nil, _, _), do: false

  defp incompatible_repository?(requested, connection, verified) do
    requested.verification == "verified" &&
      {requested.provider, requested.host, requested.external_id} !=
        {"github", connection.host, verified.external_id}
  end

  @doc false
  def connection_failure!(connection, failure, now) do
    invalid_delay = invalid_retry_delay?(failure.retry_after)

    cond do
      failure.class in [:authentication, :permission] ||
        failure.code == :rate_limit_recovery_required || invalid_delay ->
        connection
        |> change(state: "verification_required", version: connection.version + 1)
        |> Commands.update!()

      failure.class == :rate_limited ->
        deadline = DateTime.add(now, max(failure.retry_after || 60, 1))

        deadline =
          if connection.rate_limited_until &&
               DateTime.compare(connection.rate_limited_until, deadline) == :gt,
             do: connection.rate_limited_until,
             else: deadline

        connection |> change(rate_limited_until: deadline) |> Commands.update!()

      true ->
        connection
    end
  end

  defp operator(%Principal{kind: :operator}), do: :ok
  defp operator(_), do: {:error, Error.new(:forbidden)}

  defp repository!(connection, verified, attrs) do
    canonical =
      Repo.get_by(Repository,
        provider: "github",
        host: connection.host,
        external_id: verified.external_id,
        verification: "verified"
      )

    requested =
      if attrs["repository_id"] do
        if !Params.uuid?(attrs["repository_id"]), do: Commands.fail!(:not_found)
        Repo.get(Repository, attrs["repository_id"]) || Commands.fail!(:not_found)
      end

    if conflicting_repository?(requested, canonical),
      do: Commands.fail!(:conflict, %{reason: "identity_collision"})

    if incompatible_repository?(requested, connection, verified),
      do: Commands.fail!(:conflict)

    record = requested || canonical

    save!(record, %Repository{},
      kind: "git",
      provider: "github",
      host: connection.host,
      external_id: verified.external_id,
      verification: "verified",
      display_name: verified.full_name,
      version: if(record, do: record.version + 1, else: 1)
    )
  end

  defp mapping!(project_id, id) do
    if !Params.uuid?(id), do: Commands.fail!(:not_found)

    Repo.get_by(GitHubProjectMapping, id: id, project_id: project_id) ||
      Commands.fail!(:not_found)
  end

  defp readable_mapping!(project_id, id) do
    mapping = mapping!(project_id, id)
    if !mapping.enabled, do: Commands.fail!(:forbidden)
    association = Repo.get(ProjectRepository, mapping.project_repository_id)
    repository = Repo.get!(GitHubRepository, mapping.github_repository_id)

    if !association || association.project_id != project_id ||
         association.repository_id != repository.repository_id,
       do: Commands.fail!(:forbidden)

    mapping
  end

  @doc false
  def save!(nil, record, values), do: record |> change(values) |> Commands.insert!()
  def save!(record, _, values), do: record |> change(values) |> Commands.update!()
  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: Repo.rollback(error)
  defp numeric_id?(value), do: is_binary(value) && Regex.match?(~r/\A[1-9][0-9]{0,19}\z/, value)
  defp id(value) when is_integer(value) and value > 0, do: Integer.to_string(value)
  defp id(value) when is_binary(value), do: if(numeric_id?(value), do: value)
  defp id(_), do: nil
  defp nested_id(%{"id" => value}), do: id(value)
  defp nested_id(_), do: nil

  defp safe_action(value) when is_binary(value),
    do: if(Regex.match?(~r/\A[a-z_]{1,64}\z/, value), do: value)

  defp safe_action(_), do: nil

  def connection_projection(r),
    do:
      Projection.fields(
        r,
        ~w(id host app_id installation_id private_key_ref webhook_secret_ref enabled state version rate_limited_until)a
      )

  def mapping_projection(m, r),
    do:
      Projection.fields(m, ~w(id project_id project_repository_id enabled version)a)
      |> Map.put(
        "repository",
        Projection.fields(
          r,
          ~w(id repository_id connection_id external_id full_name default_branch state verified_at connection_version version)a
        )
      )

  def object_projection(r),
    do:
      Projection.fields(
        r,
        ~w(id kind resource_id facts untrusted_input external_updated_at observed_at source_id version)a
      )

  def sync_projection(r),
    do:
      Projection.fields(
        r,
        ~w(id kind resource_id page state generation fence attempt_count next_attempt_at scan_started_at last_scan_started_at last_completed_at last_error_class last_error_code)a
      )

  def delivery_projection(r),
    do: %{
      "id" => r.id,
      "delivery_id" => r.delivery_id,
      "state" => r.state,
      "reason" => r.reason,
      "event_count" => length(r.event_ids),
      "duplicate" => false
    }
end
