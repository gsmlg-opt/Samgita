defmodule SamgitaWeb.ProjectController do
  use SamgitaWeb, :controller

  alias Samgita.Projects
  alias Samgita.Domain.Project

  action_fallback SamgitaWeb.FallbackController

  def index(conn, _params) do
    projects = Projects.list_projects()
    render(conn, :index, projects: projects)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, project} <- Projects.get_project(id) do
      render(conn, :show, project: project)
    end
  end

  def create(conn, %{"project" => project_params}) do
    with {:ok, %Project{} = project} <- Projects.create_project(project_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/projects/#{project}")
      |> render(:show, project: project)
    end
  end

  def update(conn, %{"id" => id, "project" => project_params}) do
    with {:ok, project} <- Projects.get_project(id),
         {:ok, %Project{} = updated} <- Projects.update_project(project, project_params) do
      render(conn, :show, project: updated)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, project} <- Projects.get_project(id),
         {:ok, _} <- Projects.delete_project(project) do
      send_resp(conn, :no_content, "")
    end
  end

  def pause(conn, %{"project_id" => id}) do
    with {:ok, %Project{} = project} <- Projects.pause_project(id) do
      render(conn, :show, project: project)
    end
  end

  def resume(conn, %{"project_id" => id}) do
    with {:ok, %Project{} = project} <- Projects.resume_project(id) do
      render(conn, :show, project: project)
    end
  end
end
