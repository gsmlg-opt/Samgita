defmodule Samgita.GitHub.ConsoleSelectionTest do
  use Samgita.DataCase, async: false
  alias Samgita.Domain.GitHubPatCatalog
  alias Samgita.GitHub.Console
  alias Samgita.Workers.GitHubPatCatalogWorker

  defmodule Catalog do
    def user(_), do: {:ok, %{id: 5, login: "operator"}}

    def catalog(_) do
      Process.put(:catalog_reads, Process.get(:catalog_reads, 0) + 1)
      repos = Process.get(__MODULE__, [])
      owners = Enum.uniq_by(Enum.map(repos, &%{id: &1.owner_id, login: &1.owner}), & &1.id)
      {:ok, %{owners: owners, repositories: repos}}
    end
  end

  setup do
    for {key, value} <- [
          github_console_client: Catalog,
          github_pat_key_base: String.duplicate("fixture", 8)
        ] do
      original = Application.fetch_env(:samgita, key)
      Application.put_env(:samgita, key, value)

      on_exit(fn ->
        case original do
          {:ok, previous} -> Application.put_env(:samgita, key, previous)
          :error -> Application.delete_env(:samgita, key)
        end
      end)
    end

    :ok
  end

  test "only the catalog job updates stored names and owners; saving uses the last published list" do
    old_repo = %{id: 41, owner: "sample", owner_id: 7, name: "old-name"}
    transferred = %{old_repo | owner: "another-org", owner_id: 9, name: "new-name"}
    Process.put(Catalog, [old_repo])
    :ok = Console.connect("local-fixture", nil)
    assert :ok = perform_refresh()
    :ok = Console.save_selection(Console.version(), [old_repo.id])
    previous_version = Console.version()

    Process.put(Catalog, [transferred, %{old_repo | id: 42}])
    assert {:ok, %{repositories: [^old_repo]}} = Console.catalog(previous_version)
    assert {:error, :invalid_selection} = Console.save_selection(previous_version, [42])
    assert :ok = Console.refresh_catalog(previous_version)
    assert Console.settings().repositories == [old_repo]
    assert Process.get(:catalog_reads) == 1

    assert :ok = perform_refresh()
    assert Console.settings().repositories == [transferred]
    assert previous_version == Console.version()
    assert :ok = Console.save_selection(previous_version, [42])
    assert {:error, :stale} = Console.save_selection(previous_version, [])
    assert Process.get(:catalog_reads) == 2
  end

  test "organization scope follows additions, removals and transfers while individual choices follow the repository" do
    first = %{id: 10, owner: "studio", owner_id: 7, name: "first"}
    second = %{first | id: 11, name: "second"}
    third = %{first | id: 12, name: "third"}
    Process.put(Catalog, [first, second, third])
    :ok = Console.connect("local-fixture", nil)
    :ok = perform_refresh()

    assert :ok = Console.save_selection(Console.version(), [10], [7])
    assert Enum.map(Console.settings().repositories, & &1.id) == [10, 11, 12]

    moved = %{first | owner: "other", owner_id: 8}
    added = %{first | id: 13, name: "fourth"}
    Process.put(Catalog, [moved, added, %{third | owner: "other", owner_id: 8}])
    :ok = Console.refresh_catalog(Console.version())
    :ok = perform_refresh()

    assert %{repositories: repos, repository_ids: [10], selected_owners: [%{id: 7}]} =
             Console.settings()

    assert Enum.map(repos, & &1.id) == [10, 13]
    assert :ok = Console.save_selection(Console.version(), [10], [])
    assert Console.settings().repositories == [moved]
  end

  defp perform_refresh do
    %{connection: connection} = Console.settings()
    snapshot = Repo.get!(GitHubPatCatalog, connection.id)
    GitHubPatCatalogWorker.perform(Repo.get!(Styx.Job, snapshot.job_id))
  end
end
