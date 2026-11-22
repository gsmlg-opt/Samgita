defmodule Samgita.GitHub.PatCatalog do
  @moduledoc "Persisted PAT directory snapshots refreshed by an explicitly queued Styx job."
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]
  alias Samgita.Domain.{GitHubPatCatalog, GitHubPatConnection}
  alias Samgita.GitHub.{Console, PatCipher, PatClient}
  alias Samgita.Repo
  alias Samgita.Workers.GitHubPatCatalogWorker

  @active_states ~w(available scheduled executing retryable suspended)
  @errors ~w(unavailable invalid_response invalid_pagination catalog_too_large invalid_token forbidden not_found unapproved_destination storage_key_unavailable unreadable_token rate_limit_recovery_required refresh_interrupted)a

  def producer do
    Styx.check_queue(queue: :hub_github)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  def directory(row) do
    case Repo.get(GitHubPatCatalog, row.id) do
      %{credential_version: version, data: data} when version == row.credential_version ->
        decode(data)

      _ ->
        decode(nil)
    end
  end

  def read(row, producer \\ nil) do
    case Repo.get(GitHubPatCatalog, row.id) do
      %{credential_version: version} = snapshot when version == row.credential_version ->
        catalog = decode(snapshot.data)
        interrupted = snapshot.status == "refreshing" && !active_job?(snapshot, producer)

        Map.merge(catalog, %{
          status: if(interrupted, do: :failed, else: status(snapshot.status)),
          error: if(interrupted, do: :refresh_interrupted, else: error(snapshot.error_code))
        })

      _ ->
        Map.merge(decode(nil), %{status: :uninitialized, error: nil})
    end
  end

  # The caller holds the connection lock and owns the surrounding transaction.
  def enqueue(row, mode, producer \\ nil) when mode in [:initial, :manual, :replace] do
    snapshot = Repo.get(GitHubPatCatalog, row.id)
    same_credential = snapshot && snapshot.credential_version == row.credential_version

    cond do
      same_credential && snapshot.status == "refreshing" && active_job?(snapshot, producer) ->
        {:ok, :unchanged}

      same_credential && mode == :initial ->
        {:ok, :unchanged}

      true ->
        queue(row, snapshot, mode, same_credential)
    end
  end

  defp queue(row, snapshot, mode, same_credential) do
    generation = Ecto.UUID.generate()

    args = %{
      "connection_id" => row.id,
      "credential_version" => row.credential_version,
      "generation" => generation
    }

    with {:ok, job} <- Styx.insert(GitHubPatCatalogWorker.new(args), retry: false) do
      attrs = %{
        credential_version: row.credential_version,
        generation: generation,
        status: "refreshing",
        data: if(same_credential && mode != :replace, do: snapshot.data),
        error_code: nil,
        prune: mode == :replace || (same_credential && snapshot.prune) || false,
        fence: nil,
        job_id: job.id
      }

      case Repo.insert_or_update(
             change(snapshot || %GitHubPatCatalog{connection_id: row.id}, attrs)
           ) do
        {:ok, _} -> {:ok, :queued}
        {:error, _} -> {:error, :catalog_storage_unavailable}
      end
    else
      {:error, _} -> {:error, :enqueue_failed}
    end
  end

  def perform(%Styx.Job{args: args} = job) do
    case claim(args) do
      {:ok, {:work, row, snapshot}} ->
        settle(row, snapshot, fetch(row), job)

      {:ok, {:wait, until}} ->
        {:snooze, max(until - now(), 1)}

      {:ok, :stale} ->
        :ok

      {:error, _} ->
        {:error, :catalog_storage_unavailable}
    end
  end

  defp claim(args) do
    Repo.transact(fn ->
      row = locked_connection(args["connection_id"], true)
      snapshot = Repo.get(GitHubPatCatalog, args["connection_id"])

      cond do
        !current?(row, snapshot, args) || snapshot.status != "refreshing" ->
          {:ok, :stale}

        is_integer(row.retry_at) && row.retry_at > now() ->
          {:ok, {:wait, row.retry_at}}

        true ->
          with {:ok, snapshot} <- Repo.update(change(snapshot, fence: Ecto.UUID.generate())) do
            {:ok, {:work, row, snapshot}}
          end
      end
    end)
  end

  defp fetch(row) do
    with {:ok, token} <- PatCipher.open(row.ciphertext, row.id, row.github_id) do
      client = Application.get_env(:samgita, :github_console_client, PatClient)
      client.catalog(token)
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp settle(row, snapshot, outcome, job) do
    result =
      Repo.transact(fn ->
        current = locked_connection(row.id)
        latest = Repo.get(GitHubPatCatalog, row.id)

        if current?(current, latest, Map.from_struct(snapshot)) && latest.fence == snapshot.fence do
          publish(current, latest, outcome, job)
        else
          {:ok, :stale}
        end
      end)

    case result do
      {:ok, :stale} ->
        :ok

      {:ok, action} ->
        Phoenix.PubSub.broadcast(Samgita.PubSub, "github:console", :github_catalog_changed)
        action

      {:error, _} ->
        {:error, :catalog_storage_unavailable}
    end
  end

  defp publish(row, snapshot, {:ok, catalog}, job) do
    case encode(catalog) do
      {:ok, data} ->
        with :ok <- refresh_selected(row, decode(data), snapshot.prune),
             {:ok, _} <-
               Repo.update(
                 change(snapshot,
                   status: "ready",
                   data: data,
                   error_code: nil,
                   prune: false,
                   fence: nil
                 )
               ) do
          {:ok, :ok}
        end

      {:error, reason} ->
        publish(row, snapshot, {:error, reason}, job)
    end
  end

  defp publish(row, snapshot, {:error, {:rate_limited, until}}, _job) when is_integer(until) do
    retry_at = max(row.retry_at || 0, until)

    with {:ok, _} <- Repo.update(change(row, retry_at: retry_at)),
         {:ok, _} <- Repo.update(change(snapshot, error_code: "rate_limited", fence: nil)) do
      {:ok, {:snooze, max(retry_at - now(), 1)}}
    end
  end

  defp publish(_row, snapshot, {:error, reason}, job) do
    code = if reason in @errors, do: reason, else: :unavailable
    retry? = code == :unavailable && job.attempt < job.max_attempts
    state = if retry?, do: "refreshing", else: "failed"

    with {:ok, _} <-
           Repo.update(
             change(snapshot, status: state, error_code: Atom.to_string(code), fence: nil)
           ) do
      action = if retry?, do: {:error, code}, else: {:cancel, code}
      {:ok, action}
    end
  end

  defp publish(row, snapshot, _outcome, job),
    do: publish(row, snapshot, {:error, :invalid_response}, job)

  defp refresh_selected(row, catalog, prune) do
    row = Repo.preload(row, [:selections, :owner_selections])
    Console.catalog_refreshed(row, catalog, prune)
  end

  defp current?(nil, _, _), do: false
  defp current?(_, nil, _), do: false

  defp current?(row, snapshot, args) do
    credential = args["credential_version"] || args[:credential_version]
    generation = args["generation"] || args[:generation]

    row.credential_version == credential && snapshot.credential_version == credential &&
      snapshot.generation == generation
  end

  defp locked_connection(id, ciphertext \\ false) do
    query = from c in GitHubPatConnection, where: c.id == ^id, lock: "FOR UPDATE"
    query = if ciphertext, do: select_merge(query, [c], %{ciphertext: c.ciphertext}), else: query
    Repo.one(query)
  end

  @doc false
  def active_job?(%{job_id: nil}, _producer), do: false

  def active_job?(%{job_id: id}, producer) do
    case Repo.get(Styx.Job, id) do
      %{state: state} = job when state in @active_states -> !previous_producer?(job, producer)
      _ -> false
    end
  end

  @doc false
  def previous_producer?(
        %{
          state: "executing",
          worker: worker,
          queue: "hub_github",
          attempted_by: [node, old_uuid],
          attempted_at: %DateTime{} = attempted_at
        },
        %{node: node, uuid: current_uuid, queue: queue, started_at: %DateTime{} = started_at}
      )
      when worker in [
             "Samgita.Workers.GitHubPatCatalogWorker",
             "Samgita.Workers.GitHubPatRepositorySyncWorker",
             "Samgita.Workers.GitHubPatWorkflowWorker"
           ] and
             queue in [:hub_github, "hub_github"] and is_binary(node) and node != "" and
             is_binary(old_uuid) and old_uuid != "" and is_binary(current_uuid) and
             current_uuid != "" do
    # The observation may predate another restart. Only an earlier job is provably orphaned.
    old_uuid != current_uuid && DateTime.compare(attempted_at, started_at) == :lt
  end

  def previous_producer?(_, _), do: false

  defp status("ready"), do: :ready
  defp status("refreshing"), do: :refreshing
  defp status(_), do: :failed

  defp error(nil), do: nil
  defp error("rate_limited"), do: :rate_limited
  defp error(value), do: Enum.find(@errors, :unavailable, &(Atom.to_string(&1) == value))

  defp encode(%{owners: owners, repositories: repositories} = catalog)
       when is_list(owners) and is_list(repositories) do
    data = %{
      "owners" => Enum.map(owners, &%{"id" => &1.id, "login" => &1.login}),
      "repositories" =>
        Enum.map(
          repositories,
          &%{"id" => &1.id, "owner_id" => &1.owner_id, "owner" => &1.owner, "name" => &1.name}
        ),
      "memberships_available" => Map.get(catalog, :memberships_available, true) == true
    }

    {:ok, data}
  rescue
    _ -> {:error, :invalid_response}
  end

  defp encode(_), do: {:error, :invalid_response}

  defp decode(nil), do: %{owners: [], repositories: [], memberships_available: true}

  defp decode(data) do
    %{
      owners: Enum.map(data["owners"], &%{id: &1["id"], login: &1["login"]}),
      repositories:
        Enum.map(
          data["repositories"],
          &%{id: &1["id"], owner_id: &1["owner_id"], owner: &1["owner"], name: &1["name"]}
        ),
      memberships_available: data["memberships_available"]
    }
  end

  defp now, do: System.system_time(:second)
end
