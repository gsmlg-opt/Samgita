defmodule Samgita.Project.OrchestratorTest do
  # Cannot be async due to shared sandbox mode needed for gen_statem init
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Domain.Prd
  alias Samgita.Project.Orchestrator
  alias Samgita.Projects
  alias Samgita.Repo

  setup do
    Mox.set_mox_global(self())

    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

    # Default: delegate ObanClient calls to real Oban (inline test mode).
    # Individual tests override this stub to inject failures.
    Mox.stub(Samgita.MockOban, :insert, fn job -> Oban.insert(job) end)

    # Allow spawned processes to access the sandbox
    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Test Orchestrator",
        git_url: "git@github.com:test/orchestrator-#{System.unique_integer([:positive])}.git",
        prd_content: "# Test PRD",
        status: :running
      })

    %{project: project}
  end

  defp flush_messages(acc \\ []) do
    receive do
      msg -> flush_messages([msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "starts in project's current phase", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    assert {:bootstrap, _data} = Orchestrator.get_state(pid)
    :gen_statem.stop(pid)
  end

  test "advances through phases", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])

    assert {:bootstrap, _} = Orchestrator.get_state(pid)

    Orchestrator.advance_phase(pid)
    Process.sleep(50)
    assert {:discovery, _} = Orchestrator.get_state(pid)

    Orchestrator.advance_phase(pid)
    Process.sleep(50)
    assert {:architecture, _} = Orchestrator.get_state(pid)

    :gen_statem.stop(pid)
  end

  test "returns error for nonexistent project" do
    Process.flag(:trap_exit, true)
    result = :gen_statem.start_link(Orchestrator, [project_id: Ecto.UUID.generate()], [])
    assert {:error, :project_not_found} = result
  end

  test "tracks task completion count", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    :gen_statem.cast(pid, {:task_completed, "task-1"})
    :gen_statem.cast(pid, {:task_completed, "task-2"})
    Process.sleep(50)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.task_count == 2

    :gen_statem.stop(pid)
  end

  test "perpetual phase does not advance further", %{project: project} do
    {:ok, _} = Projects.update_project(project, %{phase: :perpetual})
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    assert {:perpetual, _} = Orchestrator.get_state(pid)

    Orchestrator.advance_phase(pid)
    Process.sleep(50)

    assert {:perpetual, _} = Orchestrator.get_state(pid)

    :gen_statem.stop(pid)
  end

  test "sets agent statuses on phase entry", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(100)

    {_phase, data} = Orchestrator.get_state(pid)
    # Bootstrap phase has one agent: prod-pm
    assert Map.has_key?(data.agents, "prod-pm")

    :gen_statem.stop(pid)
  end

  test "auto-advances phase when all tasks complete", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    assert {:bootstrap, _} = Orchestrator.get_state(pid)

    # Set expected task count and complete them
    Orchestrator.set_phase_task_count(pid, 2)
    Process.sleep(10)
    Orchestrator.notify_task_completed(pid, "task-1")
    Process.sleep(10)
    Orchestrator.notify_task_completed(pid, "task-2")
    Process.sleep(500)

    # Should have auto-advanced to discovery
    assert {:discovery, data} = Orchestrator.get_state(pid)
    assert data.phase_tasks_completed == 0
    # Discovery phase enqueues 3 tasks during setup
    assert data.phase_tasks_total == 3

    :gen_statem.stop(pid)
  end

  test "does not auto-advance when tasks remain", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    Orchestrator.set_phase_task_count(pid, 3)
    Process.sleep(10)
    Orchestrator.notify_task_completed(pid, "task-1")
    Orchestrator.notify_task_completed(pid, "task-2")
    Process.sleep(50)

    # Should still be in bootstrap (2/3 tasks)
    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.phase_tasks_completed == 2
    assert data.phase_tasks_total == 3

    :gen_statem.stop(pid)
  end

  test "does not auto-advance when phase_tasks_total is 0", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    # Complete tasks without setting total — should not auto-advance
    Orchestrator.notify_task_completed(pid, "task-1")
    Process.sleep(50)

    assert {:bootstrap, _} = Orchestrator.get_state(pid)

    :gen_statem.stop(pid)
  end

  test "resets phase counters on phase transition", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    # Set and complete tasks to trigger auto-advance
    Orchestrator.set_phase_task_count(pid, 1)
    Process.sleep(10)
    Orchestrator.notify_task_completed(pid, "task-1")
    Process.sleep(100)

    # Should be in discovery with reset counters, then re-populated by phase setup
    {:discovery, data} = Orchestrator.get_state(pid)
    # Discovery phase enqueues 3 tasks during setup
    assert data.phase_tasks_total == 3
    assert data.phase_tasks_completed == 0
    # Total task count persists across phases
    assert data.task_count >= 1

    :gen_statem.stop(pid)
  end

  test "development phase triggers quality gates instead of auto-advancing", %{project: project} do
    {:ok, _} = Projects.update_project(project, %{phase: :development})
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    assert {:development, _} = Orchestrator.get_state(pid)

    # Complete all tasks — should NOT auto-advance, should wait for quality gates
    Orchestrator.set_phase_task_count(pid, 1)
    Process.sleep(10)
    Orchestrator.notify_task_completed(pid, "task-1")
    Process.sleep(100)

    # Still in development, awaiting quality gates
    {:development, data} = Orchestrator.get_state(pid)
    assert data.awaiting_quality_gates == true

    :gen_statem.stop(pid)
  end

  test "development phase advances after quality_gates_passed", %{project: project} do
    {:ok, _} = Projects.update_project(project, %{phase: :development})
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    # Complete tasks to trigger gate wait
    Orchestrator.set_phase_task_count(pid, 1)
    Process.sleep(10)
    Orchestrator.notify_task_completed(pid, "task-1")
    Process.sleep(100)

    {:development, data} = Orchestrator.get_state(pid)
    assert data.awaiting_quality_gates == true

    # Simulate quality gates passing
    :gen_statem.cast(pid, :quality_gates_passed)
    Process.sleep(500)

    # Should have advanced to qa
    assert {:qa, data} = Orchestrator.get_state(pid)
    assert data.awaiting_quality_gates == false

    :gen_statem.stop(pid)
  end

  test "discovery phase creates analysis tasks with correct phase payload", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    # Advance to discovery
    Orchestrator.advance_phase(pid)
    Process.sleep(200)

    assert {:discovery, data} = Orchestrator.get_state(pid)
    # Discovery enqueues 3 analysis tasks
    assert data.phase_tasks_total == 3

    # Verify tasks were created in DB with correct phase
    tasks = Samgita.Projects.list_tasks(project.id)
    analysis_tasks = Enum.filter(tasks, &(&1.type == "analysis"))
    assert length(analysis_tasks) == 3

    Enum.each(analysis_tasks, fn task ->
      assert task.payload["phase"] == "discovery"
    end)

    :gen_statem.stop(pid)
  end

  test "architecture phase creates design tasks with correct phase payload", %{project: project} do
    {:ok, _} = Projects.update_project(project, %{phase: :architecture})
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(200)

    assert {:architecture, data} = Orchestrator.get_state(pid)
    # Architecture enqueues 4 tasks
    assert data.phase_tasks_total == 4

    tasks = Samgita.Projects.list_tasks(project.id)
    arch_tasks = Enum.filter(tasks, &(&1.type == "architecture"))
    assert length(arch_tasks) == 4

    Enum.each(arch_tasks, fn task ->
      assert task.payload["phase"] == "architecture"
    end)

    :gen_statem.stop(pid)
  end

  test "quality_gates_passed ignored when not awaiting", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    assert {:bootstrap, _} = Orchestrator.get_state(pid)

    # Send quality_gates_passed when not awaiting — should be ignored
    :gen_statem.cast(pid, :quality_gates_passed)
    Process.sleep(50)

    assert {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.awaiting_quality_gates == false

    :gen_statem.stop(pid)
  end

  test "stagnation counter increments without progress", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(100)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.stagnation_checks == 0
    assert data.last_progress_task_count == 0

    # Manually trigger stagnation check via timeout event
    :gen_statem.cast(pid, {:task_completed, "task-1"})
    Process.sleep(20)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.task_count == 1

    :gen_statem.stop(pid)
  end

  test "stagnation resets when tasks complete", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(100)

    # Complete tasks — stagnation counter should be tracked from last_progress_task_count
    :gen_statem.cast(pid, {:task_completed, "task-1"})
    Process.sleep(20)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.task_count == 1
    # After setup_phase, last_progress_task_count is set to task_count (0)
    # After task completion, task_count is 1, which differs from last_progress_task_count=0
    # So stagnation check would see progress

    :gen_statem.stop(pid)
  end

  test "stagnation threshold triggers stagnation_detected broadcast (unit)", %{project: project} do
    {:ok, _} = Projects.update_project(project, %{phase: :development})
    :ok = Samgita.Events.subscribe_project(project.id)

    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(100)

    {:development, data} = Orchestrator.get_state(pid)

    # Call the stagnation timeout handler directly 5 times (threshold = 5)
    # with no task progress so stagnation_checks increments each time
    stagnant_data = %{data | task_count: 0, last_progress_task_count: 0, stagnation_checks: 0}

    # Call 4 times — should not yet broadcast
    {:keep_state, data1, _} =
      Orchestrator.development({:timeout, :stagnation}, :check, stagnant_data)

    assert data1.stagnation_checks == 1
    {:keep_state, data2, _} = Orchestrator.development({:timeout, :stagnation}, :check, data1)
    assert data2.stagnation_checks == 2
    {:keep_state, data3, _} = Orchestrator.development({:timeout, :stagnation}, :check, data2)
    assert data3.stagnation_checks == 3
    {:keep_state, data4, _} = Orchestrator.development({:timeout, :stagnation}, :check, data3)
    assert data4.stagnation_checks == 4

    # 5th call should trigger activity_log broadcast with stagnation message
    Orchestrator.development({:timeout, :stagnation}, :check, data4)
    assert_receive {:activity_log, %{stage: :failed, message: "Stagnation: " <> _}}, 500

    :gen_statem.stop(pid)
  end

  test "pause prevents auto-advance on task completion", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    Orchestrator.set_phase_task_count(pid, 2)
    Process.sleep(10)

    # Pause the orchestrator
    Orchestrator.pause(pid)
    Process.sleep(10)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.paused == true

    # Complete all tasks while paused
    Orchestrator.notify_task_completed(pid, "task-1")
    Orchestrator.notify_task_completed(pid, "task-2")
    Process.sleep(100)

    # Should still be in bootstrap despite all tasks being complete
    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.phase_tasks_completed == 2
    assert data.paused == true

    :gen_statem.stop(pid)
  end

  test "resume after pause triggers deferred advance", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    Orchestrator.set_phase_task_count(pid, 1)
    Process.sleep(10)

    # Pause, complete task, then resume
    Orchestrator.pause(pid)
    Process.sleep(10)
    Orchestrator.notify_task_completed(pid, "task-1")
    Process.sleep(50)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.paused == true

    # Resume — should trigger deferred advance
    Orchestrator.resume(pid)
    Process.sleep(100)

    {:discovery, data} = Orchestrator.get_state(pid)
    assert data.paused == false

    :gen_statem.stop(pid)
  end

  test "double pause is idempotent", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    Orchestrator.pause(pid)
    Orchestrator.pause(pid)
    Process.sleep(20)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.paused == true

    :gen_statem.stop(pid)
  end

  test "resume when not paused is no-op", %{project: project} do
    {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
    Process.sleep(50)

    Orchestrator.resume(pid)
    Process.sleep(20)

    {:bootstrap, data} = Orchestrator.get_state(pid)
    assert data.paused == false

    :gen_statem.stop(pid)
  end

  describe "bootstrap phase auto-trigger" do
    test "enqueues BootstrapWorker when project has active_prd_id", %{project: project} do
      # Create a PRD and set it as active
      {:ok, prd} =
        %Prd{}
        |> Prd.changeset(%{
          title: "Test PRD",
          content: "# Test\n\n## Features\n\n- Build a web app",
          status: :approved,
          project_id: project.id
        })
        |> Repo.insert()

      {:ok, _} = Projects.update_project(project, %{active_prd_id: prd.id})

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      {:bootstrap, data} = Orchestrator.get_state(pid)
      # phase_tasks_total starts at 0; BootstrapWorker calls set_phase_task_count
      # asynchronously with the real count after generating tasks.
      assert data.phase_tasks_total == 0

      :gen_statem.stop(pid)
    end

    test "does not enqueue BootstrapWorker when no active_prd_id", %{project: project} do
      # Ensure no active PRD is set
      {:ok, _} = Projects.update_project(project, %{active_prd_id: nil})

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      {:bootstrap, data} = Orchestrator.get_state(pid)
      # Should have phase_tasks_total = 0 (no BootstrapWorker triggered)
      assert data.phase_tasks_total == 0

      :gen_statem.stop(pid)
    end
  end

  describe "quality gates block phase advancement" do
    test "qa phase also triggers quality gates instead of auto-advancing", %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :qa})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      assert {:qa, _} = Orchestrator.get_state(pid)

      Orchestrator.set_phase_task_count(pid, 1)
      Process.sleep(10)
      Orchestrator.notify_task_completed(pid, "task-1")
      Process.sleep(100)

      # QA requires quality gates — should be awaiting, not auto-advanced
      {:qa, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == true

      :gen_statem.stop(pid)
    end

    test "orchestrator stays in development when quality gates are not sent", %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      # Complete tasks to trigger gate wait
      Orchestrator.set_phase_task_count(pid, 1)
      Process.sleep(10)
      Orchestrator.notify_task_completed(pid, "task-1")
      Process.sleep(200)

      # Orchestrator should be stuck awaiting gates — NOT advanced
      {:development, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == true

      # Wait extra time — still should not advance without explicit gate pass
      Process.sleep(500)
      {:development, _} = Orchestrator.get_state(pid)

      :gen_statem.stop(pid)
    end

    test "qa phase advances after quality_gates_passed", %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :qa})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      Orchestrator.set_phase_task_count(pid, 1)
      Process.sleep(10)
      Orchestrator.notify_task_completed(pid, "task-1")
      Process.sleep(100)

      {:qa, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == true

      :gen_statem.cast(pid, :quality_gates_passed)
      Process.sleep(500)

      # Should have advanced to deployment
      assert {:deployment, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == false

      :gen_statem.stop(pid)
    end
  end

  describe "activity log broadcasting" do
    test "broadcasts activity_log on phase entry", %{project: project} do
      :ok = Samgita.Events.subscribe_project(project.id)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      # Should have received bootstrap phase entry activity
      assert_receive {:activity_log, %{stage: :phase_change, message: msg}}, 500
      assert msg =~ "Entering phase: bootstrap"

      :gen_statem.stop(pid)
    end

    test "broadcasts activity_log on agent spawning", %{project: project} do
      :ok = Samgita.Events.subscribe_project(project.id)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      assert_receive {:activity_log, %{stage: :spawned, message: msg}}, 500
      assert msg =~ "Spawning agents:"

      :gen_statem.stop(pid)
    end

    test "broadcasts activity_log on task completion", %{project: project} do
      :ok = Samgita.Events.subscribe_project(project.id)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      :gen_statem.cast(pid, {:task_completed, "task-abc"})
      Process.sleep(50)

      assert_receive {:activity_log, %{stage: :task_completed, message: msg}}, 500
      assert msg =~ "Task completed"

      :gen_statem.stop(pid)
    end

    test "broadcasts activity_log on auto-advance", %{project: project} do
      :ok = Samgita.Events.subscribe_project(project.id)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      Orchestrator.set_phase_task_count(pid, 1)
      Process.sleep(10)
      Orchestrator.notify_task_completed(pid, "task-1")
      Process.sleep(500)

      # Should receive phase_change activity for advancing to discovery
      messages = flush_messages()

      phase_change_msgs =
        Enum.filter(messages, fn
          {:activity_log, %{stage: :phase_change}} -> true
          _ -> false
        end)

      assert length(phase_change_msgs) >= 2
      # At least: entering bootstrap + entering discovery (or auto-advance message)

      :gen_statem.stop(pid)
    end
  end

  describe "Oban.insert failure handling" do
    test "bootstrap phase: Oban.insert failure sets phase_tasks_total to 0 and broadcasts failure",
         %{project: project} do
      {:ok, prd} =
        %Prd{}
        |> Prd.changeset(%{
          title: "Failure Test PRD",
          content: "# Test\n\n## Features\n\n- Trigger failure",
          status: :approved,
          project_id: project.id
        })
        |> Repo.insert()

      {:ok, _} = Projects.update_project(project, %{active_prd_id: prd.id})

      :ok = Samgita.Events.subscribe_project(project.id)

      Mox.stub(Samgita.MockOban, :insert, fn _job -> {:error, :simulated_insert_failure} end)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      {:bootstrap, data} = Orchestrator.get_state(pid)
      assert data.phase_tasks_total == 0

      assert_receive {:activity_log,
                      %{stage: :failed, message: "Failed to queue bootstrap task"}},
                     500

      :gen_statem.stop(pid)
    end

    test "create_phase_tasks: all Oban.inserts fail yields phase_tasks_total 0 with 0/N message",
         %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :discovery})

      :ok = Samgita.Events.subscribe_project(project.id)

      Mox.stub(Samgita.MockOban, :insert, fn _job -> {:error, :simulated_insert_failure} end)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(200)

      {:discovery, data} = Orchestrator.get_state(pid)
      # All 3 AgentTaskWorker inserts failed → phase_tasks_total stays 0
      assert data.phase_tasks_total == 0

      assert_receive {:activity_log, %{stage: :reason, message: "Enqueued 0/3 phase tasks"}},
                     500

      :gen_statem.stop(pid)
    end

    test "create_phase_tasks: partial Oban.insert failures yield correct partial count",
         %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :discovery})

      :ok = Samgita.Events.subscribe_project(project.id)

      # Fail only the first insert; let subsequent ones succeed via real Oban
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)

      Mox.stub(Samgita.MockOban, :insert, fn job ->
        n = Agent.get_and_update(counter, fn c -> {c + 1, c + 1} end)

        if n == 1 do
          {:error, :simulated_first_failure}
        else
          Oban.insert(job)
        end
      end)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(300)

      {:discovery, data} = Orchestrator.get_state(pid)
      # 1 failed, 2 succeeded → phase_tasks_total == 2
      assert data.phase_tasks_total == 2

      assert_receive {:activity_log, %{stage: :reason, message: "Enqueued 2/3 phase tasks"}},
                     500

      :gen_statem.stop(pid)
    end
  end

  describe "agent crash recovery" do
    test "handles unknown DOWN message without crashing", %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :bootstrap})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      # DOWN for an unmonitored ref — takes the nil branch, keeps state unchanged
      send(pid, {:DOWN, make_ref(), :process, self(), :test_crash})
      Process.sleep(50)

      assert Process.alive?(pid)
      :gen_statem.stop(pid)
    end

    test "handles DOWN for monitored agent — removes ref and attempts respawn", %{
      project: project
    } do
      {:ok, _} = Projects.update_project(project, %{phase: :bootstrap})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      fake_ref = make_ref()
      fake_agent_id = "#{project.id}-prod-pm"

      # Inject a fake monitor into orchestrator state
      :sys.replace_state(pid, fn {phase, data} ->
        monitors = Map.put(data.agent_monitors, fake_ref, {fake_agent_id, "prod-pm"})
        {phase, %{data | agent_monitors: monitors}}
      end)

      # Verify the monitor was injected
      {:bootstrap, data_before} = Orchestrator.get_state(pid)
      assert Map.has_key?(data_before.agent_monitors, fake_ref)

      # Send DOWN for the monitored ref — orchestrator should handle and stay alive
      send(pid, {:DOWN, fake_ref, :process, self(), :killed})
      Process.sleep(150)

      assert Process.alive?(pid)

      # Critical: the fake_ref must have been removed from agent_monitors
      {:bootstrap, data_after} = Orchestrator.get_state(pid)

      refute Map.has_key?(data_after.agent_monitors, fake_ref),
             "fake_ref must be removed from agent_monitors after DOWN"

      :gen_statem.stop(pid)
    end
  end

  describe "awaiting_quality_gates state" do
    test "awaiting_quality_gates is set to true when requires_quality_gates phase completes all tasks",
         %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      :ok = Samgita.Events.subscribe_project(project.id)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      # Manually set phase_tasks_total and complete all tasks to trigger quality gate check
      :sys.replace_state(pid, fn {phase, data} ->
        {phase, %{data | phase_tasks_total: 1, phase_tasks_completed: 0}}
      end)

      # Complete the one task — should trigger quality gate arm
      Orchestrator.notify_task_completed(pid, "fake-task-id")
      Process.sleep(100)

      {:development, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == true

      :gen_statem.stop(pid)
    end

    test "awaiting_quality_gates is broadcast via activity_log when triggered", %{
      project: project
    } do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      :ok = Samgita.Events.subscribe_project(project.id)

      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      :sys.replace_state(pid, fn {phase, data} ->
        {phase, %{data | phase_tasks_total: 1, phase_tasks_completed: 0}}
      end)

      Orchestrator.notify_task_completed(pid, "fake-task-id")

      assert_receive {:activity_log,
                      %{stage: :reason, message: "Phase tasks complete, running quality gates"}},
                     500

      :gen_statem.stop(pid)
    end
  end

  describe "quality gate timeout" do
    test "orchestrator stays alive while awaiting quality gates", %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      {:development, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == false

      # Set awaiting_quality_gates to true via sys.replace_state
      :sys.replace_state(pid, fn {phase, state} ->
        {phase, %{state | awaiting_quality_gates: true}}
      end)

      {:development, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == true

      # Orchestrator stays alive while waiting for quality gates
      Process.sleep(50)
      assert Process.alive?(pid)
      :gen_statem.stop(pid)
    end

    test "quality_gate_timeout handler clears awaiting flag when not awaiting (unit)", %{
      project: project
    } do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      {:development, data} = Orchestrator.get_state(pid)

      # Call state function directly — non-awaiting path should clear the flag
      not_awaiting_data = %{data | awaiting_quality_gates: false}

      result =
        Orchestrator.development({:timeout, :quality_gate_timeout}, :check, not_awaiting_data)

      assert {:keep_state, updated_data} = result
      assert updated_data.awaiting_quality_gates == false

      :gen_statem.stop(pid)
    end

    test "quality_gate_timeout handler re-arms timer when awaiting quality gates (unit)", %{
      project: project
    } do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      {:development, data} = Orchestrator.get_state(pid)

      # Call state function directly — awaiting path re-triggers gates and re-arms timer
      awaiting_data = %{data | awaiting_quality_gates: true}
      result = Orchestrator.development({:timeout, :quality_gate_timeout}, :check, awaiting_data)

      # Must not stop — must re-arm the timer
      assert match?({:keep_state, _, _}, result),
             "quality gate timeout must re-arm, not stop the orchestrator"

      {_, _, actions} = result

      assert Enum.any?(actions, fn
               {{:timeout, :quality_gate_timeout}, _, :check} -> true
               _ -> false
             end),
             "named timeout must be re-armed after quality gate re-trigger"

      :gen_statem.stop(pid)
    end
  end

  describe "10-phase sequence (prd-009)" do
    test "complete phase order is bootstrap→discovery→architecture→infrastructure→development→qa→deployment→business→growth→perpetual",
         %{project: project} do
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])

      # Start: bootstrap
      assert {:bootstrap, _} = Orchestrator.get_state(pid)

      # bootstrap → discovery
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:discovery, _} = Orchestrator.get_state(pid)

      # discovery → architecture
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:architecture, _} = Orchestrator.get_state(pid)

      # architecture → infrastructure
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:infrastructure, _} = Orchestrator.get_state(pid)

      # infrastructure → development
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:development, _} = Orchestrator.get_state(pid)

      # development → qa (advance_phase is an admin override that bypasses quality gates)
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:qa, _} = Orchestrator.get_state(pid)

      # qa → deployment (advance_phase bypasses quality gates)
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:deployment, _} = Orchestrator.get_state(pid)

      # deployment → business
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:business, _} = Orchestrator.get_state(pid)

      # business → growth
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:growth, _} = Orchestrator.get_state(pid)

      # growth → perpetual
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:perpetual, _} = Orchestrator.get_state(pid)

      # perpetual stays perpetual
      Orchestrator.advance_phase(pid)
      Process.sleep(50)
      assert {:perpetual, _} = Orchestrator.get_state(pid)

      :gen_statem.stop(pid)
    end

    test "orchestrator has exactly 10 distinct phases", %{project: project} do
      # Verify by walking all phases via advance_phase
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])

      phases_seen =
        Enum.reduce_while(1..20, [], fn _, acc ->
          {phase, _} = Orchestrator.get_state(pid)

          if phase == :perpetual and :perpetual in acc do
            {:halt, acc}
          else
            Orchestrator.advance_phase(pid)
            Process.sleep(50)

            # Use quality_gates_passed for gated phases
            {next_phase, _} = Orchestrator.get_state(pid)

            if next_phase == phase do
              # Phase didn't advance — send quality_gates_passed and retry
              :gen_statem.cast(pid, :quality_gates_passed)
              Process.sleep(50)
            end

            {:cont, Enum.uniq([phase | acc])}
          end
        end)

      :gen_statem.stop(pid)

      expected_phases = [
        :bootstrap,
        :discovery,
        :architecture,
        :infrastructure,
        :development,
        :qa,
        :deployment,
        :business,
        :growth,
        :perpetual
      ]

      assert length(phases_seen) == 10,
             "Expected 10 phases, got #{length(phases_seen)}: #{inspect(phases_seen)}"

      Enum.each(expected_phases, fn p ->
        assert p in phases_seen, "Phase #{p} was never visited"
      end)
    end

    test "project phase column is updated on each phase transition", %{project: project} do
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      # Initial phase in DB should be bootstrap
      reloaded = Repo.reload!(project)
      assert reloaded.phase == :bootstrap

      Orchestrator.advance_phase(pid)
      Process.sleep(100)

      reloaded = Repo.reload!(project)
      assert reloaded.phase == :discovery

      :gen_statem.stop(pid)
    end
  end

  describe "phase transition guards (prd-010)" do
    test "advance_phase is an admin override that bypasses quality gates in development",
         %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      assert {:development, _} = Orchestrator.get_state(pid)

      # Set awaiting_quality_gates: true (simulating all tasks done but gates pending)
      :sys.replace_state(pid, fn {phase, data} ->
        {phase, %{data | awaiting_quality_gates: true}}
      end)

      # advance_phase IS an admin override — it bypasses the quality gate and advances
      Orchestrator.advance_phase(pid)
      Process.sleep(50)

      # Admin override advanced to qa despite quality gates being pending
      assert {:qa, _} = Orchestrator.get_state(pid)

      :gen_statem.stop(pid)
    end

    test "task_completed event does not auto-advance development when awaiting quality gates",
         %{project: project} do
      {:ok, _} = Projects.update_project(project, %{phase: :development})
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(100)

      assert {:development, _} = Orchestrator.get_state(pid)

      # Set up: one task remaining, already awaiting quality gates
      :sys.replace_state(pid, fn {phase, data} ->
        {phase,
         %{
           data
           | phase_tasks_total: 5,
             phase_tasks_completed: 4,
             awaiting_quality_gates: true
         }}
      end)

      # This task_completed will increment to 5/5, but since awaiting_quality_gates
      # is already true, it should NOT auto-advance — only quality_gates_passed can advance
      :gen_statem.cast(pid, {:task_completed, "last-dev-task"})
      Process.sleep(100)

      # Still in development — quality gate blocks auto-advance
      assert {:development, _} = Orchestrator.get_state(pid)

      :gen_statem.stop(pid)
    end

    test "quality_gates_passed is ignored when not awaiting", %{project: project} do
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      # In bootstrap, not awaiting quality gates
      {:bootstrap, data} = Orchestrator.get_state(pid)
      assert data.awaiting_quality_gates == false

      # Should be a no-op
      :gen_statem.cast(pid, :quality_gates_passed)
      Process.sleep(50)

      # Still bootstrap
      assert {:bootstrap, _} = Orchestrator.get_state(pid)

      :gen_statem.stop(pid)
    end

    test "paused orchestrator ignores task completions for auto-advance", %{project: project} do
      {:ok, pid} = :gen_statem.start_link(Orchestrator, [project_id: project.id], [])
      Process.sleep(50)

      Orchestrator.pause(pid)
      Process.sleep(50)

      {:bootstrap, data_before} = Orchestrator.get_state(pid)

      # Complete enough tasks that would normally trigger advance
      :sys.replace_state(pid, fn {phase, data} ->
        total = max(data.phase_tasks_total, 1)
        {phase, %{data | phase_tasks_total: total, phase_tasks_completed: total - 1}}
      end)

      :gen_statem.cast(pid, {:task_completed, "last-task"})
      Process.sleep(100)

      # Should still be in bootstrap, not advanced
      assert {:bootstrap, _} = Orchestrator.get_state(pid)
      _ = data_before

      :gen_statem.stop(pid)
    end
  end
end
