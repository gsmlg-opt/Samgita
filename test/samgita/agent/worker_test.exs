defmodule Samgita.Agent.WorkerTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.Worker

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

      # Wait for RARV cycle to complete (using echo mock in test)
      Process.sleep(500)

      {state, data} = Worker.get_state(pid)
      assert state == :idle
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
  end
end
