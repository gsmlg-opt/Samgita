defmodule Samgita.GitHub.PatWorkflowRuns do
  @moduledoc "The latest twenty workflow runs, refreshed by Styx while a repository tab is active."
  import Ecto.Changeset, only: [change: 2]
  alias Samgita.Domain.GitHubPatWorkflowSnapshot, as: Snapshot
  alias Samgita.GitHub.{Console, PatCatalog, PatCipher, PatClient}
  alias Samgita.Repo
  alias Samgita.Workers.GitHubPatWorkflowWorker

  @active ~w(requested queued pending in_progress waiting)
  @errors ~w(unavailable invalid_response repository_changed forbidden not_found invalid_token rate_limited refresh_interrupted unapproved_destination storage_key_unavailable unreadable_token rate_limit_recovery_required)a

  def read(connection, repository_id) do
    producer = PatCatalog.producer()

    case Repo.transact(fn ->
           with {:ok, target} <- target(connection, repository_id, :share) do
             snapshot = snapshot(connection, repository_id)
             snapshot = if current?(snapshot, target), do: snapshot
             {:ok, view(snapshot, target.repository, producer)}
           end
         end) do
      {:ok, result} -> result
      {:error, :stale} -> empty()
    end
  end

  def request(connection, repository_id, mode) when mode in [:initial, :manual, :poll] do
    producer = PatCatalog.producer()

    queued =
      Repo.transact(fn ->
        with {:ok, target} <- target(connection, repository_id, :update) do
          existing = snapshot(connection, repository_id)
          current = if current?(existing, target), do: existing

          if refresh?(current, mode, producer) do
            args = %{
              "connection_id" => connection.id,
              "credential_version" => connection.credential_version,
              "repository_id" => repository_id
            }

            with {:ok, job} <- Styx.insert(GitHubPatWorkflowWorker.new(args), retry: false) do
              row =
                existing || %Snapshot{connection_id: connection.id, repository_id: repository_id}

              Repo.insert_or_update!(
                change(row,
                  credential_version: connection.credential_version,
                  owner_id: if(current, do: current.owner_id, else: target.repository.owner_id),
                  runs: if(current, do: current.runs, else: []),
                  synced_at: current && current.synced_at,
                  job_id: job.id,
                  error_code: nil,
                  fence: nil
                )
              )

              {:ok, :queued}
            end
          else
            {:ok, :unchanged}
          end
        end
      end)

    case queued do
      {:ok, :queued} -> broadcast(repository_id)
      {:ok, :unchanged} -> :ok
      {:error, :stale} -> {:error, :stale}
      {:error, _} -> {:error, :sync_enqueue_failed}
    end
  end

  defp refresh?(nil, mode, _producer), do: mode != :poll

  defp refresh?(snapshot, mode, producer) do
    cond do
      PatCatalog.active_job?(snapshot, producer) ->
        false

      mode == :manual ->
        true

      mode == :initial ->
        snapshot.job_id != nil

      true ->
        active?(snapshot) &&
          DateTime.diff(DateTime.utc_now(), snapshot.synced_at, :millisecond) >= 10_000
    end
  end

  def perform(%Styx.Job{args: args} = job) do
    connection = %{id: args["connection_id"], credential_version: args["credential_version"]}
    id = args["repository_id"]

    claim =
      Repo.transact(fn ->
        with {:ok, target, row} <- work(connection, id, job.id) do
          if is_integer(target.connection.retry_at) && target.connection.retry_at > now() do
            {:ok, {:wait, target.connection.retry_at}}
          else
            claimed = Repo.update!(change(row, fence: Ecto.UUID.generate()))
            {:ok, {:read, target, claimed.fence}}
          end
        end
      end)

    case claim do
      {:ok, {:read, target, fence}} ->
        outcome = fetch(target)

        result =
          Repo.transact(fn ->
            with {:ok, current, %{fence: ^fence} = snapshot} <- work(connection, id, job.id) do
              publish(current, snapshot, outcome)
            else
              _ -> {:error, :stale}
            end
          end)

        case result do
          {:ok, action} ->
            broadcast(id)
            action

          {:error, :stale} ->
            :ok

          {:error, _} ->
            {:error, :sync_storage_unavailable}
        end

      {:ok, {:wait, until}} ->
        {:snooze, max(until - now(), 1)}

      {:error, :stale} ->
        :ok

      {:error, _} ->
        {:error, :sync_storage_unavailable}
    end
  end

  defp work(connection, id, job_id) do
    with {:ok, target} <- target(connection, id, :update),
         %{job_id: ^job_id} = row <- snapshot(connection, id),
         true <- current?(row, target) do
      {:ok, target, row}
    else
      _ -> {:error, :stale}
    end
  end

  defp fetch(%{connection: row, repository: repository}) do
    with {:ok, token} <- PatCipher.open(row.ciphertext, row.id, row.github_id) do
      client = Application.get_env(:samgita, :github_console_client, PatClient)
      client.workflow_runs(token, repository)
    end
  end

  defp publish(target, snapshot, {:ok, %{repository: repo, runs: runs}}) when is_list(runs) do
    if repo.id == snapshot.repository_id && owner_matches?(repo.owner_id, target) do
      Repo.update!(
        change(snapshot,
          runs: Enum.take(runs, 20),
          owner_id: repo.owner_id,
          synced_at: DateTime.utc_now(),
          error_code: nil,
          job_id: nil,
          fence: nil
        )
      )

      {:ok, :ok}
    else
      publish(target, snapshot, {:error, :repository_changed})
    end
  end

  defp publish(%{connection: row}, snapshot, {:error, {:rate_limited, until}})
       when is_integer(until) do
    deadline = max(row.retry_at || 0, until)
    Repo.update!(change(row, retry_at: deadline))
    Repo.update!(change(snapshot, error_code: "rate_limited", fence: nil))
    {:ok, {:snooze, max(deadline - now(), 1)}}
  end

  defp publish(_target, snapshot, {:error, reason}) do
    code = if reason in @errors, do: reason, else: :unavailable
    Repo.update!(change(snapshot, error_code: Atom.to_string(code), job_id: nil, fence: nil))
    {:ok, {:cancel, code}}
  end

  defp target(%{id: id, credential_version: version}, repository_id, lock),
    do: Console.sync_target(id, version, repository_id, lock)

  defp target(_, _, _), do: {:error, :stale}

  defp snapshot(connection, repository_id),
    do: Repo.get_by(Snapshot, connection_id: connection.id, repository_id: repository_id)

  defp current?(nil, _), do: false

  defp current?(snapshot, target),
    do:
      snapshot.credential_version == target.connection.credential_version &&
        owner_matches?(snapshot.owner_id, target)

  defp owner_matches?(owner, target),
    do:
      is_nil(target.repository.required_owner_id) || owner == target.repository.required_owner_id

  defp empty, do: %{rows: [], synced_at: nil, status: :uninitialized, error: nil, active?: false}
  defp view(nil, _repo, _producer), do: empty()

  defp view(snapshot, repo, producer) do
    error = Enum.find(@errors, &(Atom.to_string(&1) == snapshot.error_code))

    {status, error} =
      cond do
        PatCatalog.active_job?(snapshot, producer) -> {:refreshing, error}
        snapshot.job_id != nil -> {:failed, :refresh_interrupted}
        error != nil -> {:failed, error}
        true -> {:ready, nil}
      end

    rows =
      Enum.map(snapshot.runs, fn r ->
        %{
          id: r["id"],
          name: r["name"],
          title: r["title"],
          number: r["number"],
          branch: r["branch"],
          event: r["event"],
          status: r["status"],
          conclusion: r["conclusion"],
          actor: r["actor"],
          updated_at: r["updated_at"],
          url: r["url"] || "https://github.com/#{repo.owner}/#{repo.name}/actions/runs/#{r["id"]}"
        }
      end)

    %{
      rows: rows,
      synced_at: snapshot.synced_at,
      status: status,
      error: error,
      active?: active?(snapshot)
    }
  end

  defp active?(snapshot) do
    snapshot.synced_at != nil && snapshot.error_code in [nil, "unavailable", "rate_limited"] &&
      Enum.any?(snapshot.runs, &(&1["status"] in @active && is_nil(&1["conclusion"])))
  end

  defp broadcast(id), do: Console.broadcast_repository(id, {:github_workflow_runs_changed, id})
  defp now, do: System.system_time(:second)
end
