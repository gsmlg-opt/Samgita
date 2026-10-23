# Samgita Codex driver

An independently reusable supervised Elixir client for the immutable official
Codex app-server **0.163.0**, source
`83086188ae0614bd882818ff1aa23f3194962012`. Native schemas, binary provenance and
the full compatibility ledger live in `docs/codex-app-server/`. Schema coverage
and the journeys below do not establish complete behavioral compatibility.

The package depends on the reusable `samgita_protocol_codex` schema/wire package
and Mint WebSocket transport. It has no Repo, project schema, orchestration,
Phoenix or application configuration inheritance. Loading it starts no listener,
provider or Codex process; the consumer explicitly starts a Session.

```elixir
alias SamgitaCodexDriver.Session
alias SamgitaCodexDriver.Transport.Stdio

{:ok, session} = Session.start_link(
  transport: {Stdio, [
    executable: "/absolute/path/to/pinned/codex",
    args: ["app-server", "--listen", "stdio://"],
    cwd: "/isolated/workspace",
    env: %{"HOME" => "/isolated/home", "CODEX_HOME" => "/isolated/codex"}
  ]}
)
{:ok, initialize_wire} = Session.initialize(session,
  %{"name" => "my_consumer", "version" => "0.1.0"},
  %{"experimentalApi" => false}
)
{:ok, full_wire} = Session.request(session, "thread/list", %{"limit" => 10}, effect: :read)
{:ok, events} = Session.drain(session)
```

Keep native results and errors intact. An `Error` preserves upstream error wire
for its authorized caller, while Inspect and Exception output redact it. Never
log native payloads blindly: tool input, account/authentication, configuration and
error data can contain secrets. Do not create atoms from wire values.

## Lifecycle and interactions

Successful initialization sends the upstream `initialized` notification before
making the Session ready. Requests correlate typed IDs in their connection
generation; native server requests have a separate direction and opaque handles.
Notifications/items retain their complete payloads in a bounded ordered pull
queue. The owner receives one `:events_available` wakeup and drains the queue.

`Session.status/1` exposes a non-secret process-lifetime `instance_id` and a
connection `generation`. For fenced callers, `request_native/3` and `respond/4`
accept `:expected_instance_id`, `:expected_generation` and
`:dispatch_deadline_ms` (absolute Unix milliseconds). The serialized Session
checks them immediately before sending, so a queued request cannot cross a
reconnect or begin dispatch after its deadline. A prior status read alone cannot
provide this guarantee. A send already begun can still have an uncertain outcome.

For a drained `%{kind: :server_request, wire: wire, handle: handle}`, inspect the
exact action, check your current authorization, and explicitly call
`Session.respond(session, handle, {:ok, native_result})` or return a native error.
There is no automatic approval. Changed, resolved, expired and previous-generation
handles fail closed. Dynamic tools and user input use this same native interaction
path. A successful local send is not proof of upstream consumption: inspect
interaction outcomes and later upstream resolution/item events. Timeout errors do
not authorize a new approval or prove a tool stopped.

`Session.reconnect/1` closes this connection and opens a new one. It never resends
requests. Initialize again and explicitly read/resume an existing thread.
Upstream may replay its pending ordinary interactions during thread resume; this
does not replay missing notification history. The driver exposes a gap and local
sequence, which is not an upstream replay cursor. Timed-out/disconnected mutations
remain uncertain until caller-owned reconciliation. Local request IDs do not
create upstream idempotency. `abandon/2` only stops a local wait; use the actual
upstream interruption operation where appropriate and reconcile its effects.

Children use temporary supervisor restart semantics. The owner dying closes owned
resources; reconnect, process restart and execution recovery require an explicit
consumer decision. Task completion/review/acceptance belong to Samgita or the
consumer, never this package.

Owned stdio shutdown waits for the helper to confirm child/descendant cleanup and
exit, including when the Session owner has already died. The shutdown wait is
bounded to five seconds. `Session.close/1` returns a typed error if termination
cannot be confirmed; its surviving Session exposes `phase: :shutdown_failed` and
`shutdown_error`. Pending mutations remain uncertain and reconnect is refused.
Investigate the original process before starting a replacement. Calling the
stdio transport directly raises the corresponding safe typed error on failure.
An already confirmed close remains idempotent. Borrowed WebSocket/UDS server
processes and sockets remain under their original owner's control.

## Transports and limits

| Transport | Options and ownership |
| --- | --- |
| `Transport.Stdio` | `:executable`, `:args`, `:cwd`, explicit absolute `:codex_home` or `:env` CODEX_HOME. Owns the spawned process group. Python 3 handles group cleanup on port/owner death; stderr is drained separately. Ambient HOME/Codex/auth/proxy environment is excluded unless explicitly opted in. |
| `Transport.WebSocket` | `:url`, optional Bearer `:token` or explicit `:headers`, optional pinned `:connect_address`. WSS validates trust, hostname and SNI. Plaintext remote WS needs explicit `:allow_insecure`; no redirects or Origin header. Owns only the client connection. |
| `Transport.UnixSocket` | Absolute `:socket_path`, optional `:path` default `/app-server`. Uses WebSocket over UDS, never JSONL; never unlinks the borrowed socket or invokes `/daemon/shutdown`. |

Set `:max_message_bytes` on the Session. Transport options separately bound frames,
reads, connect and send deadlines. Sessions bound pending requests, interactions,
uncertain operations and event count/bytes. Overflow disconnects with an explicit
history gap rather than silently losing approvals. The UDS peer frame-size header
limits outgoing messages. Current process-group cleanup and real-binary evidence
qualify Linux; other operating systems need their own qualification.

Upgrade 401/403/429 remain failures with safe HTTP status/Retry-After metadata.
Both upstream capability-token and signed-bearer authentication use the explicit
Bearer header; successful signed-JWT real-service qualification is a separate
profile. Codex upgrade authentication alone does not enforce Samgita membership,
lease/fence ownership or post-upgrade credential revocation. Platform consumers
must enforce those boundaries and destination approval independently.

## Verification

Run from this package directory in the repository's Elixir/OTP environment:

```sh
mix deps.get
export CODEX_BINARY=/absolute/path/to/the/immutable/pinned/codex
mix compile --warnings-as-errors
mix test
mix format --check-formatted
```

`real_session_test.exs` uses the actual Codex binary with
`scripts/codex/model_fixture.py`, a deterministic loopback Responses **model**
fixture, not an app-server emulator. It exercises text/image input, complete item
lifecycles, native errors, explicit command approval/denial/cancellation, dynamic
tool responses, plan-mode user input and explicit WebSocket reconnect/resume.
Only the exact synthetic `printf samgita_fixture` command in the disposable
workspace can be approved by that test. No account or paid model is used.

The native turn suites add all seven `UserInput` forms, UTF-8 spans/client IDs
persisted across an owned-process restart, model-capability-dependent media
normalization, skill selection and selected turn overrides. The pinned server's
schema acceptance does not guarantee provider forwarding: inline/local `low`
image detail, remote audio references and unsupported audio model profiles
produce upstream placeholders. Original native user-item payloads remain
available. See the [turn qualification record](../../docs/codex-app-server/turn-input-qualification.md)
for exact scenarios and limits; file-ID capture and synthetic media do not
establish file resolution, recognition or live provider acceptance.

`transport_real_codex_test.exs` verifies actual stdio, authenticated WS and UDS
handshake/thread reads. Scripted tests separately inject framing, TLS, deadline,
disconnect, control and bounded-buffer failures. A missing CODEX_BINARY fails the
real tests with a prerequisite message; it is not skipped compatibility proof.

The [standalone example](examples/consumer/README.md) is copied with its three
reusable package dependencies outside the umbrella by
`scripts/codex/verify_consumer.py`. It starts actual Codex and verifies no Ecto,
Phoenix or Samgita application is present. These checks remain scoped evidence;
external authentication/backend/platform profiles and the manifest determine the
remaining full-compatibility gates. Nothing here publishes a package or deploys
a service. The separate Samgita A11 LiveView credential telemetry blocker remains.
