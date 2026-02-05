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
        agent_runs = Projects.list_agent_runs(project.id)
        available_agents = get_available_agent_types()
        prds = Samgita.Prds.list_prds(project.id)

        {:ok,
         assign(socket,
           page_title: project.name,
           project: project,
           tasks: tasks,
           agent_runs: agent_runs,
           available_agents: available_agents,
           prds: prds,
           editing_prd: false,
           prd_content: project.prd_content || "",
           show_task_form: false,
           task_form: %{type: "", payload: "{}"}
         )}

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
    case Projects.start_project(socket.assigns.project.id) do
      {:ok, project} ->
        {:noreply, assign(socket, project: project)}

      {:error, _} ->
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

  # PRD Management events
  def handle_event("create_plan", _, socket) do
    case Projects.enqueue_task(
      socket.assigns.project.id,
      "generate-prd",
      "prod-pm",
      %{
        project_name: socket.assigns.project.name,
        git_url: socket.assigns.project.git_url,
        working_path: socket.assigns.project.working_path,
        existing_prd: socket.assigns.project.prd_content
      }
    ) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "PRD generation task queued. The product manager agent will analyze your project and create a PRD.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to queue PRD generation task")}
    end
  end

  def handle_event("edit_prd", _, socket) do
    {:noreply, assign(socket, editing_prd: true, prd_content: socket.assigns.project.prd_content || "")}
  end

  def handle_event("cancel_prd", _, socket) do
    {:noreply, assign(socket, editing_prd: false, prd_content: socket.assigns.project.prd_content || "")}
  end

  def handle_event("save_prd", %{"prd_content" => content}, socket) do
    case Projects.update_prd(socket.assigns.project, content) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(project: project, editing_prd: false, prd_content: content)
         |> put_flash(:info, "PRD updated successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update PRD")}
    end
  end

  def handle_event("update_prd_content", %{"value" => content}, socket) do
    {:noreply, assign(socket, prd_content: content)}
  end

  # Task Management events
  def handle_event("show_task_form", _, socket) do
    {:noreply, assign(socket, show_task_form: true)}
  end

  def handle_event("hide_task_form", _, socket) do
    {:noreply, assign(socket, show_task_form: false, task_form: %{type: "", payload: "{}"})}
  end

  def handle_event("create_task", %{"task" => task_params}, socket) do
    payload = case Jason.decode(task_params["payload"]) do
      {:ok, parsed} -> parsed
      _ -> %{}
    end

    attrs = %{
      type: task_params["type"],
      payload: payload,
      priority: String.to_integer(task_params["priority"] || "5"),
      status: :pending
    }

    case Projects.create_task(socket.assigns.project.id, attrs) do
      {:ok, _task} ->
        tasks = Projects.list_tasks(socket.assigns.project.id)
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
        tasks = Projects.list_tasks(socket.assigns.project.id)
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
  def handle_info({:agent_state_changed, _agent_id, _state}, socket) do
    agent_runs = Projects.list_agent_runs(socket.assigns.project.id)
    {:noreply, assign(socket, agent_runs: agent_runs)}
  end

  @impl true
  def handle_info({:task_completed, _task}, socket) do
    tasks = Projects.list_tasks(socket.assigns.project.id)
    {:noreply, assign(socket, tasks: tasks)}
  end

  @impl true
  def handle_info({:agent_spawned, _agent_id, _agent_type}, socket) do
    agent_runs = Projects.list_agent_runs(socket.assigns.project.id)
    {:noreply, assign(socket, agent_runs: agent_runs)}
  end

  @impl true
  def handle_info({:prd_generated, _project_id}, socket) do
    case Projects.get_project(socket.assigns.project.id) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(project: project, prd_content: project.prd_content || "")
         |> put_flash(:info, "PRD has been generated successfully!")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  # Helper functions
  defp get_available_agent_types do
    [
      %{name: "prod-pm", category: "Product", description: "Product planning, PRD creation"},
      %{name: "prod-design", category: "Product", description: "UX/UI design"},
      %{name: "eng-frontend", category: "Engineering", description: "Frontend development"},
      %{name: "eng-backend", category: "Engineering", description: "Backend services"},
      %{name: "eng-database", category: "Engineering", description: "Database design"},
      %{name: "eng-mobile", category: "Engineering", description: "Mobile apps"},
      %{name: "eng-api", category: "Engineering", description: "API development"},
      %{name: "eng-qa", category: "Engineering", description: "Quality assurance"},
      %{name: "eng-perf", category: "Engineering", description: "Performance optimization"},
      %{name: "eng-infra", category: "Engineering", description: "Infrastructure"},
      %{name: "ops-devops", category: "Operations", description: "DevOps automation"},
      %{name: "ops-sre", category: "Operations", description: "Site reliability"},
      %{name: "ops-security", category: "Operations", description: "Security"},
      %{name: "data-ml", category: "Data", description: "Machine learning"},
      %{name: "data-eng", category: "Data", description: "Data engineering"}
    ]
  end

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
  def agent_state_color(:failed), do: "text-red-600"
  def agent_state_color(_), do: "text-zinc-500"

  def task_status_color(:pending), do: "bg-yellow-100 text-yellow-800"
  def task_status_color(:running), do: "bg-blue-100 text-blue-800"
  def task_status_color(:completed), do: "bg-green-100 text-green-800"
  def task_status_color(:failed), do: "bg-red-100 text-red-800"
  def task_status_color(:dead_letter), do: "bg-zinc-100 text-zinc-800"
  def task_status_color(_), do: "bg-zinc-100 text-zinc-600"

  def relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end
end
