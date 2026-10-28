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
making the Session ready. On the pinned server, the successful initialize request
itself establishes readiness; client notifications are logging-only. The Session
keeps its canonical send-before-ready policy and fails initialization if that
send fails. Early, omitted or duplicate notifications do not change server state.
See [initialization qualification](../../docs/codex-app-server/initialization-qualification.md).

`Session.notify_native/3` sends a complete client-notification envelope, including
omitted versus null parameters and future fields. It checks the pinned schema by
default; `validation: :wire` explicitly permits extensions without claiming their
compatibility. `{:ok, %{outcome: :sent_unconfirmed}}` means only a local transport
write. It allocates no request ID, awaits no ACK, changes no handshake readiness
and never replays after reconnect. Failed writes return uncertain native evidence
and disconnect. Do not resend an extension with possible effects without
reconciliation. The pinned `initialized` notification only logs on the server.

Requests correlate typed IDs in their connection
generation; native server requests have a separate direction and opaque handles.
Notifications/items retain their complete payloads in a bounded ordered pull
queue. The owner receives one `:events_available` wakeup and drains the queue.

`Session.status/1` exposes a non-secret process-lifetime `instance_id` and a
connection `generation`. If the transport metadata callback raises, throws or
exits, it returns `{:error, %SamgitaProtocolCodex.Error{code:
:transport_callback_failed}}` and disconnects. A later status reports the actual
disconnected or shutdown-failed state. Consumers must handle both return shapes;
an error cannot establish current ownership or health.

For fenced callers, `request_native/3`, `notify_native/3`
and `respond/4`
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

Validated terminal dynamic-item or turn evidence retires only matching unanswered
dynamic handles and timers. A reply through that old handle fails explicitly.
This does not create an acknowledgement, settle a previously sent reply or retire
another interaction family. Reconcile any unconfirmed reply separately.

`Session.reconnect/1` closes this connection and opens a new one. It never resends
requests. Initialize again and explicitly read/resume an existing thread.
Upstream may replay its pending ordinary interactions during thread resume; this
does not replay missing notification history. The driver exposes a gap and local
sequence, which is not an upstream replay cursor. Timed-out/disconnected mutations
remain uncertain until caller-owned reconciliation. Local request IDs do not
create upstream idempotency. `abandon/2` only stops a local wait; use the actual
upstream interruption operation where appropriate and reconcile its effects.

Known execution queries, including `server/diagnostics`, `thread/search`,
`thread/searchOccurrences`, `thread/items/list`, `thread/items/read` and
`thread/timeline/list`, report a lost response without recording uncertain
execution. Pending queries consume `max_pending`; pending mutations and retained
uncertain mutations also consume `max_uncertain`. Unknown methods remain
potentially mutating. A query failure still reports transport gaps where
applicable and never causes an automatic retry or resolves another operation.
See the [query recovery qualification](../../docs/codex-app-server/query-uncertainty-qualification.md)
for exact pinned-source semantics, fault checks and limits.

A normally returned transport-open error leaves the Session disconnected and
available for another explicit reconnect. If a replacement open callback raises,
throws or exits, reconnect returns a sanitized `transport_callback_failed` and
stops the Session so owner-death guardians can reap partial allocations whose
connection handle was never returned. Pending callers receive their uncertain
outcomes before replacement begins. Consume and persist those outcomes; the
terminated Session's in-memory inventories are no longer queryable. Starting a
new Session remains an explicit consumer decision after cleanup and recovery.

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

## Native operation semantics

These operations share lossless request/event handling, but have different
execution and recovery rules in the pinned server:

| Native family | Observable boundary |
| --- | --- |
| `command/exec` and write/resize/terminate | The request completes with execution output/status; output may stream separately. Process IDs belong to a connection, whose disconnect terminates its standalone commands. A local abandonment is still uncertain until actual effects are reconciled. |
| `thread/shellCommand` | Immediate submission ACK, followed by `userShell` item/turn events. It runs on the native host outside the thread sandbox. A client disconnect removes its subscription and does not stop the command. Timeout item exit `-1` differs from standalone command timeout `124`. |
| `thread/queue/*` | Experimental durable per-thread queue; idle/resume may dispatch, interruption preserves its pause, and explicit selected/head start changes it. Client message IDs do not deduplicate submissions; no public queue CAS exists. |
| `thread/inject_items` | Appends native Responses items without starting a user turn. Idle injection waits for its preparation checkpoint; the [ordinary cold-history profile](../../docs/codex-app-server/ordinary-injected-history-qualification.md) checks complete disk records immediately after ACK and exact next-provider input after restart. During an active turn the same ACK means pending-input enqueue; it does not establish durability. The [held-tool profile](../../docs/codex-app-server/ordinary-active-injected-history-qualification.md) qualifies FIFO consumption after explicit reply and volatile-queue removal after explicit interruption, preserving earlier history across cold resume. Reconcile actual history before deciding recovery; a lost response never authorizes blind resubmission. Native content annotations and provider projections can differ from the original losslessly transported request. |
| `threadSection/*`, `thread/section/move` | Stable persisted native organization; these are not Samgita Projects or repository memberships. There is no public section CAS. |
| `thread/readState/update` | Experimental durable read/unread action with an opaque expected revision and structured conflict. Reading/listing does not acknowledge attention. |
| `thread/realtime/*` | Experimental realtime lifecycle. Empty RPC results acknowledge operation submission; startup can fail asynchronously. Started, error and closed notifications determine session outcome. The V2 backend prompt prefers nonblank configuration over a request prompt. User appendText gains `[USER] `; assistant text uses output_text. appendAudio forwards data to V2 without its request-side sample metadata/item ID. Blank appendSpeech is a no-op; nonblank V2 speech sends `[BACKEND] ` text plus response.create. Backend receipt, audio generation and transcript persistence require separate evidence. |
| `thread/realtime/listVoices` | Experimental thread-independent builtin voice catalog, including ordered version lists and reported defaults. Explicitly selecting a returned default is separate from omitting the voice parameter, and listing a voice does not qualify its synthesis or playback. |
| V3 realtime startup/stop | An omitted WebSocket version uses native configuration. Ordered initial messages preserve roles/text at `/v1/live`. Stock requested stop drops the backend connection through task cancellation; its native closed notification does not guarantee an application `session.close` or WebSocket close frame. |
| Realtime mode instructions | Explicit custom start/end text enters actual developer content at the active/inactive transition. A later model request retains prior start text in history and adds end text. An RPC ACK alone does not prove injection; loaded includeTurns reads provide the persistence barrier for full history. |
| `plugin/installed`, `plugin/search`, `plugin/reconcile` and `marketplace/*` | Installed enablement and search discovery differ: local search reports `enabled: false`. An unauthenticated empty reconcile result does not establish remote synchronization or readiness. Local marketplace removal preserves referenced source files; explicit Git upgrade materializes an owned snapshot. |
| `externalAgentConfig/*`, `hooks/list`, `collaborationMode/list` | An import ID acknowledges submission; correlated progress, completion and durable history determine results. Progress reports individual items, while completion groups and sorts them. Recording history stores external reports without importing files or sessions. Listed hooks are metadata and do not run their commands. |

The command, queue, organization and model-discovery qualification records under
`docs/codex-app-server/` declare the exact native tests and remaining profiles.
Native capability metadata and successful synthetic commands do not establish
inference, sandbox enforcement, live authentication or Samgita Task acceptance.

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

Private user/network namespace profiles are explicit tests rather than default
discovery. The native qualification fixtures require Python 3.11 or newer for
standard-library TOML validation. Both native CI jobs explicitly select Python
3.13 and load the required-skills fixture before starting Codex. The stdio transport's Python
cleanup helper does not itself require TOML support.

On the declared Linux profile with `unshare`/`ip` and the pinned binary:

```sh
mix test test/native_command_lifecycle_profile.exs \
  test/native_model_discovery_profile.exs test/native_user_shell_profile.exs \
  test/native_tool_interactions_profile.exs test/native_realtime_lifecycle_profile.exs
```

Authentication, executor and account/Apps namespace profiles are separate required
CI steps as recorded in the qualification ledger. A denied prerequisite fails;
there is no skip or host-network fallback.

The default actual-native suite also requires the `rg` executable from ripgrep
on the host PATH. On Debian/Ubuntu, install the `ripgrep` package before running
the suite. The content-search fixture adds only the explicitly discovered
executable to its private PATH; missing ripgrep fails with
`BLOCKED_ENV: ripgrep required`. The selected conformance CI job installs this
prerequisite before running both required driver partitions.

Run from this package directory in the repository's Elixir/OTP environment:

```sh
mix deps.get
export CODEX_BINARY=/absolute/path/to/the/immutable/pinned/codex
export CODEX_APP_SERVER_BINARY=/absolute/path/to/the/separately/pinned/codex-app-server
mix compile --warnings-as-errors
mix test
mix format --check-formatted
```

The separate native source-selector test requires the official standalone
`codex-app-server` executable. From the repository root,
`python3 -B scripts/codex/fetch_standalone_pin.py` obtains its separately pinned
Linux musl artifact without starting it. Its top-level argv differs from the
combined `codex app-server` entry. See the [exact profile and evidence](../../docs/codex-app-server/standalone-source-selector-qualification.md).
Under the current test restriction, use only the reviewed ordinary selection
in `scripts/codex/check_ordinary.py`; the broad commands above remain required
future gates and must not be run while that restriction applies.

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

Additional turn suites qualify standalone `toolOutput` and restart history under
both negotiation modes, sticky/null settings and collaboration precedence. A
controlled `mcp://` mention test demonstrates optional-server startup waiting and
explicit synthetic elicitation. Retention annotations are not compaction proof;
mentions do not grant tool permission. These are selected stdio outcomes, with the
remaining matrix recorded in the same qualification document.

Image preparation tests add valid synthetic PNG resize/dimension/patch-budget
evidence across inline, local and structured output, plus exact Unicode scalar
text boundaries. Native item payloads remain distinct from prepared provider
content. Image-byte limits, optional image features and actual model vision remain
unqualified.

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

Callback-formatted Session status and error Inspect/messages redact native
payloads. External transport callback exceptions are contained at invocation:
arbitrary reasons and argument-bearing stacks are discarded before OTP reporting.
Only fixed callback names enter the sanitized failure. Safely returned native
Errors retain their authorized wire; a typed raised cleanup Error retains its
existing checked-shutdown contract. Unconfirmed close still blocks replacement.
Callback-authored logs, malformed callback return values and unrelated process
exceptions are outside this boundary. See the
[qualification and limits](../../docs/codex-app-server/session-confidentiality-qualification.md).

Privileged raw OTP debugging is not a safe export path: `:sys.get_state`
exposes state, and on OTP27 enabling `:sys.log` leaves raw Debug history in the
outer `:sys.get_status` term, outside the Session callback. Treat that access as
trusted and keep it out of telemetry/exporters. This boundary does not establish
complete credential isolation or close Samgita's raw framework A11 exposure.
