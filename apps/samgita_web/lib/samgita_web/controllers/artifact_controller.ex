defmodule SamgitaWeb.ArtifactController do
  use SamgitaWeb, :controller

  alias Samgita.Projects

  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => project_id}) do
    with {:ok, _project} <- Projects.get_project(project_id) do
      artifacts = Projects.list_artifacts(project_id)
      render(conn, :index, artifacts: artifacts)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, artifact} <- Projects.get_artifact(id) do
      render(conn, :show, artifact: artifact)
    end
  end
end
