defmodule Samgita.Telemetry do
  @moduledoc """
  Application telemetry events for metrics and observability.
  """

  def agent_task_start(metadata) do
    :telemetry.execute(
      [:samgita, :agent, :task_start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  def agent_task_complete(metadata, measurements) do
    :telemetry.execute(
      [:samgita, :agent, :task_complete],
      measurements,
      metadata
    )
  end

  def agent_task_failure(metadata, measurements) do
    :telemetry.execute(
      [:samgita, :agent, :task_failure],
      measurements,
      metadata
    )
  end

  def phase_transition(project_id, from_phase, to_phase) do
    :telemetry.execute(
      [:samgita, :project, :phase_transition],
      %{system_time: System.system_time()},
      %{project_id: project_id, from: from_phase, to: to_phase}
    )
  end

  def agent_spawned(project_id, agent_type, node) do
    :telemetry.execute(
      [:samgita, :agent, :spawned],
      %{count: 1},
      %{project_id: project_id, agent_type: agent_type, node: node}
    )
  end
end
