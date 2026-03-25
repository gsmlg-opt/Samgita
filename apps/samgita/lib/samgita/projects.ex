defmodule Samgita.Projects do
  @moduledoc """
  Context module for project management.
  """

  import Ecto.Query
  alias Samgita.Domain.AgentRun
  alias Samgita.Domain.Project
  alias Samgita.Domain.Task, as: TaskSchema
  alias Samgita.Project.Orchestrator
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
         true <- project.status == :running || {:error, :not_running},
         {:ok, project} <- update_project(project, %{status: :paused}) do
      notify_orchestrator_pause(id)
      {:ok, project}
    end
  end

  def resume_project(id) do
    with {:ok, project} <- get_project(id),
         true <- project.status == :paused || {:error, :not_paused},
         {:ok, project} <- update_project(project, %{status: :running}) do
      notify_orchestrator_resume(id)
      {:ok, project}
    end
  end

  defp notify_orchestrator_pause(project_id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] -> Orchestrator.pause(pid)
      [] -> :ok
    end
  end

  defp notify_orchestrator_resume(project_id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] -> Orchestrator.resume(pid)
      [] -> :ok
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
      update_active_prd_status(project.active_prd_id, :approved)
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
      update_active_prd_status(project.active_prd_id, :draft)
      fail_pending_tasks(id)
      update_project(project, %{status: :failed, active_prd_id: nil})
    end
  end

  defp update_active_prd_status(nil, _status), do: :ok

  defp update_active_prd_status(prd_id, status) do
    case Samgita.Prds.get_prd(prd_id) do
      {:ok, prd} -> Samgita.Prds.update_prd(prd, %{status: status})
      _ -> :ok
    end
  end

  defp fail_pending_tasks(project_id) do
    from(t in TaskSchema,
      where: t.project_id == ^project_id,
      where: t.status in [:pending, :running]
    )
    |> Repo.update_all(set: [status: :failed, error: %{"reason" => "project terminated"}])
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

  def complete_task(id) do
    case Repo.get(TaskSchema, id) do
      nil ->
        {:error, :not_found}

      task ->
        task
        |> TaskSchema.changeset(%{status: :completed, completed_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  def retry_task(id) do
    with {:ok, task} <- get_task(id),
         true <- task.status in [:failed, :dead_letter] || {:error, :not_retriable},
         {:ok, task} <-
           task
           |> TaskSchema.changeset(%{status: :pending, attempts: 0, error: nil})
           |> Repo.update() do
      # Re-enqueue in Oban
      agent_type = get_in(task.payload, ["agent_type"]) || "eng-backend"

      Oban.insert(
        AgentTaskWorker.new(%{
          task_id: task.id,
          project_id: task.project_id,
          agent_type: agent_type
        })
      )

      {:ok, task}
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

  @doc "Find or create an agent run for a project and agent type."
  def find_or_create_agent_run(project_id, agent_type, attrs \\ %{}) do
    case AgentRun
         |> where(project_id: ^project_id, agent_type: ^agent_type)
         |> where([a], is_nil(a.ended_at))
         |> Repo.one() do
      nil ->
        %AgentRun{}
        |> AgentRun.changeset(
          Map.merge(
            %{
              project_id: project_id,
              agent_type: agent_type,
              status: :idle,
              started_at: DateTime.utc_now(),
              node: Atom.to_string(Node.self())
            },
            attrs
          )
        )
        |> Repo.insert()

      agent_run ->
        {:ok, agent_run}
    end
  end

  @doc "Update an agent run's status and metrics."
  def update_agent_run(agent_run, attrs) do
    agent_run
    |> AgentRun.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns aggregate task counts by status for a project."
  def task_stats(project_id) do
    TaskSchema
    |> where(project_id: ^project_id)
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Returns task stats for multiple projects in a single query, avoiding N+1."
  def task_stats_batch(project_ids) when is_list(project_ids) do
    if project_ids == [] do
      %{}
    else
      TaskSchema
      |> where([t], t.project_id in ^project_ids)
      |> group_by([t], [t.project_id, t.status])
      |> select([t], {t.project_id, t.status, count(t.id)})
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), fn {_pid, status, count} -> {status, count} end)
      |> Map.new(fn {pid, stats} -> {pid, Map.new(stats)} end)
    end
  end

  # Artifact management

  alias Samgita.Domain.Artifact

  def list_artifacts(project_id) do
    Artifact
    |> where(project_id: ^project_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_artifact(id) do
    case Repo.get(Artifact, id) do
      nil -> {:error, :not_found}
      artifact -> {:ok, artifact}
    end
  end

  def create_artifact(project_id, attrs) do
    %Artifact{}
    |> Artifact.changeset(Map.put(attrs, :project_id, project_id))
    |> Repo.insert()
  end

  def delete_artifact(%Artifact{} = artifact) do
    Repo.delete(artifact)
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
