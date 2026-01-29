defmodule SamgitaWeb.TaskControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Projects

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Task Test",
        git_url: "git@github.com:org/task-test-#{System.unique_integer([:positive])}.git"
      })

    %{project: project}
  end

  describe "index" do
    test "lists tasks for project", %{conn: conn, project: project} do
      {:ok, _task} = Projects.create_task(project.id, %{type: "build", priority: 1})
      conn = get(conn, ~p"/api/projects/#{project}/tasks")
      assert [task] = json_response(conn, 200)["data"]
      assert task["type"] == "build"
    end

    test "returns empty list for project with no tasks", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/tasks")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns 404 for nonexistent project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/tasks")
      assert json_response(conn, 404)
    end
  end

  describe "show" do
    test "shows task by id", %{conn: conn, project: project} do
      {:ok, task} = Projects.create_task(project.id, %{type: "test", priority: 2})
      conn = get(conn, ~p"/api/projects/#{project}/tasks/#{task}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == task.id
      assert data["type"] == "test"
      assert data["priority"] == 2
    end

    test "returns 404 for missing task", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/tasks/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "retry" do
    test "retries a failed task", %{conn: conn, project: project} do
      {:ok, task} =
        Projects.create_task(project.id, %{type: "build", status: :failed, attempts: 3})

      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      data = json_response(conn, 200)["data"]
      assert data["status"] == "pending"
      assert data["attempts"] == 0
    end

    test "retries a dead_letter task", %{conn: conn, project: project} do
      {:ok, task} =
        Projects.create_task(project.id, %{type: "deploy", status: :dead_letter, attempts: 5})

      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn, 200)["data"]["status"] == "pending"
    end

    test "rejects retry for pending task", %{conn: conn, project: project} do
      {:ok, task} = Projects.create_task(project.id, %{type: "lint", priority: 1})
      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn, 422)
    end

    test "rejects retry for completed task", %{conn: conn, project: project} do
      {:ok, task} =
        Projects.create_task(project.id, %{type: "test", status: :completed, priority: 1})

      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn, 422)
    end

    test "rejects retry for running task", %{conn: conn, project: project} do
      {:ok, task} =
        Projects.create_task(project.id, %{type: "build", status: :running, priority: 1})

      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn, 422)
    end

    test "returns 404 for nonexistent task", %{conn: conn, project: project} do
      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{Ecto.UUID.generate()}/retry")
      assert json_response(conn, 404)
    end
  end

  describe "integration scenarios" do
    test "list tasks shows tasks in priority order", %{conn: conn, project: project} do
      {:ok, _t1} = Projects.create_task(project.id, %{type: "test", priority: 3})
      {:ok, _t2} = Projects.create_task(project.id, %{type: "build", priority: 1})
      {:ok, _t3} = Projects.create_task(project.id, %{type: "deploy", priority: 2})

      conn = get(conn, ~p"/api/projects/#{project}/tasks")
      tasks = json_response(conn, 200)["data"]

      assert length(tasks) == 3
      priorities = Enum.map(tasks, & &1["priority"])
      assert priorities == Enum.sort(priorities)
    end

    test "list tasks filters by status", %{conn: conn, project: project} do
      {:ok, _t1} = Projects.create_task(project.id, %{type: "test", status: :pending})
      {:ok, _t2} = Projects.create_task(project.id, %{type: "build", status: :completed})
      {:ok, _t3} = Projects.create_task(project.id, %{type: "deploy", status: :failed})

      conn = get(conn, ~p"/api/projects/#{project}/tasks")
      tasks = json_response(conn, 200)["data"]
      assert length(tasks) == 3

      statuses = Enum.map(tasks, & &1["status"])
      assert "pending" in statuses
      assert "completed" in statuses
      assert "failed" in statuses
    end

    test "show task includes all fields", %{conn: conn, project: project} do
      {:ok, task} =
        Projects.create_task(project.id, %{
          type: "integration_test",
          priority: 5,
          status: :pending,
          payload: %{target: "api", suite: "full"}
        })

      conn = get(conn, ~p"/api/projects/#{project}/tasks/#{task}")
      data = json_response(conn, 200)["data"]

      assert data["id"] == task.id
      assert data["type"] == "integration_test"
      assert data["priority"] == 5
      assert data["status"] == "pending"
      assert data["payload"]["target"] == "api"
      assert data["payload"]["suite"] == "full"
      assert data["attempts"] == 0
    end

    test "create multiple tasks and verify persistence", %{conn: conn, project: project} do
      tasks =
        for i <- 1..10 do
          {:ok, task} =
            Projects.create_task(project.id, %{type: "task_#{i}", priority: rem(i, 3)})

          task
        end

      conn = get(conn, ~p"/api/projects/#{project}/tasks")
      fetched_tasks = json_response(conn, 200)["data"]

      assert length(fetched_tasks) == 10

      for task <- tasks do
        fetched = Enum.find(fetched_tasks, &(&1["id"] == task.id))
        assert fetched != nil
      end
    end

    test "retry task multiple times", %{conn: conn, project: project} do
      alias Samgita.Domain.Task, as: TaskSchema
      alias Samgita.Repo

      {:ok, task} = Projects.create_task(project.id, %{type: "flaky", status: :failed})

      # First retry
      conn1 = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn1, 200)["data"]["attempts"] == 0

      # Mark as failed again
      task = Repo.get!(TaskSchema, task.id)

      {:ok, task} =
        task
        |> TaskSchema.changeset(%{status: :failed, attempts: 1})
        |> Repo.update()

      # Second retry
      conn2 = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn2, 200)["data"]["attempts"] == 0
    end

    test "task lifecycle: pending -> running -> completed", %{conn: conn, project: project} do
      alias Samgita.Domain.Task, as: TaskSchema
      alias Samgita.Repo

      {:ok, task} = Projects.create_task(project.id, %{type: "lifecycle", priority: 1})

      # Check initial state
      conn1 = get(conn, ~p"/api/projects/#{project}/tasks/#{task}")
      assert json_response(conn1, 200)["data"]["status"] == "pending"

      # Update to running
      task = Repo.get!(TaskSchema, task.id)

      {:ok, task} =
        task
        |> TaskSchema.changeset(%{status: :running})
        |> Repo.update()

      conn2 = get(conn, ~p"/api/projects/#{project}/tasks/#{task}")
      assert json_response(conn2, 200)["data"]["status"] == "running"

      # Update to completed
      task = Repo.get!(TaskSchema, task.id)

      {:ok, _task} =
        task
        |> TaskSchema.changeset(%{status: :completed})
        |> Repo.update()

      conn3 = get(conn, ~p"/api/projects/#{project}/tasks/#{task}")
      assert json_response(conn3, 200)["data"]["status"] == "completed"
    end
  end
end
