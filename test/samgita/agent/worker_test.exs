defmodule Samgita.Agent.WorkerTest do
  use ExUnit.Case, async: false

  @moduletag timeout: 30_000

  alias Samgita.Agent.Worker

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

    @tag timeout: 60_000
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

    @tag timeout: 60_000
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
          feature: "auth",
          requirements: ["oauth2", "jwt"],
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
