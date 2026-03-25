defmodule Samgita.Agent.WorkerTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 300_000

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Agent.Worker

  setup do
    Mox.set_mox_global(self())

    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

    # Enable shared sandbox mode for both repos since Worker spawns processes that need DB access
    Sandbox.mode(Samgita.Repo, {:shared, self()})
    Sandbox.mode(SamgitaMemory.Repo, {:shared, self()})

    :ok
  end

  defp await_idle(pid, remaining_ms \\ 10_000) do
    case Worker.get_state(pid) do
      {:idle, data} ->
        {:idle, data}

      _ when remaining_ms <= 0 ->
        flunk("Worker did not return to :idle within timeout")

      _ ->
        Process.sleep(100)
        await_idle(pid, remaining_ms - 100)
    end
  end

  describe "start_link/1" do
    test "starts in idle state" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])
      assert {:idle, _data} = Worker.get_state(pid)
      :gen_statem.stop(pid)
    end

    test "initializes with correct agent type and project id" do
      project_id = Ecto.UUID.generate()

      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-frontend",
        project_id: project_id
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])
      {:idle, data} = Worker.get_state(pid)

      assert data.agent_type == "eng-frontend"
      assert data.project_id == project_id
      assert data.task_count == 0
      assert data.retry_count == 0
      assert data.learnings == []

      :gen_statem.stop(pid)
    end
  end

  describe "assign_task/2" do
    test "transitions through RARV cycle and returns to idle" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-1", type: "implement", payload: %{}}
      Worker.assign_task(pid, task)

      # Wait for RARV cycle to complete
      {state, data} = await_idle(pid)
      assert state == :idle
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end

    test "accepts multiple tasks sequentially" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      # Assign first task
      task1 = %{id: "task-1", type: "implement", payload: %{feature: "auth"}}
      Worker.assign_task(pid, task1)

      {state1, data1} = await_idle(pid)
      assert state1 == :idle
      assert data1.task_count == 1

      # Assign second task
      task2 = %{id: "task-2", type: "test", payload: %{coverage: 80}}
      Worker.assign_task(pid, task2)

      {state2, data2} = await_idle(pid)
      assert state2 == :idle
      assert data2.task_count == 2

      :gen_statem.stop(pid)
    end

    test "handles task with string keys" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{"id" => "task-1", "type" => "implement", "payload" => %{"data" => "test"}}
      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end
  end

  describe "RARV state transitions" do
    test "transitions from idle -> reason -> act -> reflect -> verify -> idle" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      # Start in idle
      {:idle, _} = Worker.get_state(pid)

      task = %{id: "task-1", type: "implement", payload: %{}}
      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end

    test "accumulates learnings through RARV cycle" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-1", type: "implement", payload: %{}}
      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.learnings != []

      :gen_statem.stop(pid)
    end

    test "resets retry_count after successful task" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-1", type: "implement", payload: %{}}
      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.retry_count == 0

      :gen_statem.stop(pid)
    end
  end

  describe "agent type variations" do
    test "works with different agent types" do
      agent_types = ["eng-frontend", "eng-backend", "ops-devops", "data-ml", "prod-pm"]

      for agent_type <- agent_types do
        opts = [
          id: "test-worker-#{System.unique_integer([:positive])}",
          agent_type: agent_type,
          project_id: Ecto.UUID.generate()
        ]

        {:ok, pid} = :gen_statem.start_link(Worker, opts, [])
        {:idle, data} = Worker.get_state(pid)

        assert data.agent_type == agent_type

        :gen_statem.stop(pid)
      end
    end
  end

  describe "task payload variations" do
    test "handles empty payload" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-1", type: "test", payload: %{}}
      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end

    test "handles complex nested payload" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{
        id: "task-1",
        type: "implement",
        payload: %{
          feature: "api-endpoint",
          requirements: ["rest", "validation", "error-handling"],
          config: %{timeout: 30, retries: 3}
        }
      }

      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end

    test "handles missing type field" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-1", payload: %{}}
      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end

    test "handles missing payload field" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-1", type: "implement"}
      Worker.assign_task(pid, task)

      {:idle, data} = await_idle(pid)
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end
  end

  describe "specialized task types" do
    test "handles analysis task type (discovery phase)" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "prod-pm",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{
        id: "task-analysis",
        type: "analysis",
        payload: %{"description" => "Analyze codebase structure", "phase" => "discovery"}
      }

      Worker.assign_task(pid, task)
      {:idle, data} = await_idle(pid)
      assert data.task_count == 1
      :gen_statem.stop(pid)
    end

    test "handles architecture task type" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{
        id: "task-arch",
        type: "architecture",
        payload: %{"description" => "Design backend architecture", "phase" => "architecture"}
      }

      Worker.assign_task(pid, task)
      {:idle, data} = await_idle(pid)
      assert data.task_count == 1
      :gen_statem.stop(pid)
    end

    test "handles review task type" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "review-code",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{
        id: "task-review",
        type: "review",
        payload: %{"description" => "Code review for quality", "phase" => "qa"}
      }

      Worker.assign_task(pid, task)
      {:idle, data} = await_idle(pid)
      assert data.task_count == 1
      :gen_statem.stop(pid)
    end

    test "handles test task type" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-qa",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{
        id: "task-test",
        type: "test",
        payload: %{"description" => "Run full test suite", "phase" => "qa"}
      }

      Worker.assign_task(pid, task)
      {:idle, data} = await_idle(pid)
      assert data.task_count == 1
      :gen_statem.stop(pid)
    end
  end

  describe "build_commit_message/3" do
    test "includes agent type, task description, and trailers" do
      task = %{id: "task-123", type: "implement", payload: %{"description" => "add auth module"}}
      message = Worker.build_commit_message("eng-backend", task, :development)

      # Subject line
      assert message =~ "[samgita] eng-backend: implement: add auth module"

      # Git trailers
      assert message =~ "Agent-Type: eng-backend"
      assert message =~ "Phase: development"
      assert message =~ "Task-ID: task-123"
      assert message =~ "Samgita-Version:"
    end

    test "uses task type when no description in payload" do
      task = %{id: "task-456", type: "test", payload: %{}}
      message = Worker.build_commit_message("eng-qa", task, :qa)

      assert message =~ "[samgita] eng-qa: test"
      assert message =~ "Task-ID: task-456"
      assert message =~ "Phase: qa"
    end

    test "uses 'task' when task has no type" do
      task = %{id: "task-789"}
      message = Worker.build_commit_message("ops-devops", task, :infrastructure)

      assert message =~ "[samgita] ops-devops: task"
      assert message =~ "Task-ID: task-789"
    end

    test "uses 'unknown' task id when task has no id" do
      task = %{type: "review"}
      message = Worker.build_commit_message("review-code", task, :qa)

      assert message =~ "Task-ID: unknown"
    end

    test "message has correct multi-line format with blank line before trailers" do
      task = %{id: "t1", type: "implement", payload: %{"description" => "feature X"}}
      message = Worker.build_commit_message("eng-frontend", task, :development)

      lines = String.split(message, "\n")

      # First line is the subject
      assert hd(lines) == "[samgita] eng-frontend: implement: feature X"

      # Second line is blank (separating subject from trailers)
      assert Enum.at(lines, 1) == ""

      # Remaining lines are trailers
      trailer_lines = Enum.drop(lines, 2)
      assert Enum.any?(trailer_lines, &String.starts_with?(&1, "Agent-Type:"))
      assert Enum.any?(trailer_lines, &String.starts_with?(&1, "Phase:"))
      assert Enum.any?(trailer_lines, &String.starts_with?(&1, "Task-ID:"))
      assert Enum.any?(trailer_lines, &String.starts_with?(&1, "Samgita-Version:"))
    end
  end

  describe "build_task_description/1" do
    test "returns type and description when both present" do
      task = %{type: "implement", payload: %{"description" => "build login"}}
      assert Worker.build_task_description(task) == "implement: build login"
    end

    test "returns type when no description" do
      task = %{type: "test", payload: %{}}
      assert Worker.build_task_description(task) == "test"
    end

    test "returns type when payload missing" do
      task = %{type: "review"}
      assert Worker.build_task_description(task) == "review"
    end

    test "returns 'task' for empty map" do
      assert Worker.build_task_description(%{}) == "task"
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = Worker.child_spec(id: "agent-1", agent_type: "eng-backend", project_id: "proj-1")
      assert spec.id == "agent-1"
      assert spec.restart == :transient
    end

    test "includes correct start function" do
      opts = [id: "agent-1", agent_type: "eng-backend", project_id: "proj-1"]
      spec = Worker.child_spec(opts)

      assert {Worker, :start_link, [^opts]} = spec.start
    end
  end
end
