# Explicit Codex runtime integration

This document describes the current source implementation, not full compatibility
or deployment acceptance. It supplements [design](design.md) and the
[implementation ledger](implementation-plan.md); exact executed checks and release
status belong in [qualification](qualification.md). The coordinating local run
passed selected platform real-binary journeys. The retained dependency advisory
is repaired; raw-telemetry confidentiality remains blocked. Current aggregate,
driver transport repairs and hosted results are tracked in qualification and the
[repair record](repair-qualification.md).

The [official standalone app-server profile](standalone-source-selector-qualification.md)
adds explicit native source selection for independent ordinary driver checks.
It uses a separate pin and top-level argv; platform runtime defaults still use
the retained combined executable. No automatic platform/service switch follows
from this local source-selector qualification.

## Ownership and identities

An operator registers an ordinary Agent with `runtime_driver: "codex"` and
`runtime_version: "0.163.0"`. Runtime metadata neither grants membership nor
starts a process. The registered Agent authenticates, connects, joins a Project
with the worker role, opens an execution session, claims a Task and starts its
Attempt through existing domain APIs. Synapsis follows exactly these rules.

`Samgita.CodexRuntime.bind/3` then records a native binding for that running Attempt.
Its identities have separate purposes:

| Identity | Meaning |
| --- | --- |
| Agent UUID | Stable registered machine identity |
| Connection UUID/generation | Current authenticated Agent connection |
| Execution session UUID | Existing Samgita execution-session record |
| Attempt UUID/fence/authority epoch | Current database-owned execution authority |
| Runtime binding UUID | Durable native journal associated with one Attempt |
| `runtime_ref` UUID | Caller-assigned native runtime reference, unique across bindings |
| `instance_id` UUID | Native driver process-instance boundary for journal correlation |
| `driver_generation` | Generation of the independently started driver Session |
| Native request/thread/turn IDs | Upstream identities, retained in encrypted envelopes and explicit links |

A composite foreign key binds Project, Task, Agent and execution session to the
same Attempt. Unique indexes prevent two bindings for one Attempt or reuse of a
runtime reference. The protocol and driver packages remain independently reusable;
the Repo-dependent bridge lives in `apps/samgita`, outside those packages.

## Intent, ticket and settlement

The [real-native authority cases](native-authority-qualification.md) demonstrate
membership/fence revocation before reply preparation and worker-role revocation
before dispatch. Rejected repeats preserve the journal and leave native work
unresolved. They do not establish instantaneous revocation of a ticket already
committed before network I/O; connection instance, generation and deadline
guards remain a separate boundary.

The required [independent-transaction authority profile](native-authority-qualification.md#management-wins-dispatch-with-independent-postgresql-transactions)
uses a separate scratch database so retained genuinely pending native effects
cannot contaminate global activation/restart checks. It observes the actual
PostgreSQL blocker before allowing management to commit, then requires rejected
dispatch with no ticket/send. This qualifies that pre-ticket ordering only.

The additive [queued-ticket expiry case](native-authority-qualification.md#queued-response-expires-after-ticket-commit)
observes a genuine response queued before its committed ticket deadline and
handled afterward. Session rejects it without consuming the native interaction;
the expired durable operation stays unresolved and cannot be redispatched or
settled as an ordinary success. It does not add synchronous revocation across
the commit-to-send interval or remote idempotency.

The sending Agent chooses the native action. Samgita validates and records it:

1. **Prepare:** persist a native request or client notification with a command UUID, current lease proof,
   binding `expected_version`, full `native` envelope and optional `timeout_ms`.
   The intent has state `prepared`. This performs no network I/O.
2. **Dispatch:** supply the operation's `expected_version` and current lease proof.
   One transaction changes it to `in_flight`, stores only a digest of a random
   dispatch token and returns the native envelope plus token once. The deadline
   is bounded by the requested timeout, Attempt lease and execution deadline.
3. **Send:** after that transaction commits, use the selected native Session to
   send the exact envelope. No database lock spans the transport operation.
4. **Settle:** submit a new command UUID, operation version and dispatch token,
   together with the correlated native response/error or
   `delivery_outcome: "uncertain"`. Current credentials, Project membership,
   connection, Attempt state, lease, fence, authority epoch and native instance
   are checked again. Native response IDs must match the original typed ID.

Client notifications retain an absent wire ID. Their required journal identity
is a keyed fingerprint of `["client_notification", operation_uuid]`, never an ID
injected into the native envelope. Replaying a command returns its existing
intent; a distinct explicit command may prepare the same notification again.
The platform validates only the pinned client-notification schema; the
standalone Session's wire-extension option cannot bypass platform validation.

For notifications, settlement accepts only absent/null native response with
`sent_unconfirmed` or `uncertain`. A successful local write is neither a remote
ACK nor a completion result. The bridge cannot store a failed send's outgoing
notification as an invented server response. Notification dispatch uses the same
one-use ticket, instance/generation/deadline fences and current authorization as
requests. It does not advance the incoming journal sequence, create a Task/turn,
change readiness or clear gaps and other unresolved effects.

Preparation and settlement support command-receipt replay under current
authorization. A reused command ID with changed semantics conflicts. Dispatch
deliberately does not replay a plaintext ticket. A lost dispatch response or
caller crash can leave `in_flight` work whose external outcome is unknown; never
obtain a new intent merely to repeat that mutation. A local command UUID or wire
request ID is not an upstream idempotency guarantee.

`Samgita.CodexRuntime.Driver.execute/7` implements dispatch, native send and fenced
settlement for an already started `SamgitaCodexDriver.Session`. It starts nothing
and retries nothing. Request timeouts use the remaining ticket deadline. Native
errors retain their original envelope; transport/session failures produce
uncertainty. Settlement failure after a possible send must be assessed explicitly.

For the local bridge, bind `instance_id` to the non-secret UUID returned by
`Session.status/1`. That UUID remains stable for one Session GenServer lifetime;
generation changes identify reconnects within it. The bridge checks both instance
and generation before obtaining a ticket, then passes both plus the ticket
deadline to the serialized Session dispatch guard. A reconnect queued between the
status check and native call cannot send an old-generation ticket. Equal generation
numbers on different Sessions cannot select another process accidentally. Remote
API submissions remain the authenticated owner's explicit instance claim, not
independent proof of remote process identity. No mandatory Samgita transport proxy
is introduced.

Unknown methods are rejected by the pinned schema. The effect classifier uses a
small explicit request-read allowlist and conservatively treats other methods as
mutations. Only `initialized/client_notification` is separately classified as
logging-only read, following pinned `message_processor.rs:740–751`; an in-flight
notification still blocks resolved-execution claims. Paused Projects cannot dispatch new mutations except explicit
`turn/interrupt`. Ambiguous mutations, including unconfirmed interaction replies,
block fresh mutation dispatch; current interaction replies and interruption remain
available for control. Registration, schedules, event delivery, recovery and
application restart cannot create or dispatch an intent automatically.

## Events and interaction decisions

Consumers drain Session events and explicitly persist each original envelope,
`source_sequence`, `instance_id` and `driver_generation`. A local source sequence
is evidence of what that driver observed; it is not an upstream replay cursor.

The journal validates notifications and server requests against the pinned
contracts. Native responses recorded as events must correlate to a known request.
Within one instance and driver generation, reusing a sequence with identical
content returns the existing event; changed content conflicts. Native request
identity, response correlation and interaction resolution also include that
generation. Reconnect may reuse upstream IDs without settling an earlier
generation's uncertain approval. Repetition does not extend an interaction's
expiry. Skipped
sequences set `notification_gap`; late insertion cannot manufacture completeness.
At most 128 unexpired pending server interactions and 128 prepared/in-flight
operations may be active per binding. Native envelopes are bounded at 8 MiB.

A server request records a pending interaction with an expiry bounded by 60 seconds
and the Attempt's remaining lease/deadline. An explicit decision uses the original
request ID and a schema-valid response/error. It creates a `client_response`
intent and marks the interaction `reply_prepared`; it does not send or approve
anything by itself. A worker owner or operator may prepare the response, subject
to current execution authority. Only the owning Agent can obtain its dispatch
ticket through the Agent API.

For a reply, `Driver.execute/7` also requires the original Session interaction
handle matching native ID and generation. A successful local send settles as
`sent_unconfirmed`; a failed/ambiguous send settles as `uncertain`. Neither proves
the remote action ran or accepted this particular decision. A matching
`serverRequest/resolved` notification records resolution evidence using both
request and thread identity. It may reflect cancellation or another client's
response, so it cannot establish which decision was accepted.

The bridge treats a failed `Session.status/1` as lost current ownership. Before
ticket issuance this rejects dispatch without a durable change. After a ticket
has committed it records an uncertain outcome without sending or retrying the
native operation. Status exceptions cannot be treated as a healthy connection or
an invitation to execute again. Repeated scripted status failures test this
interface separately from actual native-generation qualification.

Thread/turn links retain native lifecycle evidence. No item, artifact, approval,
turn completion or successful RPC automatically changes Task acceptance.

## APIs and access boundaries

All paths below append to `/projects/:project_id/codex-runtimes`. Agent paths use
the `/api/agent` prefix, machine Bearer credentials and the current
`x-agent-connection` header. Operator paths use `/api` and retain existing API-key
and infrastructure boundaries. This introduces no accounts or tenant system.

| Method and suffix | Agent API | Operator API |
| --- | --- | --- |
| `GET` base path, `GET /:id` | Project read role | Yes |
| `POST` base path | Worker owner: bind running Attempt | No |
| `GET /:id/operations`, `GET /:id/events` | Project read role, safe metadata | Yes |
| `POST /:id/operations` | Worker owner: prepare request or pinned client notification | No |
| `POST /:id/events` | Worker owner: record original driver event | No |
| `POST /:id/events/:event_id/reply` | Worker owner: prepare decision | Yes, with current execution fences |
| `POST /:id/operations/:operation_id/dispatch` | Worker owner: one-use ticket | No |
| `POST /:id/operations/:operation_id/settle` | Worker owner: token-bound outcome | No |
| `POST /:id/operations/:operation_id/cancel` | Worker owner: unsent intent only | Yes |
| `POST /:id/reconnect` | Current worker owner after explicit Attempt rebind | No |
| `POST /:id/operations/:operation_id/reconcile` | No | Evidence-only recovery |
| `POST /:id/attest-cessation` | No | Evidence-only gap/cessation assessment |
| `GET /:id/operations/:operation_id/native`, `GET /:id/events/:event_id/native` | Owning Agent with Project read role | Yes |

Read roles are observer, worker, manager or reviewer. They do not grant another
Agent's protected payload access or execution rights. Context authorization runs
inside the existing ordered authority/Agent/Project locks before command replay;
Task, Attempt, binding and operation locks serialize competing writes. Expected
versions reject stale operations. All controller responses use `Cache-Control:
no-store`; native payload and dispatch-token responses require secret handling.

## Encryption and key configuration

Full native request/response/event payloads may contain credentials or untrusted
project input. The database stores AES-256-GCM ciphertext with a random nonce and
associated data binding runtime UUID, record UUID and request/response/event slot.
Native fingerprints use a keyed HMAC; receipts and ordinary audit projections
contain safe metadata instead of plaintext envelopes, lease proofs or dispatch
tokens. Native thread/turn identifiers and lifecycle states are public link
metadata; avoid placing secrets in those identifiers or administrative references.

Deployment configuration uses existing runtime environment/secret injection:

- `SAMGITA_NATIVE_PAYLOAD_KEYS`: a nonempty JSON map of versioned key IDs to
  base64-encoded keys of exactly 32 bytes.
- `SAMGITA_NATIVE_PAYLOAD_KEY_ID`: the active key ID in that map.

Key IDs match `[A-Za-z0-9_-]{1,100}`. Keys stay outside the database and source
control. Missing keys fail closed; they do not authorize execution. Bindings retain
their original fingerprint-key ID, and ciphertext retains its encryption-key ID.
Rotation must retain old keys for existing payloads and replay comparisons. Back up
the key material separately under the deployment's existing secret controls.
Do not overwrite a versioned key or remove it while its records remain needed.

Protected native reads intentionally decrypt complete envelopes for the owner or
operator. Those callers must not log them or pass real secrets through the known
A11-affected LiveView parameter path. At-rest encryption and filtered logs do not
close that upstream telemetry confidentiality blocker.

## Recovery, Task policy and migration

Explicit reconnect records the current instance/generation using the current
Attempt connection/fence. Reusing an instance requires a strictly higher driver
generation; a new Session instance may begin at generation 1. It cancels prepared
intents, marks dispatched/unconfirmed work
uncertain, makes prior interactions stale, resets the local source sequence and
sets a notification gap. No old request or decision is resent. Read current native
state through the selected driver and obtain independent cessation/effect evidence
before administrative recovery; there is no fabricated notification replay.

Validated terminal dynamic-item/turn evidence may retire a matching unanswered
current-generation `item/tool/call` as `terminal_observed` only when no associated
reply has left the prepared/cancelled states. Prepared replies are cancelled
atomically. Reconnect preserves this known-unsent terminal state; it cannot
resolve dispatched or ambiguous responses. Other interaction families and
unresolved operations remain guarded. See
[durable tool retirement](platform-tool-retirement-qualification.md).

Operator reconciliation changes uncertain/unconfirmed or expired in-flight
operations to `reconciled`, retaining an evidence reference. Cessation attestation
records separate evidence, marks observed live links ceased and clears the
binding's gap marker. Neither operation sends a native call, settles other
operations, releases Task holds or claims upstream deduplication. Administrative
evidence references must point to an actual assessment, not an automatic timeout.

Unresolved native effects, observed live turns/active threads and notification gaps
block an Attempt report claiming resolved execution and block effect resolution.
After independent resolution, existing Attempt reporting may submit successful
work to `awaiting_review`. Project review and acceptance decisions must still
produce `accepted`; native execution completion is evidence rather than acceptance.

Migration `20261023000003_add_native_runtime_journal.exs` adds Agent runtime
metadata, four journal/link tables, indexes and scope constraints.
`20261023000004_scope_native_identity_to_generation.exs` adds generation-qualified
identity indexes before replacing the earlier indexes, retaining every record.
The migrations preserve
existing Project UUIDs, Tasks, Attempts, historical records and prior migrations.
It does not backfill bindings, replay execution or start old orchestration.
Development qualification applies migrations only to explicit isolated scratch
databases; this checkpoint performs no production migration.

Rollback preserves journal history. Stop native admission through existing
authority controls, fence current writers and assess outstanding effects before
changing software. Both migrations' `down/0` deliberately refuse destructive
rollback. Use a compatible binary that understands the retained journals, or
keep native execution disabled while applying a forward corrective migration.
An older binary cannot be assumed to enforce the new unresolved-native guards.
Retain encryption keys, backups and the normal legacy-cutover gates. Do not drop
tables, delete records or replay uncertain operations to make a downgrade work.

## Evidence limits and remaining work

The immutable target remains official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. Its separate Rust/TypeScript-backed
export supplement is locally derived and preserves official JSON bytes. The
regenerated [manifest](compatibility-manifest.json) and
[qualification ledger](qualification.md) contain the current requirement,
field/variant and progress totals; none is fully verified. Eleven requirements
remain source-blocked: four legacy approval directions, three prediction
directions and four unavailable notification emitters. The exact immutable
producer audits remain in [legacy approvals](legacy-approval-qualification.md),
[direct MCP](mcp-direct-qualification.md) and
[platform gates](platform-gates-qualification.md); retained declarations or
scripted peers cannot supply actual emission evidence. Selected
local tests cover nine of eleven interaction
families; neither their presence nor generated schemas verifies all variants.
The isolated native [authentication](isolated-auth.md) and
[executor environment](isolated-environment.md) and [Apps metadata](isolated-apps.md)
profiles use the actual pinned
app-server with owned synthetic dependencies in private network namespaces.
The [catalog/installed profile](isolated-app-catalog.md) adds persisted discovery
snapshots and checks that untrusted loopback MCP receives no ChatGPT credentials;
the [fuzzy-search profile](fuzzy-search-qualification.md) uses only synthetic local
files and actual native session notifications.
They neither authenticate a real provider account nor establish remote Agent
service integration, execution sandbox enforcement or full field coverage.

Context, API and independent-PostgreSQL-backend race tests cover selected domain
and transmission boundaries. The new real-binary platform journey covers an
ordinary Agent and a differently named Synapsis Agent, explicit command approval,
event persistence, progress/artifacts and separate review/acceptance. The
coordinating local run passed that selected journey and a wrong-Session-instance
regression. Consult qualification for actual results and final-source
aggregate/hosted checks. Real accounts, remote Agent
services, complete deployment profiles, package publication, production cutover
and deployment remain separate, unclaimed outcomes.
