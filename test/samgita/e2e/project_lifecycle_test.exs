defmodule Samgita.E2E.ProjectLifecycleTest do
  @moduledoc """
  End-to-end tests for complete project lifecycle.
  """

  use Samgita.DataCase, async: false

  alias Samgita.Projects
  alias Samgita.Domain.{Task, AgentRun, Snapshot}
  alias Samgita.Repo

  setup do
    :timer.sleep(100)
    :ok
  end

  describe "complete project lifecycle" do
    test "create project with full attributes" do
      {:ok, project} =
        Projects.create_project(%{
          name: "E2E Test Project",
          git_url: "git@github.com:test/e2e-#{System.unique_integer([:positive])}.git",
          working_path: "/tmp/e2e-test",
          prd_content: "Build a simple REST API with authentication"
        })

      assert project.phase == :bootstrap
      assert project.status == :pending
      assert project.name == "E2E Test Project"
      assert project.prd_content =~ "REST API"
    end

    test "create multiple tasks and verify execution order by priority" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Priority Test",
          git_url: "git@github.com:test/priority-#{System.unique_integer([:positive])}.git"
        })

      {:ok, low_priority} = Projects.create_task(project.id, %{type: "test", priority: 10})
      {:ok, med_priority} = Projects.create_task(project.id, %{type: "build", priority: 5})
      {:ok, high_priority} = Projects.create_task(project.id, %{type: "deploy", priority: 1})

      tasks = Projects.list_tasks(project.id)
      [first, second, third] = tasks

      assert first.id == high_priority.id
      assert first.priority == 1
      assert second.id == med_priority.id
      assert second.priority == 5
      assert third.id == low_priority.id
      assert third.priority == 10
    end

    test "task failure and retry workflow" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Retry Test",
          git_url: "git@github.com:test/retry-#{System.unique_integer([:positive])}.git"
        })

      {:ok, task} = Projects.create_task(project.id, %{type: "integration_test", priority: 1})

      # Simulate failure
      task =
        task
        |> Task.changeset(%{status: :failed, error: %{reason: "timeout"}})
        |> Repo.update!()

      assert task.status == :failed

      # Retry the task
      {:ok, retried_task} = Projects.retry_task(task.id)

      assert retried_task.status == :pending
      assert retried_task.attempts == 0
      assert retried_task.error == nil
    end

    test "project status transitions" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Status Test",
          git_url: "git@github.com:test/status-#{System.unique_integer([:positive])}.git"
        })

      assert project.status == :pending

      # Update to running
      {:ok, updated} = Projects.update_project(project, %{status: :running})
      assert updated.status == :running

      # Pause
      {:ok, paused} = Projects.pause_project(project.id)
      assert paused.status == :paused

      # Resume
      {:ok, resumed} = Projects.resume_project(project.id)
      assert resumed.status == :running
    end

    test "snapshot creation and retrieval" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Snapshot Test",
          git_url: "git@github.com:test/snapshot-#{System.unique_integer([:positive])}.git"
        })

      {:ok, _snapshot} =
        Repo.insert(%Snapshot{
          project_id: project.id,
          phase: "implementation",
          agent_states: %{agent1: "active"},
          task_queue_state: %{pending: 5},
          memory_state: %{learnings: ["pattern1"]}
        })

      snapshots =
        Snapshot
        |> Ecto.Query.where(project_id: ^project.id)
        |> Repo.all()

      assert length(snapshots) == 1
      [snapshot] = snapshots
      assert snapshot.phase == "implementation"
      assert snapshot.agent_states["agent1"] == "active"
    end

    test "concurrent task creation and retrieval" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Concurrent Test",
          git_url: "git@github.com:test/concurrent-#{System.unique_integer([:positive])}.git"
        })

      task_types = ["frontend", "backend", "database", "testing", "deployment"]

      tasks =
        for type <- task_types do
          {:ok, task} = Projects.create_task(project.id, %{type: type, priority: 1})
          task
        end

      assert length(tasks) == 5

      stored_tasks = Projects.list_tasks(project.id)
      assert length(stored_tasks) == 5

      for task <- tasks do
        {:ok, fetched} = Projects.get_task(task.id)
        assert fetched.id == task.id
      end
    end

    test "agent run lifecycle tracking" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Agent Tracking Test",
          git_url: "git@github.com:test/tracking-#{System.unique_integer([:positive])}.git"
        })

      {:ok, agent_run} =
        Repo.insert(%AgentRun{
          project_id: project.id,
          agent_type: "eng-backend",
          node: "node@localhost",
          pid: "test-pid-123",
          status: :idle,
          started_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert agent_run.status == :idle
      assert agent_run.agent_type == "eng-backend"

      # Transition through RARV states
      agent_run
      |> AgentRun.changeset(%{status: :reason})
      |> Repo.update!()

      agent_run
      |> AgentRun.changeset(%{status: :act})
      |> Repo.update!()

      # Complete
      _updated_run =
        agent_run
        |> AgentRun.changeset(%{
          status: :verify,
          ended_at: DateTime.utc_now() |> DateTime.truncate(:second),
          total_tasks: 5,
          total_tokens: 1000,
          total_duration_ms: 5000
        })
        |> Repo.update!()

      runs = Projects.list_agent_runs(project.id)
      assert length(runs) == 1
      [run] = runs
      assert run.total_tasks == 5
      assert run.total_tokens == 1000
    end

    test "task with complex payload" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Complex Payload Test",
          git_url: "git@github.com:test/payload-#{System.unique_integer([:positive])}.git"
        })

      {:ok, task} =
        Projects.create_task(project.id, %{
          type: "integration_test",
          priority: 5,
          payload: %{
            target: "api",
            suite: "full",
            config: %{timeout: 30, retries: 3}
          }
        })

      {:ok, fetched} = Projects.get_task(task.id)
      assert fetched.payload["target"] == "api"
      assert fetched.payload["suite"] == "full"
      assert fetched.payload["config"]["timeout"] == 30
    end

    test "multiple projects isolation" do
      {:ok, project1} =
        Projects.create_project(%{
          name: "Project 1",
          git_url: "git@github.com:test/proj1-#{System.unique_integer([:positive])}.git"
        })

      {:ok, project2} =
        Projects.create_project(%{
          name: "Project 2",
          git_url: "git@github.com:test/proj2-#{System.unique_integer([:positive])}.git"
        })

      {:ok, _task1} = Projects.create_task(project1.id, %{type: "build", priority: 1})
      {:ok, _task2} = Projects.create_task(project2.id, %{type: "test", priority: 1})

      tasks1 = Projects.list_tasks(project1.id)
      tasks2 = Projects.list_tasks(project2.id)

      assert length(tasks1) == 1
      assert length(tasks2) == 1
      assert hd(tasks1).project_id == project1.id
      assert hd(tasks2).project_id == project2.id
    end
  end

  describe "error scenarios" do
    test "rejects invalid git URL" do
      result =
        Projects.create_project(%{
          name: "Invalid Git",
          git_url: "not-a-valid-url"
        })

      assert {:error, changeset} = result
      assert changeset.errors[:git_url]
    end

    test "handles missing PRD content" do
      {:ok, project} =
        Projects.create_project(%{
          name: "No PRD",
          git_url: "git@github.com:test/no-prd-#{System.unique_integer([:positive])}.git"
        })

      assert project.prd_content == nil
      assert project.phase == :bootstrap
    end

    test "get_task returns error for nonexistent task" do
      result = Projects.get_task(Ecto.UUID.generate())
      assert {:error, :not_found} = result
    end

    test "prevents retry of completed tasks" do
      {:ok, project} =
        Projects.create_project(%{
          name: "No Retry Completed",
          git_url: "git@github.com:test/no-retry-#{System.unique_integer([:positive])}.git"
        })

      {:ok, task} = Projects.create_task(project.id, %{type: "test", status: :completed})

      result = Projects.retry_task(task.id)
      assert {:error, :not_retriable} = result
    end

    test "prevents retry of pending tasks" do
      {:ok, project} =
        Projects.create_project(%{
          name: "No Retry Pending",
          git_url: "git@github.com:test/no-retry-pending-#{System.unique_integer([:positive])}.git"
        })

      {:ok, task} = Projects.create_task(project.id, %{type: "test", priority: 1})

      result = Projects.retry_task(task.id)
      assert {:error, :not_retriable} = result
    end

    test "task with invalid status" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Invalid Status",
          git_url: "git@github.com:test/invalid-status-#{System.unique_integer([:positive])}.git"
        })

      result = Projects.create_task(project.id, %{type: "test", status: :invalid_status})

      assert {:error, changeset} = result
      assert changeset.errors[:status]
    end
  end

  describe "performance and scale" do
    test "create and list many tasks efficiently" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Scale Test",
          git_url: "git@github.com:test/scale-#{System.unique_integer([:positive])}.git"
        })

      # Create 50 tasks
      for i <- 1..50 do
        {:ok, _task} =
          Projects.create_task(project.id, %{
            type: "task_#{i}",
            priority: rem(i, 10)
          })
      end

      tasks = Projects.list_tasks(project.id)
      assert length(tasks) == 50

      # Verify sorting by priority
      priorities = Enum.map(tasks, & &1.priority)
      assert priorities == Enum.sort(priorities)
    end

    test "bulk task status updates" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Bulk Update Test",
          git_url: "git@github.com:test/bulk-#{System.unique_integer([:positive])}.git"
        })

      tasks =
        for i <- 1..10 do
          {:ok, task} = Projects.create_task(project.id, %{type: "task_#{i}", priority: i})
          task
        end

      # Mark half as completed
      for task <- Enum.take(tasks, 5) do
        task
        |> Task.changeset(%{status: :completed})
        |> Repo.update!()
      end

      all_tasks = Projects.list_tasks(project.id)
      completed = Enum.filter(all_tasks, &(&1.status == :completed))
      pending = Enum.filter(all_tasks, &(&1.status == :pending))

      assert length(completed) == 5
      assert length(pending) == 5
    end
  end
end
