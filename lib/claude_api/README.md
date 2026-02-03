# ClaudeAPI for Elixir

An Elixir implementation of Claude Code's capabilities using the Anthropic Messages API.

## Features

- **File Operations**: Read, Write, Edit files with precise control
- **Command Execution**: Run bash commands with timeout support
- **File Search**: Glob patterns and regex search (grep)
- **Multi-turn Conversations**: Maintain context across interactions
- **Tool Use**: Automatic tool execution and result handling
- **RARV Cycle**: Reason-Act-Reflect-Verify orchestration

## Installation

The ClaudeAPI is built into Samgita. No additional installation needed.

## Configuration

Set your authentication token (supports both Claude Code OAuth token and Anthropic API key):

```bash
# Option 1: Claude Code OAuth token (preferred if using Claude Code)
export CLAUDE_CODE_OAUTH_TOKEN=your-oauth-token

# Option 2: Anthropic API key
export ANTHROPIC_API_KEY=sk-ant-api03-...
```

Or in `config/runtime.exs`:

```elixir
config :samgita,
  claude_code_oauth_token: System.get_env("CLAUDE_CODE_OAUTH_TOKEN"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
```

The client will check for `CLAUDE_CODE_OAUTH_TOKEN` first, then fall back to `ANTHROPIC_API_KEY`.

## Quick Start

### Simple Query (Stateless)

```elixir
{:ok, response} = ClaudeAPI.query(
  "You are a calculator",
  "What is 42 * 137?"
)

IO.puts(response)
# => "42 * 137 = 5,754"
```

### Conversational Agent (Stateful)

```elixir
# Create an agent
agent = ClaudeAPI.new("You are a helpful coding assistant")

# Ask a question
{:ok, response, agent} = ClaudeAPI.ask(agent, "List all .ex files")

# Continue the conversation
{:ok, response, agent} = ClaudeAPI.ask(agent, "Read the first file")
```

## Available Tools

### File Operations

```elixir
# read_file - Read file with line numbers
# write_file - Create/overwrite file
# edit_file - Exact string replacement

agent = ClaudeAPI.new("You help manage files")

{:ok, response, agent} = ClaudeAPI.ask(
  agent,
  "Read config/config.exs and show me the first 20 lines"
)
```

### Command Execution

```elixir
# bash - Execute shell commands

agent = ClaudeAPI.new("You help with git operations")

{:ok, response, _agent} = ClaudeAPI.ask(
  agent,
  "Show me the git status and recent commits"
)
```

### File Search

```elixir
# glob - Find files by pattern
# grep - Search content with regex

agent = ClaudeAPI.new("You help find files")

{:ok, response, _agent} = ClaudeAPI.ask(
  agent,
  "Find all files containing 'defmodule' in lib/"
)
```

## Examples

### Example 1: Code Review

```elixir
agent = ClaudeAPI.new("""
You are a code reviewer. Read files, identify issues,
and suggest improvements.
""")

{:ok, review, _agent} = ClaudeAPI.ask(
  agent,
  "Review lib/samgita_web/router.ex and suggest improvements"
)

IO.puts(review)
```

### Example 2: File Refactoring

```elixir
agent = ClaudeAPI.new("""
You are an Elixir refactoring expert.
Read code, make improvements, and write the changes.
""")

{:ok, response, _agent} = ClaudeAPI.ask(
  agent,
  """
  Read lib/claude_agent/client.ex and:
  1. Add @doc comments to private functions
  2. Extract the API URL to a module attribute
  3. Write the changes back
  """
)
```

### Example 3: RARV Cycle

The agent automatically follows the RARV cycle:

1. **Reason**: Analyze the task and plan approach
2. **Act**: Execute tools (read, write, bash, etc.)
3. **Reflect**: Review results and learnings
4. **Verify**: Check success and iterate if needed

```elixir
agent = ClaudeAPI.new("""
You are a test-driven developer. Follow TDD practices:
1. Write tests first
2. Implement code to pass tests
3. Verify tests pass
4. Refactor if needed
""")

{:ok, response, _agent} = ClaudeAPI.ask(
  agent,
  """
  Create a Calculator module with add/2 and multiply/2 functions.
  Write tests in test/calculator_test.exs and run them to verify.
  """
)
```

## Architecture

```
ClaudeAPI
├── ClaudeAPI.Client      # HTTP client using http_fetch
├── ClaudeAPI.Agent       # RARV cycle orchestration
├── ClaudeAPI.Tools       # Tool registry
└── ClaudeAPI.Tools.*     # Tool implementations
    ├── Read                # File reading
    ├── Write               # File writing
    ├── Edit                # String replacement
    ├── Bash                # Command execution
    ├── Glob                # File pattern matching
    └── Grep                # Content search
```

## Model Selection

```elixir
# Use Opus for complex reasoning
agent = ClaudeAPI.new(
  "You are an architect",
  model: "claude-opus-4-5-20251101"
)

# Use Sonnet for general development (default)
agent = ClaudeAPI.new("You are a developer")

# Use Haiku for simple tasks (coming soon)
agent = ClaudeAPI.new(
  "You run tests",
  model: "claude-haiku-4-0-20250710"
)
```

## Integration with Samgita

The ClaudeAPI integrates with Samgita's agent system:

```elixir
# In your agent worker (gen_statem)
defmodule Samgita.Agent.Worker do
  # RARV cycle states: :reason -> :act -> :reflect -> :verify

  def reason(agent_type, task) do
    claude_agent = ClaudeAPI.new(agent_system_prompt(agent_type))

    {:ok, plan, claude_agent} = ClaudeAPI.ask(
      claude_agent,
      "Analyze this task: #{task.description}"
    )

    # Store claude_agent in state for next step
    {:next_state, :act, %{claude_agent: claude_agent, plan: plan}}
  end

  def act(state) do
    {:ok, result, claude_agent} = ClaudeAPI.ask(
      state.claude_agent,
      "Execute the plan: #{state.plan}"
    )

    {:next_state, :reflect, %{state | result: result, claude_agent: claude_agent}}
  end

  # ... reflect and verify states
end
```

## API Reference

See module documentation:

```elixir
h ClaudeAPI
h ClaudeAPI.Client
h ClaudeAPI.Agent
h ClaudeAPI.Tools
```

## Testing

```bash
# Set API key
export ANTHROPIC_API_KEY=sk-ant-...

# Run examples
mix run examples/claude_agent_example.exs

# Interactive testing
iex -S mix
iex> agent = ClaudeAPI.new("You are helpful")
iex> ClaudeAPI.ask(agent, "Hello!")
```

## Comparison to Claude Code CLI

| Feature | Claude Code CLI | ClaudeAPI |
|---------|-----------------|-------------|
| File Read/Write/Edit | ✅ | ✅ |
| Bash execution | ✅ | ✅ |
| Glob/Grep | ✅ | ✅ |
| Streaming | ✅ | 🚧 (planned) |
| LSP integration | ✅ | 🚧 (planned) |
| MCP servers | ✅ | 🚧 (planned) |
| Git operations | ✅ | ✅ (via bash) |
| Task management | ✅ | 🚧 (planned) |
| Multi-turn | ✅ | ✅ |
| BEAM native | ❌ | ✅ |
| Distributed | ❌ | ✅ (with Samgita) |

## Roadmap

- [ ] Streaming support with SSE
- [ ] LSP tool integration
- [ ] MCP server support
- [ ] WebSearch and WebFetch tools
- [ ] Task management integration
- [ ] Telemetry and metrics
- [ ] Rate limiting and retries
- [ ] Caching layer

## License

Part of the Samgita project.
