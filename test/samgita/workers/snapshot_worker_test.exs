defmodule Samgita.Workers.SnapshotWorkerTest do
  use Samgita.DataCase, async: false

  alias Samgita.Workers.SnapshotWorker
  alias Samgita.Projects
  alias Samgita.Domain.Snapshot

  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Samgita.Repo, {:shared, self()})

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

    assert length(snapshots) == 1
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

    assert length(snapshots) == 0
  end
end
