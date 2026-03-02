defmodule Samgita.Project.SupervisorTest do
  use Samgita.DataCase, async: false

  alias Samgita.Project.Supervisor, as: ProjectSupervisor

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Samgita.Projects.create_project(%{
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
end
