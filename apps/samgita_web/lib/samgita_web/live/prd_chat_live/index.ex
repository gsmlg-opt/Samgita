defmodule SamgitaWeb.PrdChatLive.Index do
  use SamgitaWeb, :live_view

  alias Samgita.{Projects, Prds}

  @impl true
  def mount(%{"project_id" => project_id, "prd_id" => prd_id}, _session, socket) do
    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, prd} <- Prds.get_prd(prd_id) do
      {:ok,
       assign(socket,
         page_title: prd.title,
         project: project,
         prd: prd,
         title: prd.title,
         content: prd.content || "",
         preview: false
       )}
    else
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "PRD not found")
         |> push_navigate(to: ~p"/projects/#{project_id}")}
    end
  end

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Projects.get_project(project_id) do
      {:ok, project} ->
        {:ok,
         assign(socket,
           page_title: "New PRD",
           project: project,
           prd: nil,
           title: "",
           content: "",
           preview: false
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("validate", %{"prd" => params}, socket) do
    {:noreply,
     assign(socket,
       title: params["title"] || socket.assigns.title,
       content: params["content"] || socket.assigns.content
     )}
  end

  @impl true
  def handle_event("save", %{"prd" => params}, socket) do
    title = String.trim(params["title"] || "")
    content = String.trim(params["content"] || "")

    if title == "" do
      {:noreply, put_flash(socket, :error, "Title is required")}
    else
      save_prd(socket, title, content)
    end
  end

  @impl true
  def handle_event("toggle_preview", _, socket) do
    {:noreply, assign(socket, preview: !socket.assigns.preview)}
  end

  defp save_prd(%{assigns: %{prd: nil}} = socket, title, content) do
    attrs = %{
      project_id: socket.assigns.project.id,
      title: title,
      content: content,
      status: if(content == "", do: :draft, else: :approved)
    }

    case Prds.create_prd(attrs) do
      {:ok, _prd} ->
        {:noreply,
         socket
         |> put_flash(:info, "PRD created")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create PRD")}
    end
  end

  defp save_prd(%{assigns: %{prd: prd}} = socket, title, content) do
    attrs = %{
      title: title,
      content: content,
      status: if(content == "", do: :draft, else: :approved)
    }

    case Prds.update_prd(prd, attrs) do
      {:ok, _prd} ->
        {:noreply,
         socket
         |> put_flash(:info, "PRD updated")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update PRD")}
    end
  end
end
