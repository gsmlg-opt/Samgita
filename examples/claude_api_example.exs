# Example usage of ClaudeAPI
#
# Run with: mix run examples/claude_agent_example.exs
#
# Make sure to set ANTHROPIC_API_KEY environment variable first:
# export ANTHROPIC_API_KEY=sk-ant-...

IO.puts("=== ClaudeAPI Example ===\n")

# Example 1: Simple query (stateless)
IO.puts("Example 1: Simple Calculator")
IO.puts("------------------------------")

case ClaudeAPI.query("You are a calculator", "What is 15 * 23?") do
  {:ok, response} ->
    IO.puts("Response: #{response}\n")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

# Example 2: File operations with conversation
IO.puts("Example 2: File Operations")
IO.puts("---------------------------")

agent = ClaudeAPI.new("""
You are a helpful file assistant. When asked to work with files,
use the available tools to read, write, and edit files.
""")

case ClaudeAPI.ask(agent, "List all .ex files in the lib/ directory") do
  {:ok, response, agent} ->
    IO.puts("Response: #{response}\n")

    # Continue conversation
    case ClaudeAPI.ask(agent, "How many files were found?") do
      {:ok, response, _agent} ->
        IO.puts("Follow-up: #{response}\n")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}\n")
    end

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

# Example 3: Code generation and execution
IO.puts("Example 3: RARV Cycle (Reason-Act-Reflect-Verify)")
IO.puts("--------------------------------------------------")

agent = ClaudeAPI.new("""
You are an Elixir developer. When asked to create code:
1. Reason about the requirements
2. Act by writing the code to a file
3. Reflect on what you created
4. Verify it looks correct

Be concise in your responses.
""")

case ClaudeAPI.ask(
       agent,
       """
       Create a simple Elixir module in /tmp/example.ex that:
       - Has a module called Example
       - Has a function greet(name) that returns "Hello, \#{name}!"
       """
     ) do
  {:ok, response, _agent} ->
    IO.puts("Response: #{response}\n")

    # Verify the file was created
    if File.exists?("/tmp/example.ex") do
      IO.puts("✓ File created successfully")
      {:ok, content} = File.read("/tmp/example.ex")
      IO.puts("\nGenerated code:")
      IO.puts(content)
    end

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}\n")
end

IO.puts("\n=== Examples Complete ===")
