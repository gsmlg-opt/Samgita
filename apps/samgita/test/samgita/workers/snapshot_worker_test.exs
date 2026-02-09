defmodule Samgita.Workers.SnapshotWorkerTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Domain.Snapshot
  alias Samgita.Projects
  alias Samgita.Repo
  alias Samgita.Workers.SnapshotWorker

  import Ecto.Query

  setup do
    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Snapshot Test",
        git_url: "git@github.com:test/snapshot-#{System.unique_integer([:positive])}.git",
        status: :running
      })

    %{project: project}
  end

  test "creates snapshot for running project", %{project: project} do
    assert :ok = SnapshotWorker.perform(%Oban.Job{args: %{}})

    snapshots =
      Snapshot
      |> where(project_id: ^project.id)
      |> Repo.all()

    assert [_] = snapshots
    assert hd(snapshots).phase == "bootstrap"
  end

  test "does not create snapshot for non-running project" do
    {:ok, project} =
      Projects.create_project(%{
        name: "Paused",
        git_url: "git@github.com:test/paused-#{System.unique_integer([:positive])}.git",
        status: :paused
      })

    assert :ok = SnapshotWorker.perform(%Oban.Job{args: %{}})

    snapshots =
      Snapshot
      |> where(project_id: ^project.id)
      |> Repo.all()

    assert snapshots == []
  end

  test "latest_snapshot/1 returns nil when no snapshots", %{project: _project} do
    project_id = Ecto.UUID.generate()
    assert is_nil(SnapshotWorker.latest_snapshot(project_id))
  end

  test "latest_snapshot/1 returns the most recent snapshot", %{project: project} do
    # Create a snapshot in bootstrap phase
    assert :ok = SnapshotWorker.perform(%Oban.Job{args: %{}})

    snapshot = SnapshotWorker.latest_snapshot(project.id)
    assert snapshot != nil
    assert snapshot.phase == "bootstrap"
    assert snapshot.project_id == project.id
  end

  test "restore_from_snapshot/1 restores project phase", %{project: project} do
    # Create a snapshot in bootstrap phase
    assert :ok = SnapshotWorker.perform(%Oban.Job{args: %{}})

    # Advance project to development
    {:ok, _} = Projects.update_project(project, %{phase: :development})

    # Restore from snapshot (bootstrap)
    assert {:ok, %{project: restored, snapshot: _}} =
             SnapshotWorker.restore_from_snapshot(project.id)

    assert restored.phase == :bootstrap
  end

  test "restore_from_snapshot/1 returns error when no snapshots" do
    project_id = Ecto.UUID.generate()
    assert {:error, :no_snapshot} = SnapshotWorker.restore_from_snapshot(project_id)
  end

  test "cleanup_old_snapshots keeps only the specified number", %{project: project} do
    # Create 12 snapshots
    for _ <- 1..12 do
      SnapshotWorker.perform(%Oban.Job{args: %{}})
    end

    snapshots =
      Snapshot
      |> where(project_id: ^project.id)
      |> Repo.all()

    # Default keep is 10, so should have cleaned up 2
    assert length(snapshots) == 10
  end
end
