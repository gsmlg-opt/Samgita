# Codex app-server client and driver design

Status: implementation in progress. Baseline: Samgita
`4fe354f2ce916aa32517c361a171b8878bf6ca84`. Target: official Codex
`rust-v0.163.0`, source commit `83086188ae0614bd882818ff1aa23f3194962012`.
The Linux musl executable, source archive and complete generated-schema bundles
are pinned by SHA-256 in the Codex protocol package's
`priv/upstream/0.163.0/provenance.json`.
See [the goal](goal.md), [implementation ledger](implementation-plan.md) and
[qualification](qualification.md). The implemented platform boundary is described
in [platform integration](platform-integration.md). This document does not claim
full compatibility or acceptance of the current checkpoint.

## Boundaries

`apps/samgita_protocol_codex` owns immutable upstream schemas, native envelopes,
validation and version-specific metadata. Its existing neutral adapter remains a
convenience API with its documented restrictions until separately extended.
Native calls preserve all upstream fields, missing versus null, string/integer
IDs, structured errors and unknown additions without converting input to atoms.
Validation cannot silently normalize or drop input.

Pinned source semantics can correct a demonstrated exporter discrepancy only
through a separately labeled, reproducible contract with preserved official
artifacts. The timeline output correction in
[history qualification](thread-history-qualification.md) changes six contract
field names across two native turn-boundary variants, never received data or
validation constraints. Hash checks fail closed on source/export drift.

`apps/samgita_codex_driver` owns explicitly started supervised sessions and
stdio, WebSocket and WebSocket-over-Unix-socket transports. It depends on the Codex wire package,
not Repo, web, orchestration or platform configuration. The pure schema layer
starts no executable or connection. Loading the driver does not start a listener
or agent. The root umbrella's explicit application list remains core and web.

`apps/samgita` and `apps/samgita_web` own management authorization, durable links
and audit, approvals and operator/programmatic presentation. Native capability
advertisement grants no Project permission. A turn completion report cannot
accept a Task. Secrets use existing external references. The separate
[A11 boundary](a11-ingress-boundary.md) includes raw HTTP metadata before
application Plugs and raw LiveView parameters; neither controller entry nor
at-rest encryption establishes confidentiality for real credentials.

## Session contract

Initialization, including experimental opt-in, follows the pinned upstream
sequence. The upstream initialize request establishes readiness; its client
`initialized` notification is logging-only. The Session validates the correlated
success and sends the canonical notification before declaring local readiness.
Early/duplicate notifications cannot initialize the server. See
[initialization qualification](initialization-qualification.md) for the source,
three-transport evidence, client failure policy and remaining profiles.
Separate incoming and outgoing request tables prevent bidirectional ID
collisions. A connection generation binds pending server interactions; late
responses from another generation cannot approve a request. Every request settles
at most once. Deadlines, send failures, disconnect and process exit clean pending
state and expose whether a mutation may have executed.

The driver must deliver every notification and server request intact. It never
automatically approves, executes a tool, responds on a caller's behalf, retries a
possibly executed mutation or infers upstream deduplication from a local ID.
Bounded buffering fails visibly and requires reconciliation; it cannot silently
discard an approval or lifecycle event. Reconnect creates a new initialization
boundary and reports an event gap when upstream supplies no replay guarantee.
Thread read/resume can reconcile current state; neither reconstructs a complete
missing notification history.

The implemented Session uses temporary supervisor restart semantics and monitors
its owner and pending callers. An owner exit closes owned resources. Deadlines or
caller loss settle a pending call once; a potentially executed mutation is retained
in the bounded uncertainty table. A caller cannot label an unclassified operation
as a safe read. `abandon/2` stops a local wait only. Reconciliation records caller
evidence; it does not query upstream implicitly or resend anything.

`request_native/3` preserves the original envelope, including trace and future
fields. Native schema validation is the default. Explicit `validation: :wire`
allows protocol experiments without claiming schema conformance. Every response
still passes envelope validation and retains upstream error data. Failures redact
payloads in Inspect, exception messages and GenServer status output. Authorized
callers remain responsible for handling raw native data as potentially secret.

`notify_native/3` supplies the separate native client-notification path. It
preserves the envelope without inventing an ID, uses the same serialized
instance/generation/deadline dispatch guards, and returns only a local
`sent_unconfirmed` outcome. It cannot allocate request correlation, acknowledge
upstream processing or change readiness. Failed writes retain uncertain evidence;
reconnect never replays a notification. Platform preparation permits only pinned
notification schemas and uses a separate local operation identity.

The event queue is bounded by count and encoded bytes, with one availability
wakeup while nonempty. Interaction handles contain the connection generation and
an opaque reference. Resolution notifications must also match the thread. Local
interaction expiry sends an explicit error; it never approves an operation.
Reply outcomes distinguish `sent_unconfirmed`, `uncertain` after a failed send or
disconnect, and `resolution_observed`. Resolution may represent another client's
response or cancellation, so it does not prove this decision was accepted. Owners
acknowledge local outcome records explicitly to release their bounded capacity.

Validated terminal dynamic-item or turn evidence retires only matching unanswered
dynamic handles and their timers. It sends no reply, creates no resolution or
outcome and never clears an already unconfirmed reply. The platform journal
applies the corresponding current-instance/generation/identity check under its
authority locks, retiring only requests proved unsent and cancelling prepared
responses atomically. It preserves that terminal evidence across reconnect;
dispatched or ambiguous operations still require explicit reconciliation. See
[native interactions](tool-interactions-qualification.md) and
[durable retirement](platform-tool-retirement-qualification.md).

Transport adapters own framing and only the resources they create. Stdio uses
JSONL and an owned child process with bounded cleanup. WebSocket uses upstream
JSON text framing, controls, negotiated transport/auth options and explicit
destination policy. Borrowed resources remain owned by the caller. REST is not a
Codex transport. Actual listener/authentication support is derived from pinned
source and tested against the pinned executable.
Bytes received during WebSocket upgrade stay in bounded transport state and
precede later active-socket data. A mailbox wakeup cannot confer wire order or
replay consumed upgrade bytes; deterministic tests cover this boundary.

Stdio drains stderr separately. A guardian owns the port, monitors the Session,
and survives its death long enough to await the Python process-group helper's
cleanup acknowledgement and exit. A shared completion reference preserves the
confirmed outcome for later close calls without a global registry. The helper
bounds input buffering and termination, reaps owned descendants on Linux, and
keeps its cleanup control separate from native JSONL. A five-second shutdown
deadline fails explicitly; helper disappearance alone is not proof of cleanup.
Session preserves pending mutation uncertainty and refuses reconnect after
unconfirmed shutdown, so failure cannot launch a replacement owned process.
It excludes ambient home, provider and credential
environment unless explicitly supplied. Consumers must provide an isolated
absolute CODEX_HOME. WebSocket supports explicit Bearer headers, destination
pinning, WSS trust/hostname/SNI checks, control frames and upgrade error metadata.
Upstream refuses Origin headers. Its upgrade authentication is not continuous
credential validation; the platform must still enforce current membership and
connection authority. Borrowed Unix sockets are never unlinked or shut down.

## Pinned semantic findings

The stable generated schemas alone do not describe runtime experimental gates.
Rust annotations distinguish false booleans, ordinary optional null, explicit
null in double options, empty optional collections and custom empty paths. Source
metadata plus real-binary probes preserve those distinctions. Request field gates
do not apply to correlated response fields: stable upstream thread results include
fields that disappear from the stable generated bundle. Responses validate against
the full pinned schema. Notification method gates remain a separate contract.

The deterministic backend is a loopback Responses model fixture; the app-server in
those tests is the real immutable executable. Command and patch approvals are
limited to the explicitly asserted synthetic action of each test, a private shell
and a disposable cwd.
The executable rejects `approvalPolicy: "untrusted"` in this configuration, so the
fixture uses its observed `on-request` behavior rather than relying on older docs.

Selected real-binary turn qualification now covers all seven native `UserInput`
forms, text spans and persisted client IDs, plus context, causal metadata,
service-tier and output-schema fields. Native user-item evidence and captured
model requests are separate surfaces: the pinned runtime may normalize or omit
media according to model capabilities and preparation rules. The driver must
preserve those outcomes without adding its own normalization. See
[turn inputs and parameters](turn-input-qualification.md) for the exact stdio
profile, supported/unsupported branches and remaining evidence limits.

Native standalone `toolOutput` is a first-class function-output item: it can start
an idle turn without an earlier tool call and is distinct from ordinary user
input. Its optional retention flag annotates internal history; provider payloads
must not acquire that internal flag or an invented call ID. Exact `mcp://` mentions
make a named server a startup dependency before model tool binding. They do not
grant permissions. Selected real-binary history, settings and controlled MCP
startup evidence is recorded in the same qualification document.

The image follow-up captures actual PNG preparation across inline, local and
structured-output paths, including dimension/patch budgets and preparation before
model-detail normalization. Exact Unicode scalar boundaries are distinct from
client/fixture byte caps. These are request-construction outcomes; no provider
vision, GiB-boundary or optional image-feature acceptance is implied.

Realtime operation submission and session startup are different boundaries.
The pinned server can return an empty result before asynchronous preparation
fails; consumers must observe started/error/closed events. Selected V2 behavior
uses the actual native app-server with an owned WebSocket backend, including
typed durable transcript items, replacement and explicit restart. Nonblank
configured prompts override request prompts. This evidence does not qualify
V1/V3, WebRTC/existing-call success, handoffs, delegated model execution or real
audio/backends; see [realtime lifecycle](realtime-lifecycle-qualification.md).

The official JSON exporter omits `getAuthStatus`, `getConversationSummary` and
`gitDiffToRemote`, plus `rawResponse/completed` and `rawResponseItem/completed`.
Their separate supplement uses the same executable's experimental TypeScript
export, pinned `v1.rs` serde declarations and existing official shared definitions.
`source/supplemental-origin.json` labels this conversion as locally derived;
`source/export.rs` records the exporter boundary. Original official JSON bytes
remain unchanged. Conversion fails on unsupported declaration syntax or serde
semantics; it does not establish runtime behavior. At that source-completeness
checkpoint the inventory had 485 requirements (one `implemented`, 480 `missing`,
four `blocked`) and 6,621
field/variant contracts (three `implemented`, 6,618 `missing`) for full behavioral
qualification. Current regenerated counts and subsequent evidence are recorded
in [qualification](qualification.md). Exact declaration-branch matching also prevents a gate
on one untagged variant from rejecting another variant with the same field name.

The immutable release also has two output exporter/serializer disagreements:
timeline turn boundaries and promoted realtime items use native camelCase names
that the JSON exporter describes in snake_case. `Schema.Output` derives narrow
validation-contract corrections from full hash-pinned Rust source and the same
executable's TypeScript export. It preserves official JSON files, received values,
types, required fields, unions and numeric constraints. Effective output-contract
hashes are separate manifest metadata; a changed contract cannot silently retain
prior verification. Supplemental raw-response contracts remain separate. See
[native history](thread-history-qualification.md) and
[realtime output](realtime-output-qualification.md); contract correction alone
does not qualify enabled realtime backend behavior.

## Implemented platform boundary

`Samgita.CodexRuntime` adds an explicit journal around an ordinary Agent's running
Attempt. Registration stores `runtime_driver=codex` and `runtime_version=0.163.0`;
it starts no worker, executable, connection or listener. Stable Agent identity,
authenticated Agent connection, execution session, Attempt fence, native runtime
reference, native instance and driver generation remain separate identities.
Project membership supplies roles; runtime metadata and capabilities grant none.

Additive tables retain runtime bindings, native operation intents, source events
and thread/turn links. A unique binding belongs to one Attempt and records its
Project, Task, Agent, session, connection generation, fence and authority epoch.
Current authorization runs before command-receipt replay and settlement. Safe
metadata projections are distinct from explicit protected native-payload reads.

An Agent persists a validated intent, obtains a one-use dispatch ticket, sends
through its already started driver outside the transaction, then reports a
correlated response or uncertain outcome. `Samgita.CodexRuntime.Driver` implements
that explicit sequence without launching a process or retrying transmission.
Ticket loss or caller failure after dispatch leaves durable uncertainty; a retry
does not issue another ticket. Local command IDs do not confer upstream
idempotency. The local bridge checks the Session's process-lifetime instance UUID
and driver generation before obtaining a ticket; serialized Session dispatch then
checks the expected instance, generation and absolute ticket deadline atomically
with sending. This closes the race between an earlier status read and reconnect.
Remote API callers still explicitly claim their native instance; Samgita does not
force those transports through its server.

Full request, response and event envelopes use AES-256-GCM with deployment-supplied
versioned keys. Associated data binds ciphertext to its runtime, record and slot;
keyed fingerprints support replay comparison without retaining plaintext native
content in receipts or domain audit events. Key configuration is external to the
database. This protects stored payloads; it does not close the separate A11 raw
LiveView telemetry exposure or authorize logging decrypted native data.

Consumers persist drained events using their original driver sequence and
generation. Duplicate sequence/content pairs retain the existing event and
interaction expiry; conflicting content fails. Gaps remain visible rather than
being filled with invented history. Interaction decisions become explicit intents
for the original server request; dispatch and settlement remain separate. A sent
reply is unconfirmed until resolution evidence arrives. Mutation ambiguity blocks
new mutations, while explicit interruption and current interaction replies remain
available for control and resolution.

Reconnect cancels unsent intents, fences prior interactions, marks prior dispatched
work uncertain and records a notification gap. Operator reconciliation and cessation
attestation record evidence; neither sends a request nor accepts a Task. Unresolved
native effects and live turns block a report claiming resolved execution. A valid
successful Attempt report submits the Task to `awaiting_review`; explicit review
and acceptance decisions remain required. Scheduled checks and project-event
delivery cannot create native execution implicitly.

The context/API/race tests provide selected local evidence. The coordinating run
passed the platform journey through the real pinned executable and explicit
approval under two ordinary Agent names. Aggregate checks against the combined
source, hosted checks, external profiles and full manifest acceptance remain
separate gates, recorded in qualification rather than inferred here.

## Evidence and deployment profiles

The generated compatibility manifest covers all four message directions,
parameter/result types and variants, errors, field/method gates and lifecycle
rules. Each entry names implementation ownership and planned/actual evidence.
Wire/schema tests, scripted fault tests, real-binary deterministic tests,
Samgita integration and credential/platform acceptance are distinct layers.
An entry cannot be verified solely because a generic native call can send JSON.

Initial harness platform: Linux x86_64, isolated CODEX_HOME/workspace, no live
account or paid provider. Additional platform/backend profiles must be explicitly
declared and evidenced. An upstream unavailable response qualifies only that
unavailable path. Success paths requiring another environment remain blocked.
All profile claims remain provisional until qualification records exact evidence.

Explicit Linux namespace profiles exercise native browser/device authentication,
authenticated executor registration and Apps metadata against owned synthetic
dependencies. Only loopback is available; native protocol output is forwarded
unchanged, and method/HTTP allowlists prevent inference and unrelated execution.
The executor profile runs the pinned release for both app-server and exec-server.
These profiles fail when isolation is unavailable and never fall back to shared
callback ports. They run separately from default package discovery and require
explicit hosted jobs. Their scoped success cannot establish real-provider
authorization, all backend/OS variants or A11 confidentiality acceptance.
