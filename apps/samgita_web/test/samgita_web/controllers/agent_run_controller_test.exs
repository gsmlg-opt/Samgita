defmodule SamgitaWeb.AgentRunControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Domain.AgentRun
  alias Samgita.Projects
  alias Samgita.Repo

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Agent Test",
        git_url: "git@github.com:org/agent-test-#{System.unique_integer([:positive])}.git"
      })

    %{project: project}
  end

  defp create_agent_run(project_id, agent_type) do
    %AgentRun{}
    |> AgentRun.changeset(%{
      agent_type: agent_type,
      project_id: project_id,
      node: "nonode@nohost",
      status: :idle
    })
    |> Repo.insert!()
  end

  describe "index" do
    test "lists agent runs for project", %{conn: conn, project: project} do
      create_agent_run(project.id, "eng-backend")
      conn = get(conn, ~p"/api/projects/#{project}/agents")
      assert [agent] = json_response(conn, 200)["data"]
      assert agent["agent_type"] == "eng-backend"
    end

    test "returns empty list when no agents", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/agents")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns 404 for nonexistent project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/agents")
      assert json_response(conn, 404)
    end
  end

  describe "show" do
    test "shows agent run by id", %{conn: conn, project: project} do
      agent_run = create_agent_run(project.id, "eng-frontend")
      conn = get(conn, ~p"/api/projects/#{project}/agents/#{agent_run}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == agent_run.id
      assert data["agent_type"] == "eng-frontend"
      assert data["status"] == "idle"
    end

    test "returns 404 for missing agent run", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/agents/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end
end
