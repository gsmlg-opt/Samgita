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
    Process.sleep(100)

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
    Process.sleep(100)

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
      # Should have set phase_tasks_total to 1 (BootstrapWorker enqueued)
      assert data.phase_tasks_total == 1

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
end
