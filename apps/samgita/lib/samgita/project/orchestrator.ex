defmodule Samgita.Project.Orchestrator do
  @moduledoc """
  Orchestrator state machine managing project lifecycle phases.

  Transitions through phases:
  :bootstrap -> :discovery -> :architecture -> :infrastructure ->
  :development -> :qa -> :deployment -> :business -> :growth -> :perpetual
  """

  @behaviour :gen_statem

  require Logger

  alias Samgita.ObanClient
  alias Samgita.Projects
  alias Samgita.Workers.AgentTaskWorker
  alias Samgita.Workers.BootstrapWorker
  alias Samgita.Workers.QualityGateWorker
  alias Samgita.Workers.SnapshotWorker

  @stagnation_check_interval_ms 300_000
  @stagnation_threshold 5
  @quality_gate_timeout_ms 600_000

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
    stagnation_checks: 0,
    paused: false,
    agent_monitors: %{}
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

  @doc "Pause the orchestrator. Halts phase advancement and task processing."
  def pause(pid) do
    :gen_statem.cast(pid, :pause)
  end

  @doc "Resume the orchestrator. Restores phase advancement and task processing."
  def resume(pid) do
    :gen_statem.cast(pid, :resume)
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

      {agent_statuses, monitors} =
        Enum.reduce(agent_types, {%{}, data.agent_monitors}, fn agent_type, {statuses, mons} ->
          {status, new_mons} = spawn_phase_agent(data.project_id, agent_type, mons)
          {Map.put(statuses, agent_type, status), new_mons}
        end)

      data = %{data | agents: agent_statuses, agent_monitors: monitors}

      # Enqueue phase-specific tasks (rescue to prevent orchestrator crash)
      task_count =
        try do
          enqueue_phase_tasks(phase, data)
        rescue
          e ->
            Logger.error(
              "[Orchestrator] #{data.project_id}: enqueue_phase_tasks raised: #{Exception.message(e)}"
            )

            broadcast_activity(data, :failed, "Failed to enqueue #{phase} tasks")
            0
        end

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

      handle_task_completion(phase, data)
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

      # Check if tasks already completed before this count was set
      maybe_deferred_advance(unquote(phase), data)
    end

    def unquote(phase)(:cast, :pause, data) do
      if data.paused do
        :keep_state_and_data
      else
        Logger.info("[Orchestrator] #{data.project_id}: pausing in phase #{unquote(phase)}")
        broadcast_activity(data, :reason, "Orchestrator paused")
        {:keep_state, %{data | paused: true}}
      end
    end

    def unquote(phase)(:cast, :resume, data) do
      if data.paused do
        Logger.info("[Orchestrator] #{data.project_id}: resuming in phase #{unquote(phase)}")
        broadcast_activity(data, :reason, "Orchestrator resumed")

        data = %{data | paused: false}
        maybe_deferred_advance(unquote(phase), data)
      else
        :keep_state_and_data
      end
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

          {:keep_state, data, [{{:timeout, :stagnation}, @stagnation_check_interval_ms, :check}]}
        else
          data = %{data | stagnation_checks: checks}

          {:keep_state, data, [{{:timeout, :stagnation}, @stagnation_check_interval_ms, :check}]}
        end
      else
        # Progress was made, reset stagnation counter
        data = %{
          data
          | last_progress_task_count: data.task_count,
            stagnation_checks: 0
        }

        {:keep_state, data, [{{:timeout, :stagnation}, @stagnation_check_interval_ms, :check}]}
      end
    end

    # Agent crash recovery — respawn monitored agents on DOWN
    def unquote(phase)(:info, {:DOWN, ref, :process, _pid, reason}, data) do
      case Map.pop(data.agent_monitors, ref) do
        {nil, _} ->
          :keep_state_and_data

        {{agent_id, agent_type}, remaining_monitors} ->
          reason_str = inspect(reason, limit: 10, printable_limit: 50)

          Logger.warning(
            "[Orchestrator] #{data.project_id}: agent #{agent_id} crashed: #{reason_str}, respawning"
          )

          broadcast_activity(
            data,
            :failed,
            "Agent #{agent_id} crashed (#{reason_str}), respawning"
          )

          data = %{data | agent_monitors: remaining_monitors}

          {status, new_monitors} =
            spawn_phase_agent(data.project_id, agent_type, data.agent_monitors)

          agents = Map.put(data.agents, agent_type, status)
          {:keep_state, %{data | agents: agents, agent_monitors: new_monitors}}
      end
    end

    # Quality gate timeout — re-trigger if waiting too long
    def unquote(phase)(
          {:timeout, :quality_gate_timeout},
          :check,
          %{awaiting_quality_gates: true} = data
        ) do
      phase = unquote(phase)

      Logger.warning(
        "[Orchestrator] #{data.project_id}: quality gate timeout in #{phase}, re-triggering"
      )

      broadcast_activity(data, :failed, "Quality gate timed out, re-triggering")
      trigger_quality_gates(phase, data)
      {:keep_state, data, [{{:timeout, :quality_gate_timeout}, @quality_gate_timeout_ms, :check}]}
    end

    def unquote(phase)({:timeout, :quality_gate_timeout}, :check, data) do
      {:keep_state, %{data | awaiting_quality_gates: false}}
    end

    # Catch-all handlers — prevent gen_statem crash on unexpected messages
    def unquote(phase)(:info, _msg, _data), do: :keep_state_and_data
    def unquote(phase)(:cast, _msg, _data), do: :keep_state_and_data
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

  defp agent_id_for(project_id, agent_type), do: "#{project_id}-#{agent_type}"

  defp spawn_phase_agent(project_id, agent_type, monitors) do
    agent_id = agent_id_for(project_id, agent_type)

    case Horde.Registry.lookup(Samgita.AgentRegistry, agent_id) do
      [{_pid, _}] ->
        {:running, monitors}

      [] ->
        spec =
          {Samgita.Agent.Worker, id: agent_id, agent_type: agent_type, project_id: project_id}

        case Horde.DynamicSupervisor.start_child(Samgita.AgentSupervisor, spec) do
          {:ok, pid} ->
            ref = Process.monitor(pid)
            Samgita.Events.agent_spawned(project_id, agent_id, agent_type)

            entry =
              Samgita.Events.build_log_entry(
                :orchestrator,
                "orchestrator",
                :spawned,
                "Agent #{agent_id} (#{agent_type}) started"
              )

            Samgita.Events.activity_log(project_id, entry)
            {:running, Map.put(monitors, ref, {agent_id, agent_type})}

          {:error, {:already_started, pid}} ->
            ref = Process.monitor(pid)
            {:running, Map.put(monitors, ref, {agent_id, agent_type})}

          {:error, reason} ->
            reason_str = inspect(reason, limit: 10, printable_limit: 50)
            Logger.warning("Failed to spawn agent #{agent_id}: #{reason_str}")

            entry =
              Samgita.Events.build_log_entry(
                :orchestrator,
                "orchestrator",
                :failed,
                "Failed to spawn agent #{agent_id}: #{reason_str}"
              )

            Samgita.Events.activity_log(project_id, entry)
            {:failed, monitors}
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
    prd_id = data.project && data.project.active_prd_id

    gate_type =
      case current_phase do
        :development -> "pre_qa"
        :qa -> "pre_deploy"
        _ -> "pre_qa"
      end

    ObanClient.insert(
      QualityGateWorker.new(%{
        project_id: data.project_id,
        prd_id: prd_id,
        gate_type: gate_type
      })
    )
  rescue
    e ->
      Logger.warning(
        "[Orchestrator] #{data.project_id}: failed to trigger quality gates: #{inspect(e)}"
      )
  catch
    :exit, _ -> :ok
  end

  # Phase-specific task generation.
  # Returns the number of tasks enqueued (used to set phase_tasks_total).
  defp enqueue_phase_tasks(:bootstrap, data) do
    project = refresh_project(data)

    case project.active_prd_id do
      nil ->
        broadcast_activity(data, :reason, "Bootstrap phase: no active PRD, awaiting PRD creation")
        0

      prd_id ->
        broadcast_activity(
          data,
          :reason,
          "Bootstrap phase: analyzing PRD and generating task backlog"
        )

        case ObanClient.insert(
               BootstrapWorker.new(%{
                 project_id: project.id,
                 prd_id: prd_id
               })
             ) do
          {:ok, _job} ->
            # Return 0 — BootstrapWorker will call set_phase_task_count with
            # the real count after generating tasks. Returning 0 prevents
            # premature phase advancement (phase_complete? returns false when total=0).
            0

          {:error, reason} ->
            Logger.error(
              "[Orchestrator] #{data.project_id}: failed to queue BootstrapWorker: #{inspect(reason, limit: 10, printable_limit: 50)}"
            )

            broadcast_activity(data, :failed, "Failed to queue bootstrap task")
            0
        end
    end
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

    create_phase_tasks(project, tasks, data, :discovery)
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

    create_phase_tasks(project, tasks, data, :architecture)
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

    create_phase_tasks(project, tasks, data, :infrastructure)
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

    create_phase_tasks(project, tasks, data, :deployment)
  end

  defp enqueue_phase_tasks(:development, data) do
    project = refresh_project(data)

    tasks = [
      %{
        type: "implement",
        description: "Implement core backend features from architecture design",
        agent_type: "eng-backend",
        priority: 1
      },
      %{
        type: "implement",
        description: "Implement frontend UI components from design specs",
        agent_type: "eng-frontend",
        priority: 1
      },
      %{
        type: "implement",
        description: "Implement database migrations and data layer",
        agent_type: "eng-database",
        priority: 2
      },
      %{
        type: "implement",
        description: "Implement API endpoints and integrations",
        agent_type: "eng-api",
        priority: 2
      },
      %{
        type: "test",
        description: "Write comprehensive test suite for implemented features",
        agent_type: "eng-qa",
        priority: 3
      },
      %{
        type: "implement",
        description: "Write technical documentation and API docs",
        agent_type: "prod-techwriter",
        priority: 3
      }
    ]

    create_phase_tasks(project, tasks, data, :development)
  end

  defp enqueue_phase_tasks(:qa, data) do
    project = refresh_project(data)

    tasks = [
      %{
        type: "test",
        description: "Run full test suite and verify all tests pass",
        agent_type: "eng-qa",
        priority: 1
      },
      %{
        type: "review",
        description: "Performance testing and optimization",
        agent_type: "eng-perf",
        priority: 2
      },
      %{
        type: "review",
        description: "Security audit and vulnerability assessment",
        agent_type: "review-security",
        priority: 2
      },
      %{
        type: "review",
        description: "Code review for quality and maintainability",
        agent_type: "review-code",
        priority: 2
      }
    ]

    create_phase_tasks(project, tasks, data, :qa)
  end

  defp enqueue_phase_tasks(_phase, _data) do
    # business, growth, perpetual — tasks come from
    # the task backlog or are manually created
    0
  end

  defp create_phase_tasks(project, task_defs, data, phase) do
    prd_id =
      case project do
        %{active_prd_id: id} when not is_nil(id) -> id
        _ -> nil
      end

    enqueued =
      Enum.count(task_defs, fn task_def ->
        attrs = %{
          type: task_def.type,
          payload: %{
            "description" => task_def.description,
            "agent_type" => task_def.agent_type,
            "prd_id" => prd_id,
            "phase" => to_string(phase)
          },
          priority: task_def.priority,
          status: :pending
        }

        with {:ok, task} <- Projects.create_task(project.id, attrs),
             {:ok, _job} <-
               ObanClient.insert(
                 AgentTaskWorker.new(%{
                   task_id: task.id,
                   project_id: project.id,
                   agent_type: task_def.agent_type
                 })
               ) do
          true
        else
          {:error, %Ecto.Changeset{} = reason} ->
            Logger.warning(
              "[Orchestrator] Failed to create phase task: #{inspect(reason, limit: 10, printable_limit: 50)}"
            )

            false

          {:error, reason} ->
            Logger.error(
              "[Orchestrator] Failed to queue task: #{inspect(reason, limit: 10, printable_limit: 50)}"
            )

            false
        end
      end)

    broadcast_activity(
      data,
      :reason,
      "Enqueued #{enqueued}/#{length(task_defs)} phase tasks"
    )

    enqueued
  end

  defp refresh_project(data) do
    case Projects.get_project(data.project_id) do
      {:ok, project} -> project
      _ -> data.project
    end
  rescue
    _ -> data.project
  catch
    :exit, _ -> data.project
  end

  defp maybe_deferred_advance(phase, data) do
    if phase_complete?(data) do
      advance_or_gate(phase, data)
    else
      {:keep_state, data}
    end
  end

  defp advance_or_gate(phase, data) do
    if requires_quality_gates?(phase) and not data.awaiting_quality_gates do
      trigger_quality_gates(phase, data)
      {:keep_state, %{data | awaiting_quality_gates: true}}
    else
      case next_phase(phase) do
        nil -> {:keep_state, data}
        next -> {:next_state, next, reset_phase_counters(data)}
      end
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
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp persist_phase(data, phase) do
    case Projects.get_project(data.project_id) do
      {:ok, project} -> Projects.update_project(project, %{phase: phase})
      _ -> :ok
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp handle_task_completion(phase, data) do
    if data.paused do
      Logger.info("[Orchestrator] #{data.project_id}: paused, deferring phase check")
      {:keep_state, data}
    else
      handle_phase_completion(phase, data)
    end
  end

  defp handle_phase_completion(phase, data) do
    if phase_complete?(data) and not data.awaiting_quality_gates do
      handle_completed_phase(phase, data)
    else
      {:keep_state, data}
    end
  end

  defp handle_completed_phase(phase, data) do
    if requires_quality_gates?(phase) do
      Logger.info("[Orchestrator] #{data.project_id}: triggering quality gates for #{phase}")
      broadcast_activity(data, :reason, "Phase tasks complete, running quality gates")
      trigger_quality_gates(phase, data)

      {:keep_state, %{data | awaiting_quality_gates: true},
       [{{:timeout, :quality_gate_timeout}, @quality_gate_timeout_ms, :check}]}
    else
      advance_to_next_phase(phase, data)
    end
  end

  defp advance_to_next_phase(phase, data) do
    create_phase_checkpoint(data, phase)

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

  defp create_phase_checkpoint(data, phase) do
    ObanClient.insert(
      SnapshotWorker.new(%{project_id: data.project_id, trigger: "phase_complete_#{phase}"})
    )
  rescue
    e ->
      Logger.warning(
        "[Orchestrator] #{data.project_id}: failed to create phase checkpoint: #{inspect(e)}"
      )
  catch
    :exit, _ -> :ok
  end
end
