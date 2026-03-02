defmodule Samgita.Project.RecoveryTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Project.Recovery
  alias Samgita.Projects

  setup do
    Sandbox.mode(Samgita.Repo, {:shared, self()})
    :ok
  end

  test "recover_projects returns {0, 0} when no running projects" do
    assert {0, 0} = Recovery.recover_projects()
  end

  test "recover_projects skips pending projects" do
    {:ok, _} =
      Projects.create_project(%{
        name: "Pending Project",
        git_url: "git@github.com:test/pending-#{System.unique_integer([:positive])}.git",
        prd_content: "# Pending",
        status: :pending
      })

    assert {0, 0} = Recovery.recover_projects()
  end

  test "recover_projects skips running projects without active_prd_id" do
    {:ok, _} =
      Projects.create_project(%{
        name: "No PRD Project",
        git_url: "git@github.com:test/no-prd-#{System.unique_integer([:positive])}.git",
        prd_content: "# No PRD",
        status: :running
      })

    assert {0, 0} = Recovery.recover_projects()
  end

  test "recover_projects recovers running project with active_prd" do
    {:ok, project} =
      Projects.create_project(%{
        name: "Running Project",
        git_url: "git@github.com:test/running-#{System.unique_integer([:positive])}.git",
        prd_content: "# Running",
        status: :pending
      })

    {:ok, prd} =
      Samgita.Prds.create_prd(%{
        project_id: project.id,
        title: "Test PRD",
        content: "# Test",
        status: :approved
      })

    # Simulate a project that was running when BEAM stopped
    {:ok, _} =
      Projects.update_project(project, %{
        status: :running,
        phase: :discovery,
        active_prd_id: prd.id
      })

    {recovered, failed} = Recovery.recover_projects()
    assert recovered == 1
    assert failed == 0

    # Verify orchestrator is running (phase may advance due to inline Oban execution)
    Process.sleep(500)

    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project.id}) do
      [{pid, _}] ->
        {phase, _data} = Samgita.Project.Orchestrator.get_state(pid)
        # Orchestrator starts at persisted phase but may auto-advance with inline Oban
        assert phase in [:discovery, :architecture, :infrastructure, :development]
        :gen_statem.stop(pid)

      [] ->
        flunk("Orchestrator should be running after recovery")
    end

    # Clean up supervisor
    Process.sleep(100)

    case Horde.Registry.lookup(Samgita.AgentRegistry, {:project_supervisor, project.id}) do
      [{pid, _}] -> Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, pid)
      [] -> :ok
    end
  end

  test "recover_projects resets stuck running tasks" do
    {:ok, project} =
      Projects.create_project(%{
        name: "Stuck Tasks Project",
        git_url: "git@github.com:test/stuck-#{System.unique_integer([:positive])}.git",
        prd_content: "# Stuck",
        status: :pending
      })

    {:ok, prd} =
      Samgita.Prds.create_prd(%{
        project_id: project.id,
        title: "Test PRD",
        content: "# Test",
        status: :approved
      })

    {:ok, _} =
      Projects.update_project(project, %{
        status: :running,
        phase: :bootstrap,
        active_prd_id: prd.id
      })

    # Create a stuck running task
    {:ok, task} =
      Projects.create_task(project.id, %{
        type: "implement",
        status: :running,
        started_at: DateTime.utc_now()
      })

    {recovered, _} = Recovery.recover_projects()
    assert recovered == 1

    # Verify task was reset to pending
    {:ok, updated_task} = Projects.get_task(task.id)
    assert updated_task.status == :pending
    assert updated_task.started_at == nil

    # Clean up
    Process.sleep(200)

    case Horde.Registry.lookup(Samgita.AgentRegistry, {:project_supervisor, project.id}) do
      [{pid, _}] -> Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, pid)
      [] -> :ok
    end
  end
end
