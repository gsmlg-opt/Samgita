defmodule SamgitaWeb.ProjectJSON do
  alias Samgita.Domain.Project

  def index(%{projects: projects}) do
    %{data: for(project <- projects, do: data(project))}
  end

  def show(%{project: project}) do
    %{data: data(project)}
  end

  defp data(%Project{} = project) do
    %{
      id: project.id,
      name: project.name,
      git_url: project.git_url,
      working_path: project.working_path,
      phase: project.phase,
      status: project.status,
      config: project.config,
      inserted_at: project.inserted_at,
      updated_at: project.updated_at
    }
  end
end
