defmodule SamgitaWeb.TaskControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Projects

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Task Test",
        git_url: "git@github.com:org/task-test-#{System.unique_integer([:positive])}.git"
      })

    %{project: project}
  end

  describe "index" do
    test "lists tasks for project", %{conn: conn, project: project} do
      {:ok, _task} = Projects.create_task(project.id, %{type: "build", priority: 1})
      conn = get(conn, ~p"/api/projects/#{project}/tasks")
      assert [task] = json_response(conn, 200)["data"]
      assert task["type"] == "build"
    end

    test "returns empty list for project with no tasks", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/tasks")
      assert json_response(conn, 200)["data"] == []
    end

    test "returns 404 for nonexistent project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/tasks")
      assert json_response(conn, 404)
    end
  end

  describe "show" do
    test "shows task by id", %{conn: conn, project: project} do
      {:ok, task} = Projects.create_task(project.id, %{type: "test", priority: 2})
      conn = get(conn, ~p"/api/projects/#{project}/tasks/#{task}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == task.id
      assert data["type"] == "test"
      assert data["priority"] == 2
    end

    test "returns 404 for missing task", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project}/tasks/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "retry" do
    test "retries a failed task", %{conn: conn, project: project} do
      {:ok, task} =
        Projects.create_task(project.id, %{type: "build", status: :failed, attempts: 3})

      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      data = json_response(conn, 200)["data"]
      assert data["status"] == "pending"
      assert data["attempts"] == 0
    end

    test "retries a dead_letter task", %{conn: conn, project: project} do
      {:ok, task} =
        Projects.create_task(project.id, %{type: "deploy", status: :dead_letter, attempts: 5})

      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn, 200)["data"]["status"] == "pending"
    end

    test "rejects retry for pending task", %{conn: conn, project: project} do
      {:ok, task} = Projects.create_task(project.id, %{type: "lint", priority: 1})
      conn = post(conn, ~p"/api/projects/#{project}/tasks/#{task}/retry")
      assert json_response(conn, 422)
    end
  end
end
