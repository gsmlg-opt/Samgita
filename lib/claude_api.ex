defmodule ClaudeAPI do
  @moduledoc """
  Claude Agent SDK for Elixir.

  Provides Claude Code-like capabilities including:
  - File operations (Read, Write, Edit)
  - Command execution (Bash)
  - File search (Glob, Grep)
  - Multi-turn conversations with tool use
  - RARV cycle orchestration

  ## Quick Start

      # Initialize an agent
      agent = ClaudeAPI.new("You are a helpful coding assistant")

      # Run a task
      {:ok, response} = ClaudeAPI.ask(agent, "List all .ex files in lib/")

      # Continue the conversation
      {:ok, response} = ClaudeAPI.ask(agent, "Now read the first file")

  ## Configuration

  Set your authentication (supports both Claude Code OAuth and Anthropic API key):

      # In config/runtime.exs
      config :samgita,
        claude_code_oauth_token: System.get_env("CLAUDE_CODE_OAUTH_TOKEN"),
        anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

      # Or export in shell
      export CLAUDE_CODE_OAUTH_TOKEN=your-token
      # or
      export ANTHROPIC_API_KEY=sk-ant-...

  ## Available Tools

  - `read_file` - Read file contents with line numbers
  - `write_file` - Write content to a file
  - `edit_file` - Perform exact string replacement
  - `bash` - Execute shell commands
  - `glob` - Find files matching patterns
  - `grep` - Search for patterns in files

  ## Example: File Operations

      agent = ClaudeAPI.new("You help manage files")

      {:ok, response} = ClaudeAPI.ask(agent, \"\"\"
      Read the mix.exs file and tell me what dependencies are listed.
      \"\"\")

  ## Example: Code Generation

      agent = ClaudeAPI.new(\"\"\"
      You are an Elixir code generator. Write clean, idiomatic code.
      \"\"\")

      {:ok, response} = ClaudeAPI.ask(agent, \"\"\"
      Create a GenServer module called MyApp.Worker that maintains a counter.
      Write it to lib/my_app/worker.ex
      \"\"\")

  ## Example: RARV Cycle

      # The agent automatically follows the RARV cycle:
      # 1. Reason - Analyze the task
      # 2. Act - Execute tools
      # 3. Reflect - Review results
      # 4. Verify - Check success

      agent = ClaudeAPI.new("You are a test-driven developer")

      {:ok, response} = ClaudeAPI.ask(agent, \"\"\"
      Create a function to calculate fibonacci numbers,
      write tests for it, and verify they pass.
      \"\"\")
  """

  alias ClaudeAPI.Agent

  @type t :: Agent.conversation_state()

  @doc """
  Create a new agent with a system prompt.

  ## Options

  - `:model` - Claude model to use (default: claude-sonnet-4-5-20250929)
  - `:tools` - List of tools to make available (default: all)

  ## Examples

      iex> agent = ClaudeAPI.new("You are a helpful assistant")

      iex> agent = ClaudeAPI.new(
      ...>   "You are a code reviewer",
      ...>   model: "claude-opus-4-5-20251101"
      ...> )
  """
  @spec new(String.t(), keyword()) :: t()
  def new(system_prompt, opts \\ []) do
    Agent.init(system_prompt, opts)
  end

  @doc """
  Ask the agent a question or give it a task.

  Returns the agent's text response and updated state.

  ## Options

  - `:max_turns` - Maximum conversation turns (default: 10)

  ## Examples

      iex> agent = ClaudeAPI.new("You help with files")
      iex> {:ok, response, agent} = ClaudeAPI.ask(agent, "List .ex files")
      iex> IO.puts(response)

      iex> agent = ClaudeAPI.new("You are a calculator")
      iex> {:ok, "42", _agent} = ClaudeAPI.ask(agent, "What is 6 * 7?")
  """
  @spec ask(t(), String.t(), keyword()) :: {:ok, String.t(), t()} | {:error, term()}
  def ask(agent, message, opts \\ []) do
    Agent.run(agent, message, opts)
  end

  @doc """
  Execute a single message and get a response (stateless).

  This is useful for one-off requests without maintaining conversation history.

  ## Examples

      iex> {:ok, response} = ClaudeAPI.query(
      ...>   "You are a calculator",
      ...>   "What is 2 + 2?"
      ...> )
      iex> IO.puts(response)
      "4"
  """
  @spec query(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def query(system_prompt, message, opts \\ []) do
    agent = new(system_prompt, opts)

    case ask(agent, message, opts) do
      {:ok, response, _agent} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get all available tools.
  """
  @spec tools() :: list(map())
  def tools, do: ClaudeAPI.Tools.all()
end
