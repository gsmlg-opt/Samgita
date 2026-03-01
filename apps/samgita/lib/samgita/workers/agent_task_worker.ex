defmodule Samgita.Workers.AgentTaskWorker do
  @moduledoc """
  Oban worker that dispatches tasks to agent workers.
  Finds or spawns the appropriate agent and assigns the task.
  """

  use Oban.Worker,
    queue: :agent_tasks,
    max_attempts: 5,
    unique: [period: 60, states: [:available, :executing]]

  require Logger

  alias Samgita.Domain.Task, as: TaskSchema
  alias Samgita.Repo

  @impl true
  def perform(%Oban.Job{args: args}) do
    task_id = args["task_id"]
    project_id = args["project_id"]
    agent_type = args["agent_type"]

    Logger.info("AgentTaskWorker: executing task #{task_id} with agent type #{agent_type}")

    with {:ok, task} <- get_task(task_id),
         :ok <- mark_task_running(task),
         {:ok, agent_pid} <- find_or_spawn_agent(project_id, agent_type),
         :ok <- execute_task(agent_pid, task) do
      mark_task_completed(task)
      Samgita.Events.task_completed(task)

      entry =
        Samgita.Events.build_log_entry(
          :task,
          task_id,
          :completed,
          "Task completed (agent: #{agent_type})"
        )

      Samgita.Events.activity_log(project_id, entry)
      :ok
    else
      {:error, reason} ->
        Logger.error("AgentTaskWorker failed: #{inspect(reason)}")

        entry =
          Samgita.Events.build_log_entry(
            :task,
            task_id,
            :failed,
            "Task failed: #{inspect(reason)}"
          )

        Samgita.Events.activity_log(project_id, entry)
        handle_failure(task_id, reason)
        {:error, reason}
    end
  end

  defp get_task(task_id) do
    case Repo.get(TaskSchema, task_id) do
      nil -> {:error, :task_not_found}
      task -> {:ok, task}
    end
  end

  defp mark_task_running(task) do
    task
    |> TaskSchema.changeset(%{status: :running, started_at: DateTime.utc_now()})
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp mark_task_completed(task) do
    task
    |> TaskSchema.changeset(%{
      status: :completed,
      completed_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  defp find_or_spawn_agent(project_id, agent_type) do
    agent_id = "#{project_id}-#{agent_type}"

    case Horde.Registry.lookup(Samgita.AgentRegistry, agent_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spawn_agent(project_id, agent_type, agent_id)
    end
  end

  defp spawn_agent(project_id, agent_type, agent_id) do
    spec = {
      Samgita.Agent.Worker,
      id: agent_id, agent_type: agent_type, project_id: project_id
    }

    case Horde.DynamicSupervisor.start_child(Samgita.AgentSupervisor, spec) do
      {:ok, pid} ->
        Samgita.Events.agent_spawned(project_id, agent_id, agent_type)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      error ->
        error
    end
  end

  defp execute_task(agent_pid, task) do
    Samgita.Agent.Worker.assign_task(agent_pid, task)
    :ok
  end

  defp handle_failure(task_id, reason) do
    case Repo.get(TaskSchema, task_id) do
      nil ->
        :ok

      task ->
        attempts = task.attempts + 1
        status = if attempts >= 5, do: :dead_letter, else: :failed

        task
        |> TaskSchema.changeset(%{
          status: status,
          attempts: attempts,
          error: %{reason: inspect(reason)}
        })
        |> Repo.update()
    end
  end
end
