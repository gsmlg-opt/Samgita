defmodule Samgita.Project.Orchestrator do
  @moduledoc """
  Orchestrator state machine managing project lifecycle phases.

  Transitions through phases:
  :bootstrap -> :discovery -> :architecture -> :infrastructure ->
  :development -> :qa -> :deployment -> :business -> :growth -> :perpetual
  """

  @behaviour :gen_statem

  require Logger

  alias Samgita.Projects
  alias Samgita.Domain.Project

  defstruct [
    :project_id,
    :project,
    :agents,
    :task_count,
    :started_at
  ]

  @phases [
    :bootstrap,
    :discovery,
    :architecture,
    :infrastructure,
    :development,
    :qa,
    :deployment,
    :business,
    :growth,
    :perpetual
  ]

  ## Public API

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    :gen_statem.start_link(
      {:via, Horde.Registry, {Samgita.AgentRegistry, {:orchestrator, project_id}}},
      __MODULE__,
      opts,
      []
    )
  end

  def get_state(pid) do
    :gen_statem.call(pid, :get_state)
  end

  def advance_phase(pid) do
    :gen_statem.cast(pid, :advance_phase)
  end

  def child_spec(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    %{
      id: {:orchestrator, project_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  ## gen_statem callbacks

  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    case Projects.get_project(project_id) do
      {:ok, project} ->
        data = %__MODULE__{
          project_id: project_id,
          project: project,
          agents: %{},
          task_count: 0,
          started_at: DateTime.utc_now()
        }

        {:ok, project.phase, data}

      {:error, :not_found} ->
        {:stop, :project_not_found}
    end
  end

  ## Phase state callbacks - each phase follows the same pattern

  for phase <- @phases do
    def unquote(phase)(:enter, old_state, data) do
      phase = unquote(phase)
      Logger.info("Project #{data.project_id} entering phase: #{phase} (from #{old_state})")

      broadcast_phase_change(data, phase)
      persist_phase(data, phase)

      {:keep_state_and_data, [{:state_timeout, 0, :setup_phase}]}
    end

    def unquote(phase)(:state_timeout, :setup_phase, data) do
      phase = unquote(phase)
      agent_types = agents_for_phase(phase)

      Logger.info(
        "Phase #{phase}: spawning agents #{inspect(agent_types)} for project #{data.project_id}"
      )

      data = %{data | agents: Map.new(agent_types, &{&1, :pending})}
      {:keep_state, data}
    end

    def unquote(phase)(:cast, :advance_phase, data) do
      phase = unquote(phase)

      case next_phase(phase) do
        nil ->
          Logger.info("Project #{data.project_id} in perpetual mode - no next phase")
          :keep_state_and_data

        next ->
          {:next_state, next, data}
      end
    end

    def unquote(phase)({:call, from}, :get_state, data) do
      {:keep_state_and_data, [{:reply, from, {unquote(phase), data}}]}
    end

    def unquote(phase)(:cast, {:task_completed, _task_id}, data) do
      data = %{data | task_count: data.task_count + 1}
      {:keep_state, data}
    end
  end

  ## Internal helpers

  defp next_phase(current) do
    idx = Enum.find_index(@phases, &(&1 == current))

    case Enum.at(@phases, idx + 1) do
      nil -> nil
      phase -> phase
    end
  end

  defp agents_for_phase(:bootstrap), do: ["prod-pm"]
  defp agents_for_phase(:discovery), do: ["prod-pm", "prod-design", "data-analytics"]

  defp agents_for_phase(:architecture),
    do: ["eng-backend", "eng-frontend", "eng-database", "eng-infra"]

  defp agents_for_phase(:infrastructure), do: ["ops-devops", "eng-infra", "ops-security"]

  defp agents_for_phase(:development),
    do: [
      "eng-frontend",
      "eng-backend",
      "eng-database",
      "eng-api",
      "eng-qa",
      "prod-techwriter"
    ]

  defp agents_for_phase(:qa),
    do: ["eng-qa", "eng-perf", "review-code", "review-security", "ops-security"]

  defp agents_for_phase(:deployment), do: ["ops-devops", "ops-sre", "ops-release"]

  defp agents_for_phase(:business),
    do: ["biz-marketing", "biz-sales", "biz-legal", "biz-support"]

  defp agents_for_phase(:growth),
    do: ["growth-hacker", "growth-community", "growth-success", "growth-lifecycle"]

  defp agents_for_phase(:perpetual),
    do: ["eng-qa", "eng-perf", "ops-monitor", "review-code"]

  defp broadcast_phase_change(data, phase) do
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "project:#{data.project_id}",
      {:phase_changed, data.project_id, phase}
    )
  end

  defp persist_phase(data, phase) do
    case Projects.get_project(data.project_id) do
      {:ok, project} -> Projects.update_project(project, %{phase: phase})
      _ -> :ok
    end
  end
end
