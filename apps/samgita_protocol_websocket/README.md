# Optional native WebSocket transport

This standalone Mix package carries `samgita_protocol` JSON text frames over RFC
6455 WebSockets at `/app-server`. It uses Bandit/WebSockAdapter for the server
and MintWebSocket for the client. It has no Phoenix, Repo, provider or Backplane
dependency and starts no listener or Agent automatically. Requiring this package
does not start another Sigma/Synapsis service.

From this directory, using the repository's Elixir environment:

```sh
devenv shell --no-tui -- mix deps.get
devenv shell --no-tui -- mix test
devenv shell --no-tui -- mix compile --warnings-as-errors
devenv shell --no-tui -- mix format --check-formatted
devenv shell --no-tui -- iex -S mix
```

These projects own their dependency/build directories and lockfiles; do not run
their checks through the platform umbrella.

## Explicit fake Agent journey

In IEx, supply a local test credential explicitly. The fake's state is in memory
and disappears when it stops. It simulates no LLM and executes no tools.

```elixir
alias SamgitaProtocolWebSocket.{Client, FakeAgent}

token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
{:ok, fake} = FakeAgent.start_link(token: token, port: 0, owner: self())
groups = SamgitaProtocol.Capabilities.all()
{:ok, client} = Client.connect(FakeAgent.url(fake), token: token, capabilities: groups)

{:ok, _} = Client.request(client, "connection/initialize", %{
  "versions" => ["1.0"], "capabilities" => groups
})

event = %{
  "schema_version" => "1.0", "event_id" => "demo-event",
  "delivery_attempt_id" => "delivery-1", "created_at" => "2026-10-22T00:00:00Z",
  "correlation_id" => "demo-correlation", "type" => "project.updated",
  "payload" => %{"summary" => "Example"}
}
{:ok, %{"acceptance" => "received"}} = Client.request(client,
  "project/event.receive", %{"event" => event}, command_id: "receive-demo")
{:ok, %{"thread_id" => thread}} = Client.request(client, "thread/start", %{}, command_id: "thread-demo")
{:ok, %{"turn_id" => turn}} = Client.request(client, "turn/start", %{
  "thread_id" => thread, "input" => [%{"type" => "text", "text" => "Example"}]
}, command_id: "turn-demo")
:ok = FakeAgent.emit_delta(fake, thread, turn, "Simulated output")
```

The owner receives `{:samgita_protocol, client_pid, {:notification, message}}`
and `{:samgita_protocol, client_pid, {:request, request}}`. After processing a
stream notification, call `Client.ack_cursor(client, stream_id, cursor)`;
socket receipt alone is not an acknowledgement. `stream/resume` returns retained
notifications, or `replay_gap` if the host has evicted them.
Successful `stream/resume` results are validated and their new events are also
forwarded through the owner mailbox before the request returns. Process and
acknowledge them through the same path as live notifications. Duplicate cursors
are not forwarded again.

To test server-initiated approvals, call
`FakeAgent.request_approval(fake, thread, turn, "approval-1")`, receive the exact
`approval/request` through the owner mailbox, then explicitly decide:

```elixir
receive do
  {:samgita_protocol, ^client, {:request, %{"method" => "approval/request"} = request}} ->
    :ok = Client.reply(client, request, {:ok, %{
      "approval_id" => request["params"]["approval_id"],
      "decision" => "deny", "scope" => "once"
    }})
end
```

For the opposite direction the fake owner receives
`{:fake_agent_approval_requested, approval_id, socket_pid}` and must explicitly
send `{:fake_approval, approval_id, "approve" | "deny"}` to that socket. The
fake's handler waits at most five seconds, then returns a timeout. Nothing
automatically approves a request.

## Reconnect and ownership

`Client.reconnect/1` closes the old connection and authenticates again. Send
`connection/initialize` again, reconcile outstanding command/event IDs with the
host, and explicitly resume the thread before requesting more fake output.
There is no automatic replay or retry. A disconnected/timed-out sent mutation
returns `ambiguous_disconnect`: its effect may already have occurred. Read
requests return `disconnected` or `timeout`. Reusing a request ID does not create
durable command idempotency.

After an authenticated host query or an audited operator reconciliation resolves
an uncertain command, explicitly call
`Client.resolve_uncertain(client, command_id, %{"status" => "completed" | "not_accepted" | "reconciled", "evidence_ref" => reference})`.
This returns the original request and clears its uncertainty slot; it neither
verifies the evidence nor retries work. Only the host/operator can establish the
outcome. Persist `Client.checkpoints(client)` after processed acknowledgements;
restore them with `Client.connect(url, checkpoints: saved_map, ...)` after a
process restart. `Client.replay_cursor(client, stream_id)` returns the processed
cursor to request during explicit replay.

The fake keeps event deduplication, event status, threads, approvals and replay
records across socket reconnects while the fake process is alive. Retrying an
event changes only `delivery_attempt_id`; conflicting payloads for the same
`event_id` fail. Event responses say `acceptance: "received"`, and reports say
`management_acceptance: "not_requested"`. They prove neither durable acceptance
nor authoritative platform transitions.

## Hosting and bounds

`Server.start_link/1` requires explicit `port`, `handler` and
`authenticate: fn bearer -> {:ok, principal} | :error end`. It binds loopback by
default. `SamgitaProtocolWebSocket.Plug` can be mounted in an existing endpoint;
it accepts only `GET /app-server` without a query string. Authentication runs
before upgrade and dispatch, including after reconnect. The host handler owns
authorization, persistence, durable idempotency and lifecycle; the protocol
cannot confer any of these.

Use WSS for remote connections and terminate server TLS at an existing endpoint
or infrastructure proxy. The client rejects plaintext non-loopback targets
unless `allow_insecure: true` is explicitly set. Userinfo, query strings and
fragments are rejected; redirects are never followed. Tokens travel only in the
Authorization header, and neither the transport nor fake logs them. Process
status reports redact connection state. Hosts must likewise avoid logging their
authentication input or handler state.

Hosts that enforce destination policy can pass an already approved IP tuple as
`connect_address`. The client dials that address while retaining the URL hostname
for Host/SNI and TLS verification; it does not resolve or approve an allowlist.
Failed HTTP upgrades expose only status and a bounded `retry_after`
detail, without response bodies or authentication headers. A 429 upgrade remains
an error, never delivery acceptance.

Core defaults bound pending requests (64), notification buffers (128), completed
responses (128), streams (64), JSON messages (1 MiB) and request timers (30 s).
Client connection establishment is bounded by `connect_timeout_ms` (5 s).
The adapter drains core notifications into the explicit owner mailbox and
disconnects when that mailbox reaches `max_buffer`; the owner should be a
dedicated consumer. It never silently drops a notification while staying
connected. When forwarding fails, the unforwarded notification does not advance
the core cursor; reconnect and replay from the processed checkpoint can recover
it. An entire replay batch must fit the core and owner buffers or the connection
closes with its prior cursors intact. Mint's unfinished receive buffer is capped
conservatively at the
frame limit plus RFC frame overhead; a larger aggregate socket read is closed
even if it contains multiple individually valid messages. Use replay/status
reconciliation after any disconnect.

Server frame and fragmented-message limits default to 1 MiB. The fake caps each
record collection at `max_records` (128), keeps only `replay_limit` (4) messages
per known stream, and fails new records with `buffer_full`; it never evicts an
event and silently forgets deduplication. Completed fake records are retained
until the explicitly started fake stops. Each connection has independent
negotiation/correlation state; host replay state belongs to the fake process.

Stop explicit instances when finished:

```elixir
Client.close(client)
GenServer.stop(fake)
```

The focused suite exercises real loopback upgrades, authentication, text/binary
and malformed/oversized input, unsupported methods, bidirectional approvals,
event deduplication, lifecycle errors, cancellation, reconnect, replay gaps,
pending limits, mailbox overload, bounded fake records, and ambiguous mutation
disconnect/timeouts. It does not establish real Sigma, Synapsis or Codex
compatibility, TLS deployment behavior, or durable platform management.
