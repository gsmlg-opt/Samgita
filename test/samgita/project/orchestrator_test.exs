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
end
