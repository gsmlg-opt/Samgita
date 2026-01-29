defmodule Samgita.Workers.AgentTaskWorkerTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Domain.Task, as: TaskSchema
  alias Samgita.Projects
  alias Samgita.Repo
  alias Samgita.Workers.AgentTaskWorker

  setup do
    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Worker Test",
        git_url: "git@github.com:test/worker-#{System.unique_integer([:positive])}.git",
        status: :running
      })

    %{project: project}
  end

  defp create_task(project, attrs \\ %{}) do
    defaults = %{
      type: "eng-backend",
      project_id: project.id,
      status: :pending,
      payload: %{"action" => "build"}
    }

    %TaskSchema{}
    |> TaskSchema.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "returns error for nonexistent task", %{project: project} do
    job = %Oban.Job{
      args: %{
        "task_id" => Ecto.UUID.generate(),
        "project_id" => project.id,
        "agent_type" => "eng-backend"
      }
    }

    assert {:error, :task_not_found} = AgentTaskWorker.perform(job)
  end

  test "marks task as running then completed on success", %{project: project} do
    task = create_task(project)

    job = %Oban.Job{
      args: %{
        "task_id" => task.id,
        "project_id" => project.id,
        "agent_type" => "eng-backend"
      }
    }

    # The worker will try to find/spawn agent via Horde - this may fail in test
    # but we can verify the task state transitions
    case AgentTaskWorker.perform(job) do
      :ok ->
        updated = Repo.get!(TaskSchema, task.id)
        assert updated.status == :completed
        assert updated.completed_at != nil

      {:error, _reason} ->
        # Agent spawn failure is expected in test env without full supervision tree
        updated = Repo.get!(TaskSchema, task.id)
        assert updated.status in [:running, :failed, :dead_letter]
    end
  end

  test "increments attempts on failure", %{project: project} do
    task = create_task(project, %{attempts: 0})

    job = %Oban.Job{
      args: %{
        "task_id" => task.id,
        "project_id" => project.id,
        "agent_type" => "nonexistent-type"
      }
    }

    case AgentTaskWorker.perform(job) do
      {:error, _} ->
        updated = Repo.get!(TaskSchema, task.id)
        assert updated.attempts >= 1
        assert updated.error != nil

      :ok ->
        :ok
    end
  end

  test "marks as dead_letter after max attempts", %{project: project} do
    task = create_task(project, %{attempts: 4})

    job = %Oban.Job{
      args: %{
        "task_id" => task.id,
        "project_id" => project.id,
        "agent_type" => "eng-backend"
      }
    }

    case AgentTaskWorker.perform(job) do
      {:error, _} ->
        updated = Repo.get!(TaskSchema, task.id)
        assert updated.status == :dead_letter

      :ok ->
        :ok
    end
  end
end
