defmodule Samgita.Agent.WorkerIntegrationTest do
  use ExUnit.Case, async: false

  alias Samgita.Agent.Worker
  alias Samgita.Repo

  @moduletag :integration

  setup do
    # Ensure test file doesn't exist
    test_file = "/tmp/samgita_test_#{:rand.uniform(10000)}.txt"
    File.rm(test_file)

    on_exit(fn ->
      File.rm(test_file)
    end)

    {:ok, test_file: test_file}
  end

  describe "RARV cycle with file operations" do
    @tag timeout: 60_000
    test "agent can write, edit, and remove a file", %{test_file: test_file} do
      # Start agent worker
      {:ok, pid} =
        Worker.start_link(
          id: "test-agent-#{:rand.uniform(10000)}",
          agent_type: "eng-backend",
          project_id: "test-project"
        )

      # Verify initial state
      assert {:idle, _data} = Worker.get_state(pid)

      # Task 1: Write a file
      write_task = %{
        type: "write_file",
        payload: %{
          path: test_file,
          content: "Hello from Samgita agent!"
        }
      }

      Worker.assign_task(pid, write_task)

      # Wait for task completion (agent goes back to idle)
      assert wait_for_state(pid, :idle, 30_000)

      # Verify file was created
      assert File.exists?(test_file)
      assert File.read!(test_file) == "Hello from Samgita agent!"

      # Task 2: Edit the file
      edit_task = %{
        type: "edit_file",
        payload: %{
          path: test_file,
          old_string: "Hello",
          new_string: "Goodbye"
        }
      }

      Worker.assign_task(pid, edit_task)
      assert wait_for_state(pid, :idle, 30_000)

      # Verify file was edited
      assert File.read!(test_file) == "Goodbye from Samgita agent!"

      # Task 3: Remove the file
      remove_task = %{
        type: "remove_file",
        payload: %{
          path: test_file
        }
      }

      Worker.assign_task(pid, remove_task)
      assert wait_for_state(pid, :idle, 30_000)

      # Verify file was removed
      refute File.exists?(test_file)

      # Stop the agent
      :gen_statem.stop(pid)
    end
  end

  # Helper to wait for agent to reach a specific state
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
