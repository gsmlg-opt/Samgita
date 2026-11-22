defmodule Samgita.GitHub.PatCatalogFunctionalTest do
  use Samgita.DataCase, async: false
  alias Samgita.Domain.{GitHubPatCatalog, GitHubPatConnection}
  alias Samgita.GitHub.{PatCatalog, PatCipher}
  alias Samgita.Workers.GitHubPatCatalogWorker

  defmodule FixtureClient do
    def catalog(_) do
      Process.put(:catalog_requests, Process.get(:catalog_requests, 0) + 1)

      case Process.get(:catalog_outcome) do
        callback when is_function(callback, 0) -> callback.()
        value -> value
      end
    end
  end

  setup do
    for {key, value} <- [
          github_console_client: FixtureClient,
          github_pat_key_base: String.duplicate("catalog-fixture", 4)
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

    id = Ecto.UUID.generate()
    {:ok, ciphertext} = PatCipher.seal("synthetic-catalog-fixture", id, 5)

    row =
      Repo.insert!(%GitHubPatConnection{
        id: id,
        github_id: 5,
        login: "operator",
        ciphertext: ciphertext,
        credential_version: Ecto.UUID.generate(),
        version: Ecto.UUID.generate()
      })

    Process.put(:catalog_requests, 0)
    Process.put(:catalog_outcome, {:ok, catalog()})
    {:ok, row: row}
  end

  test "initial and concurrent refresh requests coalesce without doing directory reads", %{
    row: row
  } do
    assert PatCatalog.read(row).status == :uninitialized
    assert {:ok, :queued} = enqueue(row, :initial)
    assert {:ok, :unchanged} = enqueue(row, :initial)
    assert {:ok, :unchanged} = enqueue(row, :manual)
    assert PatCatalog.read(row).status == :refreshing
    assert Repo.aggregate(Styx.Job, :count) == 1
    assert Process.get(:catalog_requests) == 0
  end

  test "successful worker publishes the complete persisted directory", %{row: row} do
    {:ok, :queued} = enqueue(row, :initial)
    assert :ok = GitHubPatCatalogWorker.perform(job(row))
    assert %{status: :ready, error: nil, repositories: [%{id: 41}]} = PatCatalog.read(row)
    assert PatCatalog.read(row).owners == [%{id: 7, login: "sample"}]
    assert Process.get(:catalog_requests) == 1
    assert {:ok, :unchanged} = enqueue(row, :initial)
  end

  test "ordinary refresh failures preserve the old snapshot through finite job retries", %{
    row: row
  } do
    {:ok, :queued} = enqueue(row, :initial)
    assert :ok = GitHubPatCatalogWorker.perform(job(row))
    {:ok, :queued} = enqueue(row, :manual)
    Process.put(:catalog_outcome, {:error, :unavailable})
    job = job(row)

    assert {:error, :unavailable} = GitHubPatCatalogWorker.perform(%{job | attempt: 1})

    assert %{status: :refreshing, error: :unavailable, repositories: [%{id: 41}]} =
             PatCatalog.read(row)

    assert {:cancel, :unavailable} =
             GitHubPatCatalogWorker.perform(%{job | attempt: job.max_attempts})

    assert %{status: :failed, error: :unavailable, repositories: [%{id: 41}]} =
             PatCatalog.read(row)
  end

  test "a connection cooldown delays the directory job before any remote read", %{row: row} do
    row = Repo.update!(change(row, retry_at: System.system_time(:second) + 120))
    {:ok, :queued} = enqueue(row, :initial)
    assert {:snooze, delay} = GitHubPatCatalogWorker.perform(job(row))
    assert delay in 119..120
    assert Process.get(:catalog_requests) == 0
  end

  test "a replaced directory generation ignores a late response", %{row: row} do
    {:ok, :queued} = enqueue(row, :initial)
    old_job = job(row)

    Process.put(:catalog_outcome, fn ->
      row = Repo.update!(change(row, credential_version: Ecto.UUID.generate()))
      assert {:ok, :queued} = enqueue(row, :replace)
      {:ok, catalog()}
    end)

    assert :ok = GitHubPatCatalogWorker.perform(old_job)
    current = Repo.get!(GitHubPatConnection, row.id)
    assert %{status: :refreshing, repositories: []} = PatCatalog.read(current)
    assert Repo.get!(GitHubPatCatalog, row.id).prune
    assert :ok = GitHubPatCatalogWorker.perform(old_job)
    assert Process.get(:catalog_requests) == 1
  end

  test "replacement pruning survives a failed job and a later manual retry", %{row: row} do
    {:ok, :queued} = enqueue(row, :replace)
    Process.put(:catalog_outcome, {:error, :unavailable})
    initial_job = job(row)

    assert {:cancel, :unavailable} =
             GitHubPatCatalogWorker.perform(%{initial_job | attempt: initial_job.max_attempts})

    assert Repo.get!(GitHubPatCatalog, row.id).prune
    assert {:ok, :queued} = enqueue(row, :manual)
    assert Repo.get!(GitHubPatCatalog, row.id).prune
    Process.put(:catalog_outcome, {:ok, catalog()})
    assert :ok = GitHubPatCatalogWorker.perform(job(row))
    refute Repo.get!(GitHubPatCatalog, row.id).prune
  end

  test "a terminal job makes an interrupted refresh recoverable by an explicit request", %{
    row: row
  } do
    {:ok, :queued} = enqueue(row, :initial)
    Repo.update!(change(job(row), state: "discarded"))
    assert PatCatalog.read(row).status == :failed
    assert PatCatalog.read(row).error == :refresh_interrupted
    assert {:ok, :queued} = enqueue(row, :manual)
    assert PatCatalog.read(row).status == :refreshing
  end

  test "a previous local producer incarnation allows an explicit recovery", %{row: row} do
    {:ok, :queued} = enqueue(row, :initial)

    old_job =
      Repo.update!(
        change(job(row),
          state: "executing",
          attempted_by: ["local-node", "old-producer"],
          attempted_at: ~U[2026-11-20 00:00:00.000000Z]
        )
      )

    producer = %{
      node: "local-node",
      uuid: "current-producer",
      queue: "hub_github",
      started_at: ~U[2026-11-21 00:00:00.000000Z]
    }

    assert %{status: :failed, error: :refresh_interrupted} = PatCatalog.read(row, producer)
    assert {:ok, :queued} = enqueue(row, :manual, producer)
    assert job(row).id != old_job.id
    assert :ok = GitHubPatCatalogWorker.perform(old_job)
    assert Process.get(:catalog_requests) == 0
  end

  test "current, remote, and unconfirmed executing producers stay coalesced", %{row: row} do
    {:ok, :queued} = enqueue(row, :initial)

    Repo.update!(
      change(job(row),
        state: "executing",
        attempted_by: ["local-node", "current-producer"],
        attempted_at: ~U[2026-11-20 00:00:00.000000Z]
      )
    )

    for producer <- [
          %{
            node: "local-node",
            uuid: "current-producer",
            queue: "hub_github",
            started_at: ~U[2026-11-21 00:00:00.000000Z]
          },
          %{
            node: "remote-node",
            uuid: "another-producer",
            queue: "hub_github",
            started_at: ~U[2026-11-21 00:00:00.000000Z]
          },
          %{
            node: "local-node",
            uuid: "new-producer",
            queue: "hub_github",
            started_at: ~U[2026-11-19 00:00:00.000000Z]
          },
          %{node: "local-node", uuid: "new-producer", queue: "hub_github"},
          nil,
          %{}
        ] do
      assert PatCatalog.read(row, producer).status == :refreshing
      assert {:ok, :unchanged} = enqueue(row, :manual, producer)
    end
  end

  defp enqueue(row, mode, producer \\ nil) do
    Repo.transact(fn ->
      row = Repo.one!(from c in GitHubPatConnection, where: c.id == ^row.id, lock: "FOR UPDATE")
      PatCatalog.enqueue(row, mode, producer)
    end)
  end

  defp job(row) do
    snapshot = Repo.get!(GitHubPatCatalog, row.id)
    Repo.get!(Styx.Job, snapshot.job_id)
  end

  defp catalog do
    %{
      owners: [%{id: 7, login: "sample"}],
      repositories: [%{id: 41, owner_id: 7, owner: "sample", name: "one"}],
      memberships_available: true
    }
  end
end
