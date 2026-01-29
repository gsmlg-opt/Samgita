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

        tasks = Projects.list_tasks(project.id)

        {:ok,
         assign(socket,
           page_title: project.name,
           project: project,
           tasks: tasks,
           agents: []
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("start", _, socket) do
    case Projects.start_project(socket.assigns.project.id) do
      {:ok, project} ->
        {:noreply, assign(socket, project: project)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to start project")}
    end
  end

  @impl true
  def handle_event("pause", _, socket) do
    case Projects.pause_project(socket.assigns.project.id) do
      {:ok, project} ->
        {:noreply, assign(socket, project: project)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to pause project")}
    end
  end

  @impl true
  def handle_event("resume", _, socket) do
    case Projects.resume_project(socket.assigns.project.id) do
      {:ok, project} ->
        {:noreply, assign(socket, project: project)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resume project")}
    end
  end

  @impl true
  def handle_info({:phase_changed, _project_id, phase}, socket) do
    project = %{socket.assigns.project | phase: phase}
    {:noreply, assign(socket, project: project)}
  end

  @impl true
  def handle_info({:agent_state_changed, agent_id, state}, socket) do
    agents =
      socket.assigns.agents
      |> Enum.reject(&(&1.id == agent_id))
      |> Kernel.++([%{id: agent_id, state: state}])

    {:noreply, assign(socket, agents: agents)}
  end

  @impl true
  def handle_info({:task_completed, _task}, socket) do
    tasks = Projects.list_tasks(socket.assigns.project.id)
    {:noreply, assign(socket, tasks: tasks)}
  end

  @impl true
  def handle_info({:agent_spawned, agent_id, agent_type}, socket) do
    agents = [%{id: agent_id, type: agent_type, state: :idle} | socket.assigns.agents]
    {:noreply, assign(socket, agents: agents)}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  def status_text_color(:running), do: "text-green-600"
  def status_text_color(:paused), do: "text-orange-600"
  def status_text_color(:failed), do: "text-red-600"
  def status_text_color(_), do: "text-zinc-900"

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
  def agent_state_color(_), do: "text-zinc-500"

  def task_status_color(:pending), do: "bg-yellow-100 text-yellow-800"
  def task_status_color(:running), do: "bg-blue-100 text-blue-800"
  def task_status_color(:completed), do: "bg-green-100 text-green-800"
  def task_status_color(:failed), do: "bg-red-100 text-red-800"
  def task_status_color(:dead_letter), do: "bg-zinc-100 text-zinc-800"
  def task_status_color(_), do: "bg-zinc-100 text-zinc-600"
end
