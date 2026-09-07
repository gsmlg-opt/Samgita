# Agent Hub clean-start rebuild design

Date: 2026-09-06

Status: Approved in full by the user on 2026-09-06. The primary PRD, architecture, and implementation plan expand this design into delivery contracts.

## Authority and scope

The user has confirmed that Samgita has never been used and will start with a fresh database. Agent Hub replaces the legacy product entirely, in this repository, with its Git history retained. Existing records require no migration or backward compatibility.

This decision supersedes the former legacy-preservation requirements. The current `prd.md`, `architecture.md`, `plan.md`, and `AGENTS.md` follow this clean-start scope.

The first milestone includes an operational UI and a fully tested protocol with a fake external reference agent. Real Synapsis integration follows separately.

## Application boundaries

Retain two umbrella applications:

- `samgita`: Repo, Projects, Agents, Tasks, Protocol, Events, and Oban maintenance workers.
- `samgita_web`: Endpoint, operator REST API, AgentSocket/AgentChannel, and DuskMoon LiveViews.

The web application depends on core. Core never depends on web. PostgreSQL owns durable state; PubSub carries post-commit notifications. Channel processes own only transient transport state. Pure modules implement transitions, matching, and retry calculations; transactions enforce authoritative changes.

Remove the provider and memory applications, local execution workers, PRD orchestration, Horde, provider sessions, health checks, swarms, phases, RARV, DAG execution, artifacts, snapshots, quality councils, legacy Codex app-server management, and their dedicated routes, assets, tests, configuration, dependencies, and documentation.

Retain and adapt reusable Phoenix/Ecto infrastructure, API protection, DuskMoon assets, development tooling, CI, and release packaging. Each retained component must serve Agent Hub; legacy product code must not remain as unused scaffolding.

## Durable model

There are nine domain tables, in addition to Oban's infrastructure tables:

| Table | Responsibility |
|---|---|
| projects | Project identity and canonical unique git_url |
| agents | Stable identity, enabled state, approved capabilities, concurrency limit |
| agent_credentials | Credential hashes, expiry, revocation, rotation overlap |
| agent_connections | Connection history, negotiated capabilities/capacity, heartbeat |
| project_agents | Unique explicit authorization and optional capability restriction |
| tasks | Requested work, priority, requirements, retry limit, current state |
| task_attempts | Ownership, attempt number, lease, fence, execution result/error |
| protocol_receipts | Message identity/hash, sequence, replayable response descriptor |
| domain_events | Append-only transactional audit history |

Use UUID identifiers and UTC timestamps. No legacy execution mode, legacy agent_id, old migrations, or backfills survive. Fresh migrations create only the new domain and required infrastructure.

Task states: `pending`, `assigned`, `running`, `completed`, `failed`.

Attempt states: `leased`, `running`, `succeeded`, `failed`, `expired`.

Claim creates a leased Attempt and assigns its Task. Start makes both running. Completion succeeds the Attempt and completes the Task. Failure or expiry terminates the Attempt; retryable work returns to pending with an availability time, otherwise its Task becomes failed. Terminal Attempts remain immutable. Cancellation and manual retry are deferred from the first milestone as approved with the reduced state model.

Database uniqueness constraints enforce one active connection per Agent, one binding per Project-Agent pair, one active Attempt per Task, unique per-Task Attempt numbers, per-Project Task idempotency keys, per-Agent message IDs, and per-Attempt sequence numbers.

Transactions additionally enforce legal transitions, monotonically increasing fencing/Attempt numbers, terminal immutability, authorization, and capacity. These behavioral properties are not claimed to follow from unique indexes alone.

## Claims and capacity

A claim locks the Agent row to serialize concurrent requests for its capacity, validates the active connection, locks an eligible Task with bounded `FOR UPDATE SKIP LOCKED`, and rechecks authorization and eligibility before assignment. Authorization changes use compatible locking so they cannot race a successful claim.

Effective capacity is the minimum of the operator limit and the positive capacity reported at hello. Effective capabilities intersect operator-approved, connection-reported, and binding-allowed capabilities; an absent binding restriction adds no restriction, while an empty restriction permits none.

Claims count all active Attempts for that Agent, including disconnected but unexpired work. Capacity reductions prevent further claims until usage falls below the new limit. The lock order is Agent, credential/connection/binding rows, Task, then Attempt; multiple rows at a level are ordered by UUID. Reaping selects candidate IDs without locks, then takes locks in this order and revalidates. Changes to Project authorization serialize through the affected Agent rows before binding updates. Concurrent Project deletion is governed by foreign keys and the no-dependent-history rule.

Persist the Attempt, Task transition, audit events, and receipt in one transaction. Commit before returning the assignment or broadcasting. PubSub wake-ups are optional for correctness; agents poll for work when idle.

## Protocol

Use Phoenix Channels over WebSocket with mandatory machine authentication. The daemon supplies the credential in an Authorization Bearer header during the handshake. Verify the installed transport's header access using a real WebSocket test before freezing the client fixture. Never put credentials in query strings.

Authenticate identity before channel join; the topic must match that identity. Require hello before work/status messages. Every subsequent message must match the active connection.

Hello is a receipt-backed message. Repeating its message ID on the same channel returns the same welcome and does not replace the connection again. Each newly established channel sends a fresh hello message ID; reusing an old hello from a different channel is rejected. This prevents a reconnect from replaying a welcome for a dead transport.

Inbound messages: `agent.hello.v1`, `agent.heartbeat.v1`, `work.request.v1`, `task.started.v1`, `task.progress.v1`, `task.completed.v1`, `task.failed.v1`.

Outbound messages: `agent.welcome.v1`, `work.available.v1`, `work.assignment.v1`, `attempt.stop.v1`, `ack.v1`, `error.v1`.

Envelope fields include version, message_id, type, connection_id after hello, optional attempt_id and sequence, and payload. Attempt messages carry the lease token and fencing token. Task start uses sequence 1; subsequent accepted Attempt messages use contiguous increasing sequences. Connection-level messages have no Attempt sequence.

Canonical schemas and fixtures must define required fields, UUID/integer validation, response forms, and stable error codes before parallel implementation. Authenticate the connection before receipt replay; for an identical previously committed message, replay its response before checking mutable Attempt state or current lease validity. A completed message must remain replayable after its Attempt becomes terminal.

Identical messages return the same ACK, including original resulting states and event IDs. Do not change an ACK field to indicate a duplicate; expose duplicate processing through telemetry instead. Conflicting message IDs return `message_id_conflict`. Receipts store secret-free response descriptors; assignment tokens are re-derived when needed. Historical ACKs are evidence of past processing, not current execution permission. The Agent deduplicates assignments locally, reconciles on every reconnect through hello, and checks replayed assignment ownership through a fresh heartbeat before starting/resuming execution. Heartbeat responses explicitly identify valid and invalid submitted Attempts; invalid entries require stopping. An Agent also waits for a successful start ACK before first execution.

Progress messages arriving inside the minimum interval are accepted as no-ops: consume their sequence and commit a deterministic receipt, but do not update progress or append a progress event. This preserves contiguous sequencing for subsequent completion/failure messages.

Expected failures use stable error codes such as unauthorized, invalid_envelope, unsupported_version, out_of_order, lease_expired, stale_fence, and illegal_transition. Unexpected transaction failures produce a retryable generic error without committing a success receipt. Error responses must never expose stack traces or secrets.

## Leases, reconnect, and retries

Defaults: heartbeat every 15 seconds, offline after 45 seconds, lease duration 120 seconds, start deadline 20 seconds, execution timeout 900 seconds, three total Attempts, progress at most once every two seconds, and maximum message size 256 KiB. Durable maintenance is scheduled every 60 seconds; queue or database outages may delay execution. Message validation rejects expired ownership immediately even before maintenance runs.

Offline presence alone does not release ownership. Heartbeats renew only valid Attempts and never extend their execution deadline. A leased Attempt that misses its start deadline expires even if heartbeats continue. Execution timeout is measured from the server-accepted start time.

Replacement connections invalidate old sockets. Hello reconciles outstanding Attempt IDs against PostgreSQL: valid unexpired work is rebound transactionally to the replacement connection without creating a new Attempt; invalid work receives stop instructions. Renewal and reaping serialize against the same Attempt state using server time.

Retryable failures and expiry consume an Attempt. Retry delay after Attempt n is min(5 * 2^(n-1), 60) seconds; the Task remains pending but unclaimable until available_at. Samgita owns retry classification: validated invalid-input/unsupported-task errors are non-retryable; execution errors, unknown errors, and expiry are retryable within the configured budget. Any Agent retryability flag is advisory and cannot override server policy. Exhausting the configured limit ends the Task as failed. No separate dead-letter state is needed in this milestone.

Use a versioned signing key identifier on each Attempt. New Attempts use the current key; retained prior keys allow replay of earlier assignments. Tokens derive from stable Attempt facts rather than the replaceable connection ID. Store only credential/token hashes and secret-free descriptors. Runtime signing keys never enter source control or domain rows.

Fencing protects Samgita's accepted state. It cannot guarantee that a disconnected executor stops external side effects; execution is potentially repeated, and future integrations need their own idempotency/fencing contracts.

## Operator UI and API

The first milestone provides the entire setup and execution journey through DuskMoon LiveViews:

- Dashboard: connected Agents, active work, pending work, recent failures.
- Projects: create/edit/list/detail, bindings, and project Tasks. Deletion is allowed only without Tasks or bindings; reject deletion with dependent history.
- Agents: register/edit/enable/disable, approved capabilities/capacity, connection history, credential issue/revoke with one-time secret display.
- Task creation: Project, title, description, type, payload, priority, required capabilities, timeout, maximum Attempts, optional idempotency key.
- Task detail: current state, Agent, progress, result/error, Attempt history, and audit timeline.

Use existing DuskMoon layout conventions, responsive forms/tables, visible validation, accessible labels, empty states, and bounded pagination. Display useful pending reasons such as no authorized online Agent, capability mismatch, exhausted capacity, or retry delay. No nonfunctional cancellation/retry controls are shown.

REST exposes the same context commands and reads as the UI under existing API-key protection and rate limits. Browser access remains infrastructure-protected and single-tenant. PubSub refreshes read from PostgreSQL; reconnecting a LiveView reconstructs its state from durable queries.

## Security and audit

Agent credentials are shown once, stored hashed, and excluded from logs, events, receipts, telemetry, and ordinary API reads. Credential responses use no-store headers. Revocation invalidates connections authenticated with that credential; disabling an Agent invalidates all its connections and prevents work/renewals. Outstanding Attempts then expire normally.

Apply a payload allowlist to audit events rather than copying protocol bodies. Record lifecycle changes and bounded progress metadata; do not append routine heartbeat events. Keep protocol receipts and history for the milestone without automatic deletion so replay guarantees have no hidden retention cutoff. Add an explicit storage/retention policy before broader production use.

## Safe removal and delivery sequence

1. Reconcile the three primary docs and AGENTS.md with this replacement scope. Freeze wire fixtures, state transitions, schema fields, and lock ordering.
2. Create an isolated worktree under `.trees/codex/agent-hub-rebuild` from the current local HEAD, preserving the existing documentation commit. Record a tracked-file removal/retention inventory.
3. Replace the legacy application graph, routes, config, migrations, and tests with a bootable two-app foundation. Remove dedicated legacy dependencies and release entries in the same bounded change. Verify compile, empty-database migration, health route, and asset build.
4. Build Agents, Projects, bindings, credentials, Tasks, constraints, and audit contexts with focused tests.
5. Build atomic claims, deadlines, fencing, receipts, and the authenticated protocol alongside the fake Agent harness. Prove a complete Task and recovery before expanding UI behavior.
6. Complete operator LiveViews and APIs; demonstrate registration through result inspection without direct database manipulation.
7. Run integrated protocol, race, restart, UI, asset, and release-build gates; scan for legacy references and unused dependencies. Stop at the first milestone boundary.

Independent pure logic, protocol fixtures, and UI components may be delegated after their shared contracts are fixed. One owner controls migrations and shared configuration. Use small logical commits. Actual PR publication, pushing, or deployment is outside this planning task.

The clean-start decision does not identify a database to drop. Build against an explicitly named fresh test/development database; never infer permission to delete a database from an environment variable. Retain the old implementation in Git history rather than in archive directories inside the new source tree.

## Verification gates

- Pure tests cover every allowed/forbidden transition, capabilities, retry timing, and protocol validation.
- Database tests prove uniqueness, atomic rollback of state/events/receipts, task idempotency, and capacity enforcement.
- Concurrent tests use independent database transactions to exercise real locks: competing claims for one Task, competing claims for one Agent slot, connection replacement, and renewal versus reaping.
- Fake Agent tests use a real Phoenix WebSocket transport and cover handshake headers, complete execution, duplicate/conflicting messages, lost assignment/ACK, reconnect, expiry, stale fence, revocation, and restart recovery.
- Fake Agent execution is deterministic and invokes no LLM. Keep transport fixtures reusable for a later Synapsis implementation.
- UI/API tests exercise registration, binding, task creation, progress/results, validation, one-time secret behavior, and authorization. Browser verification covers the full operator journey and responsive layout.
- Build assets and release packaging with only the two applications. Verify a fresh database can migrate and the release can boot with no provider, memory Repo, pgvector, or Horde requirement.
- Run checks scoped to each delivery slice. Report unrelated failures without attempting unrelated repairs. Final whole-rebuild checks cover the replacement system and verify that obsolete routes/modules/configuration are absent.

## First milestone completion

A user can register and authorize a fake external Agent through the UI, create work, observe progress and terminal results, inspect Attempt history, and recover correctly from duplicate messages, disconnect, lease expiry, and Samgita restart. A stale Agent cannot commit a result. The repository contains only Agent Hub product code and the infrastructure it needs.

Real Synapsis, cancellation/manual retry, GitHub integration, workflows, embedded execution/providers, memory retrieval, multitenancy, browser accounts, and artifact storage remain outside this milestone.
