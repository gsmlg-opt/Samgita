defmodule SamgitaWeb.DashboardLive.Index do
  use SamgitaWeb, :live_view

  alias Samgita.Projects

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Samgita.Events.subscribe_all_projects()
    end

    projects = Projects.list_projects()

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       projects: projects,
       project_stats: load_project_stats(projects)
     )}
  end

  @impl true
  def handle_info({:project_updated, _project}, socket) do
    projects = Projects.list_projects()
    {:noreply, assign(socket, projects: projects, project_stats: load_project_stats(projects))}
  end

  @impl true
  def handle_info({:project_updated, _project_id, _phase}, socket) do
    projects = Projects.list_projects()
    {:noreply, assign(socket, projects: projects, project_stats: load_project_stats(projects))}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  defp load_project_stats(projects) do
    Map.new(projects, fn project ->
      {project.id, Projects.task_stats(project.id)}
    end)
  end

  def total_tasks(stats), do: stats |> Map.values() |> Enum.sum()
  def task_stat(stats, status), do: Map.get(stats, status, 0)

  def status_color(:pending), do: "bg-yellow-100 text-yellow-800"
  def status_color(:running), do: "bg-green-100 text-green-800"
  def status_color(:paused), do: "bg-orange-100 text-orange-800"
  def status_color(:completed), do: "bg-blue-100 text-blue-800"
  def status_color(:failed), do: "bg-red-100 text-red-800"
  def status_color(_), do: "bg-zinc-100 text-zinc-600"
end
