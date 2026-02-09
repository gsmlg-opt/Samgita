defmodule ClaudeAPI.Agent do
  @moduledoc """
  Agent orchestration for RARV cycle (Reason-Act-Reflect-Verify).

  Manages multi-turn conversations with Claude, executing tools and
  coordinating the reasoning loop.
  """

  require Logger

  @type conversation_state :: %{
          messages: list(map()),
          system_prompt: String.t(),
          tools: list(map()),
          model: String.t()
        }

  @doc """
  Initializes a new agent conversation.

  ## Examples

      iex> state = ClaudeAPI.Agent.init("You are a helpful coding assistant")
      iex> ClaudeAPI.Agent.run(state, "List all .ex files")
  """
  @spec init(String.t(), keyword()) :: conversation_state()
  def init(system_prompt, opts \\ []) do
    %{
      messages: [],
      system_prompt: system_prompt,
      tools: opts[:tools] || ClaudeAPI.Tools.all(),
      model: opts[:model] || "claude-sonnet-4-5-20250929"
    }
  end

  @doc """
  Runs a single turn of the agent conversation.

  Sends a user message, processes Claude's response, executes any tools,
  and continues the conversation until Claude returns a final text response.

  ## Examples

      iex> state = ClaudeAPI.Agent.init("You are a file assistant")
      iex> {:ok, response, new_state} = ClaudeAPI.Agent.run(state, "Read config.exs")
      iex> IO.puts(response)
  """
  @spec run(conversation_state(), String.t(), keyword()) ::
          {:ok, String.t(), conversation_state()} | {:error, term()}
  def run(state, user_message, opts \\ []) do
    max_turns = opts[:max_turns] || 10

    messages = state.messages ++ [%{role: "user", content: user_message}]

    execute_loop(%{state | messages: messages}, max_turns, 0)
  end

  # Private functions

  defp execute_loop(_state, max_turns, turn) when turn >= max_turns do
    Logger.warning("Max turns (#{max_turns}) reached")
    {:error, :max_turns_reached}
  end

  defp execute_loop(state, max_turns, turn) do
    Logger.debug("Agent turn #{turn + 1}/#{max_turns}")

    case ClaudeAPI.Client.message(state.messages,
           system: state.system_prompt,
           tools: state.tools,
           model: state.model
         ) do
      {:ok, %{"content" => content, "stop_reason" => stop_reason}} ->
        handle_response(state, content, stop_reason, max_turns, turn)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response(state, content, "end_turn", _max_turns, _turn) do
    # Claude finished responding with text
    text = extract_text(content)
    {:ok, text, state}
  end

  defp handle_response(state, content, "tool_use", max_turns, turn) do
    # Claude wants to use tools
    Logger.debug("Executing tools...")

    # Add assistant message to conversation
    assistant_message = %{role: "assistant", content: content}
    state = %{state | messages: state.messages ++ [assistant_message]}

    # Execute all tool uses
    tool_results =
      content
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn tool_use ->
        Logger.debug("Executing tool: #{tool_use["name"]}")
        {:ok, result} = ClaudeAPI.Client.execute_tool(tool_use)
        result
      end)

    # Add tool results to conversation
    user_message = %{role: "user", content: tool_results}
    state = %{state | messages: state.messages ++ [user_message]}

    # Continue the loop
    execute_loop(state, max_turns, turn + 1)
  end

  defp handle_response(state, content, stop_reason, _max_turns, _turn) do
    # Unexpected stop reason
    Logger.warning("Unexpected stop reason: #{stop_reason}")
    text = extract_text(content)
    {:ok, text, state}
  end

  defp extract_text(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("\n")
  end
end
