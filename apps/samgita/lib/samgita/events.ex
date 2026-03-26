defmodule Samgita.Events do
  @moduledoc """
  PubSub event broadcasting for real-time updates.
  """

  @pubsub Samgita.PubSub

  @spec subscribe_project(String.t()) :: :ok | {:error, term()}
  def subscribe_project(project_id) do
    Phoenix.PubSub.subscribe(@pubsub, "project:#{project_id}")
  end

  @spec subscribe_agents() :: :ok | {:error, term()}
  def subscribe_agents do
    Phoenix.PubSub.subscribe(@pubsub, "agents")
  end

  @spec subscribe_all_projects() :: :ok | {:error, term()}
  def subscribe_all_projects do
    Phoenix.PubSub.subscribe(@pubsub, "projects")
  end

  @spec task_completed(struct()) :: :ok
  def task_completed(task) do
    Phoenix.PubSub.broadcast(@pubsub, "project:#{task.project_id}", {:task_completed, task})
    Phoenix.PubSub.broadcast(@pubsub, "projects", {:task_stats_changed, task.project_id})
    Samgita.Webhooks.dispatch("task.completed", %{task_id: task.id, project_id: task.project_id})
  end

  @spec task_failed(struct()) :: :ok
  def task_failed(task) do
    Phoenix.PubSub.broadcast(@pubsub, "project:#{task.project_id}", {:task_failed, task})
    Phoenix.PubSub.broadcast(@pubsub, "projects", {:task_stats_changed, task.project_id})
    Samgita.Webhooks.dispatch("task.failed", %{task_id: task.id, project_id: task.project_id})
  end

  @spec agent_spawned(String.t(), String.t(), String.t()) :: :ok
  def agent_spawned(project_id, agent_id, agent_type) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "project:#{project_id}",
      {:agent_spawned, agent_id, agent_type}
    )

    Phoenix.PubSub.broadcast(@pubsub, "agents", {:agent_spawned, agent_id, agent_type})
  end

  @spec agent_state_changed(String.t(), String.t(), atom()) :: :ok
  def agent_state_changed(project_id, agent_id, state) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "project:#{project_id}",
      {:agent_state_changed, agent_id, state}
    )
  end

  @spec phase_changed(String.t(), atom()) :: :ok
  def phase_changed(project_id, phase) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "project:#{project_id}",
      {:phase_changed, project_id, phase}
    )

    Phoenix.PubSub.broadcast(@pubsub, "projects", {:project_updated, project_id, phase})
    Samgita.Webhooks.dispatch("project.phase_changed", %{project_id: project_id, phase: phase})
  end

  @spec project_updated(struct()) :: :ok
  def project_updated(project) do
    Phoenix.PubSub.broadcast(@pubsub, "projects", {:project_updated, project})
  end

  @spec quality_gate_completed(String.t(), atom(), [map()]) :: :ok
  def quality_gate_completed(project_id, verdict, gate_results) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "project:#{project_id}",
      {:quality_gate_results, project_id, verdict, gate_results}
    )

    findings_count =
      gate_results
      |> Enum.flat_map(fn r -> Map.get(r, :findings, []) end)
      |> length()

    Samgita.Webhooks.dispatch("quality_gate.completed", %{
      project_id: project_id,
      verdict: to_string(verdict),
      gate_count: length(gate_results),
      findings_count: findings_count
    })
  end

  @spec stagnation_detected(String.t(), atom(), non_neg_integer()) :: :ok
  def stagnation_detected(project_id, phase, checks) do
    Samgita.Webhooks.dispatch("project.stagnation_detected", %{
      project_id: project_id,
      phase: to_string(phase),
      stagnation_checks: checks
    })
  end

  @spec activity_log(String.t(), map()) :: :ok
  def activity_log(project_id, entry) do
    Phoenix.PubSub.broadcast(@pubsub, "project:#{project_id}", {:activity_log, entry})
  end

  @spec build_log_entry(atom(), String.t(), atom(), String.t(), keyword()) :: map()
  def build_log_entry(source, source_id, stage, message, opts \\ []) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      timestamp: DateTime.utc_now(),
      source: source,
      source_id: source_id,
      stage: stage,
      message: message,
      output: Keyword.get(opts, :output)
    }
  end
end
