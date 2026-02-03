# Example usage of ClaudeAgent (Claude CLI Wrapper)
#
# Run with: mix run examples/claude_agent_example.exs
#
# Prerequisites:
# 1. Install Claude CLI: curl -fsSL https://claude.ai/install.sh | bash
# 2. Authenticate with: claude login
#    OR set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY environment variable

IO.puts("=== ClaudeAgent Example (CLI Wrapper) ===\n")

# Example 1: Simple query (stateless)
IO.puts("Example 1: Simple Calculator")
IO.puts("------------------------------")

case ClaudeAgent.query("You are a calculator", "What is 15 * 23?") do
  {:ok, response} ->
    IO.puts("Response: #{response}\n")

  {:error, :claude_code_not_found} ->
    IO.puts("Error: Claude CLI not found. Please install it with: curl -fsSL https://claude.ai/install.sh | bash\n")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

# Example 2: File operations with conversation
IO.puts("Example 2: File Operations")
IO.puts("---------------------------")

agent = ClaudeAgent.new("""
You are a helpful file assistant. When asked to work with files,
use the available tools to read, write, and edit files.
""")

case ClaudeAgent.ask(agent, "List all .ex files in the lib/ directory") do
  {:ok, response, agent} ->
    IO.puts("Response: #{response}\n")

    # Continue conversation
    case ClaudeAgent.ask(agent, "How many files were found?") do
      {:ok, response, _agent} ->
        IO.puts("Follow-up: #{response}\n")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}\n")
    end

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

# Example 3: Code analysis
IO.puts("Example 3: Code Analysis")
IO.puts("------------------------")

agent = ClaudeAgent.new("""
You are an Elixir code reviewer. Analyze code for potential issues
and suggest improvements.
""")

case ClaudeAgent.ask(
       agent,
       """
       Read the lib/claude_agent.ex file and give me a brief summary
       of what it does.
       """
     ) do
  {:ok, response, _agent} ->
    IO.puts("Response: #{response}\n")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

IO.puts("\n=== Examples Complete ===")
