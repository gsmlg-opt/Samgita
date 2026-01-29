defmodule SamgitaWeb.ProjectControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Projects

  @create_attrs %{name: "Test", git_url: "git@github.com:org/test.git"}

  defp create_project(_) do
    {:ok, project} = Projects.create_project(@create_attrs)
    %{project: project}
  end

  describe "index" do
    test "lists all projects", %{conn: conn} do
      conn = get(conn, ~p"/api/projects")
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create" do
    test "creates project with valid data", %{conn: conn} do
      conn =
        post(conn, ~p"/api/projects",
          project: %{name: "New", git_url: "git@github.com:org/new.git"}
        )

      assert %{"id" => id} = json_response(conn, 201)["data"]
      assert is_binary(id)
    end

    test "returns errors for invalid data", %{conn: conn} do
      conn = post(conn, ~p"/api/projects", project: %{})
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "show" do
    setup [:create_project]

    test "shows project", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == project.id
      assert data["name"] == "Test"
    end

    test "returns 404 for missing project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "update" do
    setup [:create_project]

    test "updates project", %{conn: conn, project: project} do
      conn = put(conn, ~p"/api/projects/#{project}", project: %{name: "Updated"})
      data = json_response(conn, 200)["data"]
      assert data["name"] == "Updated"
    end
  end

  describe "delete" do
    setup [:create_project]

    test "deletes project", %{conn: conn, project: project} do
      conn = delete(conn, ~p"/api/projects/#{project}")
      assert response(conn, 204)
    end
  end

  describe "pause" do
    test "pauses running project", %{conn: conn} do
      {:ok, project} =
        Projects.create_project(%{
          name: "Run",
          git_url: "git@github.com:org/run.git",
          status: :running
        })

      conn = post(conn, ~p"/api/projects/#{project}/pause")
      assert json_response(conn, 200)["data"]["status"] == "paused"
    end
  end

  describe "resume" do
    test "resumes paused project", %{conn: conn} do
      {:ok, project} =
        Projects.create_project(%{
          name: "Paused",
          git_url: "git@github.com:org/paused.git",
          status: :paused
        })

      conn = post(conn, ~p"/api/projects/#{project}/resume")
      assert json_response(conn, 200)["data"]["status"] == "running"
    end
  end
end
