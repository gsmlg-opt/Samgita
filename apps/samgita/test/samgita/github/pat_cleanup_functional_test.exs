defmodule Samgita.GitHub.PatCleanupFunctionalTest do
  use Samgita.DataCase, async: false

  alias Samgita.Domain.{GitHubPatConnection, GitHubPatItem}
  alias Samgita.GitHub.PatCleanup
  alias Samgita.Workers.GitHubPatSyncWorker

  setup do
    connection =
      Repo.insert!(%GitHubPatConnection{
        github_id: 42,
        login: "fixture",
        ciphertext: <<0>>,
        credential_version: Ecto.UUID.generate(),
        version: Ecto.UUID.generate()
      })

    %{connection: connection}
  end

  test "the database sets the first cleanup fifteen days ahead", %{connection: connection} do
    now = DateTime.utc_now()
    assert_in_delta DateTime.diff(connection.next_cleanup_at, now), 15 * 86_400, 5
  end

  test "cleanup uses fifteen elapsed days across months and deletes only closed items", %{
    connection: connection
  } do
    due = ~U[2026-01-31 10:45:00.000000Z]
    connection = Repo.update!(change(connection, next_cleanup_at: due))
    insert_item(connection, 1, "issue", "closed")
    insert_item(connection, 2, "pull_request", "merged")
    insert_item(connection, 3, "pull_request", "closed")
    insert_item(connection, 4, "issue", "open")
    insert_item(connection, 5, "pull_request", "open")

    assert {:ok, 0} = PatCleanup.run_due(DateTime.add(due, -1))
    assert Repo.aggregate(GitHubPatItem, :count) == 5
    assert {:ok, 3} = PatCleanup.run_due(due)
    assert Repo.all(from i in GitHubPatItem, order_by: i.number, select: i.number) == [4, 5]
    assert Repo.reload!(connection).next_cleanup_at == ~U[2026-02-15 10:45:00.000000Z]

    insert_item(connection, 6, "issue", "closed")
    assert {:ok, 0} = PatCleanup.run_due(due)
    assert {:ok, 0} = PatCleanup.run_due(~U[2026-02-15 10:44:59.000000Z])
    assert {:ok, 1} = PatCleanup.run_due(~U[2026-02-15 10:45:00.000000Z])
    assert Repo.reload!(connection).next_cleanup_at == ~U[2026-03-02 10:45:00.000000Z]
  end

  test "the next automatic Styx tick catches up after downtime and preserves the cadence", %{
    connection: connection
  } do
    now = DateTime.utc_now()
    connection = Repo.update!(change(connection, next_cleanup_at: DateTime.add(now, -31, :day)))
    insert_item(connection, 1, "pull_request", "closed")

    assert :ok = GitHubPatSyncWorker.perform(%Styx.Job{args: %{"mode" => "open"}})
    assert Repo.aggregate(GitHubPatItem, :count) == 1
    assert :ok = GitHubPatSyncWorker.perform(%Styx.Job{args: %{}})
    assert Repo.aggregate(GitHubPatItem, :count) == 0
    assert Repo.reload!(connection).next_cleanup_at == DateTime.add(now, 14, :day)
  end

  defp insert_item(connection, number, kind, state) do
    Repo.insert!(%GitHubPatItem{
      connection_id: connection.id,
      repository_id: 1,
      credential_version: connection.credential_version,
      number: number,
      kind: kind,
      state: state,
      title: "Item #{number}",
      author: "fixture",
      url: "https://github.com/fixture/project",
      github_updated_at: DateTime.utc_now()
    })
  end
end
