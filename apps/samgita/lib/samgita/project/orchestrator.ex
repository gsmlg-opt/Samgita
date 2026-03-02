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

  @stagnation_check_interval_ms 300_000
  @stagnation_threshold 5

  defstruct [
    :project_id,
    :project,
    :agents,
    :started_at,
    task_count: 0,
    phase_tasks_total: 0,
    phase_tasks_completed: 0,
    phase_entered_at: nil,
    awaiting_quality_gates: false,
    last_progress_task_count: 0,
    stagnation_checks: 0
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

  @doc "Notify the orchestrator that a phase task completed. Triggers auto-advance check."
  def notify_task_completed(pid, task_id) do
    :gen_statem.cast(pid, {:task_completed, task_id})
  end

  @doc "Set expected task count for current phase. Call after dispatching phase tasks."
  def set_phase_task_count(pid, count) do
    :gen_statem.cast(pid, {:set_phase_task_count, count})
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

      data = %{
        data
        | phase_tasks_total: 0,
          phase_tasks_completed: 0,
          phase_entered_at: DateTime.utc_now()
      }

      broadcast_phase_change(data, phase)
      persist_phase(data, phase)

      broadcast_activity(
        data,
        :phase_change,
        "Entering phase: #{phase} (from #{old_state})"
      )

      {:keep_state, data, [{:state_timeout, 0, :setup_phase}]}
    end

    def unquote(phase)(:state_timeout, :setup_phase, data) do
      phase = unquote(phase)
      agent_types = agents_for_phase(phase)

      Logger.info(
        "Phase #{phase}: spawning agents #{inspect(agent_types)} for project #{data.project_id}"
      )

      broadcast_activity(
        data,
        :spawned,
        "Spawning agents: #{Enum.join(agent_types, ", ")}"
      )

      agent_statuses =
        Map.new(agent_types, fn agent_type ->
          status = spawn_phase_agent(data.project_id, agent_type)
          {agent_type, status}
        end)

      data = %{data | agents: agent_statuses}

      # Enqueue phase-specific tasks
      task_count = enqueue_phase_tasks(phase, data)

      data =
        if task_count > 0,
          do: %{data | phase_tasks_total: task_count},
          else: data

      # Start stagnation check timer
      data = %{data | last_progress_task_count: data.task_count, stagnation_checks: 0}
      {:keep_state, data, [{{:timeout, :stagnation}, @stagnation_check_interval_ms, :check}]}
    end

    def unquote(phase)(:cast, :advance_phase, data) do
      phase = unquote(phase)

      case next_phase(phase) do
        nil ->
          Logger.info("Project #{data.project_id} in perpetual mode - no next phase")
          :keep_state_and_data

        next ->
          broadcast_activity(data, :phase_change, "Phase #{phase} complete, advancing to #{next}")
          {:next_state, next, reset_phase_counters(data)}
      end
    end

    def unquote(phase)({:call, from}, :get_state, data) do
      {:keep_state_and_data, [{:reply, from, {unquote(phase), data}}]}
    end

    def unquote(phase)(:cast, {:task_completed, task_id}, data) do
      phase = unquote(phase)

      data = %{
        data
        | task_count: data.task_count + 1,
          phase_tasks_completed: data.phase_tasks_completed + 1
      }

      Logger.info(
        "[Orchestrator] Phase #{phase}: task #{task_id} completed " <>
          "(#{data.phase_tasks_completed}/#{data.phase_tasks_total})"
      )

      broadcast_activity(
        data,
        :task_completed,
        "Task completed (#{data.phase_tasks_completed}/#{data.phase_tasks_total})"
      )

      if phase_complete?(data) do
        if requires_quality_gates?(phase) do
          Logger.info("[Orchestrator] #{data.project_id}: triggering quality gates for #{phase}")
          broadcast_activity(data, :reason, "Phase tasks complete, running quality gates")
          trigger_quality_gates(phase, data)
          {:keep_state, %{data | awaiting_quality_gates: true}}
        else
          case next_phase(phase) do
            nil ->
              Logger.info("[Orchestrator] #{data.project_id}: perpetual mode, staying")
              {:keep_state, data}

            next ->
              Logger.info("[Orchestrator] #{data.project_id}: auto-advancing #{phase} → #{next}")

              broadcast_activity(
                data,
                :phase_change,
                "All phase tasks complete, auto-advancing to #{next}"
              )

              {:next_state, next, reset_phase_counters(data)}
          end
        end
      else
        {:keep_state, data}
      end
    end

    def unquote(phase)(:cast, :quality_gates_passed, data) do
      phase = unquote(phase)

      if data.awaiting_quality_gates do
        case next_phase(phase) do
          nil ->
            Logger.info("[Orchestrator] #{data.project_id}: quality gates passed, perpetual mode")
            {:keep_state, %{data | awaiting_quality_gates: false}}

          next ->
            Logger.info(
              "[Orchestrator] #{data.project_id}: quality gates passed, advancing #{phase} → #{next}"
            )

            broadcast_activity(
              data,
              :phase_change,
              "Quality gates passed, advancing to #{next}"
            )

            {:next_state, next, reset_phase_counters(%{data | awaiting_quality_gates: false})}
        end
      else
        Logger.warning(
          "[Orchestrator] #{data.project_id}: received quality_gates_passed but not awaiting"
        )

        :keep_state_and_data
      end
    end

    def unquote(phase)(:cast, {:set_phase_task_count, count}, data) do
      Logger.info(
        "[Orchestrator] Phase #{unquote(phase)}: expecting #{count} tasks for project #{data.project_id}"
      )

      data = %{data | phase_tasks_total: count}
      {:keep_state, data}
    end

    def unquote(phase)({:timeout, :stagnation}, :check, data) do
      phase = unquote(phase)

      if data.task_count == data.last_progress_task_count do
        checks = data.stagnation_checks + 1

        if checks >= @stagnation_threshold do
          Logger.warning(
            "[Orchestrator] #{data.project_id}: stagnation detected in #{phase} " <>
              "(#{checks} checks without progress)"
          )

          broadcast_activity(
            data,
            :failed,
            "Stagnation: #{checks} checks without task progress in #{phase}"
          )

          Samgita.Events.stagnation_detected(data.project_id, phase, checks)
          data = %{data | stagnation_checks: checks}

          {:keep_state, data,
           [{{:timeout, :stagnation}, @stagnation_check_interval_ms, :check}]}
        else
          data = %{data | stagnation_checks: checks}

          {:keep_state, data,
           [{{:timeout, :stagnation}, @stagnation_check_interval_ms, :check}]}
        end
      else
        # Progress was made, reset stagnation counter
        data = %{
          data
          | last_progress_task_count: data.task_count,
            stagnation_checks: 0
        }

        {:keep_state, data,
         [{{:timeout, :stagnation}, @stagnation_check_interval_ms, :check}]}
      end
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

  defp spawn_phase_agent(project_id, agent_type) do
    agent_id = "#{project_id}-#{agent_type}"

    case Horde.Registry.lookup(Samgita.AgentRegistry, agent_id) do
      [{_pid, _}] ->
        :running

      [] ->
        spec =
          {Samgita.Agent.Worker, id: agent_id, agent_type: agent_type, project_id: project_id}

        case Horde.DynamicSupervisor.start_child(Samgita.AgentSupervisor, spec) do
          {:ok, _pid} ->
            Samgita.Events.agent_spawned(project_id, agent_id, agent_type)

            entry =
              Samgita.Events.build_log_entry(
                :orchestrator,
                "orchestrator",
                :spawned,
                "Agent #{agent_id} (#{agent_type}) started"
              )

            Samgita.Events.activity_log(project_id, entry)
            :running

          {:error, {:already_started, _pid}} ->
            :running

          {:error, reason} ->
            Logger.warning("Failed to spawn agent #{agent_id}: #{inspect(reason)}")

            entry =
              Samgita.Events.build_log_entry(
                :orchestrator,
                "orchestrator",
                :failed,
                "Failed to spawn agent #{agent_id}: #{inspect(reason)}"
              )

            Samgita.Events.activity_log(project_id, entry)
            :failed
        end
    end
  end

  defp phase_complete?(%{phase_tasks_total: 0}), do: false

  defp phase_complete?(%{phase_tasks_total: total, phase_tasks_completed: completed}),
    do: completed >= total

  defp requires_quality_gates?(:development), do: true
  defp requires_quality_gates?(:qa), do: true
  defp requires_quality_gates?(_), do: false

  defp trigger_quality_gates(current_phase, data) do
    prd_id =
      case Projects.get_project(data.project_id) do
        {:ok, project} -> project.active_prd_id
        _ -> nil
      end

    gate_type =
      case current_phase do
        :development -> "pre_qa"
        :qa -> "pre_deploy"
        _ -> "pre_qa"
      end

    Oban.insert(
      Samgita.Workers.QualityGateWorker.new(%{
        project_id: data.project_id,
        prd_id: prd_id,
        gate_type: gate_type
      })
    )
  end

  # Phase-specific task generation.
  # Returns the number of tasks enqueued (used to set phase_tasks_total).
  defp enqueue_phase_tasks(:bootstrap, data) do
    # Bootstrap is handled by BootstrapWorker (triggered from LiveView start)
    broadcast_activity(data, :reason, "Bootstrap phase: awaiting PRD analysis tasks")
    0
  end

  defp enqueue_phase_tasks(:discovery, data) do
    project = refresh_project(data)

    tasks = [
      %{
        type: "analysis",
        description: "Analyze codebase structure and existing patterns",
        agent_type: "prod-pm",
        priority: 1
      },
      %{
        type: "analysis",
        description: "Map user stories and acceptance criteria from PRD",
        agent_type: "prod-design",
        priority: 2
      },
      %{
        type: "analysis",
        description: "Identify data requirements and analytics needs",
        agent_type: "data-analytics",
        priority: 3
      }
    ]

    create_phase_tasks(project, tasks, data)
  end

  defp enqueue_phase_tasks(:architecture, data) do
    project = refresh_project(data)

    tasks = [
      %{
        type: "architecture",
        description: "Design backend architecture and API contracts",
        agent_type: "eng-backend",
        priority: 1
      },
      %{
        type: "architecture",
        description: "Design frontend component architecture",
        agent_type: "eng-frontend",
        priority: 2
      },
      %{
        type: "architecture",
        description: "Design database schema and data model",
        agent_type: "eng-database",
        priority: 2
      },
      %{
        type: "architecture",
        description: "Design infrastructure and deployment architecture",
        agent_type: "eng-infra",
        priority: 3
      }
    ]

    create_phase_tasks(project, tasks, data)
  end

  defp enqueue_phase_tasks(:infrastructure, data) do
    project = refresh_project(data)

    tasks = [
      %{
        type: "implement",
        description: "Set up CI/CD pipeline and deployment scripts",
        agent_type: "ops-devops",
        priority: 1
      },
      %{
        type: "implement",
        description: "Configure infrastructure and environment provisioning",
        agent_type: "eng-infra",
        priority: 2
      },
      %{
        type: "implement",
        description: "Set up security scanning and access controls",
        agent_type: "ops-security",
        priority: 3
      }
    ]

    create_phase_tasks(project, tasks, data)
  end

  defp enqueue_phase_tasks(:deployment, data) do
    project = refresh_project(data)

    tasks = [
      %{
        type: "implement",
        description: "Prepare and execute deployment to staging",
        agent_type: "ops-devops",
        priority: 1
      },
      %{
        type: "implement",
        description: "Verify deployment health and monitoring",
        agent_type: "ops-sre",
        priority: 2
      },
      %{
        type: "implement",
        description: "Execute release checklist and cutover",
        agent_type: "ops-release",
        priority: 3
      }
    ]

    create_phase_tasks(project, tasks, data)
  end

  defp enqueue_phase_tasks(_phase, _data) do
    # development, qa, business, growth, perpetual — tasks come from
    # the task backlog (bootstrap) or are manually created
    0
  end

  defp create_phase_tasks(project, task_defs, data) do
    prd_id =
      case project do
        %{active_prd_id: id} when not is_nil(id) -> id
        _ -> nil
      end

    Enum.each(task_defs, fn task_def ->
      attrs = %{
        type: task_def.type,
        payload: %{
          "description" => task_def.description,
          "agent_type" => task_def.agent_type,
          "prd_id" => prd_id,
          "phase" => to_string(data.project_id)
        },
        priority: task_def.priority,
        status: :pending
      }

      case Projects.create_task(project.id, attrs) do
        {:ok, task} ->
          Oban.insert(
            Samgita.Workers.AgentTaskWorker.new(%{
              task_id: task.id,
              project_id: project.id,
              agent_type: task_def.agent_type
            })
          )

        {:error, reason} ->
          Logger.warning(
            "[Orchestrator] Failed to create phase task: #{inspect(reason)}"
          )
      end
    end)

    broadcast_activity(
      data,
      :reason,
      "Enqueued #{length(task_defs)} phase tasks"
    )

    length(task_defs)
  end

  defp refresh_project(data) do
    case Projects.get_project(data.project_id) do
      {:ok, project} -> project
      _ -> data.project
    end
  end

  defp reset_phase_counters(data) do
    %{data | phase_tasks_total: 0, phase_tasks_completed: 0}
  end

  defp broadcast_activity(data, stage, message) do
    entry =
      Samgita.Events.build_log_entry(:orchestrator, "orchestrator", stage, message)

    Samgita.Events.activity_log(data.project_id, entry)
  end

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
