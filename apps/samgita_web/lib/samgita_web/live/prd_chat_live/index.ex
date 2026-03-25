defmodule SamgitaWeb.PrdChatLive.Index do
  use SamgitaWeb, :live_view

  alias Samgita.{Prds, Projects}

  @impl true
  def mount(%{"project_id" => project_id, "prd_id" => prd_id}, _session, socket) do
    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, prd} <- Prds.get_prd(prd_id) do
      messages = Prds.list_messages(prd_id)

      {:ok,
       assign(socket,
         page_title: prd.title,
         project: project,
         prd: prd,
         title: prd.title,
         content: prd.content || "",
         preview: false,
         active_tab: :editor,
         chat_messages: messages,
         chat_input: "",
         generating: false
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
           preview: false,
           active_tab: :editor,
           chat_messages: [],
           chat_input: "",
           generating: false
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
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

  @impl true
  def handle_event("update_chat_input", %{"chat_input" => value}, socket) do
    {:noreply, assign(socket, chat_input: value)}
  end

  @impl true
  def handle_event("send_message", %{"chat_input" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      send_chat_message(socket, message)
    end
  end

  @impl true
  def handle_event("generate_prd", _, socket) do
    if socket.assigns.generating || socket.assigns.chat_messages == [] do
      {:noreply, socket}
    else
      socket = assign(socket, generating: true)
      pid = self()
      messages = socket.assigns.chat_messages
      prd_id = prd_id(socket)

      Task.start(fn ->
        result = generate_prd_from_chat(messages, prd_id)
        send(pid, {:prd_generated, result})
      end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:chat_response, {:ok, response}, user_message}, socket) do
    prd_id = prd_id(socket)

    user_msg = build_message(:user, user_message)
    assistant_msg = build_message(:assistant, response)

    if prd_id do
      Prds.add_user_message(prd_id, user_message)
      Prds.add_assistant_message(prd_id, response)
    end

    {:noreply,
     assign(socket,
       chat_messages: socket.assigns.chat_messages ++ [user_msg, assistant_msg],
       chat_input: "",
       generating: false
     )}
  end

  @impl true
  def handle_info({:chat_response, {:error, reason}, user_message}, socket) do
    user_msg = build_message(:user, user_message)
    error_content = "Sorry, I encountered an error: #{inspect(reason)}"
    error_msg = build_message(:assistant, error_content)

    {:noreply,
     socket
     |> assign(
       chat_messages: socket.assigns.chat_messages ++ [user_msg, error_msg],
       chat_input: "",
       generating: false
     )
     |> put_flash(:error, "Claude request failed: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({:prd_generated, {:ok, content}}, socket) do
    {:noreply,
     socket
     |> assign(content: content, generating: false, active_tab: :editor)
     |> put_flash(:info, "PRD generated from conversation")}
  end

  @impl true
  def handle_info({:prd_generated, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(generating: false)
     |> put_flash(:error, "PRD generation failed: #{inspect(reason)}")}
  end

  defp send_chat_message(socket, message) do
    socket = assign(socket, generating: true)
    pid = self()
    chat_history = socket.assigns.chat_messages

    Task.start(fn ->
      prompt = build_prompt(chat_history, message)

      result =
        SamgitaProvider.query(prompt,
          system_prompt:
            "You are a helpful product manager assistant. Help the user define and refine their Product Requirements Document (PRD). Ask clarifying questions, suggest improvements, and help structure requirements clearly."
        )

      send(pid, {:chat_response, result, message})
    end)

    {:noreply, socket}
  end

  defp build_prompt(history, new_message) do
    history_text =
      Enum.map_join(history, "\n\n", fn msg ->
        role = if msg.role in [:user, "user"], do: "User", else: "Assistant"
        "#{role}: #{msg.content}"
      end)

    if history_text == "" do
      new_message
    else
      "Previous conversation:\n#{history_text}\n\nUser: #{new_message}"
    end
  end

  defp generate_prd_from_chat(messages, prd_id) do
    conversation =
      Enum.map_join(messages, "\n\n", fn msg ->
        role = if msg.role in [:user, "user"], do: "User", else: "Assistant"
        "#{role}: #{msg.content}"
      end)

    prompt = """
    Based on the following conversation, generate a well-structured Product Requirements Document (PRD) in Markdown format.

    Include these sections as applicable:
    - Project Overview
    - Problem Statement
    - Goals & Objectives
    - User Stories
    - Technical Requirements
    - Non-functional Requirements
    - Milestones
    - Success Metrics

    Conversation:
    #{conversation}

    Generate the PRD now:
    """

    case SamgitaProvider.query(prompt,
           system_prompt:
             "You are an expert product manager. Generate a comprehensive PRD in Markdown format based on the conversation provided. Output only the PRD content, no preamble."
         ) do
      {:ok, content} ->
        if prd_id do
          Prds.add_system_message(prd_id, "Generated PRD from conversation")
        end

        {:ok, content}

      error ->
        error
    end
  end

  defp build_message(role, content) do
    %{role: role, content: content, inserted_at: DateTime.utc_now()}
  end

  defp prd_id(%{assigns: %{prd: %{id: id}}}), do: id
  defp prd_id(_), do: nil

  defp save_prd(%{assigns: %{prd: nil}} = socket, title, content) do
    status = if(content == "", do: :draft, else: :approved)

    attrs = %{
      project_id: socket.assigns.project.id,
      title: title,
      content: content,
      status: status
    }

    case Prds.create_prd(attrs) do
      {:ok, prd} ->
        maybe_start_project(socket.assigns.project, prd, status)

        {:noreply,
         socket
         |> put_flash(:info, "PRD created")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create PRD")}
    end
  end

  defp save_prd(%{assigns: %{prd: prd}} = socket, title, content) do
    status = if(content == "", do: :draft, else: :approved)

    attrs = %{
      title: title,
      content: content,
      status: status
    }

    case Prds.update_prd(prd, attrs) do
      {:ok, updated_prd} ->
        maybe_start_project(socket.assigns.project, updated_prd, status)

        {:noreply,
         socket
         |> put_flash(:info, "PRD updated")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update PRD")}
    end
  end

  defp maybe_start_project(project, prd, :approved) do
    if project.status in [:pending, :failed] do
      Projects.start_project(project.id, prd.id)
    end
  end

  defp maybe_start_project(_project, _prd, _status), do: :ok
end
