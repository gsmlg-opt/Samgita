defmodule SamgitaWeb.ProjectLive.Index do
  use SamgitaWeb, :live_view

  alias Samgita.Domain.Project
  alias Samgita.Projects

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Projects.get_project(id) do
      {:ok, project} ->
        if connected?(socket) do
          Samgita.Events.subscribe_project(project.id)
        end

        prds = Samgita.Prds.list_prds(project.id)
        selected_prd = find_prd(prds, project.active_prd_id)
        {tasks, agent_runs} = load_prd_scoped_data(project, selected_prd)

        {:ok,
         socket
         |> assign(
           page_title: project.name,
           project: project,
           prds: prds,
           selected_prd: selected_prd,
           tasks: tasks,
           agent_runs: agent_runs,
           active_agents: %{},
           show_task_form: false,
           task_form: %{type: "", payload: "{}"},
           log_count: 0
         )
         |> stream(:activity_log, [])}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  # Project control events
  @impl true
  def handle_event("start", _, socket) do
    prd = socket.assigns.selected_prd

    with true <- not is_nil(prd) || {:error, :no_prd_selected},
         {:ok, project} <- Projects.start_project(socket.assigns.project.id, prd.id) do
      Projects.enqueue_task(
        project.id,
        "bootstrap",
        "prod-pm",
        %{
          prd_id: prd.id,
          prd_title: prd.title,
          prd_content: prd.content,
          project_name: project.name,
          git_url: project.git_url,
          working_path: project.working_path
        }
      )

      prds = Samgita.Prds.list_prds(project.id)
      selected_prd = find_prd(prds, project.active_prd_id)
      {tasks, agent_runs} = load_prd_scoped_data(project, selected_prd)

      {:noreply,
       assign(socket,
         project: project,
         prds: prds,
         selected_prd: selected_prd,
         tasks: tasks,
         agent_runs: agent_runs
       )}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to start project")}
    end
  end

  def handle_event("pause", _, socket) do
    case Projects.pause_project(socket.assigns.project.id) do
      {:ok, project} ->
        {:noreply, assign(socket, project: project)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to pause project")}
    end
  end

  def handle_event("resume", _, socket) do
    case Projects.resume_project(socket.assigns.project.id) do
      {:ok, project} ->
        {:noreply, assign(socket, project: project)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resume project")}
    end
  end

  def handle_event("stop", _, socket) do
    case Projects.stop_project(socket.assigns.project.id) do
      {:ok, project} ->
        prds = Samgita.Prds.list_prds(project.id)

        {:noreply,
         socket
         |> assign(
           project: project,
           prds: prds,
           selected_prd: nil,
           active_agents: %{},
           tasks: [],
           agent_runs: []
         )
         |> put_flash(:info, "Project stopped")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to stop project")}
    end
  end

  def handle_event("restart", _, socket) do
    case Projects.restart_project(socket.assigns.project.id) do
      {:ok, project} ->
        prds = Samgita.Prds.list_prds(project.id)
        selected_prd = find_prd(prds, project.active_prd_id)
        {tasks, agent_runs} = load_prd_scoped_data(project, selected_prd)

        Projects.enqueue_task(
          project.id,
          "bootstrap",
          "prod-pm",
          %{
            prd_id: selected_prd.id,
            prd_title: selected_prd.title,
            prd_content: selected_prd.content,
            project_name: project.name,
            git_url: project.git_url,
            working_path: project.working_path
          }
        )

        {:noreply,
         socket
         |> assign(
           project: project,
           prds: prds,
           selected_prd: selected_prd,
           tasks: tasks,
           agent_runs: agent_runs,
           active_agents: %{},
           log_count: 0
         )
         |> stream(:activity_log, [], reset: true)
         |> put_flash(:info, "Project restarted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to restart project")}
    end
  end

  def handle_event("terminate", _, socket) do
    case Projects.terminate_project(socket.assigns.project.id) do
      {:ok, project} ->
        prds = Samgita.Prds.list_prds(project.id)

        {:noreply,
         socket
         |> assign(
           project: project,
           prds: prds,
           selected_prd: nil,
           active_agents: %{},
           tasks: [],
           agent_runs: []
         )
         |> put_flash(:info, "Project terminated")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to terminate project")}
    end
  end

  # PRD selection events
  def handle_event("select_prd", %{"id" => id}, socket) do
    prds = socket.assigns.prds
    selected_prd = find_prd(prds, id)
    {tasks, agent_runs} = load_prd_scoped_data(socket.assigns.project, selected_prd)

    {:noreply,
     assign(socket,
       selected_prd: selected_prd,
       tasks: tasks,
       agent_runs: agent_runs
     )}
  end

  def handle_event("delete_prd", %{"id" => id}, socket) do
    case Samgita.Prds.get_prd(id) do
      {:ok, prd} ->
        case Samgita.Prds.delete_prd(prd) do
          {:ok, _} ->
            prds = Samgita.Prds.list_prds(socket.assigns.project.id)

            selected_prd =
              if socket.assigns.selected_prd && socket.assigns.selected_prd.id == id,
                do: nil,
                else: socket.assigns.selected_prd

            {:noreply,
             socket
             |> assign(prds: prds, selected_prd: selected_prd)
             |> put_flash(:info, "PRD deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete PRD")}
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "PRD not found")}
    end
  end

  # Task Management events
  def handle_event("show_task_form", _, socket) do
    {:noreply, assign(socket, show_task_form: true)}
  end

  def handle_event("hide_task_form", _, socket) do
    {:noreply, assign(socket, show_task_form: false, task_form: %{type: "", payload: "{}"})}
  end

  def handle_event("create_task", %{"task" => task_params}, socket) do
    payload =
      case Jason.decode(task_params["payload"]) do
        {:ok, parsed} -> parsed
        _ -> %{}
      end

    # Include prd_id in payload if a PRD is selected
    payload =
      if socket.assigns.selected_prd do
        Map.put(payload, "prd_id", socket.assigns.selected_prd.id)
      else
        payload
      end

    attrs = %{
      type: task_params["type"],
      payload: payload,
      priority: String.to_integer(task_params["priority"] || "5"),
      status: :pending
    }

    case Projects.create_task(socket.assigns.project.id, attrs) do
      {:ok, _task} ->
        {tasks, _} = load_prd_scoped_data(socket.assigns.project, socket.assigns.selected_prd)

        {:noreply,
         socket
         |> assign(tasks: tasks, show_task_form: false, task_form: %{type: "", payload: "{}"})
         |> put_flash(:info, "Task created successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create task")}
    end
  end

  def handle_event("retry_task", %{"id" => id}, socket) do
    case Projects.retry_task(id) do
      {:ok, _} ->
        {tasks, _} = load_prd_scoped_data(socket.assigns.project, socket.assigns.selected_prd)
        {:noreply, assign(socket, tasks: tasks) |> put_flash(:info, "Task queued for retry")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to retry task")}
    end
  end

  # PubSub event handlers
  @impl true
  def handle_info({:phase_changed, _project_id, phase}, socket) do
    project = %{socket.assigns.project | phase: phase}
    {:noreply, assign(socket, project: project)}
  end

  @impl true
  def handle_info({:agent_state_changed, agent_id, state}, socket) do
    agent_runs = Projects.list_agent_runs(socket.assigns.project.id)
    active_agents = Map.put(socket.assigns.active_agents, agent_id, %{state: state})
    {:noreply, assign(socket, agent_runs: agent_runs, active_agents: active_agents)}
  end

  @impl true
  def handle_info({:task_completed, _task}, socket) do
    {tasks, _} = load_prd_scoped_data(socket.assigns.project, socket.assigns.selected_prd)
    {:noreply, assign(socket, tasks: tasks)}
  end

  @impl true
  def handle_info({:agent_spawned, agent_id, agent_type}, socket) do
    agent_runs = Projects.list_agent_runs(socket.assigns.project.id)

    active_agents =
      Map.put(socket.assigns.active_agents, agent_id, %{state: :idle, type: agent_type})

    {:noreply, assign(socket, agent_runs: agent_runs, active_agents: active_agents)}
  end

  @impl true
  def handle_info({:activity_log, entry}, socket) do
    {:noreply,
     socket
     |> stream_insert(:activity_log, entry)
     |> assign(:log_count, socket.assigns.log_count + 1)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  # Helper functions

  defp find_prd(_prds, nil), do: nil

  defp find_prd(prds, id) do
    Enum.find(prds, &(&1.id == id))
  end

  defp load_prd_scoped_data(project, nil) do
    {Projects.list_tasks(project.id), Projects.list_agent_runs(project.id)}
  end

  defp load_prd_scoped_data(project, prd) do
    tasks = Projects.list_tasks_for_prd(project.id, prd.id)
    agent_runs = Projects.list_agent_runs(project.id)
    {tasks, agent_runs}
  end

  def can_start?(project, selected_prd) do
    project.status in [:pending, :completed, :failed] && selected_prd != nil
  end

  def can_pause?(project), do: project.status == :running
  def can_resume?(project), do: project.status == :paused
  def can_stop?(project), do: project.status in [:running, :paused]
  def can_restart?(project), do: project.status in [:running, :paused] && project.active_prd_id != nil
  def can_terminate?(project), do: project.status in [:running, :paused]
  def is_running?(project), do: project.status in [:running, :paused]

  def status_text_color(:running), do: "text-green-500"
  def status_text_color(:paused), do: "text-orange-500"
  def status_text_color(:failed), do: "text-red-500"
  def status_text_color(_), do: "text-base-content/70"

  def prd_status_color(:draft), do: "bg-base-300 text-base-content/70"
  def prd_status_color(:in_progress), do: "bg-blue-100 text-blue-800"
  def prd_status_color(:review), do: "bg-yellow-100 text-yellow-800"
  def prd_status_color(:approved), do: "bg-green-100 text-green-800"
  def prd_status_color(:archived), do: "bg-zinc-100 text-zinc-500"
  def prd_status_color(_), do: "bg-zinc-100 text-zinc-600"

  def phase_color(phase, current_phase) do
    phases = Project.phases()
    phase_idx = Enum.find_index(phases, &(&1 == phase))
    current_idx = Enum.find_index(phases, &(&1 == current_phase))

    cond do
      phase_idx < current_idx -> "bg-green-500"
      phase_idx == current_idx -> "bg-blue-500"
      true -> "bg-zinc-200"
    end
  end

  def agent_state_color(:idle), do: "text-zinc-500"
  def agent_state_color(:reason), do: "text-purple-600"
  def agent_state_color(:act), do: "text-blue-600"
  def agent_state_color(:reflect), do: "text-yellow-600"
  def agent_state_color(:verify), do: "text-green-600"
  def agent_state_color(:failed), do: "text-red-600"
  def agent_state_color(_), do: "text-zinc-500"

  def task_status_color(:pending), do: "bg-yellow-100 text-yellow-800"
  def task_status_color(:running), do: "bg-blue-100 text-blue-800"
  def task_status_color(:completed), do: "bg-green-100 text-green-800"
  def task_status_color(:failed), do: "bg-red-100 text-red-800"
  def task_status_color(:dead_letter), do: "bg-zinc-100 text-zinc-800"
  def task_status_color(_), do: "bg-zinc-100 text-zinc-600"

  def log_stage_color(:reason), do: "text-purple-400"
  def log_stage_color(:act), do: "text-blue-400"
  def log_stage_color(:reflect), do: "text-yellow-400"
  def log_stage_color(:verify), do: "text-green-400"
  def log_stage_color(:phase_change), do: "text-cyan-400"
  def log_stage_color(:spawned), do: "text-emerald-400"
  def log_stage_color(:completed), do: "text-green-300"
  def log_stage_color(:failed), do: "text-red-400"
  def log_stage_color(_), do: "text-zinc-400"

  def source_badge_class(:agent), do: "bg-blue-900 text-blue-300"
  def source_badge_class(:orchestrator), do: "bg-purple-900 text-purple-300"
  def source_badge_class(:task), do: "bg-emerald-900 text-emerald-300"
  def source_badge_class(_), do: "bg-zinc-800 text-zinc-400"

  def log_source_label(:agent), do: "AGT"
  def log_source_label(:orchestrator), do: "ORC"
  def log_source_label(:task), do: "TSK"
  def log_source_label(_), do: "SYS"

  def format_log_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  def relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
