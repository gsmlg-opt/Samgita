defmodule SamgitaWeb.PrdControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Prds
  alias Samgita.Projects

  defp create_project(_) do
    {:ok, project} =
      Projects.create_project(%{name: "Test", git_url: "git@github.com:org/prd-test.git"})

    %{project: project}
  end

  defp create_prd(%{project: project}) do
    {:ok, prd} =
      Prds.create_prd(%{
        project_id: project.id,
        title: "Test PRD",
        content: "# Test\n\nSome content"
      })

    %{prd: prd}
  end

  describe "index" do
    setup [:create_project]

    test "lists empty prds for project", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/prds")
      assert json_response(conn, 200)["data"] == []
    end

    test "lists prds for project", %{conn: conn, project: project} do
      {:ok, _prd} =
        Prds.create_prd(%{project_id: project.id, title: "PRD 1", content: "Content 1"})

      conn = get(conn, ~p"/api/projects/#{project}/prds")
      data = json_response(conn, 200)["data"]
      assert length(data) == 1
      assert hd(data)["title"] == "PRD 1"
    end
  end

  describe "show" do
    setup [:create_project, :create_prd]

    test "shows prd", %{conn: conn, project: project, prd: prd} do
      conn = get(conn, ~p"/api/projects/#{project}/prds/#{prd}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == prd.id
      assert data["title"] == "Test PRD"
      assert data["content"] == "# Test\n\nSome content"
    end

    test "returns 404 for missing prd", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/prds/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "create" do
    setup [:create_project]

    test "creates prd with valid data", %{conn: conn, project: project} do
      conn =
        post(conn, ~p"/api/projects/#{project}/prds",
          prd: %{title: "New PRD", content: "New content"}
        )

      data = json_response(conn, 201)["data"]
      assert data["title"] == "New PRD"
      assert data["project_id"] == project.id
      assert data["status"] == "draft"
    end

    test "returns errors for missing title", %{conn: conn, project: project} do
      conn = post(conn, ~p"/api/projects/#{project}/prds", prd: %{content: "No title"})
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update" do
    setup [:create_project, :create_prd]

    test "updates prd", %{conn: conn, project: project, prd: prd} do
      conn =
        put(conn, ~p"/api/projects/#{project}/prds/#{prd}",
          prd: %{title: "Updated PRD", content: "Updated content"}
        )

      data = json_response(conn, 200)["data"]
      assert data["title"] == "Updated PRD"
      assert data["content"] == "Updated content"
    end
  end

  describe "delete" do
    setup [:create_project, :create_prd]

    test "deletes prd", %{conn: conn, project: project, prd: prd} do
      conn = delete(conn, ~p"/api/projects/#{project}/prds/#{prd}")
      assert response(conn, 204)

      conn = get(build_conn(), ~p"/api/projects/#{project}/prds/#{prd}")
      assert json_response(conn, 404)
    end
  end
end
