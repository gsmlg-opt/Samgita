# Claude Integration Guide

This document explains how Samgita integrates with LLM providers via the `samgita_provider` abstraction.

Last updated: 2026-04-03

## Overview

Samgita follows a **CLI-first** architecture: it does NOT call LLM APIs directly by default. Instead, it orchestrates CLI tools and API clients as supervised processes via `SamgitaProvider`.

The v1 provider was fire-and-forget: a single `query/2` callback that mapped to `claude --print` with no session persistence. v2 adds **session lifecycle management** alongside the existing CLI-first approach — providers can now maintain multi-turn conversation state across RARV cycles, stream responses in real time, and report health for circuit breaker integration. The original `query/2` is retained as a convenience wrapper.

## Architecture

```
SamgitaProvider (public API)
    │
    ├─ SamgitaProvider.Provider (behaviour — 6 callbacks + legacy query/2)
    │
    ├─ SamgitaProvider.ClaudeCode (Port-based sessions)
    │     └─ Port.open("claude", ["--interactive", ...])
    │
    ├─ SamgitaProvider.ClaudeAPI (HTTP sessions) — NEW
    │     └─ api.anthropic.com/v1/messages (SSE streaming)
    │
    ├─ SamgitaProvider.Synapsis (Synapsis sessions) — NEW
    │     └─ HTTP API + Phoenix Channel
    │
    ├─ SamgitaProvider.Codex (System.cmd wrapper)
    │     └─ System.cmd("codex", ["--full-auto", ...])
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

### One-Shot Query (v1 Convenience)

```elixir
# Simple query — opens session, sends message, closes session
{:ok, response} = SamgitaProvider.query("What is 15 * 23?")

# With options
{:ok, response} = SamgitaProvider.query("Analyze this code",
  system_prompt: "You are a code reviewer",
  model: "sonnet",
  max_turns: 5
)
```

### Session-Based Usage (v2)

```elixir
# Open a session
{:ok, session} = SamgitaProvider.start_session(
  "You are an eng-backend agent.",
  model: "sonnet",
  working_dir: "/tmp/worktree-abc"
)

# Send messages within the session (conversation state preserved)
{:ok, response, session} = SamgitaProvider.send_message(session, "Implement the users API endpoint.")
{:ok, response, session} = SamgitaProvider.send_message(session, "Now add input validation.")

# Stream a response
{:ok, ref, session} = SamgitaProvider.stream_message(session, "Refactor for performance.", self())
# Receive chunks: {:stream_chunk, ^ref, chunk}

# Close when done
:ok = SamgitaProvider.close_session(session)
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `:model` | `"sonnet"` | Model name passed to provider |
| `:max_turns` | `10` | Maximum tool-use turns |
| `:system_prompt` | Generic helper | System prompt for the conversation |
| `:working_dir` | `nil` | Working directory for CLI providers |

## Session Lifecycle

The v2 provider behaviour defines six callbacks that replace the single `query/2` as the primary interface:

### Callbacks

**`start_session(system_prompt, opts)`** — Creates a new provider session. For CLI providers, this starts a long-running Port process. For API providers, this initializes an HTTP client and empty message history. Returns `{:ok, session}` or `{:error, reason}`.

**`send_message(session, message)`** — Sends a user message within an existing session. The provider appends the message to conversation history (or writes to Port stdin) and returns the assistant response. Returns `{:ok, response, updated_session}` or `{:error, reason}`.

**`stream_message(session, message, subscriber_pid)`** — Asynchronous variant of `send_message`. Returns immediately with a stream reference. The subscriber process receives `{:stream_chunk, ref, chunk}` messages as tokens arrive. Returns `{:ok, stream_ref, updated_session}` or `{:error, reason}`. Providers that do not support streaming implement this as a wrapper that sends one final chunk.

**`close_session(session)`** — Terminates the session. Closes the Port, drops the HTTP connection, or sends a DELETE to the remote API. Returns `:ok`. Sessions that crash are not automatically restarted — the caller decides whether to open a new one.

**`capabilities()`** — Returns a map describing the provider's feature set: `supports_streaming`, `supports_tools`, `supports_multi_turn`, `max_context_tokens`, `available_models`. Used by the Worker to adapt its behaviour per provider.

**`health_check()`** — Returns `:ok` or `{:error, reason}`. Consumed by the circuit breaker to route agents away from degraded providers.

### Backward Compatibility

The existing `query/2` is retained as a convenience that opens a session, sends one message, and closes it. All existing callers continue to work unchanged.

### Session State

The session is an opaque struct owned by the provider implementation. For `ClaudeCode`, it wraps a Port reference. For `ClaudeAPI`, it wraps an HTTP client and accumulated message list. For `Synapsis`, it wraps a remote session ID. The Agent Worker holds the session reference in its gen_statem data and passes it through RARV cycles.

## Session Lifecycle in the Worker

The Agent Worker integrates provider sessions into its RARV cycle:

1. **Session open** — When the Worker enters `:reason` for the first time on a task, it calls `start_session/2` with the agent's system prompt and task context.
2. **Session reuse** — The session stays open through `:reason` -> `:act` -> `:reflect` -> `:verify`. Each RARV state sends messages within the same session, preserving conversation history and reducing prompt tokens by 60-80% on subsequent iterations.
3. **Session close** — When the task completes (success or terminal failure), the Worker calls `close_session/1`.
4. **Error recovery** — If the session errors mid-cycle (Port crash, HTTP timeout, Synapsis disconnect), the Worker opens a fresh session and retries from the current RARV state — not from the beginning. This bounds the blast radius of provider failures.

The Worker stores the session reference in its gen_statem data struct as the `:session` field. If `session` is `nil`, the Worker opens one on first use.

## Provider Implementations

### ClaudeCode (Port-based)

Transitions from v1's `System.cmd` (fire-and-forget) to `Port.open` (long-running). The Port runs `claude --interactive` (or equivalent stateful mode). Messages are sent as JSON-delimited lines on stdin, responses read as structured JSON from stdout. Streaming is natural — stdout chunks arrive as Port messages.

```
Port.open({:spawn_executable, claude_path},
  [:binary, :exit_status, :use_stdio,
   args: ["--interactive", "--output-format", "json",
          "--model", model, "--dangerously-skip-permissions"]])
```

### ClaudeAPI (HTTP/SSE)

Direct HTTP client to `api.anthropic.com/v1/messages`. Session state is the accumulated messages list managed in-process. Streaming uses Server-Sent Events. This is the production-grade path for fine-grained control over token budgets, tool definitions, and model selection.

- `start_session` — stores config, initializes empty message history
- `send_message` — POST to Messages API with full conversation history, appends response
- `stream_message` — POST with `stream: true`, forwards SSE events to subscriber
- `close_session` — drops the message history (no remote state to clean up)

### Synapsis (HTTP + Phoenix Channel)

Talks to a running Synapsis instance that provides persistent sessions, tool execution, workspace management, and swarm coordination. Samgita becomes the strategic orchestrator; Synapsis becomes the tactical executor.

- `start_session` — POST `/api/sessions` with agent mode, model, tools, working directory
- `send_message` — POST `/api/sessions/:id/messages`, synchronous response
- `stream_message` — connects to Phoenix Channel `session:{id}`, receives streaming token events
- `close_session` — DELETE `/api/sessions/:id`

Three deployment models: colocated (localhost), single remote, multi-instance (round-robin). Falls back to `ClaudeCode` if all Synapsis instances are unavailable.

### Codex (System.cmd wrapper)

Remains `System.cmd`-based since Codex CLI lacks interactive mode. `start_session` is a no-op that stores config. `send_message` runs `codex --full-auto` with the accumulated context baked into the prompt. No real streaming — `stream_message` wraps `send_message` and emits one final chunk.

### Mock (Test)

The `:mock` atom provider returns `{:ok, "mock response"}` for `query/2` and implements trivial session callbacks for testing. No external dependencies.

## Integration Points

### Agent Workers

`Samgita.Agent.Claude.chat/2` delegates to `SamgitaProvider.query/2` (v1) or session-based calls (v2). The agent worker (`apps/samgita/lib/samgita/agent/worker.ex`) manages the session lifecycle as described above.

### Embeddings

`SamgitaMemory.Workers.Embedding` reads `Application.get_env(:samgita_provider, :anthropic_api_key)` for the Voyage API (not for Claude — this is a shared config location).

## Authentication

Claude Code CLI manages its own authentication:
- `claude login` for interactive setup
- `ANTHROPIC_API_KEY` environment variable

For `ClaudeAPI`, the API key is read from `config :samgita_provider, :anthropic_api_key`.

For `Synapsis`, connection credentials are stored per-project in the `synapsis_endpoints` field.

SamgitaProvider does not manage auth tokens for CLI providers — the CLI handles this.

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

For session-based usage, provider errors during `send_message` or `stream_message` should trigger the Worker's error recovery path (open fresh session, retry from current state).

## Testing

```bash
# Run provider tests
mix test apps/samgita_provider/test

# Run example (requires Claude CLI)
mix run examples/claude_agent_example.exs
```

## Adding New Providers

Implement the `SamgitaProvider.Provider` behaviour with all six session callbacks:

```elixir
defmodule SamgitaProvider.MyProvider do
  @behaviour SamgitaProvider.Provider

  @impl true
  def start_session(system_prompt, opts) do
    # Initialize session state (Port, HTTP client, etc.)
    {:ok, %{system_prompt: system_prompt, history: [], config: opts}}
  end

  @impl true
  def send_message(session, message) do
    # Send message, get response, update session
    response = do_inference(session, message)
    updated = %{session | history: session.history ++ [message, response]}
    {:ok, response, updated}
  end

  @impl true
  def stream_message(session, message, subscriber_pid) do
    # Start async streaming, return ref
    ref = make_ref()
    spawn(fn ->
      response = do_inference(session, message)
      send(subscriber_pid, {:stream_chunk, ref, response})
      send(subscriber_pid, {:stream_done, ref})
    end)
    {:ok, ref, session}
  end

  @impl true
  def close_session(_session), do: :ok

  @impl true
  def capabilities do
    %{
      supports_streaming: true,
      supports_tools: true,
      supports_multi_turn: true,
      max_context_tokens: 200_000,
      available_models: ["sonnet", "opus"]
    }
  end

  @impl true
  def health_check, do: :ok

  # Legacy convenience — default implementation opens session, sends, closes
  @impl true
  def query(prompt, opts) do
    system_prompt = Keyword.get(opts, :system_prompt, "You are a helpful assistant.")
    {:ok, session} = start_session(system_prompt, opts)
    {:ok, response, _session} = send_message(session, prompt)
    close_session(session)
    {:ok, response}
  end
end
```

Then configure:

```elixir
config :samgita_provider, provider: SamgitaProvider.MyProvider
```

The behaviour provides default implementations for `query/2` (delegates to session lifecycle) and `stream_message/3` (wraps `send_message/2`), so minimal providers only need to implement `start_session/2`, `send_message/2`, `close_session/1`, `capabilities/0`, and `health_check/0`.

## References

- `apps/samgita_provider/` — Provider source code
- `docs/design-v2.md` — v2 design document (provider evolution, section 1)
- `docs/CONSTITUTION.md` — CLI-first architecture rationale
- `examples/claude_agent_example.exs` — Usage example
