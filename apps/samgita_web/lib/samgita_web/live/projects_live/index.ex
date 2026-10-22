defmodule SamgitaWeb.ProjectsLive.Index do
  use SamgitaWeb, :live_view
  alias Samgita.{Management, Principal, Projects}
  alias SamgitaWeb.ProjectsLive.Support, as: UI

  @impl true
  def mount(_, _, socket),
    do: {:ok, assign(socket, page_title: "Projects", form: UI.new_form("project"), error: nil)}

  @impl true
  def handle_params(params, _, socket) do
    case Management.projects(Principal.operator(), params) do
      {:ok, page} ->
        {:noreply, assign(socket, page: page)}

      {:error, error} ->
        {:noreply,
         assign(socket,
           page: %{"data" => [], "limit" => 25, "offset" => 0, "total" => 0},
           error: UI.error(error)
         )}
    end
  end

  @impl true
  def handle_event("change:project", %{"project" => values}, socket),
    do: {:noreply, assign(socket, form: UI.changed("project", values, nil), error: nil)}

  def handle_event("create", %{"project" => values}, socket) do
    case Projects.create(Principal.operator(), UI.attrs(values)) do
      {:ok, project} ->
        {:noreply, push_navigate(socket, to: ~p"/projects/#{project["id"]}")}

      {:error, error} ->
        {:noreply,
         assign(socket, form: UI.rejected("project", values, error), error: UI.error(error))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl space-y-6 p-4 sm:p-6">
      <header>
        <h1 class="text-3xl font-bold">Projects</h1><p class="text-on-surface-variant">
          Manage logical work and the Agents authorized to act on it.
        </p>
      </header>
      <div class="grid items-start gap-6 lg:grid-cols-[2fr_1fr]">
        <.dm_card>
          <:title>Registered projects</:title>
          <p :if={@page["data"] == []} id="projects-empty">
            No projects yet. Create a project to begin.
          </p>
          <ul class="divide-y divide-outline-variant">
            <li :for={project <- @page["data"]} class="py-4" id={"project-" <> project["id"]}>
              <.link
                navigate={~p"/projects/#{project["id"]}"}
                class="text-lg font-semibold text-primary"
              >{project["name"]}</.link>
              <p>{project["description"]}</p><p class="text-sm text-on-surface-variant">
                {project["state"]} · version {project["version"]}
              </p>
            </li>
          </ul>
          <UI.pagination
            offset={@page["offset"]}
            limit={@page["limit"]}
            total={@page["total"]}
            path="/projects"
          />
        </.dm_card>
        <.dm_card>
          <:title>Create project</:title>
          <p class="mb-4 text-sm text-on-surface-variant">
            A repository or PRD is optional. Project identity stays stable when repositories change.
          </p>
          <UI.command_form
            form={@form}
            event="create"
            label="Create project"
            error={@error}
            primary
            fields={[{"name", "Name", "text"}, {"description", "Description", "textarea"}]}
          />
        </.dm_card>
      </div>
    </div>
    """
  end
end
