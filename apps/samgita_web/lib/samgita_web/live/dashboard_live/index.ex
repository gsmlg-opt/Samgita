defmodule SamgitaWeb.DashboardLive.Index do
  use SamgitaWeb, :live_view

  alias Samgita.Projects

  @max_activity_entries 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Samgita.Events.subscribe_all_projects()
    end

    projects = Projects.list_projects()

    if connected?(socket) do
      Enum.each(projects, fn p -> Samgita.Events.subscribe_project(p.id) end)
    end

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       projects: projects,
       project_stats: load_project_stats(projects),
       activity_log: []
     )}
  end

  @impl true
  def handle_info({:project_updated, _project}, socket) do
    projects = Projects.list_projects()
    subscribe_new_projects(projects, socket.assigns.projects)
    {:noreply, assign(socket, projects: projects, project_stats: load_project_stats(projects))}
  end

  @impl true
  def handle_info({:project_updated, _project_id, _phase}, socket) do
    projects = Projects.list_projects()
    {:noreply, assign(socket, projects: projects, project_stats: load_project_stats(projects))}
  end

  @impl true
  def handle_info({:task_stats_changed, project_id}, socket) do
    stats = Projects.task_stats(project_id)
    project_stats = Map.put(socket.assigns.project_stats, project_id, stats)
    {:noreply, assign(socket, project_stats: project_stats)}
  end

  @impl true
  def handle_info({:activity_log, entry}, socket) do
    activity_log =
      [entry | socket.assigns.activity_log]
      |> Enum.take(@max_activity_entries)

    {:noreply, assign(socket, activity_log: activity_log)}
  end

  @impl true
  def handle_info({:phase_changed, _project_id, _phase}, socket) do
    projects = Projects.list_projects()
    {:noreply, assign(socket, projects: projects, project_stats: load_project_stats(projects))}
  end

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  defp subscribe_new_projects(new_projects, old_projects) do
    old_ids = MapSet.new(old_projects, & &1.id)

    Enum.each(new_projects, fn p ->
      unless MapSet.member?(old_ids, p.id) do
        Samgita.Events.subscribe_project(p.id)
      end
    end)
  end

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

  def activity_dot_color(%{stage: :spawned}), do: "bg-success"
  def activity_dot_color(%{stage: :phase_change}), do: "bg-primary"
  def activity_dot_color(%{stage: :task_completed}), do: "bg-success"
  def activity_dot_color(%{stage: :failed}), do: "bg-error"
  def activity_dot_color(%{stage: :reason}), do: "bg-tertiary"
  def activity_dot_color(_), do: "bg-on-surface-variant"
end
