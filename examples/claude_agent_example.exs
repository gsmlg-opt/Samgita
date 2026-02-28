# Example usage of SamgitaProvider
#
# Run with: mix run examples/claude_agent_example.exs
#
# Prerequisites:
# 1. Install Claude CLI: curl -fsSL https://claude.ai/install.sh | bash
# 2. Authenticate with: claude login

IO.puts("=== SamgitaProvider Example ===\n")

# Example 1: Simple query (stateless)
IO.puts("Example 1: Simple Calculator")
IO.puts("------------------------------")

case SamgitaProvider.query("What is 15 * 23?", system_prompt: "You are a calculator") do
  {:ok, response} ->
    IO.puts("Response: #{response}\n")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

# Example 2: File listing
IO.puts("Example 2: File Operations")
IO.puts("---------------------------")

case SamgitaProvider.query("List all .ex files in the lib/ directory",
       system_prompt: """
       You are a helpful file assistant. When asked to work with files,
       use the available tools to read, write, and edit files.
       """,
       max_turns: 5
     ) do
  {:ok, response} ->
    IO.puts("Response: #{response}\n")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

# Example 3: Code analysis
IO.puts("Example 3: Code Analysis")
IO.puts("------------------------")

case SamgitaProvider.query(
       "Read the apps/samgita_provider/lib/samgita_provider.ex file and give a brief summary.",
       system_prompt: """
       You are an Elixir code reviewer. Analyze code for potential issues
       and suggest improvements.
       """,
       max_turns: 5
     ) do
  {:ok, response} ->
    IO.puts("Response: #{response}\n")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

IO.puts("\n=== Examples Complete ===")
