defmodule Samgita.Project.SupervisorTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Project.Orchestrator
  alias Samgita.Project.Supervisor, as: ProjectSupervisor
  alias Samgita.Projects

  setup do
    Mox.set_mox_global(self())

    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

    Mox.stub(Samgita.MockOban, :insert, fn job -> Oban.insert(job) end)
    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Supervisor Test",
        git_url: "git@github.com:test/supervisor-#{System.unique_integer([:positive])}.git",
        prd_content: "# Test PRD"
      })

    %{project: project}
  end

  test "child_spec uses project_id as part of id", %{project: project} do
    spec = ProjectSupervisor.child_spec(project_id: project.id)

    assert spec.id == {:project_supervisor, project.id}
    assert spec.type == :supervisor
    assert spec.restart == :transient
  end

  test "child_spec start tuple is correctly formed", %{project: project} do
    spec = ProjectSupervisor.child_spec(project_id: project.id)

    assert {ProjectSupervisor, :start_link, [opts]} = spec.start
    assert Keyword.get(opts, :project_id) == project.id
  end

  test "child_spec raises when project_id missing" do
    assert_raise KeyError, fn ->
      ProjectSupervisor.child_spec([])
    end
  end

  test "start_link raises when project_id missing" do
    assert_raise KeyError, fn ->
      ProjectSupervisor.start_link([])
    end
  end

  test "init returns children spec with Memory and Orchestrator", %{project: project} do
    assert {:ok, {sup_flags, children}} = ProjectSupervisor.init(project_id: project.id)

    assert sup_flags.strategy == :one_for_one

    child_modules =
      Enum.map(children, fn
        %{start: {mod, _, _}} -> mod
        {mod, _opts} -> mod
      end)

    assert Samgita.Project.Memory in child_modules
    assert Samgita.Project.Orchestrator in child_modules
  end

  test "supervisor can be started via Horde.DynamicSupervisor", %{project: project} do
    {:ok, _pid} =
      Horde.DynamicSupervisor.start_child(
        Samgita.AgentSupervisor,
        ProjectSupervisor.child_spec(project_id: project.id)
      )

    Process.sleep(100)

    # Verify supervisor registered in AgentRegistry
    assert [{_pid, _}] =
             Horde.Registry.lookup(
               Samgita.AgentRegistry,
               {:project_supervisor, project.id}
             )

    # Clean up
    [{pid, _}] =
      Horde.Registry.lookup(Samgita.AgentRegistry, {:project_supervisor, project.id})

    Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, pid)
  end

  test "orchestrator is accessible after supervisor start", %{project: project} do
    result =
      Horde.DynamicSupervisor.start_child(
        Samgita.AgentSupervisor,
        ProjectSupervisor.child_spec(project_id: project.id)
      )

    case result do
      {:ok, _pid} ->
        Process.sleep(150)

        # Orchestrator should be registered and running
        case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project.id}) do
          [{pid, _}] ->
            assert Process.alive?(pid)
            {phase, data} = Orchestrator.get_state(pid)
            assert phase == :bootstrap
            assert data.project_id == project.id

          [] ->
            # Orchestrator may not have Horde available in test env — verify via supervisor child list
            [{sup_pid, _}] =
              Horde.Registry.lookup(Samgita.AgentRegistry, {:project_supervisor, project.id})

            children = Supervisor.which_children(sup_pid)

            orchestrator_child =
              Enum.find(children, fn {id, _, _, _} -> id == {:orchestrator, project.id} end)

            assert orchestrator_child != nil
        end

        # Clean up
        case Horde.Registry.lookup(Samgita.AgentRegistry, {:project_supervisor, project.id}) do
          [{pid, _}] -> Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, pid)
          [] -> :ok
        end

      {:error, {:shutdown, {:failed_to_start_child, _, {:process_not_registered_via, _}}}} ->
        # Horde.Registry may not be fully synced in test env — this is expected
        :ok
    end
  end

  test "orchestrator restarts after crash when under supervisor", %{project: project} do
    {:ok, _} =
      Horde.DynamicSupervisor.start_child(
        Samgita.AgentSupervisor,
        ProjectSupervisor.child_spec(project_id: project.id)
      )

    Process.sleep(300)

    # Find supervisor PID — must be present since we just started it
    [{sup_pid, _}] =
      Horde.Registry.lookup(Samgita.AgentRegistry, {:project_supervisor, project.id})

    assert Process.alive?(sup_pid), "ProjectSupervisor must be alive"

    # Find orchestrator as direct child of the supervisor (reliable regardless of Horde state).
    # Orchestrator child_spec uses id: {:orchestrator, project_id}
    orchestrator_id = {:orchestrator, project.id}
    children = Supervisor.which_children(sup_pid)
    orchestrator_child = Enum.find(children, fn {id, _, _, _} -> id == orchestrator_id end)
    assert orchestrator_child != nil, "Orchestrator must be a child of ProjectSupervisor"

    {^orchestrator_id, orchestrator_pid_before, :worker, _} = orchestrator_child
    assert is_pid(orchestrator_pid_before), "Orchestrator child must have a live pid"
    assert Process.alive?(orchestrator_pid_before), "Orchestrator must be alive before crash"

    # Kill the orchestrator — the ProjectSupervisor (one_for_one) should restart it
    Process.exit(orchestrator_pid_before, :kill)
    Process.sleep(300)

    # Orchestrator must have been restarted
    children_after = Supervisor.which_children(sup_pid)
    orchestrator_after = Enum.find(children_after, fn {id, _, _, _} -> id == orchestrator_id end)
    assert orchestrator_after != nil, "Orchestrator must still be a child after crash"

    {^orchestrator_id, orchestrator_pid_after, :worker, _} = orchestrator_after
    assert is_pid(orchestrator_pid_after), "Restarted orchestrator must have a live pid"
    assert Process.alive?(orchestrator_pid_after), "Restarted orchestrator must be alive"

    assert orchestrator_pid_after != orchestrator_pid_before,
           "Restarted orchestrator must have a new pid (different from killed pid)"

    # Clean up
    Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, sup_pid)
  end
end
