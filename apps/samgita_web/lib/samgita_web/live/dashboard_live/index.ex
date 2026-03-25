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
    project_ids = Enum.map(projects, & &1.id)
    batch_stats = Projects.task_stats_batch(project_ids)

    Map.new(projects, fn project ->
      {project.id, Map.get(batch_stats, project.id, %{})}
    end)
  end

  def total_tasks(stats), do: stats |> Map.values() |> Enum.sum()
  def task_stat(stats, status), do: Map.get(stats, status, 0)

  def status_badge_color(:pending), do: "warning"
  def status_badge_color(:running), do: "success"
  def status_badge_color(:paused), do: "warning"
  def status_badge_color(:completed), do: "primary"
  def status_badge_color(:failed), do: "error"
  def status_badge_color(_), do: ""
end
