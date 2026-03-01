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

  def start_project(id, prd_id) do
    with {:ok, project} <- get_project(id),
         true <- project.status in [:pending, :completed, :failed] || {:error, :already_active},
         {:ok, prd} <- Samgita.Prds.get_prd(prd_id),
         true <- prd.project_id == project.id || {:error, :prd_not_in_project},
         {:ok, _prd} <- Samgita.Prds.update_prd(prd, %{status: :in_progress}),
         {:ok, project} <-
           update_project(project, %{
             status: :running,
             phase: :bootstrap,
             active_prd_id: prd_id
           }) do
      Horde.DynamicSupervisor.start_child(
        Samgita.AgentSupervisor,
        {Samgita.Project.Supervisor, project_id: project.id}
      )

      {:ok, project}
    end
  end

  def stop_project(id) do
    with {:ok, project} <- get_project(id),
         true <- project.status in [:running, :paused] || {:error, :not_active} do
      terminate_supervisor(id)

      if project.active_prd_id do
        case Samgita.Prds.get_prd(project.active_prd_id) do
          {:ok, prd} -> Samgita.Prds.update_prd(prd, %{status: :approved})
          _ -> :ok
        end
      end

      update_project(project, %{status: :completed, active_prd_id: nil})
    end
  end

  def restart_project(id) do
    with {:ok, project} <- get_project(id),
         true <- project.status in [:running, :paused] || {:error, :not_active},
         true <- project.active_prd_id != nil || {:error, :no_active_prd} do
      prd_id = project.active_prd_id
      terminate_supervisor(id)

      {:ok, project} =
        update_project(project, %{status: :pending, phase: :bootstrap, active_prd_id: nil})

      start_project(project.id, prd_id)
    end
  end

  def terminate_project(id) do
    with {:ok, project} <- get_project(id),
         true <- project.status in [:running, :paused] || {:error, :not_active} do
      terminate_supervisor(id)

      if project.active_prd_id do
        case Samgita.Prds.get_prd(project.active_prd_id) do
          {:ok, prd} -> Samgita.Prds.update_prd(prd, %{status: :draft})
          _ -> :ok
        end
      end

      from(t in TaskSchema,
        where: t.project_id == ^id,
        where: t.status in [:pending, :running]
      )
      |> Repo.update_all(set: [status: :failed, error: %{"reason" => "project terminated"}])

      update_project(project, %{status: :failed, active_prd_id: nil})
    end
  end

  defp terminate_supervisor(id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:project_supervisor, id}) do
      [{pid, _}] ->
        Horde.DynamicSupervisor.terminate_child(Samgita.AgentSupervisor, pid)

      [] ->
        :ok
    end
  end

  def list_tasks_for_prd(project_id, prd_id) do
    TaskSchema
    |> where(project_id: ^project_id)
    |> where([t], fragment("?->>'prd_id' = ?", t.payload, ^prd_id))
    |> order_by(asc: :priority, asc: :inserted_at)
    |> Repo.all()
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
