# Claude Integration Guide

This document explains the two Claude integration modules in Samgita and when to use each.

## Overview

Samgita provides two ways to interact with Claude:

1. **ClaudeAgent** - CLI wrapper (matches `@anthropic-ai/claude-agent-sdk`)
2. **ClaudeAPI** - Direct HTTP API client

Both provide the same high-level API (`new/2`, `ask/3`, `query/3`) but differ in implementation and use cases.

## Comparison Table

| Feature | ClaudeAgent | ClaudeAPI |
|---------|-------------|-----------|
| **Implementation** | CLI wrapper | Direct HTTP API |
| **Authentication** | CLI managed | Manual config |
| **Tool Availability** | All Claude Code tools | Limited (custom impl) |
| **Streaming** | ✅ (CLI native) | 🚧 (planned) |
| **MCP Servers** | ✅ (CLI native) | ❌ |
| **LSP Integration** | ✅ (CLI native) | ❌ |
| **Dependencies** | Claude Code CLI | None |
| **Use Case** | Prototyping | Production |
| **ADR Alignment** | ADR-004 compliant | Alternative approach |

## ClaudeAgent (CLI Wrapper)

### Architecture

```
ClaudeAgent
    │
    ├─ ClaudeAgent.Query
    │     └─ System.cmd/3
    │           └─ claude-code CLI
```

**Location:** `lib/claude_agent.ex`, `lib/claude_agent/query.ex`

### How It Works

1. Finds Claude CLI executable (`claude` command)
2. Builds command-line arguments
3. Executes CLI via `System.cmd/3`
4. Parses JSON output

### Authentication

Uses Claude CLI's built-in authentication:
- `CLAUDE_CODE_OAUTH_TOKEN` environment variable
- `ANTHROPIC_API_KEY` environment variable
- Or configured via `claude login`

### Prerequisites

Install Claude CLI:
```bash
curl -fsSL https://claude.ai/install.sh | bash
claude login
```

Or set environment variables:
```bash
export CLAUDE_CODE_OAUTH_TOKEN=your-token
# or
export ANTHROPIC_API_KEY=sk-ant-...
```

### Example Usage

```elixir
# Simple query (stateless)
{:ok, response} = ClaudeAgent.query(
  "You are a calculator",
  "What is 15 * 23?"
)

# Conversational agent (stateful)
agent = ClaudeAgent.new("You are a helpful coding assistant")
{:ok, response, agent} = ClaudeAgent.ask(agent, "List all .ex files")
{:ok, response, agent} = ClaudeAgent.ask(agent, "Read the first file")

# With options
agent = ClaudeAgent.new(
  "You are a code reviewer",
  model: "claude-opus-4-5-20251101",
  tools: ["Read", "Grep"],
  max_turns: 5
)
```

### Available Tools

All Claude Code tools are automatically available:
- Read, Write, Edit - File operations
- Bash - Command execution
- Glob, Grep - File search
- Task - Subagent delegation
- AskUserQuestion - User interaction
- WebFetch, WebSearch - Web access
- LSP - Language server protocol
- And more...

### When to Use

✅ **Use ClaudeAgent when:**
- Rapid prototyping and development
- You need all Claude Code tools immediately
- You already have Claude Code CLI installed
- You want CLI-managed authentication
- You need MCP server support
- You need LSP integration

❌ **Don't use ClaudeAgent when:**
- Building production systems (external dependency)
- You need fine-grained control over API calls
- You want to minimize dependencies
- Claude Code CLI is not available

### Error Handling

```elixir
case ClaudeAgent.query("You help", "Hello") do
  {:ok, response} ->
    IO.puts(response)

  {:error, :claude_code_not_found} ->
    IO.puts("Please install Claude CLI: curl -fsSL https://claude.ai/install.sh | bash")

  {:error, {:exit_code, code, output}} ->
    IO.puts("CLI error: #{output}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## ClaudeAPI (HTTP Client)

### Architecture

```
ClaudeAPI
    │
    ├─ ClaudeAPI.Agent (RARV orchestration)
    ├─ ClaudeAPI.Client (HTTP client)
    └─ ClaudeAPI.Tools
          ├─ Read
          ├─ Write
          ├─ Edit
          ├─ Bash
          ├─ Glob
          └─ Grep
```

**Location:** `lib/claude_api.ex`, `lib/claude_api/*`

### How It Works

1. Makes direct HTTPS calls to `api.anthropic.com`
2. Custom tool implementations in Elixir
3. RARV cycle orchestration
4. Streaming support (planned)

### Authentication

Requires manual configuration:
```bash
export CLAUDE_CODE_OAUTH_TOKEN=your-token
# or
export ANTHROPIC_API_KEY=sk-ant-...
```

In `config/runtime.exs`:
```elixir
config :samgita,
  claude_code_oauth_token: System.get_env("CLAUDE_CODE_OAUTH_TOKEN"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
```

### Example Usage

```elixir
# Simple query (stateless)
{:ok, response} = ClaudeAPI.query(
  "You are a calculator",
  "What is 15 * 23?"
)

# Conversational agent (stateful)
agent = ClaudeAPI.new("You are a helpful coding assistant")
{:ok, response, agent} = ClaudeAPI.ask(agent, "List all .ex files")
{:ok, response, agent} = ClaudeAPI.ask(agent, "Read the first file")

# With options
agent = ClaudeAPI.new(
  "You are a code reviewer",
  model: "claude-opus-4-5-20251101"
)
```

### Available Tools

Custom implementations:
- `read_file` - Read file with line numbers
- `write_file` - Create/overwrite file
- `edit_file` - Exact string replacement
- `bash` - Execute shell commands
- `glob` - Find files by pattern
- `grep` - Search content with regex

### When to Use

✅ **Use ClaudeAPI when:**
- Building production systems
- You need fine-grained control over API calls
- You want to minimize external dependencies
- You need custom tool implementations
- Claude Code CLI is not available

❌ **Don't use ClaudeAPI when:**
- You need all Claude Code tools (MCP, LSP, etc.)
- You want CLI-managed authentication
- Rapid prototyping (ClaudeAgent is faster to set up)

### Error Handling

```elixir
case ClaudeAPI.query("You help", "Hello") do
  {:ok, response} ->
    IO.puts(response)

  {:error, {:http_error, status, body}} ->
    IO.puts("HTTP #{status}: #{body}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Integration with Samgita Agent System

Both modules can be used in Samgita's agent workers:

```elixir
defmodule Samgita.Agent.Worker do
  @doc "RARV cycle: Reason state"
  def reason(agent_type, task) do
    # Use ClaudeAgent for development
    claude_agent = ClaudeAgent.new(agent_system_prompt(agent_type))

    # Or use ClaudeAPI for production
    # claude_agent = ClaudeAPI.new(agent_system_prompt(agent_type))

    {:ok, plan, claude_agent} = ClaudeAgent.ask(
      claude_agent,
      "Analyze this task: #{task.description}"
    )

    {:next_state, :act, %{claude_agent: claude_agent, plan: plan}}
  end

  @doc "RARV cycle: Act state"
  def act(state) do
    {:ok, result, claude_agent} = ClaudeAgent.ask(
      state.claude_agent,
      "Execute the plan: #{state.plan}"
    )

    {:next_state, :reflect, %{state | result: result, claude_agent: claude_agent}}
  end
end
```

## Testing

Both modules have example scripts:

```bash
# Test ClaudeAgent (requires Claude Code CLI)
mix run examples/claude_agent_example.exs

# Test ClaudeAPI (requires API key)
mix run examples/claude_api_example.exs
```

## Interactive Playground

The web playground at `/playground` lets you test both modules interactively:

```bash
mix phx.server
open http://localhost:3110/playground
```

Select an agent type, enter a message, and see the response in real-time.

## Recommendations

### For Development
- Use **ClaudeAgent** during development for quick iteration
- All tools available out of the box
- CLI-managed authentication

### For Production
- Use **ClaudeAPI** in production systems
- Fine-grained control and minimal dependencies
- Custom tool implementations

### For ADR-004 Compliance
- **ClaudeAgent** aligns with ADR-004 (Use Claude CLI via Erlang Port)
- This is the recommended approach per project architecture

## References

- `lib/claude_agent/README.md` - ClaudeAgent documentation
- `lib/claude_api/README.md` - ClaudeAPI documentation
- `examples/claude_agent_example.exs` - ClaudeAgent examples
- `examples/claude_api_example.exs` - ClaudeAPI examples
- [ADR-004](../docs/decisions/004-claude-cli-integration.md) - Claude integration decision
- [@anthropic-ai/claude-agent-sdk](https://github.com/anthropics/claude-agent-sdk) - TypeScript SDK reference
