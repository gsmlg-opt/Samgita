defmodule SamgitaWeb.TaskController do
  use SamgitaWeb, :controller

  alias Samgita.Projects

  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => project_id}) do
    with {:ok, _project} <- Projects.get_project(project_id) do
      tasks = Projects.list_tasks(project_id)
      render(conn, :index, tasks: tasks)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, task} <- Projects.get_task(id) do
      render(conn, :show, task: task)
    end
  end

  def retry(conn, %{"task_id" => id}) do
    with {:ok, task} <- Projects.retry_task(id) do
      render(conn, :show, task: task)
    end
  end
end
