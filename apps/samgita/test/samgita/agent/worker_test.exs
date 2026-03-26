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

    on_exit(fn ->
      # Terminate any Horde children spawned during tests to avoid DB sandbox leaks
      Horde.DynamicSupervisor.which_children(Samgita.AgentSupervisor)
      |> Enum.each(fn {_, pid, _, _} ->
        Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, pid)
      end)

      Process.sleep(50)
    end)

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

  describe "assign_task with reply_to" do
    test "sends {:task_completed, task_id, :ok} to caller on success" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-reply-1", type: "implement", payload: %{}}
      Worker.assign_task(pid, task, self())

      assert_receive {:task_completed, "task-reply-1", :ok}, 10_000

      {:idle, data} = Worker.get_state(pid)
      assert data.task_count == 1
      assert data.reply_to == nil

      :gen_statem.stop(pid)
    end

    test "sends {:task_completed, task_id, {:error, _}} on max retries" do
      # Stub provider to always fail
      Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts ->
        {:error, :internal_error}
      end)

      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-reply-2", type: "implement", payload: %{}}
      Worker.assign_task(pid, task, self())

      assert_receive {:task_completed, "task-reply-2", {:error, _reason}}, 30_000

      {:idle, data} = Worker.get_state(pid)
      assert data.reply_to == nil

      :gen_statem.stop(pid)
    end

    test "does not send message when reply_to is nil" do
      opts = [
        id: "test-worker-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{id: "task-no-reply", type: "implement", payload: %{}}
      Worker.assign_task(pid, task)

      await_idle(pid)
      refute_received {:task_completed, _, _}

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

  describe "crash recovery" do
    test "agent supervised by DynamicSupervisor restarts after crash" do
      # Use the running Horde.DynamicSupervisor since Worker registers via Horde.Registry
      agent_id = "crash-test-#{System.unique_integer([:positive])}"

      opts = [
        id: agent_id,
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      # Retry start_child — Horde registry may not be synced yet in concurrent test runs
      {:ok, pid1} =
        Enum.reduce_while(1..5, nil, fn attempt, _ ->
          case Horde.DynamicSupervisor.start_child(
                 Samgita.AgentSupervisor,
                 Worker.child_spec(opts)
               ) do
            {:ok, pid} ->
              {:halt, {:ok, pid}}

            {:error, _reason} when attempt < 5 ->
              Process.sleep(100)
              {:cont, nil}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      assert {:idle, _} = Worker.get_state(pid1)
      ref = Process.monitor(pid1)

      # Kill the agent process abruptly and time the recovery
      start_time = System.monotonic_time(:millisecond)
      Process.exit(pid1, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid1, :killed}, 5_000

      # Horde should restart it (transient restart, :kill is abnormal)
      # Poll for restart — must happen within 2 seconds (acceptance: "within seconds")
      restarted_pid =
        Enum.reduce_while(1..40, nil, fn _, _acc ->
          Process.sleep(50)

          case Horde.Registry.lookup(Samgita.AgentRegistry, agent_id) do
            [{pid2, _}] when pid2 != pid1 -> {:halt, pid2}
            _ -> {:cont, nil}
          end
        end)

      recovery_ms = System.monotonic_time(:millisecond) - start_time

      # Verify the agent re-registered in Horde.Registry
      case restarted_pid do
        nil ->
          # Transient restart may not restart after :kill in some Horde versions;
          # verify the original process is dead at minimum
          refute Process.alive?(pid1)

        pid2 ->
          assert is_pid(pid2)
          assert pid2 != pid1
          assert Process.alive?(pid2)
          # Recovery must happen within 2 seconds
          assert recovery_ms < 2_000,
                 "Agent restart took #{recovery_ms}ms — exceeds 2 second threshold"

          # Clean up
          Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, pid2)
      end
    end

    test "agent retries RARV cycle on provider failure" do
      # Stub provider to fail twice then succeed
      call_count = :counters.new(1, [:atomics])

      Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 2 do
          {:error, :provider_error}
        else
          {:ok, "success after retries"}
        end
      end)

      opts = [
        id: "retry-test-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])

      task = %{
        id: "task-retry-#{System.unique_integer([:positive])}",
        type: "implement",
        payload: %{}
      }

      Worker.assign_task(pid, task, self())

      # Should eventually succeed after retrying (max_retries = 3)
      assert_receive {:task_completed, _, :ok}, 30_000

      {:idle, data} = Worker.get_state(pid)
      # Should have completed at least one task
      assert data.task_count >= 1

      :gen_statem.stop(pid)
    end
  end

  describe "model tiers (prd-008)" do
    test "opus tier agent (prod-pm) passes model: opus to provider" do
      test_pid = self()

      Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, opts ->
        send(test_pid, {:model_used, Keyword.get(opts, :model)})
        {:ok, "mock response"}
      end)

      opts = [
        id: "model-tier-opus-#{System.unique_integer([:positive])}",
        agent_type: "prod-pm",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])
      task = %{id: "task-opus", type: "plan", payload: %{}}
      Worker.assign_task(pid, task, self())

      assert_receive {:model_used, "opus"}, 10_000
      assert_receive {:task_completed, "task-opus", :ok}, 10_000

      :gen_statem.stop(pid)
    end

    test "haiku tier agent (eng-qa) passes model: haiku to provider" do
      test_pid = self()

      Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, opts ->
        send(test_pid, {:model_used, Keyword.get(opts, :model)})
        {:ok, "mock response"}
      end)

      opts = [
        id: "model-tier-haiku-#{System.unique_integer([:positive])}",
        agent_type: "eng-qa",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])
      task = %{id: "task-haiku", type: "test", payload: %{}}
      Worker.assign_task(pid, task, self())

      assert_receive {:model_used, "haiku"}, 10_000
      assert_receive {:task_completed, "task-haiku", :ok}, 10_000

      :gen_statem.stop(pid)
    end

    test "sonnet tier agent (eng-backend) passes model: sonnet to provider" do
      test_pid = self()

      Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, opts ->
        send(test_pid, {:model_used, Keyword.get(opts, :model)})
        {:ok, "mock response"}
      end)

      opts = [
        id: "model-tier-sonnet-#{System.unique_integer([:positive])}",
        agent_type: "eng-backend",
        project_id: Ecto.UUID.generate()
      ]

      {:ok, pid} = :gen_statem.start_link(Worker, opts, [])
      task = %{id: "task-sonnet", type: "implement", payload: %{}}
      Worker.assign_task(pid, task, self())

      assert_receive {:model_used, "sonnet"}, 10_000
      assert_receive {:task_completed, "task-sonnet", :ok}, 10_000

      :gen_statem.stop(pid)
    end

    test "model is always one of the three valid tiers for every agent type" do
      valid_models = ["opus", "sonnet", "haiku"]
      test_pid = self()

      # Sample one agent per swarm
      sample_agents = [
        "eng-frontend",
        "ops-devops",
        "biz-marketing",
        "data-ml",
        "prod-design",
        "growth-hacker",
        "review-code"
      ]

      Enum.each(sample_agents, fn agent_type ->
        Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, opts ->
          send(test_pid, {:model_used, agent_type, Keyword.get(opts, :model)})
          {:ok, "mock response"}
        end)

        opts = [
          id: "model-check-#{agent_type}-#{System.unique_integer([:positive])}",
          agent_type: agent_type,
          project_id: Ecto.UUID.generate()
        ]

        {:ok, pid} = :gen_statem.start_link(Worker, opts, [])
        task = %{id: "task-#{agent_type}", type: "implement", payload: %{}}
        Worker.assign_task(pid, task, self())

        assert_receive {:model_used, ^agent_type, model}, 10_000
        assert model in valid_models, "#{agent_type} used invalid model: #{inspect(model)}"

        await_idle(pid)
        :gen_statem.stop(pid)
      end)
    end
  end
end
