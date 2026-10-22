# SamgitaProtocol

Transport-independent Agent protocol, native schema **1.0**, package **0.1.0**, Elixir 1.18+. No runtime dependencies, application callback, Repo, platform schemas, orchestration, Phoenix, UI, Backplane or application configuration. Loading the library starts no listener or Agent. Consumers can communicate directly with their chosen host while Samgita is absent.

The three standalone Mix projects follow this repository's `apps/` layout but deliberately do not inherit umbrella configuration, dependencies, lockfiles or build paths. They are not in the platform's explicit application list:

| Package | Responsibility |
| --- | --- |
| `samgita_protocol` | Native schema/codec, capabilities, pure bidirectional connection state, handler interface and bounded replay log |
| [samgita_protocol_websocket](../samgita_protocol_websocket/README.md) | Optional authenticated RFC 6455 text transport at `/app-server`, explicit listener/client, fake Agent |
| [samgita_protocol_codex](../samgita_protocol_codex/README.md) | Optional, limited translation to pinned official Codex 0.163.0 schemas |

Run checks **from this package directory**, with Elixir on PATH (or prefix each command with `devenv shell --no-tui --no-reload --` in this repository):

```sh
mix test
mix compile --warnings-as-errors
mix format --check-formatted
python3 scripts/verify_standalone.py
```

The optional Python stdlib script copies this library and its [standalone consumer](examples/consumer/README.md) into a temporary directory outside the repository and builds/tests both with no umbrella present. Package tests themselves need only Elixir, no Python, database, LLM or running Samgita service.

## Wire contract

[protocol.schema.json](priv/schemas/1.0/protocol.schema.json) is a generated JSON Schema 2020-12 artifact; executable definitions live in `Schema`. Fixtures include accepted event/session traffic and rejected versions/methods/fields. A schema test prevents artifact drift. To regenerate after a deliberate schema change:

```sh
mix compile
mix run --no-compile -e 'IO.puts(JSON.encode!(SamgitaProtocol.Schema.Document.build()))' > priv/schemas/1.0/protocol.schema.json
```

Runtime validation additionally checks UTF-8 byte limits, JSON nesting depth (32), contextual result identity, negotiated support, replay order and connection state. A response's method-specific result schema needs its pending request; the envelope alone cannot establish that context. Unknown fields and operations fail explicitly. Native schemas and Codex reference schemas are distinct.

All keys are strings. Native requests carry `schema_version`, `type: "request"`, connection-scoped `id`, `correlation_id`, `method`, `params` and, for mutations, `command_id`. Responses echo the exact identity/context and contain exactly one object `result` or typed `error`. Notifications have no request ID. Optional `project_ref`/`task_ref` are opaque stable references; a Task reference requires a Project reference. No reference is a database dependency, credential, authorization grant, session ID or implicit Task transition.

| Identity | Meaning and retry rule |
| --- | --- |
| `schema_version` | Native wire version `1.0`; package version is independent |
| `event_id` | Stable original event identity, reused for status/deduplication across deliveries |
| `delivery_attempt_id` | Fresh identity for one delivery attempt, not a new logical event |
| `created_at` | Original UTC ISO-8601 timestamp, unchanged across retries |
| `command_id` | Stable host reconciliation/idempotency identity for one logical mutation; distinct delivery attempts may have separate command IDs |
| `id` | Connection-local request/response pairing, never a durable command receipt |
| `correlation_id` / `causation_id` | Flow identity and optional originating cause; original event metadata remains unchanged across delivery attempts |
| `stream_id` / `cursor` | Opaque stream identity and positive sequence number, paired on replayable notifications |

`Event.retry(event, new_attempt_id)` preserves **every** field except the attempt ID. The host must reject changed original content under an existing event ID. The outer delivery request can have its own correlation; original causal metadata stays in the event.

## Capabilities and acknowledgements

`connection/initialize` offers `versions`, `capabilities`, optional `required_capabilities`; its response selects `version`, supported intersection and `connection_id`. Native initialization completes on that successful response. Required omissions fail. Unknown optional remote offers may be ignored; a local handler may advertise only defined groups. Codex's separate `initialized` notification is specific to its adapter.

| Group | Operations |
| --- | --- |
| `project_events.v1` | `project/event.receive`, `.status`, `.report`: receive an event, query processing, record a decision/result |
| `sessions.v1` | `thread/start`, `/read`, `/resume`; `turn/start`, `/steer`, `/interrupt`; lifecycle notifications |
| `streaming.v1` | Item start/delta/completion notifications and explicit `stream/resume` |
| `approvals.v1` | Bidirectional `approval/request` and a bound approve/deny response |
| `cancellation.v1` | `request/cancel`, expressing cancellation intent for a request on that connection |

See the [phase contract](../../docs/redesign/protocol-phase-2.md) for exact fields/results. An Agent implements only its advertised groups; `Handler.methods/0` must match all request methods of those groups. Unsupported operations never trigger a fallback Agent. Project-event processing does not imply an execution session. No fixed development lifecycle or reasoning loop exists in this library.

These acknowledgements have separate meanings:

| Signal | What it proves |
| --- | --- |
| Successful socket write, WebSocket receipt/pong | Transport progress only; no durable or business acceptance |
| Event result `acceptance: received` | Host received the event, possibly only in memory |
| Event result `acceptance: durable` | Host asserts its inbox has committed; only a durable host may emit this |
| `processing_status: completed/failed/rejected` | Processing outcome; querying status avoids equating receipt with completion |
| Report result `report_status: recorded` | Decision/result was recorded by that host |
| `management_acceptance: accepted/rejected` | Separate authoritative management decision; `not_requested` means no Project/Task transition was requested |

The protocol validates shape and correlation, not the truth of durability assertions. Fake/consumer hosts return `received` and `not_requested`. Platform transactions, command receipts, task versions, claims, leases and execution fences belong to later integrating contexts.

## Client and server interfaces

All core APIs are pure state transformations. Callers send returned maps through a transport and handle effects explicitly:

```elixir
alias SamgitaProtocol.Client
{:ok, client} = Client.new(capabilities: ["project_events.v1"])
{:ok, request, client} = Client.request(client, "connection/initialize", %{
  "versions" => ["1.0"], "capabilities" => ["project_events.v1"]
})
# send request; receive response from authenticated host
{:ok, effects, client} = Client.receive(client, response)
```

`Codec.encode/2` / `decode/2` return `{:ok, value} | {:error, %Error{}}`. `Client.request/4`, `reply/3` return `{:ok, message, client} | {:error, error, client}`. `Client.receive/2` returns `{:ok, effects, client} | {:error, error, client}`. Effects are `{:response, id, result}`, `{:error, id, error}`, `{:request, original_request}` or `{:notification, message}`. Incoming requests remain pending until `Client.reply/3` receives that exact request and a valid bound result. Duplicate responses are suppressed in a bounded cache; conflicting content fails.

Implement `SamgitaProtocol.Handler` and explicitly create `Server.new(handler, host_state, opts)`. Authenticate before `Server.receive/2`; it returns response maps and host state. `handle_request/4` returns a result or typed error with updated state; optional notification/response callbacks handle the other direction. `Server.request/4` requires a response callback and maintains correlation for server-initiated approvals. Malformed input cannot call handlers; callback exceptions return safe errors. A callback error cannot undo a host effect already performed.

The host owns persistence, authorization, command idempotency, session lifecycle legality and tools. Repeating a completed incoming mutation may call the host again: its atomic command receipt/inbox must deduplicate it. Neither request caches nor replay hashes offer durable exactly-once effects. Runtime hosts must check approval identity, connection, deadline, action and current policy before acting; an unexpired schema timestamp or Project permission alone never grants execution. The library never auto-approves.

## Disconnect, replay and bounds

Once a request is handed out for sending, disconnect or timeout makes a mutation's result **ambiguous**. `Client.disconnect/1` / `expire/2` emit `ambiguous_disconnect` and retain the original command in `uncertain`; reads yield disconnected/timeout. `reconnect/1` requires initialization again and sends nothing. Default generated request IDs include a connection generation. An authenticated host query or audited reconciliation must establish an outcome before `resolve_uncertain/3` clears that hold. Never blindly repeat a mutation, including after process restart; the caller must durably journal identities and reconcile them. The in-memory uncertainty map cannot replace that journal.

`request/cancel` means requested/already_finished. It does not resolve the target request, roll back effects or prove tools stopped. `turn/interrupt` likewise reports requested/interrupted/already_finished; separate lifecycle evidence establishes completion. Cancelling a local wait never authorizes repeating work.

Replayable notifications carry both `stream_id` and contiguous `cursor`; unsequenced notifications are ephemeral and cannot be resumed. `Replay` is a bounded **in-memory** host log; it assigns sequence numbers only to unsequenced input and returns `replay_gap` outside retention. `Replay.since/2` returns at most 128 events per page; continue from the last returned cursor. A stream resume result returns ordered events from requested cursor + 1 through result `cursor` (or the requested cursor if empty). Foreign streams and skipped/reordered events fail.

After receiving a correlated `stream/resume` result, explicitly call `Client.receive_replay(client, result)` to ingest those events through the same bounded buffer and duplicate/gap checks. Socket receipt does not advance a checkpoint. `Client.drain/2` delivers buffered notifications; after processing them, `ack_cursor/3` advances the processed position. Persist `Client.checkpoints/1` and restore using `Client.new(checkpoints: map)` after process restart. Resume from that processed checkpoint. Checkpoints are scoped to the authenticated host and stream; never restore another host's map. The server performs cursor checks before its notification callback and marks processed only after callback success; durable checkpoint storage remains host-owned.

Defaults bound outstanding requests/uncertain commands (64), incoming requests (64), notification buffer (128), completed response cache (128), stream count (64), per-stream duplicate hashes (128), message bytes (1 MiB) and request waits (30 s). Buffer overflow fails explicitly before advancing position. Consumers must backpressure or disconnect and reconcile; they must not discard state events while staying connected. Older duplicate responses outside cache become unknown; already-processed stream cursors are ignored, while retained unprocessed hashes detect conflicting replay. Core timers advance only when the caller invokes `expire/2`.

All transport configuration is instance-local. The optional WebSocket package authenticates before upgrade and on reconnect, uses WSS outside loopback by default, rejects credential-bearing URLs/redirects, and redacts process status. Existing service/infrastructure access boundaries remain host-owned. No browser account system, platform endpoint, Sigma/Synapsis process, production migration or external repository change is included.
