defmodule Samgita.GitHub.Reconciliation do
  @moduledoc "Bounded, checkpointed reads of current GitHub state; webhook order is never current-state authority."
  import Ecto.Query
  import Ecto.Changeset
  alias Samgita.{Commands, GitHub, Repo}
  alias Samgita.Domain.{GitHubObject, GitHubObservation, GitHubRepository, GitHubSync, Repository}
  alias Samgita.GitHub.{Client, Failure, Payload}
  @ready ~w(pending retry_wait)
  @feeds ~w(issues pulls workflow_runs check_runs)
  @kinds %{
    "issues" => "issue",
    "pulls" => "pull_request",
    "workflow_runs" => "workflow_run",
    "check_runs" => "check_run"
  }
  @request_kinds Map.new(
                   ~w(issues pulls workflow_runs check_runs issue pull_request check_run check_suite workflow_run comment)a,
                   &{Atom.to_string(&1), &1}
                 )

  def run(id, opts \\ []) do
    client = Keyword.get(opts, :client, Application.get_env(:samgita, :github_client, Client))

    with {:ok, claim} <- claim(id, opts) do
      case claim do
        %{result: result} ->
          {:ok, result}

        work ->
          outcome = read_current(client, work, opts)

          settle(id, work.token, outcome, opts)
      end
    end
  end

  defp read_current(client, work, opts) do
    with {:ok, metadata} <- client.verify(work.connection, work.repository.external_id, opts),
         repository = %{
           work.repository
           | full_name: metadata.full_name,
             default_branch: metadata.default_branch
         },
         {:ok, result} <- client.fetch(work.connection, repository, work.request, opts) do
      {:ok, metadata, result}
    end
  end

  def claim(id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    GitHub.transaction(fn ->
      sync = sync!(id)
      repository = Repo.get!(GitHubRepository, sync.github_repository_id)
      connection = GitHub.connection!(repository.connection_id)

      cond do
        unavailable?(repository, connection) ->
          %{
            result:
              stop!(sync, "permission_failed", "mapping_unavailable") |> GitHub.sync_projection()
          }

        live_lease?(sync, now) ->
          %{result: GitHub.sync_projection(sync)}

        terminal?(sync) ->
          %{result: GitHub.sync_projection(sync)}

        DateTime.compare(sync.next_attempt_at, now) == :gt ->
          %{result: GitHub.sync_projection(sync)}

        cooldown?(connection, now) ->
          %{
            result:
              sync
              |> change(state: "retry_wait", next_attempt_at: connection.rate_limited_until)
              |> Commands.update!()
              |> GitHub.sync_projection()
          }

        sync.attempt_count >= 8 ->
          %{result: stop!(sync, "dead_letter", "retry_exhausted") |> GitHub.sync_projection()}

        true ->
          current =
            sync
            |> change(
              state: "running",
              fence: sync.fence + 1,
              lease_id: Ecto.UUID.generate(),
              lease_expires_at: DateTime.add(now, 120),
              next_attempt_at: DateTime.add(now, 120),
              started_at: now,
              scan_started_at: sync.scan_started_at || now,
              attempt_count: sync.attempt_count + 1
            )
            |> Commands.update!()

          %{
            connection: connection,
            repository: repository,
            token: %{
              lease_id: current.lease_id,
              fence: current.fence,
              generation: current.generation,
              connection_version: connection.version,
              repository_version: repository.version
            },
            request: %{
              kind: Map.fetch!(@request_kinds, current.kind),
              resource_id: current.resource_id,
              page: current.page,
              since: current.since
            }
          }
      end
    end)
  end

  def settle(id, token, outcome, opts \\ []) do
    now = Keyword.get(opts, :settled_at, Keyword.get(opts, :now, DateTime.utc_now()))

    GitHub.transaction(fn ->
      sync = sync!(id)
      repository = Repo.get!(GitHubRepository, sync.github_repository_id)
      connection = GitHub.connection!(repository.connection_id)
      mappings = GitHub.mappings_locked(repository.id)

      if !owned?(sync, token, repository, connection, mappings, now),
        do: Commands.fail!(:ownership_lost)

      current = settle_outcome!(sync, repository, connection, mappings, outcome, now)

      GitHub.sync_projection(current)
    end)
  end

  defp settle_outcome!(sync, repository, connection, mappings, outcome, now) do
    case outcome do
      {:ok, metadata, %{items: items, next_page: next} = result}
      when is_list(items) and length(items) <= 50 ->
        if metadata.external_id != repository.external_id || invalid_next_page?(next, sync.page),
          do: Commands.fail!(:invalid)

        update_metadata!(repository, metadata, sync)

        for object <- normalized_objects!(result, sync) do
          observe!(repository, connection, mappings, sync, object)
        end

        progress!(sync, next, now)

      {:error, %Failure{} = failure} ->
        failure!(sync, connection, failure, now)

      _ ->
        failure!(sync, connection, %Failure{class: :permanent, code: :invalid_response}, now)
    end
  end

  defp invalid_next_page?(nil, _), do: false
  defp invalid_next_page?(next, page), do: !is_integer(next) || next != page + 1

  defp update_metadata!(repository, metadata, sync) do
    # Query order governs metadata too; an older read must not undo a rename.
    if DateTime.compare(repository.verified_at, sync.started_at) != :gt do
      Repo.get!(Repository, repository.repository_id)
      |> change(display_name: metadata.full_name)
      |> Commands.update!()

      repository
      |> change(
        full_name: metadata.full_name,
        default_branch: metadata.default_branch,
        permissions: metadata.permissions,
        verified_at: sync.started_at
      )
      |> Commands.update!()
    end
  end

  defp normalized_objects!(%{missing: true, items: [], next_page: nil}, sync) do
    if sync.kind in @feeds || sync.resource_id == "", do: Commands.fail!(:invalid)
    [Payload.tombstone(sync.kind, sync.resource_id)]
  end

  defp normalized_objects!(%{missing: true}, _), do: Commands.fail!(:invalid)

  defp normalized_objects!(%{items: items}, sync) do
    Enum.map(items, fn item ->
      case Payload.object(Map.get(@kinds, sync.kind, sync.kind), item) do
        {:ok, object} -> object
        _ -> Commands.fail!(:invalid, %{reason: "invalid_external_object"})
      end
    end)
  end

  defp progress!(sync, next, now) do
    cond do
      next && next > 100 ->
        stop!(sync, "dead_letter", "page_limit")

      next ->
        sync
        |> change(
          state: "pending",
          page: next,
          next_attempt_at: now,
          lease_id: nil,
          lease_expires_at: nil,
          attempt_count: 0,
          last_error_class: nil,
          last_error_code: nil
        )
        |> Commands.update!()

      true ->
        sync
        |> change(
          state: "idle",
          page: 1,
          lease_id: nil,
          lease_expires_at: nil,
          attempt_count: 0,
          last_error_class: nil,
          last_error_code: nil,
          last_completed_at: now,
          last_scan_started_at: sync.scan_started_at,
          next_attempt_at:
            DateTime.add(
              now,
              if(sync.kind in @feeds && sync.resource_id == "",
                do: 900,
                else: 315_360_000
              )
            )
        )
        |> Commands.update!()
    end
  end

  def maintain(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    GitHub.transaction(fn ->
      due =
        Repo.all(
          from s in GitHubSync,
            where:
              (s.state in ^@ready or s.state == "running" or
                 (s.state == "idle" and s.resource_id == "")) and s.next_attempt_at <= ^now,
            order_by: [asc: s.updated_at, asc: s.next_attempt_at, asc: s.id],
            limit: 100
        )

      for sync <- due, do: maintain_sync!(sync, opts)

      %{"checked" => length(due)}
    end)
  end

  defp maintain_sync!(sync, opts) do
    repository = Repo.get!(GitHubRepository, sync.github_repository_id)
    connection = GitHub.connection!(repository.connection_id)

    if eligible?(repository, connection) && GitHub.mappings_locked(repository.id) != [] do
      if sync.state == "idle" do
        current = GitHub.request_sync!(repository, sync.kind, "", opts)

        overlap!(current, sync)
      else
        GitHub.enqueue_sync!(sync, opts)
        # Durable round-robin progress even when workers are delayed. Touching
        # the scan cursor changes neither read eligibility nor fencing/deadlines.
        sync |> change(updated_at: DateTime.utc_now()) |> Commands.update!()
      end
    else
      stop!(sync, "permission_failed", "mapping_unavailable")
    end
  end

  defp overlap!(current, sync) do
    # Overlap catches updates around a scan boundary. Other feeds may require a full paginated read.
    if sync.last_scan_started_at,
      do:
        current
        |> change(since: DateTime.add(sync.last_scan_started_at, -300))
        |> Commands.update!()
  end

  defp observe!(repository, connection, mappings, sync, object) do
    previous =
      Repo.get_by(GitHubObject,
        github_repository_id: repository.id,
        kind: object.kind,
        resource_id: object.resource_id
      )

    stale = stale_observation?(previous, object, sync)

    if !stale do
      changed =
        changed_observation?(previous, object)

      source = "reconcile:#{sync.id}:#{sync.generation}:#{sync.fence}:#{object.resource_id}"

      current =
        GitHub.save!(previous, %GitHubObject{},
          github_repository_id: repository.id,
          kind: object.kind,
          resource_id: object.resource_id,
          facts: object.facts,
          untrusted_input: object.untrusted_input,
          external_updated_at: microseconds(object.external_updated_at),
          observed_at: sync.started_at,
          source_id: source,
          version: object_version(previous, changed)
        )

      if changed do
        observation =
          %GitHubObservation{}
          |> change(
            object_id: current.id,
            version: current.version,
            facts: current.facts,
            untrusted_input: current.untrusted_input,
            external_updated_at: current.external_updated_at,
            observed_at: current.observed_at,
            source_id: source
          )
          |> Commands.insert!()

        GitHub.emit!(
          mappings,
          connection,
          Ecto.UUID.generate(),
          source,
          "github.reconciled",
          "github_object",
          current.id,
          %{
            "github_repository_id" => repository.id,
            "repository_id" => repository.repository_id,
            "facts" => current.facts,
            "kind" => current.kind,
            "external_resource_id" => current.resource_id,
            "object_version" => current.version,
            "input_trust" => "untrusted",
            "untrusted_input_ref" => observation.id,
            "observation_id" => observation.id
          }
        )
      end
    end
  end

  defp unavailable?(repository, connection),
    do: !eligible?(repository, connection) || GitHub.mappings_locked(repository.id) == []

  defp live_lease?(sync, now),
    do: sync.state == "running" && DateTime.compare(sync.lease_expires_at, now) == :gt

  defp terminal?(sync), do: sync.state not in @ready && sync.state != "running"

  defp cooldown?(connection, now),
    do:
      connection.rate_limited_until && DateTime.compare(connection.rate_limited_until, now) == :gt

  defp owned?(sync, token, repository, connection, mappings, now) do
    matching_token?(sync, token) && connection.version == token.connection_version &&
      repository.version == token.repository_version &&
      DateTime.compare(sync.lease_expires_at, now) == :gt &&
      eligible?(repository, connection) && mappings != []
  end

  defp matching_token?(sync, token) do
    sync.state == "running" && sync.lease_id == token.lease_id &&
      sync.fence == token.fence && sync.generation == token.generation
  end

  defp stale_observation?(nil, _, _), do: false

  defp stale_observation?(previous, object, sync) do
    DateTime.compare(previous.observed_at, sync.started_at) == :gt ||
      older_external_version?(previous.external_updated_at, object.external_updated_at)
  end

  defp older_external_version?(nil, _), do: false
  defp older_external_version?(_, nil), do: false
  defp older_external_version?(previous, current), do: DateTime.compare(current, previous) == :lt

  defp changed_observation?(nil, _), do: true

  defp changed_observation?(previous, object),
    do: previous.facts != object.facts || previous.untrusted_input != object.untrusted_input

  defp object_version(nil, _), do: 1
  defp object_version(previous, changed), do: previous.version + if(changed, do: 1, else: 0)

  defp failure!(sync, connection, failure, now) do
    delay =
      max(
        min(5 * Integer.pow(2, sync.attempt_count - 1), 3600),
        retry_delay(failure.retry_after)
      )

    state =
      cond do
        failure.class == :authentication -> "authentication_failed"
        failure.class == :permission -> "permission_failed"
        invalid_delay?(failure.retry_after) -> "dead_letter"
        failure.class == :permanent || sync.attempt_count >= 8 -> "dead_letter"
        true -> "retry_wait"
      end

    GitHub.connection_failure!(connection, failure, now)

    sync
    |> change(
      state: state,
      last_error_class: to_string(failure.class),
      last_error_code:
        if(invalid_delay?(failure.retry_after),
          do: "rate_limit_recovery_required",
          else: to_string(failure.code)
        ),
      next_attempt_at: DateTime.add(now, delay),
      lease_id: nil,
      lease_expires_at: nil
    )
    |> Commands.update!()
  end

  # Worker wakeups may be shorter; the durable deadline always gates remote I/O.
  defp retry_delay(n) when is_integer(n) and n >= 0 and n <= 604_800, do: max(n, 1)
  defp retry_delay(_), do: 0
  defp invalid_delay?(nil), do: false
  defp invalid_delay?(n), do: !is_integer(n) || n < 0 || n > 604_800

  defp microseconds(nil), do: nil

  defp microseconds(%DateTime{microsecond: {value, _}} = time),
    do: %{time | microsecond: {value, 6}}

  defp stop!(sync, state, code),
    do:
      sync
      |> change(
        state: state,
        lease_id: nil,
        lease_expires_at: nil,
        fence: sync.fence + 1,
        last_error_class: "permanent",
        last_error_code: code
      )
      |> Commands.update!()

  defp eligible?(repo, connection),
    do:
      repo.state == "verified" && GitHub.usable(connection) == :ok &&
        repo.connection_version == connection.version

  defp sync!(id) do
    if !Samgita.Params.uuid?(id), do: Commands.fail!(:not_found)
    Repo.get(GitHubSync, id) || Commands.fail!(:not_found)
  end
end
