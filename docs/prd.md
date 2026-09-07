# Product Requirements Document: Samgita Agent Hub — First Milestone

**Status:** Approved for implementation planning
**Date:** 2026-09-06
**Release:** Agent Hub clean-start foundation
**Related design:** `docs/agent-hub-rebuild-design.md`

---

## 1. Product Summary

Samgita Agent Hub is a self-hosted control plane for durable work performed by
long-running external Agents. An operator registers Agents, grants each Agent
access to selected Projects, creates Tasks, and observes execution. Agents
authenticate over a versioned WebSocket protocol, claim bounded work, and
report progress and terminal results.

The first milestone must prove this complete path:

```text
register Agent and issue credential
  -> create Project and authorize Agent
  -> create Task
  -> connect fake Agent
  -> claim and start an Attempt
  -> report progress
  -> complete or fail
  -> inspect Task, Attempt, and event history
```

PostgreSQL is authoritative. A socket process may disappear at any time without
losing accepted work or permitting a stale Agent to commit a result.

## 2. Clean-Start Authority

Samgita has no production data to preserve. This milestone replaces the prior
product in the existing repository while retaining Git history. It does not
migrate old records, preserve old runtime behavior, or maintain unused
compatibility layers.

The rebuilt umbrella contains two applications:

- `samgita`: Repo, Projects, Agents, Tasks, Protocol, Events, and durable Oban
  maintenance workers.
- `samgita_web`: Phoenix endpoint, operator REST API, Agent Socket/Channel, and
  DuskMoon LiveViews.

The web application depends on core; core never depends on web. PostgreSQL owns
durable state, PubSub carries post-commit notifications, and Channel processes
own only transient transport state.

Fresh migrations create only the Agent Hub domain, Oban infrastructure, and
infrastructure required by the retained Phoenix application. Retained tooling,
assets, API protection, CI, and release packaging must have an active Agent Hub
purpose.

## 3. Users and Actors

### 3.1 Operator

A trusted user of the self-hosted deployment. The Operator manages Projects,
Agents, credentials, Project authorization, and Tasks, and inspects live and
historical execution state. Browser access is single-tenant and protected by
deployment infrastructure.

### 3.2 Agent Runtime

A long-running external daemon that authenticates using a machine credential,
advertises capabilities and capacity, polls for work, executes an assignment,
and reports ordered status. The milestone uses a deterministic fake Agent as
the reference implementation.

### 3.3 Samgita Maintenance Worker

Durable Oban jobs that expire missed start and execution deadlines, reap stale
leases, and make retryable Tasks available again.

## 4. Product Goals

### G-001 — Operational setup

An Operator can complete Agent registration, credential issuance, Project
authorization, Task creation, and result inspection through the browser UI
without direct database manipulation.

### G-002 — Reliable external execution

An authenticated Agent can connect, claim eligible work within its capacity,
report state, disconnect, reconnect, and resume valid work.

### G-003 — Exactly one valid active Attempt

A Task never has more than one database-valid active Attempt, and an Agent
never receives work beyond its effective capacity.

### G-004 — Deterministic idempotency

An identical replay of a committed protocol message returns the original
response and creates no duplicate transition, Attempt, receipt, or event.

### G-005 — Safe recovery

Lease expiry, start timeout, execution timeout, network loss, connection
replacement, Agent disablement, credential revocation, and Samgita restart do
not corrupt durable state.

### G-006 — Stale-result fencing

A stale connection, expired lease, old Attempt, or old fencing token cannot
change a Task or Attempt.

### G-007 — Operational visibility

The UI and API explain Agent presence and capacity, current execution state,
pending eligibility, progress, failures, Attempt history, and audit events.

### G-008 — Focused foundation

The repository contains the Agent Hub product and only the infrastructure it
needs at the first-milestone boundary.

## 5. User Stories

1. As an Operator, I want to register an Agent and issue a credential so that
   an external daemon can authenticate.
2. As an Operator, I want a credential shown exactly once so that I can
   provision an Agent without retaining plaintext secrets in Samgita.
3. As an Operator, I want to authorize an Agent for selected Projects so that
   it cannot claim work outside its scope.
4. As an Operator, I want to constrain Agent capabilities and concurrency so
   that assignments respect operational limits.
5. As an Operator, I want to create a Project Task and see why it is pending so
   that dispatch problems are diagnosable.
6. As an Agent, I want to poll for work and receive a durable assignment so
   that lost notifications do not lose Tasks.
7. As an Agent, I want accepted message responses replayed after transport loss
   so that retrying a request is safe.
8. As an Agent, I want reconnect reconciliation so that I can resume valid work
   and stop invalid work.
9. As an Operator, I want live progress and terminal results so that I can
   monitor execution.
10. As an Operator, I want immutable Attempt and event history so that failures
    and retries are auditable.
11. As an Operator, I want credentials revoked and Agents disabled immediately
    so that compromised or unhealthy runtimes cannot claim or renew work.
12. As a maintainer, I want a fake Agent to exercise the real WebSocket protocol
    so that CI does not require Synapsis or an LLM.

## 6. Scope Exclusions

The first milestone does not include:

- real Synapsis integration;
- operator cancellation or manual retry;
- GitHub Apps, issues, pull requests, reviews, merge, release, or deployment
  automation;
- generic workflows, DAGs, phases, swarms, or Agent-to-Agent communication;
- embedded/local Codex or Claude execution and provider adapters;
- memory retrieval, vector storage, or PRD orchestration;
- Agent-created child Tasks;
- multiple repositories per Project or logical Agent pools;
- artifact storage, binary upload, or streaming logs;
- automatic remote process provisioning;
- multi-tenant accounts, browser accounts, organizations, or browser RBAC;
- mTLS identity;
- fair-share or cost-aware scheduling; or
- data migration, backfill, or compatibility with the replaced product.

No milestone implementation may preemptively build these capabilities.

## 7. Domain Model and State Rules

### 7.1 Durable records

The domain consists of nine PostgreSQL tables in addition to Oban tables:

| Record | Responsibility |
|---|---|
| Project | Project identity and canonical unique `git_url` |
| Agent | Stable identity, enabled state, approved capabilities, and Operator concurrency limit |
| Agent Credential | Credential hash, display prefix, expiry, and revocation |
| Agent Connection | Connection history, negotiated capabilities/capacity, and heartbeat state |
| Project Agent | Unique explicit authorization and optional capability restriction |
| Task | Requested work, matching requirements, retry budget, availability, and current state |
| Task Attempt | Agent ownership, Attempt number, deadlines, lease, fence, result, and error |
| Protocol Receipt | Message identity/hash, Attempt sequence, and replayable response descriptor |
| Domain Event | Append-only transactional audit history |

All identifiers are UUIDs and all timestamps are UTC.

### 7.2 Task states

The only Task states are:

- `pending`: available now or after `available_at`, with no active Attempt;
- `assigned`: owned by one leased Attempt that has not started;
- `running`: owned by one running Attempt;
- `completed`: terminal successful result; and
- `failed`: terminal unsuccessful result.

Allowed Task transitions are:

```text
pending  -> assigned
assigned -> running
assigned -> pending | failed
running  -> pending | completed | failed
```

Returning to `pending` is automatic and occurs only when the terminated Attempt
is retryable and the Task has remaining Attempt budget.

### 7.3 Attempt states

The only Attempt states are:

- `leased`: assigned but not started;
- `running`: start was accepted by Samgita;
- `succeeded`: terminal successful result;
- `failed`: terminal Agent-reported failure; and
- `expired`: terminal deadline or lease expiry.

Allowed Attempt transitions are:

```text
leased  -> running | expired
running -> succeeded | failed | expired
```

Terminal Tasks and Attempts are immutable. State changes use server time.

### 7.4 Required uniqueness

Database constraints must enforce:

- one active connection per Agent;
- one Project-Agent binding per pair;
- one active Attempt per Task;
- unique Attempt number within a Task;
- unique non-null idempotency key within a Project;
- unique message ID within an Agent; and
- unique sequence number within an Attempt.

Transactions, not unique indexes alone, enforce legal transitions,
authorization, capacity, monotonically increasing Attempt/fencing numbers, and
terminal immutability.

## 8. Functional Requirements

### 8.1 Projects

#### FR-P001 — Create and update Project

The UI and API shall create and update a Project with a required name and
canonical `git_url`. `git_url` shall be unique after canonicalization.

#### FR-P002 — List and inspect Projects

The UI and API shall list Projects with bounded pagination and show bindings,
Task counts, active work, pending work, and recent failures for one Project.

#### FR-P003 — Delete empty Project

A Project may be deleted only when it has no Tasks or Project-Agent bindings.
Deletion with dependent history shall fail with a stable error and explain the
blocking dependency.

### 8.2 Agents

#### FR-A001 — Register Agent

The UI and API shall register an Agent with a required name, enabled state,
approved capabilities, and a positive maximum concurrency.

#### FR-A002 — Update Agent

The Operator may change an Agent's name, approved capabilities, and maximum
concurrency. A capacity reduction shall prevent new claims until active usage
falls below the new effective capacity; it shall not terminate an Attempt.

#### FR-A003 — Enable and disable Agent

The Operator may enable or disable an Agent. A disabled Agent cannot
authenticate, claim work, send accepted status, or renew leases. Disabling an
Agent invalidates its active connections; outstanding Attempts resolve through
their existing deadlines.

#### FR-A004 — Stable identity

An Agent ID shall remain stable across daemon restart, credential rotation, and
connection replacement.

#### FR-A005 — Derived runtime state

Agent reads shall include configured fields, online/offline state, last
heartbeat, current connection, effective capabilities, effective capacity,
active Attempt count, and remaining capacity.

### 8.3 Agent Credentials

#### FR-C001 — Issue credential

The Operator may issue multiple overlapping credentials for an Agent. The
successful creation response shall contain the plaintext token and display
prefix exactly once.

#### FR-C002 — Store only credential hash

Samgita shall store a secure token hash, display prefix, issue time, optional
expiry, and optional revocation metadata. Plaintext shall not be retrievable
after creation.

#### FR-C003 — Protect creation response

Credential creation responses shall use no-store cache headers. Plaintext shall
not enter logs, events, receipts, telemetry, or ordinary API reads.

#### FR-C004 — Authenticate credential

The Agent Socket handshake shall reject unknown, malformed, expired, revoked,
or mismatched credentials without creating an active connection or revealing
which credential check failed.

#### FR-C005 — Revoke credential

Revocation shall prevent new authentication and invalidate every active
connection authenticated with that credential. Its outstanding Attempts shall
expire normally without lease renewal.

### 8.4 Project-Agent Authorization

#### FR-B001 — Bind Agent to Project

The UI and API shall create one explicit binding between a Project and an
Agent. An unbound Agent shall never claim that Project's Tasks.

#### FR-B002 — Restrict capabilities

A binding may define allowed capabilities. An absent restriction imposes no
additional limit; an explicitly empty restriction permits no capability.

#### FR-B003 — Effective capabilities

Effective capabilities shall be the intersection of Operator-approved Agent
capabilities, capabilities reported by the active connection, and binding-
allowed capabilities when present.

#### FR-B004 — Change authorization safely

Binding create, update, and delete operations shall serialize with claims
through the affected Agent lock. Whichever operation obtains the lock first
determines claim eligibility. Authorization changes shall affect later claims
without rewriting historical Attempts.

### 8.5 Agent Connections

#### FR-CON001 — WebSocket transport

Samgita shall expose a Phoenix Channels endpoint for Agents. Machine
authentication is mandatory even when Operator API-key protection is disabled.

#### FR-CON002 — Bearer authentication

The daemon shall send its credential in the WebSocket handshake
`Authorization: Bearer` header. Credentials shall never be accepted from a
query string. A real WebSocket integration test must verify that the installed
transport exposes the header before the fake Agent fixture is frozen.

#### FR-CON003 — Identity-bound topic

Samgita shall authenticate the Agent before Channel join, and the joined topic
shall match the authenticated Agent identity.

#### FR-CON004 — Protocol version

The Channel shall support protocol version `1` and reject unsupported versions
with the stable `unsupported_version` error.

#### FR-CON005 — Hello required

Each new Channel shall send `agent.hello.v1` with a fresh message ID before any
heartbeat, work request, or Task message. Hello reports runtime information,
capabilities, positive capacity, and locally active Attempt IDs.

#### FR-CON006 — Welcome and reconciliation

A valid hello shall receive `agent.welcome.v1` containing connection identity,
server timing configuration, negotiated capabilities/capacity, and valid or
invalid Attempt reconciliation decisions.

#### FR-CON007 — Idempotent hello

Hello shall be receipt-backed. Repeating the same hello message ID on the same
Channel returns the same welcome without replacing the connection again.
Reusing an earlier Channel's hello message ID from a different Channel shall be
rejected.

#### FR-CON008 — One active connection

Only one connection may be active for a logical Agent. A newly committed valid
connection replaces the former connection, records the replacement in history,
and causes the old socket to close best-effort.

#### FR-CON009 — Current connection validation

Every post-hello message shall identify and match the Agent's current active
connection. Messages from replaced connections shall be rejected.

#### FR-CON010 — Heartbeat and presence

An Agent shall heartbeat at the configured interval. Accepted heartbeat
updates connection and Agent last-seen data. Online/offline is derived from the
last heartbeat threshold rather than stored as authoritative domain state.

#### FR-CON011 — Connection history

Samgita shall retain connection start, last-seen, end, authenticated credential,
and end reason for Operator inspection without exposing credential material.

### 8.6 Tasks

#### FR-T001 — Create Task

The UI and API shall create a Task with Project, title, description, type, JSON
payload, priority, required capabilities, timeout, maximum Attempts, and an
optional idempotency key. Title, description, and type are required; timeouts and Attempt
limits must be positive.

#### FR-T002 — Initial state

A valid Task shall start `pending` with `available_at` set to current server
time. Automatic retry is the only milestone behavior that moves it into the
future.

#### FR-T003 — Idempotent creation

Repeating Task creation with the same non-null `(project_id, idempotency_key)`
and the same canonical create input shall return the existing Task and shall not
create a second Task or creation event. Reusing that key with different
canonical create input shall return `idempotency_key_conflict` and change no
durable state.

#### FR-T004 — List and filter Tasks

Task reads shall support bounded pagination and filters for Project, state,
Agent, type, and creation time.

#### FR-T005 — Task detail

Task detail shall include current state, availability, pending reason, current
Agent/Attempt, progress, result or error, all Attempts, and chronological domain
events.

#### FR-T006 — Pending reasons

Samgita shall derive useful pending reasons including no authorized online
Agent, capability mismatch, exhausted capacity, future availability/retry
delay, and disabled eligible Agents. A pending reason is diagnostic and not an
authoritative Task state.

### 8.7 Dispatch and Capacity

#### FR-D001 — Pull claim

An Agent shall poll with `work.request.v1`. When no eligible work exists, the
response shall be successful and contain no assignment.

#### FR-D002 — Optional wake-up

After Task creation or automatic requeue, Samgita may push
`work.available.v1` to potentially eligible online Agents. Correctness shall
not depend on delivery; idle Agents poll.

#### FR-D003 — Effective capacity

Effective connection capacity is the minimum of the Operator maximum and the
positive capacity reported at hello. Claims count every active Attempt owned by
the Agent, including disconnected but unexpired work.

#### FR-D004 — Task eligibility

A Task is eligible only when it is pending, `available_at` is not in the future,
the Agent and connection are active, a Project-Agent binding exists, all
required capabilities are effective, and the Agent has free capacity.

#### FR-D005 — Deterministic ordering

Eligible Tasks shall be considered by higher priority first, then earlier
`available_at`, earlier creation time, and UUID. Null behavior and priority
range shall be fixed in the schema contract before implementation.

#### FR-D006 — Atomic bounded claim

A claim transaction shall lock the Agent row, validate its active connection
and capacity, and select one eligible Task using bounded
`FOR UPDATE SKIP LOCKED`. It shall recheck eligibility before assignment.

#### FR-D007 — Lock order

Transactions shall acquire locks in this order: Agent, related credential /
connection / binding rows, Task, then Attempt. Multiple rows at one level shall
be ordered by UUID. Authorization mutations and reaping shall use compatible
ordering.

#### FR-D008 — Create assignment

A successful claim shall atomically create a `leased` Attempt with the next
Attempt number and a fencing token greater than every prior fence for the Task,
transition the Task to `assigned`, append events, and commit the protocol
receipt.

#### FR-D009 — Commit before response

Samgita shall commit the Attempt, Task, events, and receipt before returning
`work.assignment.v1` or broadcasting state changes.

#### FR-D010 — Replay assignment

Repeating a committed work-request message shall return the same canonical
assignment. Its lease token shall be re-derived from immutable Attempt facts
and the referenced signing key rather than stored in the receipt.

### 8.8 Execution Status

#### FR-S001 — Start Task

`task.started.v1` is sequence `1`. A valid start shall atomically transition the
leased Attempt and assigned Task to `running`, establish the server execution
deadline, append events, and commit the receipt. The Agent shall wait for the
successful ACK before beginning execution.

#### FR-S002 — Report progress

`task.progress.v1` is valid only for a running current Attempt. Accepted
progress shall update the bounded latest-progress projection, append a bounded
progress event, and commit its receipt atomically.

#### FR-S003 — Deterministic progress rate limit

A valid progress message inside the configured minimum interval shall be
accepted as a no-op: it consumes the next sequence and commits a deterministic
receipt, but does not change the progress projection or append a progress event.

#### FR-S004 — Complete Task

`task.completed.v1` shall atomically transition the current running Attempt to
`succeeded` and its Task to `completed`, persist the bounded result, append
events, and commit the receipt when every ownership, lease, fence, connection,
state, and sequence check passes.

#### FR-S005 — Fail Task

`task.failed.v1` shall atomically transition the current running Attempt to
`failed`, persist the bounded error, classify retryability using server policy,
and either return the Task to delayed `pending` or terminate it as `failed`.

#### FR-S006 — Contiguous sequence

After start at sequence `1`, accepted Attempt messages shall use contiguous
increasing sequence numbers. A different message using an already consumed
sequence or a message that skips a sequence shall be rejected with a stable
error.

#### FR-S007 — Server authority

Agent source time and retry advice may be retained as bounded metadata but
shall not override server time, state, ownership, deadlines, fencing, or retry
classification.

### 8.9 Leases, Deadlines, Reconnect, and Automatic Retry

#### FR-R001 — Lease token

Each Attempt shall have an opaque HMAC-derived lease token bound to stable
Attempt, Task, Agent, fence, and signing-key-version facts. Only the token hash
and signing key identifier shall be stored in domain rows.

#### FR-R002 — Versioned signing keys

New Attempts shall use the configured current signing key. Retained prior keys
shall permit replay of earlier assignments. Signing material shall come from
runtime secrets and shall never enter source control, domain events, receipts,
logs, telemetry, or ordinary reads.

#### FR-R003 — Validate Attempt messages

Every Attempt-scoped message shall validate authenticated Agent, current
connection, Attempt ownership, current Task Attempt, lease token, fencing token,
lease time, relevant deadline, legal state, and sequence.

#### FR-R004 — Immediate expiry enforcement

Message handling shall reject expired ownership immediately using server time,
even when the maintenance worker has not yet persisted the expiry transition.

#### FR-R005 — Heartbeat renewal

Heartbeat shall renew leases only for submitted Attempts that remain valid and
owned by the Agent. Renewal shall never extend the start deadline or execution
deadline. The ACK shall classify each submitted Attempt as valid or invalid;
the Agent must stop invalid Attempts.

#### FR-R006 — Start deadline

A leased Attempt that does not start before its configured start deadline shall
expire even if heartbeats continue.

#### FR-R007 — Execution deadline

Execution timeout shall be measured from the server-accepted start time. A
running Attempt that reaches it shall expire.

#### FR-R008 — Durable expiry

An idempotent Oban job shall be scheduled every 60 seconds. Each execution shall
identify expired candidates without locks, then acquire locks in the canonical
order, revalidate state and server time, expire the Attempt, and either delay
the Task for another Attempt or fail it. Queue or database failures may delay
execution; message validation remains the immediate ownership guard.

#### FR-R009 — Retry budget and delay

A retryable failure or expiry consumes one Attempt. When budget remains, the
Task returns to `pending` with delay after Attempt `n` equal to
`min(5 * 2^(n-1), 60)` seconds. Exhausting the configured maximum ends the Task
as `failed`.

#### FR-R010 — Retry classification

Validated invalid-input and unsupported-task errors are non-retryable.
Execution errors, unknown execution errors, lease expiry, start timeout, and
execution timeout are retryable while budget remains. Agent retry advice is
advisory only.

#### FR-R011 — Reconnect reconciliation

A replacement connection's hello shall reconcile locally active Attempt IDs
against PostgreSQL. Valid unexpired work shall be rebound transactionally to
the replacement connection without creating an Attempt; invalid work shall
receive `attempt.stop.v1` instructions.

#### FR-R012 — Safe assignment resume

An Agent shall deduplicate assignments locally. Before starting or resuming a
replayed assignment, it shall confirm current ownership through fresh hello or
heartbeat reconciliation.

#### FR-R013 — Stale result rejection

A replaced connection, terminal/expired/non-current Attempt, invalid lease
token, or fencing token lower than the Task's current fence shall never produce
a successful Task transition.

### 8.10 Protocol Envelope and Receipts

#### FR-I001 — Canonical wire contract

Before parallel implementation begins, version-controlled protocol schemas and
fixtures shall define every inbound/outbound message, required field, type,
UUID/integer constraint, response form, payload bound, and stable error code.

#### FR-I002 — Message set

Protocol version `1` supports these inbound messages:

- `agent.hello.v1`
- `agent.heartbeat.v1`
- `work.request.v1`
- `task.started.v1`
- `task.progress.v1`
- `task.completed.v1`
- `task.failed.v1`

It supports these outbound messages:

- `agent.welcome.v1`
- `work.available.v1`
- `work.assignment.v1`
- `attempt.stop.v1`
- `ack.v1`
- `error.v1`

#### FR-I003 — Envelope fields

Every inbound message shall carry version, message ID, type, and payload. Every
post-hello message shall carry connection ID. Attempt messages shall also carry
Attempt ID, lease token, fencing token, and sequence.

#### FR-I004 — Payload bounds

Samgita shall reject a message larger than the configured maximum before
domain processing. Result, error, progress, metadata, and audit projections
shall each have explicit bounds in the wire/schema contract.

#### FR-I005 — Transactional receipt

Each successfully handled inbound message shall commit a protocol receipt with
its Agent, message ID, canonical payload hash, and secret-free response
descriptor in the same transaction as its state and events.

#### FR-I006 — Identical replay

After authenticating the connection, Samgita shall replay the response for an
identical committed message before checking mutable Attempt state or current
lease validity. Replay shall preserve the original resulting states and event
IDs and shall not mark the ACK as a duplicate.

#### FR-I007 — Conflicting message ID

Reuse of an Agent message ID with a different canonical payload shall return
`message_id_conflict` and shall not change durable state.

#### FR-I008 — Terminal response replay

A completion/failure response shall remain replayable after its Attempt becomes
terminal. A historical response proves past processing but does not grant
current execution permission.

#### FR-I009 — Failure atomicity

An unexpected transaction failure shall commit no success receipt, state
change, or event and shall return a retryable generic error without stack trace
or secret detail.

#### FR-I010 — Stable errors

Expected failures shall use centralized stable codes including at least
`unauthorized`, `invalid_envelope`, `unsupported_version`, `message_id_conflict`,
`out_of_order`, `lease_expired`, `stale_fence`, and `illegal_transition`.

### 8.11 Domain Events and Audit

#### FR-E001 — Append-only audit

Every accepted state-changing Operator command and Agent message shall append
one or more versioned, append-only domain events.

#### FR-E002 — Same transaction

Aggregate state, domain events, and any protocol receipt shall commit in one
database transaction.

#### FR-E003 — Persist before publish

PubSub notification shall occur only after commit. Losing PubSub messages shall
not lose state; subscribers reconstruct state from PostgreSQL.

#### FR-E004 — Correlation

Task and Attempt lifecycle events shall share a correlation identifier and
record server time, actor identity/type, event type/version, and an allowlisted
payload.

#### FR-E005 — Secret-free payload

Event payloads shall be constructed from an allowlist and shall never copy raw
protocol bodies, credentials, lease tokens, signing material, or stack traces.

#### FR-E006 — Bounded progress audit

Accepted progress outside the minimum interval may append bounded progress
metadata. Routine heartbeat and rate-limited no-op progress shall not append
domain events.

#### FR-E007 — Milestone retention

Connections, Attempts, receipts, and domain events shall have no automatic
deletion in this milestone so replay and audit behavior have no hidden cutoff.

### 8.12 Operator REST API

#### FR-API001 — Protected administration

Operator REST endpoints shall use the retained API-key authentication and rate-
limit pipeline and return JSON with stable machine-readable errors and
validation details.

#### FR-API002 — Project resources

The API shall provide Project create, list, show, update, and safe-delete
operations, plus Project binding and Task reads.

#### FR-API003 — Agent resources

The API shall provide Agent create, list, show, update, enable, and disable
operations, including derived connection and capacity state.

#### FR-API004 — Credential resources

The API shall provide credential issue, metadata list, and revoke operations.
Only issue may return plaintext, and that response shall be no-store.

#### FR-API005 — Binding resources

The API shall provide Project-Agent binding create, list, update, and delete
operations with optional capability restrictions.

#### FR-API006 — Task resources

The API shall provide Task create, list, and show operations plus Attempt and
event history. It shall not expose controls for excluded Task operations.

#### FR-API007 — API parity

The API and UI shall invoke the same core context commands and reads; neither
shall contain separate transition or authorization logic.

### 8.13 Operator LiveViews

#### FR-UI001 — Dashboard

The Dashboard shall show connected Agents, active work, pending work, and recent
failures using durable queries and post-commit PubSub refresh.

#### FR-UI002 — Project journey

The Operator shall be able to create, edit, list, inspect, and safely delete
Projects, manage bindings, create Project Tasks, and inspect Project work.

#### FR-UI003 — Agent journey

The Operator shall be able to register, edit, enable, disable, list, and inspect
Agents, including capability/capacity configuration, connection history,
bindings, and current/recent Attempts.

#### FR-UI004 — Credential journey

The Agent detail view shall issue and revoke credentials, display non-secret
credential metadata, and present a new plaintext credential exactly once with
a clear non-recoverability warning.

#### FR-UI005 — Task creation

The Task form shall expose Project, title, description, type, JSON payload,
priority, required capabilities, timeout, maximum Attempts, and optional
idempotency key with visible validation.

#### FR-UI006 — Task detail

The Task view shall update after post-commit notifications and show current
state, pending reason, Agent, Attempt number, deadlines/lease expiration,
progress, result/error, immutable Attempt history, and audit timeline.

#### FR-UI007 — Durable reconnect

A LiveView reconnect or refresh shall reconstruct all displayed state from
PostgreSQL rather than socket or process memory.

#### FR-UI008 — Operational design

LiveViews shall use existing DuskMoon layout conventions, responsive forms and
tables, accessible labels, visible errors, useful empty states, and bounded
pagination. No additional UI library shall be introduced.

## 9. Non-Functional Requirements

### 9.1 Durability and Consistency

#### NFR-DUR001

A committed Project, Agent, Task, Attempt, connection, receipt, or event shall
survive process/node restart.

#### NFR-DUR002

Samgita shall recover authoritative execution state from PostgreSQL, not
Channel, LiveView, PubSub, or ETS process memory.

#### NFR-CONS001

Task and current Attempt states shall never contradict after a committed
transition.

#### NFR-CONS002

Concurrency tests shall demonstrate one active Attempt per Task and capacity
enforcement using independent database transactions and real locks.

#### NFR-CONS003

Renewal, reconnect, Agent/authorization changes, claims, status transitions,
and reaping shall use compatible lock order and revalidate after locking.

### 9.2 Security

#### NFR-SEC001

Agent Socket authentication is mandatory and independent of Operator API
configuration.

#### NFR-SEC002

Credential comparison shall be resistant to timing disclosure, authentication
failures shall be rate-bounded, and error responses shall not distinguish
secret-verification details.

#### NFR-SEC003

An Agent shall be unable to claim an unauthorized Project, exceed effective
capacity, act on another Agent's Attempt, or use an old connection or fence.

#### NFR-SEC004

Credentials, lease tokens, signing keys, and raw secret-bearing messages shall
not appear in logs, telemetry, receipts, domain events, or ordinary API/UI
reads.

#### NFR-SEC005

Runtime shall validate that a current lease-signing key exists and that every
key identifier required for supported replay resolves to configured secret
material.

#### NFR-SEC006

Fencing protects Samgita's accepted state only. Product documentation shall
state that disconnected execution can repeat external side effects and that
future integrations require their own idempotency/fencing contract.

### 9.3 Performance and Availability

#### NFR-PERF001

Dispatch shall use indexed eligibility predicates and bounded locking. It shall
not scan or lock the complete pending queue or all Agents for one claim.

#### NFR-PERF002

List and detail reads shall use bounded pagination and batched queries/preloads
without per-record N+1 query patterns.

#### NFR-PERF003

With 100 connected Agents and 1,000 pending Tasks on the recorded benchmark
environment, warmed work requests shall complete at p95 within 500 ms excluding
network latency and with no claim, capacity, or fencing invariant violation.
The environment and results shall be retained with the verification evidence.

#### NFR-AVL001

Loss of a wake-up or PubSub notification shall not lose a Task or accepted
transition.

#### NFR-AVL002

The fake Agent shall reconnect without Operator action after transient network
loss or server restart.

### 9.4 Observability

#### NFR-OBS001

Connection, authentication, claim, transition, expiry, automatic retry,
duplicate replay, conflict, rejection, and maintenance activity shall emit
telemetry without secret payloads.

#### NFR-OBS002

Logs shall carry correlation, Agent, Task, Attempt, and connection identifiers
where relevant while excluding secrets and raw payloads.

#### NFR-OBS003

The Operator shall be able to determine why a Task is pending or failed and why
an Attempt expired or was rejected.

### 9.5 Maintainability and Testability

#### NFR-MNT001

Channel, controller, and LiveView callbacks shall remain transport/presentation
adapters. Core contexts and pure modules shall own state transitions, matching,
protocol validation, and retry calculations.

#### NFR-MNT002

The application dependency direction shall remain `samgita_web -> samgita`.

#### NFR-MNT003

Protocol message names, schemas, and error codes shall be centralized and
version controlled.

#### NFR-TST001

CI shall exercise the complete protocol with a deterministic fake Agent over a
real WebSocket connection. No LLM or external Agent service is required.

#### NFR-TST002

Pure tests shall cover every allowed/forbidden state transition, capability
intersection, retry calculation, and protocol validation rule.

#### NFR-TST003

Database tests shall cover constraints, atomic rollback, Task idempotency,
capacity, locks, and concurrency races.

#### NFR-TST004

UI and API tests shall assert observable behavior through public surfaces rather
than private implementation details.

## 10. Configuration Defaults

| Configuration | Default |
|---|---:|
| Protocol version | `1` |
| Current lease-signing key | Required runtime secret |
| Agent heartbeat interval | 15 seconds |
| Offline threshold | 45 seconds |
| Lease duration | 120 seconds |
| Start deadline | 20 seconds after claim |
| Execution timeout | 900 seconds after accepted start |
| Maximum Attempts | 3 total Attempts |
| Automatic retry delay | `min(5 * 2^(n-1), 60)` seconds |
| Progress minimum interval | 2 seconds |
| Maximum protocol message | 256 KiB |
| Agent maximum concurrency | 1 |
| Maintenance enqueue cadence | Every 60 seconds |

Configuration belongs in runtime/application config and shall be validated at
startup where practical. Tests may override timing without changing production
semantics.

## 11. Acceptance Scenarios

### AS-001 — Complete UI-to-Agent journey

**Given** a fresh database

**When** an Operator uses the UI to create a Project, register an Agent, issue a
credential, create a binding and Task, and the fake Agent connects and executes
it

**Then** the Operator sees progress, terminal result, Attempt history, and audit
events without direct database manipulation.

### AS-002 — Protect one-time credential

**Given** an Operator issues a credential

**When** the creation response has completed

**Then** plaintext cannot be retrieved through the database, logs, events,
receipts, telemetry, API, or UI, and the original response used no-store
headers.

### AS-003 — Reject invalid credential

**Given** an unknown, expired, revoked, malformed, or incorrect credential

**When** a daemon attempts a WebSocket handshake

**Then** authentication fails, no active connection is created, and no secret
or verification detail is exposed.

### AS-004 — Replace connection and reconcile

**Given** an Agent has an active connection and valid unexpired Attempt

**When** a new authenticated Channel sends a fresh hello

**Then** the new connection becomes current, the old socket is invalidated, the
Attempt is rebound without creating another Attempt, and the Agent receives its
resume decision.

### AS-005 — Enforce authorization and capabilities

**Given** a pending Task

**When** an unbound Agent or an Agent missing one required effective capability
requests work

**Then** no assignment is returned and no Attempt is created.

### AS-006 — Claim once under contention

**Given** one eligible pending Task and two eligible Agents

**When** both claim concurrently in independent database transactions

**Then** exactly one assignment is returned and exactly one active Attempt
exists.

### AS-007 — Enforce one Agent slot

**Given** an Agent with effective capacity one and two eligible Tasks

**When** two work requests race

**Then** at most one active Attempt is owned by that Agent.

### AS-008 — Replay lost assignment response

**Given** an assignment transaction committed but its response was lost

**When** the Agent repeats the identical work-request message

**Then** Samgita returns the same assignment and re-derived lease token without
creating another Attempt or event.

### AS-009 — Replay terminal status

**Given** completion committed and its ACK was lost

**When** the identical completion is replayed after the Attempt is terminal

**Then** the original ACK, resulting states, and event IDs are returned without
another transition or event.

### AS-010 — Reject conflicting message

**Given** a message ID already has a committed receipt

**When** the Agent reuses it with different content

**Then** Samgita returns `message_id_conflict` and changes no durable state.

### AS-011 — Consume throttled progress sequence

**Given** a running Attempt recently accepted progress

**When** valid next-sequence progress arrives inside two seconds

**Then** its deterministic no-op receipt commits and sequence is consumed, but
progress and events are unchanged and the following contiguous completion can
succeed.

### AS-012 — Expire missed start

**Given** a leased Attempt continues heartbeating but does not start within 20
seconds

**When** it sends an Attempt message before maintenance has persisted expiry

**Then** Samgita rejects the message as expired without committing that message
or a success receipt; when the scheduled maintenance job executes, it persists
the expired Attempt and delays the Task as pending when budget remains or fails
the Task when budget is exhausted.

### AS-013 — Expire, reassign, and fence

**Given** Attempt 1 expires and the Task is later claimed as Attempt 2

**When** Attempt 1 sends a terminal result

**Then** Samgita rejects it and leaves Attempt 2 and the Task unchanged.

### AS-014 — Classify automatic retry

**Given** a running Attempt fails

**When** the error is an execution error and budget remains

**Then** the Attempt becomes failed and the Task returns to pending using the
specified backoff; an invalid-input or unsupported-task error instead makes the
Task failed immediately.

### AS-015 — Revoke credential during work

**Given** an Agent has a connection and active Attempt

**When** the authenticating credential is revoked

**Then** the connection is invalidated, no further message or lease renewal is
accepted, and the Attempt resolves through expiry without state corruption.

### AS-016 — Recover after Samgita restart

**Given** an active Attempt is durably committed

**When** Samgita restarts and the fake Agent reconnects before expiry

**Then** hello reconciliation recovers and rebinds the Attempt from PostgreSQL
without creating another Attempt.

### AS-017 — Roll back atomically

**Given** a forced database error during a protocol transition

**When** its transaction rolls back

**Then** Task, Attempt, event, and receipt state remain unchanged, no success is
broadcast, and the Agent receives a retryable generic error.

### AS-018 — Boot clean release

**Given** the release artifact and an explicitly named fresh database

**When** migrations run and the release boots

**Then** health, UI, API, WebSocket transport, assets, Repo, and Oban start
without any removed application, pgvector, Horde, provider, or external LLM.

## 12. Verification Gates

1. Canonical state tables, wire schemas, fixtures, and lock order are reviewed
   before parallel implementation.
2. Fresh migrations and all database constraints pass on an explicitly named
   empty test/development database. No existing database is inferred as safe to
   delete.
3. Pure unit tests cover transitions, matching, retry, and protocol parsing.
4. Database tests prove state/event/receipt atomicity and Task creation
   idempotency.
5. Independent-transaction race tests cover one-Task contention, one-Agent-slot
   contention, connection replacement, authorization versus claim, and renewal
   versus reaping.
6. Fake Agent tests use the real WebSocket handshake and cover header auth,
   hello, complete execution, no-op progress, duplicate/conflicting messages,
   lost assignment/ACK, reconnect, expiry, stale fencing, revocation, and
   restart recovery.
7. UI/API tests cover Project and Agent management, authorization, Task
   creation, progress/result inspection, validation, one-time secret behavior,
   API protection, and rate limiting.
8. Browser verification demonstrates the full Operator journey and responsive,
   accessible layouts.
9. Assets build, fresh-database migration, and the two-application release build
   and boot successfully.
10. A final repository scan confirms excluded product routes, modules,
    configuration, dependencies, migrations, tests, and documentation are
    absent.

Checks run at the scope of each delivery slice. Unrelated failures are reported
without unrelated repair.

## 13. Success Metrics

The milestone succeeds when:

1. The UI and fake Agent complete AS-001 without database manipulation or an
   external service.
2. Repeated identical messages produce no duplicate Attempt, transition,
   receipt, or event.
3. Every concurrent claim test produces one active Attempt for one Task and
   never exceeds Agent capacity.
4. Every stale-fence test rejects the old executor without changing current
   state.
5. Reconnect and restart recovery preserve valid work without a duplicate
   Attempt.
6. Operators can diagnose current Agent state, Task eligibility, progress,
   failure, automatic retry, and Attempt history through UI and API.
7. Secret scans find no plaintext credential, token, or signing key in durable
   rows, logs, telemetry, or ordinary responses.
8. The rebuilt release starts from a fresh database with exactly the two scoped
   applications and no external LLM requirement.

## 14. Definition of Done

Agent Hub first milestone is complete only when all are true:

- [ ] The repository contains a bootable `samgita` and `samgita_web` Agent Hub
      system and no unused replaced-product scaffolding.
- [ ] Fresh migrations create the nine domain tables, required indexes and
      constraints, and Oban infrastructure.
- [ ] Project, Agent, credential, binding, and Task contexts satisfy their
      requirements through UI and API.
- [ ] The authenticated version-1 Channel satisfies the frozen wire fixtures.
- [ ] Atomic claim, capacity, lease, fencing, deadlines, and automatic retry
      satisfy the state model.
- [ ] Status transitions, deterministic progress handling, receipts, ACK replay,
      and stable errors satisfy protocol tests.
- [ ] Replacement connection, reconnect reconciliation, Agent disablement,
      credential revocation, expiry, and restart recovery pass.
- [ ] Aggregate changes, receipts, and allowlisted domain events commit
      atomically and publish only after commit.
- [ ] The complete fake Agent journey passes over a real WebSocket without an
      LLM or Synapsis.
- [ ] Concurrency tests exercise real database locks and pass consistently.
- [ ] Operator UI and API expose the complete first-milestone journey and no
      excluded controls.
- [ ] Secret, payload-bound, authorization, API-protection, and rate-limit tests
      pass.
- [ ] Scoped format, static analysis, test, asset, migration, and release-build
      gates pass.
- [ ] The release boots against an explicitly named fresh database with no
      removed service or dependency requirement.
- [ ] The implementation stops at the first-milestone scope boundary.
