defmodule Samgita.Agent.WorkerIntegrationTest do
  use ExUnit.Case, async: false

  alias Samgita.Agent.Worker

  # Requires a real Claude CLI. Excluded from `mix test` by default.
  # Run with: mix test --include e2e
  @moduletag :e2e
  @moduletag timeout: 300_000

  setup do
    test_file = "/tmp/samgita_test_#{:rand.uniform(10000)}.txt"
    File.rm(test_file)
    on_exit(fn -> File.rm(test_file) end)
    {:ok, test_file: test_file}
  end

  describe "RARV cycle with file operations" do
    @tag timeout: 60_000
    test "agent can write, edit, and remove a file", %{test_file: test_file} do
      {:ok, pid} =
        Worker.start_link(
          id: "test-agent-#{:rand.uniform(10000)}",
          agent_type: "eng-backend",
          project_id: "test-project"
        )

      assert {:idle, _data} = Worker.get_state(pid)

      Worker.assign_task(pid, %{
        type: "write_file",
        payload: %{path: test_file, content: "Hello from Samgita agent!"}
      })

      assert wait_for_state(pid, :idle, 30_000)
      assert File.exists?(test_file)
      assert File.read!(test_file) == "Hello from Samgita agent!"

      Worker.assign_task(pid, %{
        type: "edit_file",
        payload: %{path: test_file, old_string: "Hello", new_string: "Goodbye"}
      })

      assert wait_for_state(pid, :idle, 30_000)
      assert File.read!(test_file) == "Goodbye from Samgita agent!"

      Worker.assign_task(pid, %{
        type: "remove_file",
        payload: %{path: test_file}
      })

      assert wait_for_state(pid, :idle, 30_000)
      refute File.exists?(test_file)

      :gen_statem.stop(pid)
    end
  end

  defp wait_for_state(pid, target_state, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_state(pid, target_state, deadline)
  end

  defp do_wait_for_state(pid, target_state, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      false
    else
      case Worker.get_state(pid) do
        {^target_state, _data} ->
          true

        _other ->
          Process.sleep(100)
          do_wait_for_state(pid, target_state, deadline)
      end
    end
  end
end
