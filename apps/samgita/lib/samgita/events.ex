defmodule Samgita.Events do
  @moduledoc """
  PubSub event broadcasting for real-time updates.
  """

  @pubsub Samgita.PubSub

  def subscribe_project(project_id) do
    Phoenix.PubSub.subscribe(@pubsub, "project:#{project_id}")
  end

  def subscribe_agents do
    Phoenix.PubSub.subscribe(@pubsub, "agents")
  end

  def subscribe_all_projects do
    Phoenix.PubSub.subscribe(@pubsub, "projects")
  end

  def task_completed(task) do
    Phoenix.PubSub.broadcast(@pubsub, "project:#{task.project_id}", {:task_completed, task})
    Samgita.Webhooks.dispatch("task.completed", %{task_id: task.id, project_id: task.project_id})
  end

  def task_failed(task) do
    Phoenix.PubSub.broadcast(@pubsub, "project:#{task.project_id}", {:task_failed, task})
    Samgita.Webhooks.dispatch("task.failed", %{task_id: task.id, project_id: task.project_id})
  end

  def agent_spawned(project_id, agent_id, agent_type) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "project:#{project_id}",
      {:agent_spawned, agent_id, agent_type}
    )

    Phoenix.PubSub.broadcast(@pubsub, "agents", {:agent_spawned, agent_id, agent_type})
  end

  def agent_state_changed(project_id, agent_id, state) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "project:#{project_id}",
      {:agent_state_changed, agent_id, state}
    )
  end

  def phase_changed(project_id, phase) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "project:#{project_id}",
      {:phase_changed, project_id, phase}
    )

    Phoenix.PubSub.broadcast(@pubsub, "projects", {:project_updated, project_id, phase})
    Samgita.Webhooks.dispatch("project.phase_changed", %{project_id: project_id, phase: phase})
  end

  def project_updated(project) do
    Phoenix.PubSub.broadcast(@pubsub, "projects", {:project_updated, project})
  end

  def activity_log(project_id, entry) do
    Phoenix.PubSub.broadcast(@pubsub, "project:#{project_id}", {:activity_log, entry})
  end

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
