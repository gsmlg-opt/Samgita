defmodule SamgitaWeb.AgentRunController do
  use SamgitaWeb, :controller

  alias Samgita.Projects

  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => project_id}) do
    with {:ok, _project} <- Projects.get_project(project_id) do
      agent_runs = Projects.list_agent_runs(project_id)
      render(conn, :index, agent_runs: agent_runs)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, agent_run} <- Projects.get_agent_run(id) do
      render(conn, :show, agent_run: agent_run)
    end
  end
end
