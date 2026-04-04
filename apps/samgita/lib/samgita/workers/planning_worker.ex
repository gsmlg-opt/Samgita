defmodule Samgita.Workers.PlanningWorker do
  @moduledoc """
  Oban worker for the planning phase. Manages the idea-to-PRD pipeline
  through 5 sequential sub-phases: research, architecture, draft, review, revise.
  """

  use Oban.Worker,
    queue: :orchestration,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :executing]]

  require Logger

  alias Samgita.Projects
  alias Samgita.Workers.AgentTaskWorker

  @max_review_iterations 3

  @impl true
  def perform(%Oban.Job{args: %{"project_id" => project_id, "sub_phase" => sub_phase} = args}) do
    iteration = Map.get(args, "iteration", 0)

    Logger.info(
      "[PlanningWorker] project=#{project_id} sub_phase=#{sub_phase} iteration=#{iteration}"
    )

    case sub_phase do
      "research" -> handle_research(project_id)
      "architecture" -> handle_architecture(project_id)
      "draft" -> handle_draft(project_id)
      "review" -> handle_review(project_id, iteration)
      "revise" -> handle_revise(project_id, iteration)
      _ -> {:error, "Unknown sub_phase: #{sub_phase}"}
    end
  end

  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    # Entry point — start with research
    handle_research(project_id)
  end

  # Sub-phase handlers

  defp handle_research(project_id) do
    tasks = [
      %{
        type: "research",
        description: "Market research and competitive analysis",
        agent_type: "plan-researcher",
        priority: 1
      },
      %{
        type: "research",
        description: "Technical feasibility and technology evaluation",
        agent_type: "plan-researcher",
        priority: 2
      }
    ]

    enqueue_planning_tasks(project_id, tasks, "research")
  end

  defp handle_architecture(project_id) do
    tasks = [
      %{
        type: "architecture",
        description: "System architecture design and technology stack selection",
        agent_type: "plan-architect",
        priority: 1
      }
    ]

    enqueue_planning_tasks(project_id, tasks, "architecture")
  end

  defp handle_draft(project_id) do
    tasks = [
      %{
        type: "draft",
        description:
          "Write structured PRD with requirements, acceptance criteria, and milestones",
        agent_type: "plan-writer",
        priority: 1
      }
    ]

    enqueue_planning_tasks(project_id, tasks, "draft")
  end

  defp handle_review(project_id, iteration) do
    if iteration >= @max_review_iterations do
      Logger.info("[PlanningWorker] Max review iterations reached, finalizing PRD")
      finalize_prd(project_id)
    else
      tasks = [
        %{
          type: "review",
          description: "Adversarial review of draft PRD — identify gaps, ambiguities, and risks",
          agent_type: "plan-reviewer",
          priority: 1
        }
      ]

      enqueue_planning_tasks(project_id, tasks, "review")
    end
  end

  defp handle_revise(project_id, _iteration) do
    tasks = [
      %{
        type: "revise",
        description: "Revise PRD based on review findings",
        agent_type: "plan-writer",
        priority: 1
      }
    ]

    enqueue_planning_tasks(project_id, tasks, "revise")
  end

  # Helpers

  defp enqueue_planning_tasks(project_id, task_defs, sub_phase) do
    Enum.each(task_defs, fn task_def ->
      attrs = %{
        type: task_def.type,
        payload: %{
          "description" => task_def.description,
          "agent_type" => task_def.agent_type,
          "phase" => "planning",
          "sub_phase" => sub_phase
        },
        priority: task_def.priority,
        status: :pending
      }

      case Projects.create_task(project_id, attrs) do
        {:ok, task} ->
          Samgita.ObanClient.insert(
            AgentTaskWorker.new(%{
              "task_id" => task.id,
              "project_id" => project_id,
              "agent_type" => task_def.agent_type
            })
          )

        {:error, reason} ->
          Logger.error("[PlanningWorker] Failed to create task: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp finalize_prd(project_id) do
    # Mark planning as complete — orchestrator handles phase transition
    Logger.info("[PlanningWorker] Planning complete for project #{project_id}")
    :ok
  end
end
