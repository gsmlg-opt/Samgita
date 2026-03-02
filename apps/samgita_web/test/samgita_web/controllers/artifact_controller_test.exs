defmodule SamgitaWeb.ArtifactControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Projects

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Artifact Test",
        git_url: "git@github.com:org/artifact-test-#{System.unique_integer([:positive])}.git"
      })

    %{project: project}
  end

  describe "index" do
    test "lists all artifacts for a project", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/artifacts")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns artifacts when they exist", %{conn: conn, project: project} do
      {:ok, _artifact} =
        Projects.create_artifact(project.id, %{
          type: :doc,
          path: "discovery/prod-pm/analysis",
          content: "# Analysis\n\nFindings here.",
          content_hash: "abc123",
          metadata: %{"phase" => "discovery"}
        })

      conn = get(conn, ~p"/api/projects/#{project}/artifacts")
      data = json_response(conn, 200)["data"]
      assert length(data) == 1
      assert hd(data)["type"] == "doc"
      assert hd(data)["path"] == "discovery/prod-pm/analysis"
    end

    test "returns 404 for missing project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/artifacts")
      assert json_response(conn, 404)
    end
  end

  describe "show" do
    test "shows an artifact", %{conn: conn, project: project} do
      {:ok, artifact} =
        Projects.create_artifact(project.id, %{
          type: :doc,
          path: "architecture/eng-backend/architecture",
          content: "# Architecture Design",
          content_hash: "def456",
          metadata: %{"phase" => "architecture", "agent_type" => "eng-backend"}
        })

      conn = get(conn, ~p"/api/projects/#{project}/artifacts/#{artifact}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == artifact.id
      assert data["content"] == "# Architecture Design"
      assert data["metadata"]["phase"] == "architecture"
    end

    test "returns 404 for missing artifact", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/artifacts/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end
end
