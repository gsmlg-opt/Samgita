defmodule SamgitaWeb.PrdChatLive.Index do
  use SamgitaWeb, :live_view

  require Logger

  alias Samgita.{Projects, Prds}
  alias Samgita.Agent.Claude, as: ClaudeAgent

  @impl true
  def mount(%{"project_id" => project_id, "prd_id" => prd_id}, _session, socket) do
    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, prd} <- Prds.get_prd_with_messages(prd_id) do
      {:ok,
       assign(socket,
         page_title: "PRD Chat: #{prd.title}",
         project: project,
         prd: prd,
         messages: prd.chat_messages,
         input: "",
         streaming_message: nil,
         generating: false,
         show_new_prd_form: false
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
           messages: [],
           input: "",
           streaming_message: nil,
           generating: false,
           show_new_prd_form: true,
           new_prd_title: ""
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("create_prd", %{"title" => title}, socket) do
    case Prds.create_prd(%{
           project_id: socket.assigns.project.id,
           title: title,
           status: :in_progress
         }) do
      {:ok, prd} ->
        # Add system message
        {:ok, _} =
          Prds.add_system_message(
            prd.id,
            "Hello! I'm your AI product manager assistant. I'll help you create a comprehensive Product Requirements Document. Let's discuss your project and I'll ask questions to understand your needs better."
          )

        messages = Prds.list_messages(prd.id)

        {:noreply,
         socket
         |> assign(
           prd: prd,
           messages: messages,
           show_new_prd_form: false,
           page_title: "PRD Chat: #{title}"
         )
         |> put_flash(:info, "PRD created successfully. Start chatting!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create PRD")}
    end
  end

  def handle_event("send_message", %{"message" => content}, socket) when content != "" do
    prd_id = socket.assigns.prd.id

    # Save user message
    case Prds.add_user_message(prd_id, content) do
      {:ok, user_msg} ->
        messages = socket.assigns.messages ++ [user_msg]

        # Start generating AI response
        send(self(), :generate_ai_response)

        {:noreply,
         assign(socket,
           messages: messages,
           input: "",
           generating: true,
           streaming_message: ""
         )}

      {:error, reason} ->
        Logger.error("Failed to save user message: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to save message")}
    end
  end

  def handle_event("send_message", _, socket), do: {:noreply, socket}

  def handle_event("update_input", params, socket) do
    value = params["message"] || params["value"] || ""
    {:noreply, assign(socket, input: value)}
  end

  def handle_event("finalize_prd", _, socket) do
    case Prds.generate_prd_content(socket.assigns.prd.id) do
      {:ok, prd} ->
        {:noreply,
         socket
         |> assign(prd: prd)
         |> put_flash(:info, "PRD content generated and saved!")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to generate PRD content")}
    end
  end

  @impl true
  def handle_info(:generate_ai_response, socket) do
    prd_id = socket.assigns.prd.id
    messages = socket.assigns.messages

    # Format conversation history into a prompt string for the Claude Agent SDK
    prompt =
      messages
      |> Enum.reject(&(&1.role == :system))
      |> Enum.map(fn msg ->
        label = if msg.role == :user, do: "User", else: "Assistant"
        "#{label}: #{msg.content}"
      end)
      |> Enum.join("\n\n")

    system_prompt = """
    You are an expert Product Manager helping create a Product Requirements Document (PRD).

    Guidelines:
    - Ask clarifying questions about the product, users, goals, and technical requirements
    - Be conversational and helpful
    - After gathering enough information, provide structured PRD sections
    - Use markdown formatting for better readability
    - Keep responses concise but informative
    - Guide the conversation naturally, asking follow-up questions
    - Do NOT use any tools - respond conversationally only

    PRD should eventually cover:
    1. Project Overview (problem, solution, target users)
    2. Goals & Objectives (success metrics, priorities)
    3. User Stories (key user journeys)
    4. Technical Requirements (stack, architecture)
    5. Non-Functional Requirements (performance, security)
    6. Milestones & Timeline

    Continue the conversation below. Only provide the next assistant response.
    """

    # Use Claude Agent SDK (CLI-based auth) instead of direct API
    result =
      ClaudeAgent.chat(prompt,
        model: "sonnet",
        system_prompt: system_prompt,
        max_turns: 1
      )

    case result do
      {:ok, text} when text != "" ->
        # Save assistant message
        case Prds.add_assistant_message(prd_id, text) do
          {:ok, assistant_msg} ->
            messages = socket.assigns.messages ++ [assistant_msg]

            {:noreply,
             assign(socket,
               messages: messages,
               generating: false,
               streaming_message: nil
             )}

          {:error, reason} ->
            Logger.error("Failed to save assistant message: #{inspect(reason)}")

            {:noreply,
             socket
             |> assign(generating: false, streaming_message: nil)
             |> put_flash(:error, "Failed to save AI response")}
        end

      {:ok, _} ->
        {:noreply,
         socket
         |> assign(generating: false, streaming_message: nil)
         |> put_flash(:error, "AI returned an empty response. Please try again.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(generating: false, streaming_message: nil)
         |> put_flash(:error, "Failed to generate response: #{inspect(reason)}")}
    end
  end

  def role_class(:user), do: "bg-blue-100 text-blue-900 ml-auto"
  def role_class(:assistant), do: "bg-zinc-100 text-zinc-900 mr-auto"
  def role_class(:system), do: "bg-purple-100 text-purple-900 mx-auto text-center text-sm"

  def role_label(:user), do: "You"
  def role_label(:assistant), do: "AI Product Manager"
  def role_label(:system), do: "System"
end
