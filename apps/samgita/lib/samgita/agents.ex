defmodule Samgita.Agents do
  @moduledoc "Stable machine registrations, credential references, connection instances and external sessions."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, Error, Events, Params, Principal, Projection, Repo}

  alias Samgita.Domain.{
    Agent,
    AgentConnection,
    AgentCredential,
    CodexHost,
    ExecutionSession,
    TaskAttempt
  }

  @read_roles ~w(observer worker manager reviewer)
  # Codex is not pinned (design §11): any well-formed version string is accepted.
  @runtime_version ~r/\A[0-9A-Za-z][0-9A-Za-z.+-]{0,63}\z/
  @fields ~w(name implementation enabled capacity advertised_capabilities approved_capabilities protocol protocol_version endpoint_metadata credential_ref runtime_driver runtime_version)a

  def register(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(principal, nil, attrs, [operation: "agent.register"], fn ctx ->
      Commands.operator!(principal)
      agent = Commands.insert!(agent_changeset(%Agent{}, attrs))
      Events.append!(nil, "agent.registered", ctx, "agent", agent.id, %{}, current: agent)
      Projection.agent(agent)
    end)
  end

  def update(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "agent.update:" <> to_string(id), agent_ids: [id]],
      fn ctx ->
        Commands.operator!(principal)
        agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
        Commands.expect!(agent, attrs)
        require_current!(agent)

        require_idle_transport_change!(
          agent,
          attrs["endpoint_metadata"] || agent.endpoint_metadata
        )

        previous = agent

        agent =
          agent
          |> agent_changeset(attrs)
          |> put_change(:version, agent.version + 1)
          |> Commands.update!()

        Events.append!(nil, "agent.updated", ctx, "agent", id, %{},
          previous: previous,
          current: agent
        )

        Projection.agent(agent)
      end
    )
  end

  @doc "Remove a registration from current use while retaining its identity and history."
  def remove(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "agent.remove:" <> to_string(id), agent_ids: [id]],
      fn ctx ->
        Commands.operator!(principal)
        agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
        Commands.expect!(agent, attrs)

        if agent.removed_at do
          Projection.agent(agent)
        else
          if Repo.exists?(
               from(a in TaskAttempt,
                 where:
                   a.agent_id == ^id and
                     (a.state in ["leased", "running"] or not a.effects_resolved)
               )
             ),
             do: Commands.fail!(:conflict, %{reason: "unresolved_execution"})

          disable_host!(ctx, id)

          removed =
            agent
            |> change(enabled: false, removed_at: DateTime.utc_now(), version: agent.version + 1)
            |> Commands.update!()

          Events.append!(nil, "agent.removed", ctx, "agent", id, %{},
            previous: agent,
            current: removed
          )

          Projection.agent(removed)
        end
      end
    )
    |> stop_removed_host()
  end

  defp disable_host!(ctx, agent_id) do
    host = Repo.one(from(h in CodexHost, where: h.agent_id == ^agent_id, lock: "FOR UPDATE"))

    if host && host.enabled do
      disabled = host |> change(enabled: false, version: host.version + 1) |> Commands.update!()

      Events.append!(
        nil,
        "codex_host.disabled",
        ctx,
        "codex_host",
        host.id,
        %{"agent_id" => agent_id, "transport" => host.transport},
        previous: host,
        current: disabled
      )
    end
  end

  defp stop_removed_host({:ok, %{"id" => id}} = result) do
    if host = Repo.get_by(CodexHost, agent_id: id), do: Samgita.CodexHosts.Runtime.sync(host.id)
    result
  end

  defp stop_removed_host(result), do: result

  defp require_current!(%Agent{removed_at: nil}), do: :ok
  defp require_current!(_agent), do: Commands.fail!(:invalid_transition)

  def get(principal, id) do
    Commands.read(principal, nil, [], fn _ ->
      Commands.operator!(principal)
      if !Params.uuid?(id), do: Commands.fail!(:not_found)
      Projection.agent(Repo.get(Agent, id) || Commands.fail!(:not_found))
    end)
  end

  def list(principal, params \\ %{}) do
    Commands.read(principal, nil, [], fn _ ->
      Commands.operator!(principal)
      {limit, offset} = Params.page(params)

      data =
        Repo.all(
          from(a in Agent,
            where: is_nil(a.removed_at),
            order_by: a.id,
            limit: ^limit,
            offset: ^offset
          )
        )

      %{"data" => Enum.map(data, &Projection.agent/1), "limit" => limit, "offset" => offset}
    end)
  end

  def put_credential(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "credential.put:" <> to_string(id), agent_ids: [id]],
      fn ctx ->
        Commands.operator!(principal)
        agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
        Commands.expect!(agent, attrs)
        require_current!(agent)
        credential = attrs["credential"]

        if !is_binary(credential) || byte_size(credential) < 32 || byte_size(credential) > 4096,
          do: Commands.fail!(:invalid, %{field: "credential"})

        changeset =
          %AgentCredential{}
          |> cast(attrs, [:reference, :expires_at])
          |> validate_length(:reference, max: 512)
          |> put_change(:agent_id, id)
          |> put_change(:digest, :crypto.hash(:sha256, credential))
          |> unique_constraint(:digest)

        record = Commands.insert!(changeset)
        current = agent |> change(version: agent.version + 1) |> Commands.update!()

        Events.append!(
          nil,
          "agent.credential_added",
          ctx,
          "agent",
          id,
          %{
            "credential_id" => record.id
          },
          previous: agent,
          current: current
        )

        Projection.credential(record)
      end
    )
  end

  @doc "Trust a pending inbound device after an explicit operator decision; only its digest is accepted."
  def pair_device(principal, attrs) do
    attrs = Params.strings(attrs)
    agent_id = if attrs["agent_id"] not in [nil, ""], do: attrs["agent_id"]

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "agent.pair_device", agent_ids: if(agent_id, do: [agent_id], else: [])],
      fn ctx ->
        Commands.operator!(principal)

        if !Params.uuid?(attrs["request_id"]),
          do: Commands.fail!(:invalid, %{field: "request_id"})

        digest = device_digest!(attrs["device_digest"])

        # Distinct pending connections for the same device cannot create two identities.
        Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "agent-device:" <> attrs["device_digest"]
        ])

        if Repo.exists?(from(c in AgentCredential, where: c.digest == ^digest)),
          do: Commands.fail!(:conflict, %{reason: "device_already_registered"})

        {previous, agent} = pair_agent!(agent_id, attrs)

        credential =
          %AgentCredential{}
          |> change(
            agent_id: agent.id,
            digest: digest,
            reference: "device:" <> attrs["request_id"]
          )
          |> unique_constraint(:digest)
          |> Commands.insert!()

        Events.append!(
          nil,
          "agent.device_paired",
          ctx,
          "agent",
          agent.id,
          %{"credential_id" => credential.id, "request_id" => attrs["request_id"]},
          previous: previous,
          current: agent
        )

        Projection.agent(agent)
      end
    )
  end

  defp pair_agent!(nil, attrs) do
    attrs =
      Map.take(attrs, ~w(name implementation))
      |> Map.merge(%{
        "endpoint_metadata" => %{"transport" => "inbound_websocket"},
        "advertised_capabilities" => ["project_events.v1"],
        "approved_capabilities" => ["project_events.v1"]
      })

    {nil, Commands.insert!(agent_changeset(%Agent{}, attrs))}
  end

  defp pair_agent!(id, attrs) do
    agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
    Commands.expect!(agent, attrs)
    require_current!(agent)

    if !agent.enabled || agent.runtime_driver ||
         Repo.exists?(from(h in CodexHost, where: h.agent_id == ^id)),
       do: Commands.fail!(:invalid, %{reason: "inbound_agent_required"})

    require_idle_transport_change!(agent, %{"transport" => "inbound_websocket"})

    current =
      agent
      |> agent_changeset(%{
        "endpoint_metadata" => %{"transport" => "inbound_websocket"},
        "credential_ref" => nil,
        "advertised_capabilities" =>
          Enum.uniq(agent.advertised_capabilities ++ ["project_events.v1"]),
        "approved_capabilities" => Enum.uniq(agent.approved_capabilities ++ ["project_events.v1"])
      })
      |> put_change(:version, agent.version + 1)
      |> Commands.update!()

    {agent, current}
  end

  defp require_idle_transport_change!(agent, endpoint) when is_map(endpoint) do
    old = agent.endpoint_metadata["transport"]
    new = endpoint["transport"]

    if new == "inbound_websocket" &&
         (agent.runtime_driver ||
            Repo.exists?(from(h in CodexHost, where: h.agent_id == ^agent.id))),
       do: Commands.fail!(:invalid, %{reason: "inbound_agent_required"})

    if old != new && "inbound_websocket" in [old, new] &&
         Repo.exists?(
           from(a in TaskAttempt,
             where:
               a.agent_id == ^agent.id and
                 (a.state in ["leased", "running"] or not a.effects_resolved)
           )
         ),
       do: Commands.fail!(:conflict, %{reason: "unresolved_execution"})
  end

  defp require_idle_transport_change!(_agent, _endpoint), do: :ok

  defp device_digest!(value) when is_binary(value) and byte_size(value) == 64 do
    case Base.decode16(value, case: :lower) do
      {:ok, digest} when byte_size(digest) == 32 -> digest
      _ -> Commands.fail!(:invalid, %{field: "device_digest"})
    end
  end

  defp device_digest!(_), do: Commands.fail!(:invalid, %{field: "device_digest"})

  @doc "Resume a trusted device, or return :unknown only for a never-registered token."
  def authenticate_device(raw)
      when is_binary(raw) and byte_size(raw) >= 32 and byte_size(raw) <= 4096 do
    lookup_device(:crypto.hash(:sha256, raw))
  end

  def authenticate_device(_), do: {:error, Error.new(:unauthorized)}

  @doc false
  def lookup_device(digest) when is_binary(digest) and byte_size(digest) == 32 do
    if Repo.exists?(from(c in AgentCredential, where: c.digest == ^digest)),
      do: device_principal(digest),
      else: :unknown
  end

  def lookup_device(_), do: {:error, Error.new(:unauthorized)}

  @doc false
  def device_principal(digest) when is_binary(digest) and byte_size(digest) == 32 do
    case Repo.get_by(AgentCredential, digest: digest) do
      %AgentCredential{revoked_at: nil, reference: "device:" <> _} = credential ->
        agent = Repo.get(Agent, credential.agent_id)

        if agent && agent.enabled && is_nil(agent.removed_at) &&
             agent.endpoint_metadata["transport"] == "inbound_websocket" &&
             "project_events.v1" in agent.advertised_capabilities &&
             "project_events.v1" in agent.approved_capabilities &&
             !Commands.expired?(credential.expires_at),
           do: {:ok, %Principal{kind: :agent, agent_id: agent.id, credential_id: credential.id}},
           else: {:error, Error.new(:unauthorized)}

      _ ->
        {:error, Error.new(:unauthorized)}
    end
  end

  def device_principal(_), do: {:error, Error.new(:unauthorized)}

  def revoke_credential(principal, id, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "credential.revoke:" <> to_string(id), agent_ids: [id]],
      fn ctx ->
        Commands.operator!(principal)
        agent = Repo.get(Agent, id) || Commands.fail!(:not_found)
        Commands.expect!(agent, attrs)
        if !Params.uuid?(attrs["credential_id"]), do: Commands.fail!(:not_found)
        record = Repo.get(AgentCredential, attrs["credential_id"]) || Commands.fail!(:not_found)
        if record.agent_id != id, do: Commands.fail!(:not_found)
        record = record |> change(revoked_at: DateTime.utc_now()) |> Commands.update!()

        Repo.update_all(
          from(c in AgentConnection,
            where: c.credential_id == ^record.id and c.state == "connected"
          ),
          set: [state: "revoked"]
        )

        current = agent |> change(version: agent.version + 1) |> Commands.update!()

        Events.append!(
          nil,
          "agent.credential_revoked",
          ctx,
          "agent",
          id,
          %{
            "credential_id" => record.id
          },
          previous: agent,
          current: current
        )

        Projection.credential(record)
      end
    )
  end

  def authenticate(raw) when is_binary(raw) and byte_size(raw) >= 32 and byte_size(raw) <= 4096 do
    digest = :crypto.hash(:sha256, raw)

    case Repo.get_by(AgentCredential, digest: digest) do
      %AgentCredential{revoked_at: nil} = c ->
        a = Repo.get(Agent, c.agent_id)

        if a && a.enabled && !Commands.expired?(c.expires_at),
          do: {:ok, %Principal{kind: :agent, agent_id: a.id, credential_id: c.id}},
          else: {:error, Error.new(:unauthorized)}

      _ ->
        {:error, Error.new(:unauthorized)}
    end
  end

  def authenticate(_), do: {:error, Error.new(:unauthorized)}

  def bind_connection(%Principal{kind: :agent} = principal, id) do
    Commands.read(principal, nil, [:credential], fn _ ->
      if !Params.uuid?(id), do: Commands.fail!(:unauthorized)
      c = Repo.get(AgentConnection, id) || Commands.fail!(:unauthorized)
      a = Repo.get!(Agent, principal.agent_id)

      if c.agent_id != principal.agent_id || c.credential_id != principal.credential_id ||
           c.state != "connected" || c.generation != a.generation ||
           Commands.expired?(c.expires_at),
         do: Commands.fail!(:unauthorized)

      %{principal | connection_id: c.id, generation: c.generation}
    end)
  end

  def bind_connection(_, _), do: {:error, Error.new(:unauthorized)}

  @doc false
  def check_ingress_connection(%Principal{kind: :agent, connection_id: id} = principal) do
    case bind_connection(principal, id) do
      {:error, %Error{code: :unauthorized}} -> classify_ingress_failure(principal)
      result -> result
    end
  end

  # A failed bind always fences the old socket. Recheck the credential under the
  # normal authority locks before describing a failure as recoverable.
  defp classify_ingress_failure(principal) do
    credential = %{principal | connection_id: nil, generation: nil}

    Commands.read(credential, nil, [:credential], fn _ ->
      connection =
        Repo.get_by(AgentConnection,
          id: principal.connection_id,
          agent_id: principal.agent_id,
          credential_id: principal.credential_id,
          generation: principal.generation
        ) || Commands.fail!(:unauthorized)

      agent = Repo.get!(Agent, principal.agent_id)

      cond do
        connection.state == "replaced" ->
          Commands.fail!(:connection_replaced)

        connection.state != "connected" ->
          Commands.fail!(:unauthorized)

        connection.generation != agent.generation ->
          Commands.fail!(:connection_replaced)

        Commands.expired?(connection.expires_at) ->
          Commands.fail!(:connection_expired)

        true ->
          Commands.fail!(:unauthorized)
      end
    end)
  end

  def connect(principal, attrs) do
    attrs = Params.strings(attrs)

    Commands.run(
      principal,
      nil,
      attrs,
      [operation: "agent.connect", roles: [:credential]],
      fn ctx ->
        if principal.kind != :agent, do: Commands.fail!(:forbidden)
        agent = Repo.get!(Agent, principal.agent_id)
        previous = agent

        Repo.update_all(
          from(c in AgentConnection, where: c.agent_id == ^agent.id and c.state == "connected"),
          set: [state: "replaced"]
        )

        agent =
          agent
          |> change(generation: agent.generation + 1, version: agent.version + 1)
          |> Commands.update!()

        connection =
          %AgentConnection{}
          |> change(
            agent_id: agent.id,
            credential_id: principal.credential_id,
            generation: agent.generation,
            state: "connected",
            expires_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
          )
          |> Repo.insert!()

        Events.append!(
          nil,
          "agent.connected",
          ctx,
          "agent",
          agent.id,
          %{
            "connection_id" => connection.id,
            "generation" => connection.generation
          },
          previous: previous,
          current: agent
        )

        Projection.connection(connection)
      end
    )
  end

  def open_session(principal, project_id, attrs) do
    attrs = Params.strings(attrs)
    agent_id = if principal.kind == :agent, do: principal.agent_id, else: attrs["agent_id"]

    Commands.run(
      principal,
      project_id,
      attrs,
      [operation: "session.open", roles: ~w(worker manager), agent_ids: [agent_id]],
      fn ctx ->
        connection_id =
          if principal.kind == :agent, do: principal.connection_id, else: attrs["connection_id"]

        if !Params.uuid?(connection_id) || !Params.uuid?(agent_id), do: Commands.fail!(:invalid)
        c = Repo.get(AgentConnection, connection_id) || Commands.fail!(:not_found)
        a = Repo.get!(Agent, agent_id)

        if !current_connection?(c, a),
          do: Commands.fail!(:unauthorized)

        session =
          %ExecutionSession{}
          |> cast(attrs, [:external_id])
          |> validate_required([:external_id])
          |> validate_length(:external_id, max: 256)
          |> change(project_id: project_id, agent_id: agent_id, connection_id: connection_id)
          |> unique_constraint([:agent_id, :project_id, :external_id])
          |> Commands.insert!()

        Events.append!(project_id, "session.recorded", ctx, "execution_session", session.id, %{},
          current: session
        )

        Projection.session(session)
      end
    )
  end

  defp current_connection?(connection, agent) do
    connection.agent_id == agent.id && connection.state == "connected" &&
      connection.generation == agent.generation && !Commands.expired?(connection.expires_at)
  end

  def list_sessions(principal, project_id, params \\ %{}) do
    Commands.read(principal, project_id, @read_roles, fn _ ->
      {limit, offset} = Params.page(params)

      data =
        Repo.all(
          from(s in ExecutionSession,
            where: s.project_id == ^project_id,
            order_by: s.id,
            limit: ^limit,
            offset: ^offset
          )
        )

      %{"data" => Enum.map(data, &Projection.session/1), "limit" => limit, "offset" => offset}
    end)
  end

  defp agent_changeset(agent, attrs) do
    changeset =
      agent
      |> cast(attrs, @fields)
      |> validate_required([:name, :protocol, :protocol_version])
      |> validate_length(:name, min: 1, max: 200)
      |> validate_length(:implementation, max: 200)
      |> validate_length(:credential_ref, max: 512)
      |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 1000)
      |> validate_inclusion(:protocol, ["samgita"])
      |> validate_inclusion(:protocol_version, [SamgitaProtocol.version()])
      |> validate_runtime()

    advertised = get_field(changeset, :advertised_capabilities)
    approved = get_field(changeset, :approved_capabilities)

    changeset =
      if SamgitaProtocol.Capabilities.validate(advertised) != :ok ||
           !is_list(approved) || !Enum.all?(approved, &(&1 in (advertised || []))),
         do: add_error(changeset, :advertised_capabilities, "invalid capabilities"),
         else: changeset

    endpoint = get_field(changeset, :endpoint_metadata)

    if valid_endpoint?(endpoint) &&
         !(endpoint["transport"] == "inbound_websocket" && get_field(changeset, :runtime_driver)),
       do: changeset,
       else: add_error(changeset, :endpoint_metadata, "invalid endpoint")
  end

  defp validate_runtime(changeset) do
    case {get_field(changeset, :runtime_driver), get_field(changeset, :runtime_version)} do
      {nil, nil} ->
        changeset

      {"codex", version} when is_binary(version) ->
        if Regex.match?(@runtime_version, version),
          do: changeset,
          else: add_error(changeset, :runtime_version, "invalid version")

      _ ->
        add_error(changeset, :runtime_driver, "unsupported runtime/version")
    end
  end

  defp valid_endpoint?(metadata) when is_map(metadata) do
    Enum.all?(Map.keys(metadata), &(&1 in ~w(url transport))) &&
      metadata["transport"] in [nil, "websocket", "stdio", "inbound_websocket"] &&
      if(metadata["transport"] == "inbound_websocket",
        do: is_nil(metadata["url"]),
        else: valid_endpoint_url?(metadata["url"])
      )
  end

  defp valid_endpoint?(_), do: false
  defp valid_endpoint_url?(nil), do: true

  defp valid_endpoint_url?(value) when is_binary(value) do
    uri = URI.parse(value)

    uri.scheme in ~w(https wss http ws) && is_binary(uri.host) && uri.userinfo == nil &&
      uri.query == nil && uri.fragment == nil
  end

  defp valid_endpoint_url?(_), do: false
end
