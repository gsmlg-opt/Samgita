defmodule SamgitaWeb.AgentRunJSON do
  alias Samgita.Domain.AgentRun

  def index(%{agent_runs: agent_runs}) do
    %{data: for(agent_run <- agent_runs, do: data(agent_run))}
  end

  def show(%{agent_run: agent_run}) do
    %{data: data(agent_run)}
  end

  defp data(%AgentRun{} = agent_run) do
    %{
      id: agent_run.id,
      agent_type: agent_run.agent_type,
      node: agent_run.node,
      status: agent_run.status,
      total_tasks: agent_run.total_tasks,
      total_tokens: agent_run.total_tokens,
      total_duration_ms: agent_run.total_duration_ms,
      started_at: agent_run.started_at,
      ended_at: agent_run.ended_at,
      project_id: agent_run.project_id,
      inserted_at: agent_run.inserted_at,
      updated_at: agent_run.updated_at
    }
  end
end
