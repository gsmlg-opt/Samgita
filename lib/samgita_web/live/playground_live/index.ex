defmodule SamgitaWeb.PlaygroundLive.Index do
  use SamgitaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Agent Playground",
       messages: [],
       input: "",
       agent: nil,
       agent_type: "coding-assistant",
       loading: false,
       error: nil
     )}
  end

  @impl true
  def handle_event("select_agent_type", %{"type" => type}, socket) do
    system_prompt = get_system_prompt(type)
    agent = ClaudeAgent.new(system_prompt)

    {:noreply,
     assign(socket,
       agent_type: type,
       agent: agent,
       messages: [],
       error: nil
     )}
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, input: message)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when byte_size(message) > 0 do
    socket =
      if socket.assigns.agent == nil do
        # Initialize agent if not already created
        system_prompt = get_system_prompt(socket.assigns.agent_type)
        agent = ClaudeAgent.new(system_prompt)
        assign(socket, agent: agent)
      else
        socket
      end

    # Add user message to chat
    messages = socket.assigns.messages ++ [%{role: "user", content: message}]
    socket = assign(socket, messages: messages, input: "", loading: true, error: nil)

    # Send async message to agent
    pid = self()

    Task.async(fn ->
      case ClaudeAgent.ask(socket.assigns.agent, message, max_turns: 5) do
        {:ok, response, new_agent} ->
          send(pid, {:agent_response, response, new_agent})

        {:error, reason} ->
          send(pid, {:agent_error, reason})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_chat", _params, socket) do
    system_prompt = get_system_prompt(socket.assigns.agent_type)
    agent = ClaudeAgent.new(system_prompt)

    {:noreply,
     assign(socket,
       messages: [],
       agent: agent,
       input: "",
       loading: false,
       error: nil
     )}
  end

  @impl true
  def handle_info({:agent_response, response, new_agent}, socket) do
    messages = socket.assigns.messages ++ [%{role: "assistant", content: response}]

    {:noreply,
     assign(socket,
       messages: messages,
       agent: new_agent,
       loading: false
     )}
  end

  @impl true
  def handle_info({:agent_error, reason}, socket) do
    error_msg = "Error: #{inspect(reason)}"

    {:noreply,
     assign(socket,
       error: error_msg,
       loading: false
     )}
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
end
