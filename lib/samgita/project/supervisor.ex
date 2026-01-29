defmodule Samgita.Project.Supervisor do
  @moduledoc """
  Per-project supervisor managing the orchestrator, memory server,
  and agent workers for a single project.
  """

  use Supervisor

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    Supervisor.start_link(__MODULE__, opts, name: via(project_id))
  end

  def child_spec(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    %{
      id: {:project_supervisor, project_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :supervisor
    }
  end

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    children = [
      {Samgita.Project.Memory, project_id: project_id},
      {Samgita.Project.Orchestrator, project_id: project_id}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via(project_id) do
    {:via, Horde.Registry, {Samgita.AgentRegistry, {:project_supervisor, project_id}}}
  end
end
