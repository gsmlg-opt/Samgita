defmodule Samgita.GitHub.Console do
  @moduledoc "The operator console's GitHub connection, cached directory and repository choices."
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2, unique_constraint: 3]

  alias Samgita.Domain.{
    GitHubPatConnection,
    GitHubPatItem,
    GitHubPatOwnerSelection,
    GitHubPatRepositorySync,
    GitHubPatSelection,
    GitHubPatWorkflowSnapshot
  }

  alias Samgita.GitHub.{PatCatalog, PatCipher, PatClient, PatSync}
  alias Samgita.Repo

  @topic "github:console"

  def subscribe, do: Phoenix.PubSub.subscribe(Samgita.PubSub, @topic)

  def subscribe_repository(id), do: Phoenix.PubSub.subscribe(Samgita.PubSub, repository_topic(id))

  def unsubscribe_repository(id),
    do: Phoenix.PubSub.unsubscribe(Samgita.PubSub, repository_topic(id))

  def broadcast_repository(id, message),
    do: Phoenix.PubSub.broadcast(Samgita.PubSub, repository_topic(id), message)

  defp repository_topic(id), do: @topic <> ":repository:" <> Integer.to_string(id)

  def settings do
    {:ok, settings} = read_connection(fn row -> {:ok, selection_settings(row)} end)
    settings
  end

  def with_settings(expected, fun) do
    read_connection(fn row ->
      with :ok <- connected(row, expected), do: {:ok, fun.(selection_settings(row))}
    end)
  end

  def version, do: Repo.one(from c in GitHubPatConnection, select: c.version)

  def connect(token, expected) do
    with true <- PatClient.valid_token?(token),
         :ok <- check_version(version(), expected),
         {:ok, _} <- PatCipher.key_base(),
         {:ok, account} <- client().user(token) do
      mutate(expected, fn current -> save_connection(current, account, token) end)
    else
      false -> {:error, :invalid_token_input}
      error -> error
    end
  end

  defp save_connection(current, account, token) do
    connection = current || %GitHubPatConnection{id: Ecto.UUID.generate()}
    same_account? = connection.github_id == account.id

    with {:ok, encrypted} <- PatCipher.seal(token, connection.id, account.id) do
      changeset =
        connection
        |> change(%{
          github_id: account.id,
          login: account.login,
          ciphertext: encrypted,
          credential_version: Ecto.UUID.generate(),
          version: Ecto.UUID.generate(),
          retry_at: nil
        })
        |> unique_constraint(:id, name: :github_pat_singleton)

      case Repo.insert_or_update(changeset) do
        {:ok, row} ->
          if current do
            Repo.delete_all(from i in GitHubPatItem, where: i.connection_id == ^row.id)
            Repo.delete_all(from s in GitHubPatRepositorySync, where: s.connection_id == ^row.id)

            Repo.delete_all(
              from w in GitHubPatWorkflowSnapshot, where: w.connection_id == ^row.id
            )
          end

          if current && !same_account? do
            replace_rows(GitHubPatSelection, row.id, [])
            replace_rows(GitHubPatOwnerSelection, row.id, [])
          end

          PatCatalog.enqueue(row, if(same_account?, do: :replace, else: :initial))

        {:error, _conflict} ->
          {:error, :stale}
      end
    end
  end

  def remove(expected) do
    mutate(expected, fn
      nil -> {:error, :disconnected}
      row -> Repo.delete(row)
    end)
  end

  def ensure_catalog(expected), do: enqueue_catalog(expected, :initial)
  def refresh_catalog(expected), do: enqueue_catalog(expected, :manual)

  defp enqueue_catalog(expected, mode) do
    producer = PatCatalog.producer()

    mutate(expected, :github_catalog_changed, fn
      nil -> {:error, :disconnected}
      row -> PatCatalog.enqueue(row, mode, producer)
    end)
  end

  def catalog(expected) do
    producer = PatCatalog.producer()

    read_connection(fn row ->
      with :ok <- connected(row, expected) do
        catalog = PatCatalog.read(row, producer)
        listed_ids = MapSet.new(catalog.repositories, & &1.id)
        unlisted = Enum.reject(explicit_repositories(row), &MapSet.member?(listed_ids, &1.id))

        owners =
          (catalog.owners ++ selected_owners(row))
          |> Enum.uniq_by(& &1.id)
          |> Enum.sort_by(&String.downcase(&1.login))

        {:ok, Map.merge(catalog, %{owners: owners, unlisted_selections: unlisted})}
      end
    end)
  end

  def save_selection(expected, repository_ids),
    do: save_selection(expected, repository_ids, :keep)

  def save_selection(expected, repository_ids, owner_ids)
      when is_list(repository_ids) and (is_list(owner_ids) or owner_ids == :keep) do
    mutate(expected, fn
      nil ->
        {:error, :disconnected}

      connection ->
        row = preload_selections(connection)
        saved = explicit_repositories(row)
        owners = selected_owners(row)
        catalog = PatCatalog.directory(row)
        owner_ids = if owner_ids == :keep, do: Enum.map(owners, & &1.id), else: owner_ids

        with {:ok, selected} <- choose(repository_ids, catalog.repositories ++ saved),
             {:ok, selected_owners} <- choose(owner_ids, catalog.owners ++ owners) do
          if same_ids?(selected, saved) && same_ids?(selected_owners, owners) do
            {:ok, :unchanged}
          else
            write_choices(row.id, selected, selected_owners)

            with {:ok, updated} <- Repo.update(change(row, version: Ecto.UUID.generate())),
                 :ok <- PatSync.request_missing() do
              {:ok, updated}
            end
          end
        end
    end)
  end

  def save_selection(_, _, _), do: {:error, :invalid_selection}

  defp choose(ids, candidates) do
    ids = MapSet.new(ids)
    selected = candidates |> Enum.filter(&MapSet.member?(ids, &1.id)) |> Enum.uniq_by(& &1.id)

    if length(selected) == MapSet.size(ids),
      do: {:ok, selected},
      else: {:error, :invalid_selection}
  end

  defp same_ids?(left, right), do: MapSet.new(left, & &1.id) == MapSet.new(right, & &1.id)

  @doc false
  def catalog_refreshed(row, catalog, prune?) do
    # Called under the worker's connection lock in the same transaction as the new directory.
    saved = explicit_repositories(row)
    owners = selected_owners(row)
    repositories = update_choices(saved, catalog.repositories, prune?)
    refreshed_owners = update_choices(owners, catalog.owners, prune?)

    if repositories != saved || refreshed_owners != owners do
      write_choices(row.id, repositories, refreshed_owners)
    end

    if !same_ids?(repositories, saved) || !same_ids?(refreshed_owners, owners) do
      Repo.update!(change(row, version: Ecto.UUID.generate()))
    end

    if refreshed_owners != [] || (prune? && repositories != []) do
      PatSync.request_missing()
    else
      :ok
    end
  end

  defp update_choices(saved, listed, prune?) do
    by_id = Map.new(listed, &{&1.id, &1})

    Enum.flat_map(saved, fn choice ->
      case Map.fetch(by_id, choice.id) do
        {:ok, current} -> [current]
        :error when prune? -> []
        :error -> [choice]
      end
    end)
  end

  defp write_choices(connection_id, repositories, owners) do
    repo_rows =
      Enum.map(repositories, fn r ->
        %{
          connection_id: connection_id,
          github_id: r.id,
          owner_id: r.owner_id,
          owner: r.owner,
          name: r.name
        }
      end)

    owner_rows =
      Enum.map(owners, &%{connection_id: connection_id, owner_id: &1.id, login: &1.login})

    replace_rows(GitHubPatSelection, connection_id, repo_rows)
    replace_rows(GitHubPatOwnerSelection, connection_id, owner_rows)
  end

  defp replace_rows(schema, connection_id, rows) do
    Repo.delete_all(from r in schema, where: r.connection_id == ^connection_id)
    Enum.each(Enum.chunk_every(rows, 1000), &Repo.insert_all(schema, &1))
  end

  defp selection_settings(nil),
    do: %{
      connection: nil,
      version: nil,
      repositories: [],
      repository_ids: [],
      selected_owners: []
    }

  defp selection_settings(row) do
    explicit = explicit_repositories(row)
    owners = selected_owners(row)

    from_owners =
      case owners do
        [] ->
          []

        _ ->
          ids = MapSet.new(owners, & &1.id)
          Enum.filter(PatCatalog.directory(row).repositories, &MapSet.member?(ids, &1.owner_id))
      end

    repositories =
      (explicit ++ from_owners)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&{String.downcase(&1.owner), String.downcase(&1.name), &1.id})

    %{
      connection: Map.take(row, [:id, :login, :github_id, :credential_version]),
      version: row.version,
      repositories: repositories,
      repository_ids: Enum.map(explicit, & &1.id),
      selected_owners: owners
    }
  end

  defp explicit_repositories(row) do
    Enum.map(
      row.selections,
      &%{id: &1.github_id, owner_id: &1.owner_id, owner: &1.owner, name: &1.name}
    )
  end

  defp selected_owners(row),
    do: Enum.map(row.owner_selections, &%{id: &1.owner_id, login: &1.login})

  # A worker reads its target before HTTP and locks it again when publishing the result.
  def sync_target(id, credential, repository_id, lock \\ :share) when lock in [:share, :update] do
    query =
      from c in GitHubPatConnection,
        where: c.id == ^id and c.credential_version == ^credential,
        select_merge: %{ciphertext: c.ciphertext}

    query =
      if lock == :update,
        do: from(c in query, lock: "FOR UPDATE"),
        else: from(c in query, lock: "FOR SHARE")

    lookup = fn ->
      with %GitHubPatConnection{} = row <- query |> Repo.one() |> preload_selections(),
           settings = selection_settings(row),
           %{} = repo <- Enum.find(settings.repositories, &(&1.id == repository_id)) do
        owner = unless repository_id in settings.repository_ids, do: repo.owner_id
        {:ok, %{connection: row, repository: Map.put(repo, :required_owner_id, owner)}}
      else
        _ -> {:error, :stale}
      end
    end

    if Repo.in_transaction?(), do: lookup.(), else: Repo.transact(lookup)
  end

  # All writers lock the connection first. The short shared transaction sees matching
  # selections and directory; GitHub network calls always happen after it returns.
  defp read_connection(operation) do
    Repo.transact(fn ->
      query = from c in GitHubPatConnection, lock: "FOR SHARE"
      operation.(query |> Repo.one() |> preload_selections())
    end)
  end

  defp preload_selections(nil), do: nil

  defp preload_selections(row) do
    Repo.preload(row,
      selections: from(r in GitHubPatSelection, order_by: [r.owner, r.name, r.github_id]),
      owner_selections: from(o in GitHubPatOwnerSelection, order_by: [o.login, o.owner_id])
    )
  end

  defp mutate(expected, message \\ :github_console_changed, operation) do
    result =
      Repo.transact(fn ->
        row = Repo.one(from c in GitHubPatConnection, lock: "FOR UPDATE")
        with :ok <- check_version(row && row.version, expected), do: operation.(row)
      end)

    case result do
      {:ok, :unchanged} -> :ok
      {:ok, _} -> Phoenix.PubSub.broadcast(Samgita.PubSub, @topic, message)
      error -> error
    end
  end

  defp check_version(version, version), do: :ok
  defp check_version(_, _), do: {:error, :stale}

  defp connected(nil, _expected), do: {:error, :disconnected}
  defp connected(row, expected), do: check_version(row.version, expected)

  defp client, do: Application.get_env(:samgita, :github_console_client, PatClient)
end
