defmodule SamgitaWeb.ProjectFormLive.Index do
  use SamgitaWeb, :live_view

  alias Samgita.Domain.Project
  alias Samgita.Git
  alias Samgita.Projects

  @impl true
  def mount(_params, _session, socket) do
    changeset = Project.changeset(%Project{}, %{})

    {:ok,
     assign(socket,
       page_title: "New Project",
       form: to_form(changeset),
       detected_path: nil,
       clone_needed: false,
       prd_content: "",
       start_mode: "from_prd",
       launch_mode: "local"
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
  def handle_event("set_start_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, start_mode: mode)}
  end

  @impl true
  def handle_event("set_launch_mode", %{"mode" => mode}, socket) when mode in ["local", "ssh"] do
    {:noreply, assign(socket, launch_mode: mode)}
  end

  @impl true
  def handle_event("save", %{"project" => params}, socket) do
    params =
      params
      |> Map.put("start_mode", socket.assigns.start_mode)
      |> put_codex_config(socket.assigns)
      |> maybe_set_path(socket.assigns)
      |> maybe_set_prd(socket.assigns)

    params =
      if params["start_mode"] == "from_idea" do
        Map.put(params, "phase", "planning")
      else
        params
      end

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

  defp maybe_set_path(params, %{launch_mode: "ssh"}), do: params

  defp maybe_set_path(params, %{detected_path: path}) when not is_nil(path) do
    Map.put_new(params, "working_path", path)
  end

  defp maybe_set_path(params, _), do: params

  defp maybe_set_prd(params, %{prd_content: content}) when content != "" do
    Map.put(params, "prd_content", content)
  end

  defp maybe_set_prd(params, _), do: params

  defp put_codex_config(params, %{launch_mode: "ssh"}) do
    codex_config = %{
      "mode" => "ssh",
      "ssh_target" => String.trim(params["ssh_target"] || ""),
      "remote_working_path" => String.trim(params["remote_working_path"] || "")
    }

    params
    |> Map.drop(["ssh_target", "remote_working_path"])
    |> Map.put("config", %{"codex_app_server" => codex_config})
    |> Map.put("working_path", nil)
  end

  defp put_codex_config(params, %{launch_mode: "local"}) do
    working_path = String.trim(params["working_path"] || "")

    codex_config =
      if working_path == "" do
        %{"mode" => "local"}
      else
        %{"mode" => "local", "working_path" => working_path}
      end

    Map.put(params, "config", %{"codex_app_server" => codex_config})
  end
end
