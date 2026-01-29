defmodule Samgita.Projects do
  @moduledoc """
  Context module for project management.
  """

  import Ecto.Query
  alias Samgita.Domain.AgentRun
  alias Samgita.Domain.Project
  alias Samgita.Domain.Task, as: TaskSchema
  alias Samgita.Repo
  alias Samgita.Workers.AgentTaskWorker

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

  def start_project(id) do
    with {:ok, project} <- get_project(id),
         {:ok, project} <- update_project(project, %{status: :running}) do
      Horde.DynamicSupervisor.start_child(
        Samgita.AgentSupervisor,
        {Samgita.Project.Supervisor, project_id: project.id}
      )

      {:ok, project}
    end
  end

  def create_task(project_id, attrs) do
    %TaskSchema{}
    |> TaskSchema.changeset(Map.put(attrs, :project_id, project_id))
    |> Repo.insert()
  end

  def list_tasks(project_id) do
    TaskSchema
    |> where(project_id: ^project_id)
    |> order_by(asc: :priority, asc: :inserted_at)
    |> Repo.all()
  end

  def get_task(id) do
    case Repo.get(TaskSchema, id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  def retry_task(id) do
    with {:ok, task} <- get_task(id),
         true <- task.status in [:failed, :dead_letter] || {:error, :not_retriable} do
      task
      |> TaskSchema.changeset(%{status: :pending, attempts: 0, error: nil})
      |> Repo.update()
    end
  end

  def list_agent_runs(project_id) do
    AgentRun
    |> where(project_id: ^project_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_agent_run(id) do
    case Repo.get(AgentRun, id) do
      nil -> {:error, :not_found}
      agent_run -> {:ok, agent_run}
    end
  end

  def enqueue_task(project_id, task_type, agent_type, payload \\ %{}) do
    with {:ok, task} <-
           create_task(project_id, %{
             type: task_type,
             payload: payload,
             queued_at: DateTime.utc_now()
           }) do
      Oban.insert(
        AgentTaskWorker.new(%{
          task_id: task.id,
          project_id: project_id,
          agent_type: agent_type
        })
      )

      {:ok, task}
    end
  end
end
