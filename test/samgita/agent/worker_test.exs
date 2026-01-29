defmodule Samgita.Agent.WorkerTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.Worker

  @opts [
    id: "test-agent-1",
    agent_type: "eng-backend",
    project_id: Ecto.UUID.generate()
  ]

  describe "start_link/1" do
    test "starts in idle state" do
      # Start without Horde registry for unit testing
      {:ok, pid} = :gen_statem.start_link(Worker, @opts, [])
      assert {:idle, _data} = Worker.get_state(pid)
      :gen_statem.stop(pid)
    end
  end

  describe "assign_task/2" do
    test "transitions through RARV cycle" do
      {:ok, pid} = :gen_statem.start_link(Worker, @opts, [])

      task = %{id: "task-1", type: "implement", payload: %{}}
      Worker.assign_task(pid, task)

      # Give it time to cycle through states
      Process.sleep(100)

      # Should be back to idle after completing the cycle
      assert {:idle, data} = Worker.get_state(pid)
      assert data.task_count == 1

      :gen_statem.stop(pid)
    end
  end
end
