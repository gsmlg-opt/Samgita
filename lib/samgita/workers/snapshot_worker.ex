defmodule Samgita.Workers.SnapshotWorker do
  @moduledoc """
  Oban worker that creates periodic state snapshots for running projects.
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 3

  require Logger

  alias Samgita.Domain.AgentRun
  alias Samgita.Domain.{Project, Snapshot}
  alias Samgita.Domain.Task, as: TaskSchema
  alias Samgita.Repo

  import Ecto.Query

  @impl true
  def perform(%Oban.Job{}) do
    running_projects =
      Project
      |> where(status: :running)
      |> Repo.all()

    Enum.each(running_projects, &create_snapshot/1)
    :ok
  end

  defp create_snapshot(project) do
    agent_states = get_agent_states(project.id)
    task_queue_state = get_task_queue_state(project.id)

    attrs = %{
      project_id: project.id,
      phase: to_string(project.phase),
      agent_states: agent_states,
      task_queue_state: task_queue_state,
      memory_state: %{}
    }

    case %Snapshot{} |> Snapshot.changeset(attrs) |> Repo.insert() do
      {:ok, snapshot} ->
        Logger.info("Snapshot created for project #{project.id}: #{snapshot.id}")
        cleanup_old_snapshots(project.id)

      {:error, changeset} ->
        Logger.error("Failed to create snapshot for #{project.id}: #{inspect(changeset.errors)}")
    end
  end

  defp get_agent_states(project_id) do
    AgentRun
    |> where(project_id: ^project_id)
    |> where([a], a.status != :failed)
    |> Repo.all()
    |> Enum.map(fn run ->
      %{
        agent_type: run.agent_type,
        status: run.status,
        total_tasks: run.total_tasks,
        total_tokens: run.total_tokens
      }
    end)
    |> then(&%{agents: &1, count: length(&1)})
  end

  defp get_task_queue_state(project_id) do
    tasks = TaskSchema |> where(project_id: ^project_id) |> Repo.all()

    %{
      pending: Enum.count(tasks, &(&1.status == :pending)),
      running: Enum.count(tasks, &(&1.status == :running)),
      completed: Enum.count(tasks, &(&1.status == :completed)),
      failed: Enum.count(tasks, &(&1.status == :failed)),
      dead_letter: Enum.count(tasks, &(&1.status == :dead_letter))
    }
  end

  defp cleanup_old_snapshots(project_id, keep \\ 10) do
    Snapshot
    |> where(project_id: ^project_id)
    |> order_by(desc: :inserted_at)
    |> offset(^keep)
    |> Repo.all()
    |> Enum.each(&Repo.delete/1)
  end
end
