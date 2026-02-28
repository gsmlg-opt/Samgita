# Claude Integration Guide

This document explains how Samgita integrates with Claude via the `samgita_provider` abstraction.

## Overview

Samgita follows a **CLI-first** architecture: it does NOT call LLM APIs directly. Instead, it orchestrates CLI tools as supervised processes via `SamgitaProvider`.

The provider abstraction invokes the `claude` CLI directly via `System.cmd/3` behind a unified `query/2` interface.

## Architecture

```
SamgitaProvider (public API)
    │
    ├─ SamgitaProvider.Provider (behaviour)
    │
    ├─ SamgitaProvider.ClaudeCode (implementation)
    │     └─ System.cmd("claude", [...])
    │           └─ --print --output-format json --dangerously-skip-permissions
    │
    └─ :mock (test atom — returns "mock response")
```

**Location:** `apps/samgita_provider/`

## Configuration

```elixir
# config/config.exs — default provider
config :samgita_provider, provider: SamgitaProvider.ClaudeCode

# config/test.exs — mock for tests
config :samgita_provider, provider: :mock

# config/runtime.exs — API key for Voyage embeddings (used by samgita_memory)
config :samgita_provider,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
```

## Usage

```elixir
# Simple query
{:ok, response} = SamgitaProvider.query("What is 15 * 23?")

# With options
{:ok, response} = SamgitaProvider.query("Analyze this code",
  system_prompt: "You are a code reviewer",
  model: "sonnet",
  max_turns: 5
)
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `:model` | `"sonnet"` | Model name passed to Claude CLI |
| `:max_turns` | `10` | Maximum tool-use turns |
| `:system_prompt` | Generic helper | System prompt for the conversation |

## How It Works

1. `SamgitaProvider.query/2` checks the configured provider
2. For `:mock`, returns `{:ok, "mock response"}` immediately
3. For `SamgitaProvider.ClaudeCode`:
   - Builds CLI args: `--print --output-format json --model <model> --system-prompt <prompt> --dangerously-skip-permissions --no-session-persistence`
   - Invokes `claude` via `System.cmd/3` with the prompt as the positional argument
   - Parses the JSON result object and extracts the `"result"` field
4. The CLI handles tool execution, context management, and conversation state
5. The `result` string is returned as `{:ok, result}`

## Integration Points

### Agent Workers

`Samgita.Agent.Claude.chat/2` delegates to `SamgitaProvider.query/2`. The agent worker (`apps/samgita/lib/samgita/agent/worker.ex`) calls `Claude.chat/2` in its RARV cycle.

### Playground

`SamgitaWeb.PlaygroundLive` calls `SamgitaProvider.query/2` directly from async tasks.

### Embeddings

`SamgitaMemory.Workers.Embedding` reads `Application.get_env(:samgita_provider, :anthropic_api_key)` for the Voyage API (not for Claude — this is a shared config location).

## Authentication

Claude Code CLI manages its own authentication:
- `claude login` for interactive setup
- `ANTHROPIC_API_KEY` environment variable

SamgitaProvider does not manage auth tokens — the CLI handles this.

## Error Handling

```elixir
case SamgitaProvider.query("Hello") do
  {:ok, response} ->
    IO.puts(response)

  {:error, :rate_limit} ->
    # Back off and retry

  {:error, :overloaded} ->
    # Back off and retry

  {:error, message} when is_binary(message) ->
    IO.puts("Error: #{message}")
end
```

## Testing

```bash
# Run provider tests
mix test apps/samgita_provider/test

# Run example (requires Claude CLI)
mix run examples/claude_agent_example.exs
```

## Adding New Providers

Implement the `SamgitaProvider.Provider` behaviour:

```elixir
defmodule SamgitaProvider.MyProvider do
  @behaviour SamgitaProvider.Provider

  @impl true
  def query(prompt, opts) do
    # Your implementation
    {:ok, "response"}
  end
end
```

Then configure:

```elixir
config :samgita_provider, provider: SamgitaProvider.MyProvider
```

## References

- `apps/samgita_provider/` — Provider source code
- `docs/CONSTITUTION.md` — CLI-first architecture rationale
- `examples/claude_agent_example.exs` — Usage example
