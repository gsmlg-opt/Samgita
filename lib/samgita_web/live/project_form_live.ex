defmodule SamgitaWeb.ProjectFormLive do
  use SamgitaWeb, :live_view

  alias Samgita.Projects
  alias Samgita.Domain.Project
  alias Samgita.Git

  @impl true
  def mount(_params, _session, socket) do
    changeset = Project.changeset(%Project{}, %{})

    {:ok,
     assign(socket,
       page_title: "New Project",
       form: to_form(changeset),
       detected_path: nil,
       clone_needed: false,
       prd_content: ""
     )}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      %Project{}
      |> Project.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("detect_path", %{"project" => %{"git_url" => url}}, socket) when url != "" do
    case Git.find_local_repo(url) do
      {:ok, path} ->
        {:noreply, assign(socket, detected_path: path, clone_needed: false)}

      :not_found ->
        {:noreply, assign(socket, detected_path: nil, clone_needed: true)}
    end
  end

  def handle_event("detect_path", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"project" => params}, socket) do
    params =
      params
      |> maybe_set_path(socket.assigns)
      |> maybe_set_prd(socket.assigns)

    case Projects.create_project(params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created")
         |> push_navigate(to: ~p"/projects/#{project}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("update_prd", %{"prd_content" => content}, socket) do
    {:noreply, assign(socket, prd_content: content)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <.link navigate={~p"/"} class="text-sm text-zinc-500 hover:text-zinc-700">
        &larr; Dashboard
      </.link>
      <h1 class="text-3xl font-bold text-zinc-900 mt-4 mb-8">New Project</h1>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
        <div>
          <label class="block text-sm font-medium text-zinc-700 mb-1">Project Name</label>
          <.input field={@form[:name]} type="text" placeholder="My Project" required />
        </div>

        <div>
          <label class="block text-sm font-medium text-zinc-700 mb-1">Git URL</label>
          <.input
            field={@form[:git_url]}
            type="text"
            placeholder="git@github.com:org/repo.git"
            phx-blur="detect_path"
            required
          />
          <p :if={@detected_path} class="text-sm text-green-600 mt-1">
            Found local clone: {@detected_path}
          </p>
          <p :if={@clone_needed} class="text-sm text-yellow-600 mt-1">
            Repo not found locally. Will clone on project start.
          </p>
        </div>

        <div>
          <label class="block text-sm font-medium text-zinc-700 mb-1">Working Path (optional)</label>
          <.input field={@form[:working_path]} type="text" placeholder="Auto-detected from git URL" />
        </div>

        <div>
          <label class="block text-sm font-medium text-zinc-700 mb-1">PRD Content</label>
          <textarea
            name="prd_content"
            rows="12"
            class="w-full rounded-lg border-zinc-300 shadow-sm focus:ring-blue-500 focus:border-blue-500"
            placeholder="Paste your Product Requirements Document here..."
            phx-change="update_prd"
          ><%= @prd_content %></textarea>
        </div>

        <div class="flex justify-end gap-3">
          <.link navigate={~p"/"} class="px-4 py-2 text-zinc-600 hover:text-zinc-900">Cancel</.link>
          <button type="submit" class="bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700">
            Create Project
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp maybe_set_path(params, %{detected_path: path}) when not is_nil(path) do
    Map.put_new(params, "working_path", path)
  end

  defp maybe_set_path(params, _), do: params

  defp maybe_set_prd(params, %{prd_content: content}) when content != "" do
    Map.put(params, "prd_content", content)
  end

  defp maybe_set_prd(params, _), do: params
end
