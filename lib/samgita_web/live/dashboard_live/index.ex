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
       projects: projects
     )}
  end

  @impl true
  def handle_info({:project_updated, _project}, socket) do
    projects = Projects.list_projects()
    {:noreply, assign(socket, projects: projects)}
  end

  @impl true
  def handle_info({:project_updated, _project_id, _phase}, socket) do
    projects = Projects.list_projects()
    {:noreply, assign(socket, projects: projects)}
  end

  def status_color(:pending), do: "bg-yellow-100 text-yellow-800"
  def status_color(:running), do: "bg-green-100 text-green-800"
  def status_color(:paused), do: "bg-orange-100 text-orange-800"
  def status_color(:completed), do: "bg-blue-100 text-blue-800"
  def status_color(:failed), do: "bg-red-100 text-red-800"
  def status_color(_), do: "bg-zinc-100 text-zinc-600"
end
