defmodule Samgita.Project.Recovery do
  @moduledoc """
  Recovers running projects on application startup.

  Scans the database for projects with status :running or :paused,
  and restarts their orchestrator supervision trees. This handles
  BEAM restarts and node failures gracefully.
  """

  use GenServer

  require Logger

  alias Samgita.Domain.Project
  alias Samgita.Project.Orchestrator
  alias Samgita.Repo

  import Ecto.Query

  @recovery_delay_ms 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Delay recovery to ensure Horde, Oban, and Repo are fully started
    Process.send_after(self(), :recover, @recovery_delay_ms)
    {:ok, %{recovered: 0, failed: 0}}
  end

  @impl true
  def handle_info(:recover, state) do
    {recovered, failed} = recover_projects()

    Logger.info("[Recovery] Startup recovery complete: #{recovered} recovered, #{failed} failed")

    {:noreply, %{state | recovered: recovered, failed: failed}}
  end

  @doc """
  Recover all projects that were running or paused when the BEAM stopped.
  Returns {recovered_count, failed_count}.
  """
  @spec recover_projects() :: {non_neg_integer(), non_neg_integer()}
  def recover_projects do
    projects =
      Project
      |> where([p], p.status in [:running, :paused])
      |> where([p], not is_nil(p.active_prd_id))
      |> Repo.all()

    Logger.info("[Recovery] Found #{length(projects)} projects to recover")

    Enum.reduce(projects, {0, 0}, fn project, {recovered, failed} ->
      case recover_project(project) do
        :ok -> {recovered + 1, failed}
        :already_running -> {recovered, failed}
        {:error, _reason} -> {recovered, failed + 1}
      end
    end)
  end

  defp recover_project(project) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project.id}) do
      [{_pid, _}] ->
        Logger.debug("[Recovery] Project #{project.id} already has orchestrator running")
        :already_running

      [] ->
        attempt_project_recovery(project)
    end
  end

  defp attempt_project_recovery(project) do
    Logger.info(
      "[Recovery] Recovering project #{project.id} (#{project.name}) " <>
        "in phase #{project.phase}, status #{project.status}"
    )

    case start_project_supervisor(project) do
      {:ok, _pid} ->
        handle_paused_project(project)
        reset_stuck_tasks(project.id)
        Logger.info("[Recovery] Project #{project.id} recovered successfully")
        :ok

      {:error, reason} ->
        Logger.error("[Recovery] Failed to recover project #{project.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_paused_project(project) do
    if project.status == :paused do
      Process.sleep(500)
      notify_orchestrator_pause(project.id)
    end
  end

  defp start_project_supervisor(project) do
    start_project_supervisor(project, 3)
  end

  defp start_project_supervisor(_project, 0) do
    {:error, :max_retries}
  end

  defp start_project_supervisor(project, retries) do
    case Horde.DynamicSupervisor.start_child(
           Samgita.AgentSupervisor,
           {Samgita.Project.Supervisor, project_id: project.id}
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.warning(
          "[Recovery] Retry #{4 - retries}/3 for project #{project.id}: #{inspect(reason)}"
        )

        Process.sleep(500)
        start_project_supervisor(project, retries - 1)
    end
  end

  defp notify_orchestrator_pause(project_id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] -> Orchestrator.pause(pid)
      [] -> :ok
    end
  end

  defp reset_stuck_tasks(project_id) do
    alias Samgita.Domain.Task, as: TaskSchema

    {count, _} =
      from(t in TaskSchema,
        where: t.project_id == ^project_id,
        where: t.status == :running
      )
      |> Repo.update_all(set: [status: :pending, started_at: nil])

    if count > 0 do
      Logger.info(
        "[Recovery] Reset #{count} stuck running tasks to pending for project #{project_id}"
      )
    end
  end
end
