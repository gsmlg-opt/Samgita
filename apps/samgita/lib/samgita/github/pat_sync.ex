defmodule Samgita.GitHub.PatSync do
  @moduledoc "Explicit and scheduled GitHub reads published as atomic per-repository snapshots."
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]
  alias Samgita.Domain.{GitHubPatItem, GitHubPatRepositorySync}
  alias Samgita.GitHub.{Console, PatCatalog, PatCipher, PatClient}
  alias Samgita.Repo
  alias Samgita.Workers.{GitHubPatRepositorySyncWorker, GitHubPatSyncWorker}

  @active_states ~w(available scheduled executing retryable suspended)
  @errors ~w(unavailable invalid_response invalid_pagination repository_changed invalid_token forbidden not_found unapproved_destination storage_key_unavailable unreadable_token rate_limit_recovery_required)a

  def request, do: request_mode("open")
  def request_missing, do: request_mode("missing")

  def request_repository(connection, repository_id, mode \\ :normal)
      when mode in [:normal, :replace] do
    producer = if mode != :replace, do: PatCatalog.producer()

    case enqueue_repository(connection, repository_id, mode, producer) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp request_mode(mode) do
    case Styx.insert(GitHubPatSyncWorker.new(%{"mode" => mode}), retry: false) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :sync_enqueue_failed}
    end
  end

  def dispatch(%Styx.Job{args: args}) do
    settings = Console.settings()
    producer = PatCatalog.producer()

    case settings.connection do
      nil ->
        :ok

      connection ->
        {result, queued?} =
          Enum.reduce_while(settings.repositories, {:ok, false}, fn repository, {:ok, queued?} ->
            case enqueue_repository(
                   connection,
                   repository.id,
                   Map.get(args, "mode", "open"),
                   producer
                 ) do
              {:ok, :queued} ->
                {:cont, {:ok, true}}

              {:ok, :unchanged} ->
                {:cont, {:ok, queued?}}

              {:error, :stale} ->
                {:cont, {:ok, queued?}}

              {:error, _} ->
                {:halt, {{:error, :sync_enqueue_failed}, queued?}}
            end
          end)

        if queued?, do: broadcast()
        result
    end
  end

  defp enqueue_repository(connection, repository_id, mode, producer) do
    Repo.transact(fn ->
      with {:ok, target} <-
             Console.sync_target(
               connection.id,
               connection.credential_version,
               repository_id,
               :update
             ) do
        sync = sync(connection.id, repository_id)
        same_credential = sync && sync.credential_version == connection.credential_version
        existing = if same_credential && sync.job_id, do: Repo.get(Styx.Job, sync.job_id)
        owner = target.repository.required_owner_id

        published? =
          same_credential && sync.synced_at != nil && (is_nil(owner) || sync.owner_id == owner)

        cond do
          mode == "missing" && published? ->
            {:ok, :unchanged}

          mode != :replace && active?(existing, producer) ->
            {:ok, :unchanged}

          true ->
            queue_repository(connection, repository_id, sync, same_credential)
        end
      end
    end)
  end

  defp queue_repository(connection, repository_id, sync, same_credential) do
    args = %{
      "connection_id" => connection.id,
      "credential_version" => connection.credential_version,
      "repository_id" => repository_id,
      "mode" => "open"
    }

    with {:ok, job} <- Styx.insert(GitHubPatRepositorySyncWorker.new(args), retry: false) do
      row =
        sync ||
          %GitHubPatRepositorySync{connection_id: connection.id, repository_id: repository_id}

      attrs = %{
        credential_version: connection.credential_version,
        job_id: job.id,
        error_code: nil,
        synced_at: if(same_credential, do: row.synced_at),
        owner_id: if(same_credential, do: row.owner_id)
      }

      case Repo.insert_or_update(change(row, attrs)) do
        {:ok, _} -> {:ok, :queued}
        {:error, _} -> {:error, :sync_storage_unavailable}
      end
    else
      {:error, _} -> {:error, :sync_enqueue_failed}
    end
  end

  def perform(%Styx.Job{} = job) do
    case claim(job) do
      {:ok, {:work, target}} ->
        started_at = DateTime.utc_now()
        result = fetch(target)
        settle(job, started_at, result)

      {:ok, {:wait, until}} ->
        {:snooze, max(until - now(), 1)}

      {:error, :stale} ->
        :ok

      {:error, _} ->
        {:error, :sync_storage_unavailable}
    end
  end

  defp claim(job) do
    Repo.transact(fn ->
      with {:ok, target} <- target(job.args),
           {:ok, _sync} <- current_sync(job) do
        if is_integer(target.connection.retry_at) && target.connection.retry_at > now(),
          do: {:ok, {:wait, target.connection.retry_at}},
          else: {:ok, {:work, target}}
      end
    end)
  end

  defp fetch(target) do
    row = target.connection

    with {:ok, token} <- PatCipher.open(row.ciphertext, row.id, row.github_id) do
      client = Application.get_env(:samgita, :github_console_client, PatClient)
      client.sync_repository(token, target.repository)
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp settle(job, started_at, result) do
    committed =
      Repo.transact(fn ->
        with {:ok, target} <- target(job.args),
             {:ok, sync} <- current_sync(job) do
          if is_nil(sync.synced_at) || DateTime.compare(sync.synced_at, started_at) == :lt,
            do: publish(target, sync, result, job, started_at),
            else: {:error, :stale}
        end
      end)

    case committed do
      {:ok, action} ->
        broadcast()
        action

      {:error, :stale} ->
        :ok

      {:error, _} ->
        {:error, :sync_storage_unavailable}
    end
  end

  defp publish(target, sync, {:ok, %{repository: repository, items: items}}, _job, started_at) do
    required_owner = Map.get(target.repository, :required_owner_id)

    if repository.id == target.repository.id &&
         (is_nil(required_owner) || repository.owner_id == required_owner) do
      rows =
        items
        |> Enum.filter(&(&1.state == "open"))
        |> Enum.map(&item_row(&1, target.connection, repository.id))

      open_numbers = Enum.group_by(rows, & &1.kind, & &1.number)

      for kind <- ["issue", "pull_request"] do
        present = Map.get(open_numbers, kind, [])

        missing =
          from i in GitHubPatItem,
            where:
              i.connection_id == ^sync.connection_id and
                i.credential_version == ^sync.credential_version and
                i.repository_id == ^sync.repository_id and i.kind == ^kind and
                i.state == "open" and i.number not in ^present

        Repo.update_all(missing, set: [state: "closed"])
      end

      Enum.each(Enum.chunk_every(rows, 500), fn batch ->
        Repo.insert_all(GitHubPatItem, batch,
          on_conflict: {:replace_all_except, [:connection_id, :repository_id, :kind, :number]},
          conflict_target: [:connection_id, :repository_id, :kind, :number]
        )
      end)

      with {:ok, _} <-
             Repo.update(
               change(sync, synced_at: started_at, owner_id: repository.owner_id, error_code: nil)
             ) do
        {:ok, :ok}
      end
    else
      {:error, :stale}
    end
  end

  defp publish(target, sync, {:error, {:rate_limited, until}}, _job, _started_at)
       when is_integer(until) do
    retry_at = max(target.connection.retry_at || 0, until)

    with {:ok, _} <- Repo.update(change(target.connection, retry_at: retry_at)),
         {:ok, _} <- Repo.update(change(sync, error_code: "rate_limited")) do
      {:ok, {:snooze, max(retry_at - now(), 1)}}
    end
  end

  defp publish(_target, sync, {:error, reason}, job, _started_at) do
    code = if reason in @errors, do: reason, else: :unavailable
    retry? = code in [:unavailable, :repository_changed] && job.attempt < job.max_attempts

    with {:ok, _} <- Repo.update(change(sync, error_code: Atom.to_string(code))) do
      {:ok, if(retry?, do: {:error, code}, else: {:cancel, code})}
    end
  end

  defp publish(target, sync, _result, job, started_at),
    do: publish(target, sync, {:error, :invalid_response}, job, started_at)

  defp item_row(item, connection, repository_id) do
    {:ok, date, _} = DateTime.from_iso8601(item.updated_at)

    %{
      connection_id: connection.id,
      repository_id: repository_id,
      credential_version: connection.credential_version,
      kind: item.kind,
      number: item.number,
      title: item.title,
      state: item.state,
      author: item.author,
      issue_type: Map.get(item, :issue_type),
      labels: Map.get(item, :labels, []),
      label_colors: Map.get(item, :label_colors) || %{},
      head_sha: Map.get(item, :head_sha),
      github_updated_at: DateTime.from_unix!(DateTime.to_unix(date, :microsecond), :microsecond),
      url: item.url
    }
  end

  defp target(args),
    do:
      Console.sync_target(
        args["connection_id"],
        args["credential_version"],
        args["repository_id"],
        :update
      )

  defp sync(connection_id, repository_id),
    do:
      Repo.get_by(GitHubPatRepositorySync,
        connection_id: connection_id,
        repository_id: repository_id
      )

  defp current_sync(job) do
    credential = job.args["credential_version"]

    case sync(job.args["connection_id"], job.args["repository_id"]) do
      %{job_id: id, credential_version: version} = sync
      when id == job.id and version == credential ->
        {:ok, sync}

      _ ->
        {:error, :stale}
    end
  end

  defp active?(nil, _producer), do: false

  defp active?(job, producer) do
    job.state in @active_states && !PatCatalog.previous_producer?(job, producer)
  end

  defp broadcast,
    do: Phoenix.PubSub.broadcast(Samgita.PubSub, "github:console", :github_feed_changed)

  defp now, do: System.system_time(:second)
end
