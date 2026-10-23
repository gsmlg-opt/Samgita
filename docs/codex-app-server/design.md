# Codex app-server client and driver design

Status: implementation in progress. Baseline: Samgita
`4fe354f2ce916aa32517c361a171b8878bf6ca84`. Target: official Codex
`rust-v0.163.0`, source commit `83086188ae0614bd882818ff1aa23f3194962012`.
The Linux musl executable, source archive and complete generated-schema bundles
are pinned by SHA-256 in `priv/upstream/0.163.0/provenance.json`.
See [the goal](goal.md), [implementation ledger](implementation-plan.md) and
[qualification](qualification.md). This document does not claim compatibility.

## Boundaries

`apps/samgita_protocol_codex` owns immutable upstream schemas, native envelopes,
validation and version-specific metadata. Its existing neutral adapter remains a
convenience API with its documented restrictions until separately extended.
Native calls preserve all upstream fields, missing versus null, string/integer
IDs, structured errors and unknown additions without converting input to atoms.
Validation cannot silently normalize or drop input.

`apps/samgita_codex_driver` owns explicitly started supervised sessions and
stdio, WebSocket and WebSocket-over-Unix-socket transports. It depends on the Codex wire package,
not Repo, web, orchestration or platform configuration. The pure schema layer
starts no executable or connection. Loading the driver does not start a listener
or agent. The root umbrella's explicit application list remains core and web.

`apps/samgita` and `apps/samgita_web` own management authorization, durable links
and audit, approvals and operator/programmatic presentation. Native capability
advertisement grants no Project permission. A turn completion report cannot
accept a Task. Secrets use existing external references; real secrets must not
enter the A11-affected LiveView parameter path.

## Session contract

Initialization, including experimental opt-in, follows the pinned upstream
sequence. Separate incoming and outgoing request tables prevent bidirectional ID
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

The event queue is bounded by count and encoded bytes, with one availability
wakeup while nonempty. Interaction handles contain the connection generation and
an opaque reference. Resolution notifications must also match the thread. Local
interaction expiry sends an explicit error; it never approves an operation.
Reply outcomes distinguish `sent_unconfirmed`, `uncertain` after a failed send or
disconnect, and `resolution_observed`. Resolution may represent another client's
response or cancellation, so it does not prove this decision was accepted. Owners
acknowledge local outcome records explicitly to release their bounded capacity.

Transport adapters own framing and only the resources they create. Stdio uses
JSONL and an owned child process with bounded cleanup. WebSocket uses upstream
JSON text framing, controls, negotiated transport/auth options and explicit
destination policy. Borrowed resources remain owned by the caller. REST is not a
Codex transport. Actual listener/authentication support is derived from pinned
source and tested against the pinned executable.

Stdio drains stderr separately and an owned Python process-group supervisor bounds
cleanup on owner/port exit. It excludes ambient home, provider and credential
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

The deterministic backend is an HTTP Responses model fixture; the app-server in
those tests is the real immutable executable. Fixture command approval is limited
to the exact `printf samgita_fixture` action, private shell and disposable cwd.
The executable rejects `approvalPolicy: "untrusted"` in this configuration, so the
fixture uses its observed `on-request` behavior rather than relying on older docs.

## Platform integration still required

No Codex runtime bindings or platform-native operation APIs are added in this
checkpoint. The ordinary Agent registry, project authorization, connection
generation, execution leases and task policy remain authoritative. Native
capabilities cannot become project permissions. Future integration needs additive
thread/turn/operation/interaction records, intent persistence before network sends,
current fenced authorization for replies and protected programmatic native results.
Network I/O must occur outside database locks. The existing project-event connector
cannot turn official Codex notifications into implicit `turn/start` operations.

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
