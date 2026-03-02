defmodule Samgita.Project.OrchestratorTest do
  # Cannot be async due to shared sandbox mode needed for gen_statem init
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Project.Orchestrator
  alias Samgita.Projects

  setup do
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
    assert data.phase_tasks_total == 0

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

    # Should be in discovery with reset counters
    {:discovery, data} = Orchestrator.get_state(pid)
    assert data.phase_tasks_total == 0
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
end
