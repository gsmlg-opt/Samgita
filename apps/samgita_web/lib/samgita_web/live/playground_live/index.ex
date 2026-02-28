defmodule SamgitaWeb.PlaygroundLive.Index do
  use SamgitaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Create initial conversation
    initial_conversation = create_conversation("coding-assistant")

    {:ok,
     assign(socket,
       page_title: "Agent Playground",
       conversations: [initial_conversation],
       current_conversation_id: initial_conversation.id,
       input: "",
       loading: false
     )}
  end

  @impl true
  def handle_event(
        "restore_conversations",
        %{"conversations" => conv_data, "current_id" => current_id},
        socket
      ) do
    conversations = Enum.map(conv_data, &deserialize_conversation/1)

    {:noreply,
     assign(socket,
       conversations: conversations,
       current_conversation_id: current_id
     )}
  end

  @impl true
  def handle_event("select_agent_type", %{"type" => type}, socket) do
    conversation = get_current_conversation(socket)
    updated_conversation = %{conversation | agent_type: type}
    conversations = update_conversation(socket.assigns.conversations, updated_conversation)

    {:noreply,
     socket
     |> assign(conversations: conversations)
     |> persist_conversations()}
  end

  @impl true
  def handle_event("new_conversation", %{"type" => type}, socket) do
    new_conversation = create_conversation(type)
    conversations = [new_conversation | socket.assigns.conversations]

    {:noreply,
     socket
     |> assign(
       conversations: conversations,
       current_conversation_id: new_conversation.id,
       input: "",
       loading: false
     )
     |> persist_conversations()}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(current_conversation_id: id, input: "", loading: false)
     |> persist_conversations()}
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => id}, socket) do
    conversations = Enum.reject(socket.assigns.conversations, &(&1.id == id))

    # If we deleted the current conversation, switch to the first one
    current_id =
      if id == socket.assigns.current_conversation_id do
        case conversations do
          [first | _] -> first.id
          [] -> nil
        end
      else
        socket.assigns.current_conversation_id
      end

    # Ensure at least one conversation exists
    conversations =
      if conversations == [] do
        [create_conversation("coding-assistant")]
      else
        conversations
      end

    current_id = current_id || List.first(conversations).id

    {:noreply,
     socket
     |> assign(
       conversations: conversations,
       current_conversation_id: current_id
     )
     |> persist_conversations()}
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, input: message)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when byte_size(message) > 0 do
    conversation = get_current_conversation(socket)

    # Add user message to conversation
    new_message = %{role: "user", content: message, timestamp: DateTime.utc_now()}
    updated_messages = conversation.messages ++ [new_message]

    updated_conversation = %{conversation | messages: updated_messages, error: nil}
    conversations = update_conversation(socket.assigns.conversations, updated_conversation)

    socket =
      socket
      |> assign(conversations: conversations, input: "", loading: true)
      |> persist_conversations()

    # Send async message to Claude Agent SDK
    pid = self()
    system_prompt = get_system_prompt(conversation.agent_type)
    conversation_id = conversation.id

    Task.async(fn ->
      case SamgitaProvider.query(message, system_prompt: system_prompt, max_turns: 5) do
        {:ok, response} ->
          send(pid, {:agent_response, conversation_id, response})

        {:error, reason} ->
          send(pid, {:agent_error, conversation_id, reason})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("noop", _params, socket) do
    # No-op handler to prevent event bubbling for delete button
    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_response, conversation_id, response}, socket) do
    conversation = Enum.find(socket.assigns.conversations, &(&1.id == conversation_id))

    if conversation do
      new_message = %{role: "assistant", content: response, timestamp: DateTime.utc_now()}
      updated_messages = conversation.messages ++ [new_message]
      updated_conversation = %{conversation | messages: updated_messages}
      conversations = update_conversation(socket.assigns.conversations, updated_conversation)

      {:noreply,
       socket
       |> assign(conversations: conversations, loading: false)
       |> persist_conversations()}
    else
      {:noreply, assign(socket, loading: false)}
    end
  end

  @impl true
  def handle_info({:agent_error, conversation_id, reason}, socket) do
    conversation = Enum.find(socket.assigns.conversations, &(&1.id == conversation_id))

    if conversation do
      error_msg = "Error: #{inspect(reason)}"
      updated_conversation = %{conversation | error: error_msg}
      conversations = update_conversation(socket.assigns.conversations, updated_conversation)

      {:noreply,
       socket
       |> assign(conversations: conversations, loading: false)
       |> persist_conversations()}
    else
      {:noreply, assign(socket, loading: false)}
    end
  end

  @impl true
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    # Task completed, ignore
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    # Task process down, ignore
    {:noreply, socket}
  end

  # Private helper functions

  defp create_conversation(agent_type) do
    %{
      id: generate_id(),
      agent_type: agent_type,
      messages: [],
      error: nil,
      created_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Overload for Socket struct (used in event handlers)
  defp get_current_conversation(%Phoenix.LiveView.Socket{} = socket) do
    Enum.find(socket.assigns.conversations, &(&1.id == socket.assigns.current_conversation_id))
  end

  # Overload for assigns map (used in templates)
  defp get_current_conversation(assigns) when is_map(assigns) do
    Enum.find(assigns.conversations, &(&1.id == assigns.current_conversation_id))
  end

  defp update_conversation(conversations, updated_conversation) do
    Enum.map(conversations, fn conv ->
      if conv.id == updated_conversation.id do
        updated_conversation
      else
        conv
      end
    end)
  end

  defp get_conversation_title(conversation) do
    case conversation.messages do
      [] ->
        "New conversation"

      [first | _] ->
        # Use first user message as title, truncated
        first.content
        |> String.slice(0..50)
        |> then(fn title ->
          if String.length(first.content) > 50, do: title <> "...", else: title
        end)
    end
  end

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  # Agent type configurations
  defp get_system_prompt("coding-assistant") do
    """
    You are a helpful coding assistant with access to file operations and shell commands.
    You can read, write, and edit files, search for code, and run commands.

    When helping with code:
    - Be concise and practical
    - Show examples when helpful
    - Use tools to inspect and modify files
    - Follow best practices for clean code
    """
  end

  defp get_system_prompt("file-manager") do
    """
    You are a file management assistant.
    You help users organize, search, and manage files in their project.

    Use glob to find files, grep to search content, and read/write to manage files.
    Be efficient and provide clear summaries of your actions.
    """
  end

  defp get_system_prompt("code-reviewer") do
    """
    You are a code review assistant.
    You read code files, identify potential issues, suggest improvements,
    and check for best practices.

    Focus on:
    - Code quality and readability
    - Potential bugs or edge cases
    - Performance considerations
    - Security issues
    - Best practices for the language/framework
    """
  end

  defp get_system_prompt("test-generator") do
    """
    You are a test generation assistant.
    You create comprehensive test cases for code.

    When generating tests:
    - Cover edge cases and error scenarios
    - Follow testing best practices
    - Write clear, descriptive test names
    - Use appropriate assertions
    """
  end

  defp get_system_prompt(_type) do
    """
    You are a helpful AI assistant with access to various tools.
    You can read and write files, search for information, and execute commands.

    Be helpful, concise, and accurate in your responses.
    """
  end

  # Persistence helpers

  defp persist_conversations(socket) do
    conversations = Enum.map(socket.assigns.conversations, &serialize_conversation/1)
    current_id = socket.assigns.current_conversation_id

    push_event(socket, "save_conversations", %{
      conversations: conversations,
      current_id: current_id
    })
  end

  defp serialize_conversation(conv) do
    %{
      "id" => conv.id,
      "agent_type" => conv.agent_type,
      "messages" => Enum.map(conv.messages, &serialize_message/1),
      "error" => conv.error,
      "created_at" => DateTime.to_iso8601(conv.created_at)
    }
  end

  defp serialize_message(msg) do
    %{
      "role" => msg.role,
      "content" => msg.content,
      "timestamp" => DateTime.to_iso8601(msg.timestamp)
    }
  end

  defp deserialize_conversation(data) do
    {:ok, created_at, _} = DateTime.from_iso8601(data["created_at"])

    %{
      id: data["id"],
      agent_type: data["agent_type"],
      messages: Enum.map(data["messages"], &deserialize_message/1),
      error: data["error"],
      created_at: created_at
    }
  end

  defp deserialize_message(data) do
    {:ok, timestamp, _} = DateTime.from_iso8601(data["timestamp"])

    %{
      role: data["role"],
      content: data["content"],
      timestamp: timestamp
    }
  end
end
