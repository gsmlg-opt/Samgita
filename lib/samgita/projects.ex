defmodule Samgita.Projects do
  @moduledoc """
  Context module for project management.
  """

  import Ecto.Query
  alias Samgita.Repo
  alias Samgita.Domain.Project

  def list_projects do
    Project
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  def get_project(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  def pause_project(id) do
    with {:ok, project} <- get_project(id),
         true <- project.status == :running || {:error, :not_running} do
      update_project(project, %{status: :paused})
    end
  end

  def resume_project(id) do
    with {:ok, project} <- get_project(id),
         true <- project.status == :paused || {:error, :not_paused} do
      update_project(project, %{status: :running})
    end
  end

  def update_prd(%Project{} = project, prd_content) do
    update_project(project, %{prd_content: prd_content})
  end
end
