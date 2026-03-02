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
  alias Samgita.Quality.InputGuardrails
  alias Samgita.Repo

  @impl true
  def perform(%Oban.Job{args: args}) do
    task_id = args["task_id"]
    project_id = args["project_id"]
    agent_type = args["agent_type"]

    Logger.info("AgentTaskWorker: executing task #{task_id} with agent type #{agent_type}")

    # Gate 1: Input Guardrails — validate before execution
    gate_result = InputGuardrails.validate(args)

    if gate_result.verdict == :fail do
      Logger.warning("AgentTaskWorker: input guardrails blocked task #{task_id}")

      entry =
        Samgita.Events.build_log_entry(
          :task,
          task_id,
          :failed,
          "Input guardrails blocked: #{Enum.map_join(gate_result.findings, "; ", & &1.message)}"
        )

      Samgita.Events.activity_log(project_id, entry)
      handle_failure(task_id, :input_guardrails_blocked)
      {:error, :input_guardrails_blocked}
    else
      execute_task_pipeline(args)
    end
  end

  defp execute_task_pipeline(args) do
    task_id = args["task_id"]
    project_id = args["project_id"]
    agent_type = args["agent_type"]

    with {:ok, task} <- get_task(task_id),
         :ok <- check_parent_dependency(task),
         :ok <- mark_task_running(task),
         {:ok, agent_pid} <- find_or_spawn_agent(project_id, agent_type),
         :ok <- execute_task(agent_pid, task) do
      mark_task_completed(task)
      Samgita.Events.task_completed(task)
      notify_orchestrator(project_id, task_id)

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
      {:error, :parent_not_completed} ->
        Logger.info("AgentTaskWorker: task #{task_id} waiting for parent to complete, snoozing")
        {:snooze, 30}

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

  defp check_parent_dependency(%{parent_task_id: nil}), do: :ok

  defp check_parent_dependency(%{parent_task_id: parent_id}) do
    case Repo.get(TaskSchema, parent_id) do
      nil -> :ok
      %{status: :completed} -> :ok
      _ -> {:error, :parent_not_completed}
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

  defp notify_orchestrator(project_id, task_id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] ->
        Samgita.Project.Orchestrator.notify_task_completed(pid, task_id)

      [] ->
        Logger.debug("AgentTaskWorker: No orchestrator found for #{project_id}, skipping notify")
    end
  end

  defp handle_failure(task_id, reason) do
    case Repo.get(TaskSchema, task_id) do
      nil ->
        :ok

      task ->
        attempts = task.attempts + 1
        failure_type = classify_failure(reason)
        max_attempts = max_attempts_for(failure_type)
        status = if attempts >= max_attempts, do: :dead_letter, else: :failed

        case task
             |> TaskSchema.changeset(%{
               status: status,
               attempts: attempts,
               error: %{
                 reason: inspect(reason),
                 failure_type: Atom.to_string(failure_type),
                 attempt: attempts,
                 max_attempts: max_attempts
               }
             })
             |> Repo.update() do
          {:ok, updated_task} ->
            Samgita.Events.task_failed(updated_task)
            {:ok, updated_task}

          error ->
            error
        end
    end
  end

  defp classify_failure(:input_guardrails_blocked), do: :terminal
  defp classify_failure(:task_not_found), do: :terminal
  defp classify_failure(:project_not_found), do: :terminal
  defp classify_failure(:rate_limited), do: :rate_limit
  defp classify_failure(:overloaded), do: :rate_limit
  defp classify_failure(:timeout), do: :transient
  defp classify_failure(:circuit_open), do: :circuit_breaker
  defp classify_failure(_), do: :unknown

  # Terminal errors should not be retried
  defp max_attempts_for(:terminal), do: 1
  # Rate limits get more retries with backoff
  defp max_attempts_for(:rate_limit), do: 8
  # Circuit breaker should retry after cool-down
  defp max_attempts_for(:circuit_breaker), do: 3
  # Default for transient and unknown
  defp max_attempts_for(_), do: 5
end
