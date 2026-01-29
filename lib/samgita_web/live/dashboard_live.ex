defmodule SamgitaWeb.DashboardLive do
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold text-zinc-900">Samgita Dashboard</h1>
        <.link
          navigate={~p"/projects/new"}
          class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
        >
          New Project
        </.link>
      </div>

      <div :if={@projects == []} class="text-center py-16 text-zinc-500">
        <p class="text-lg">No projects yet.</p>
        <p class="mt-2">Create your first project to get started.</p>
      </div>

      <div class="grid gap-4">
        <.link
          :for={project <- @projects}
          navigate={~p"/projects/#{project}"}
          class="block bg-white rounded-lg shadow p-6 hover:shadow-md transition-shadow"
        >
          <div class="flex justify-between items-start">
            <div>
              <h2 class="text-xl font-semibold text-zinc-900">{project.name}</h2>
              <p class="text-sm text-zinc-500 mt-1">{project.git_url}</p>
            </div>
            <div class="flex gap-2">
              <span class={"px-2 py-1 text-xs rounded-full font-medium #{status_color(project.status)}"}>
                {project.status}
              </span>
              <span class="px-2 py-1 text-xs rounded-full bg-zinc-100 text-zinc-600">
                {project.phase}
              </span>
            </div>
          </div>
        </.link>
      </div>
    </div>
    """
  end

  defp status_color(:pending), do: "bg-yellow-100 text-yellow-800"
  defp status_color(:running), do: "bg-green-100 text-green-800"
  defp status_color(:paused), do: "bg-orange-100 text-orange-800"
  defp status_color(:completed), do: "bg-blue-100 text-blue-800"
  defp status_color(:failed), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-zinc-100 text-zinc-600"
end
