# Samgita Agent Hub Phase 1 Architecture

**Status:** Implementation specification  
**Target repository:** `gsmlg-opt/Samgita`  
**Target path:** `docs/agent-hub-v1/architecture.md`  
**Audience:** Codex and maintainers implementing the first Agent Hub vertical slice  
**Scope:** Agent connection, project association, task creation, task dispatch, and agent-driven task status updates

---

## 1. Executive Summary

Samgita Phase 1 introduces a durable control protocol between Samgita and long-running external agent runtimes such as Synapsis.

The phase establishes one complete execution loop:

```text
operator creates agent
  -> agent connects to Samgita
  -> operator creates project
  -> operator binds agent to project
  -> operator creates task
  -> agent requests work
  -> Samgita creates a leased task attempt
  -> agent accepts and starts the attempt
  -> agent reports progress
  -> agent completes or fails the attempt
  -> Samgita updates authoritative task state
```

Samgita remains the control plane and source of truth. The connected agent runtime performs work but never directly controls task state. It submits protocol messages; Samgita validates them and applies legal state transitions inside database transactions.

This phase does not replace the existing PRD-driven orchestrator. Existing tasks and local `Samgita.Agent.Worker` execution remain on the legacy path. New Agent Hub tasks are explicitly isolated with `Task.execution_mode = :agent_hub`.

---

## 2. Context

The repository already contains the main building blocks needed for the control plane:

- PostgreSQL and Ecto for durable state.
- Oban for persistent asynchronous work.
- Phoenix PubSub and LiveView for real-time operational views.
- Horde for distributed local process registration and supervision.
- Existing `Project`, `Task`, `AgentRun`, artifacts, and orchestration modules.
- A Synapsis provider adapter for outbound LLM/session calls.
- A legacy local agent worker based on `:gen_statem`.

Those components solve local orchestration, but they do not provide a durable protocol for independently running agents. The current `AgentTaskWorker` locates or starts a local worker and synchronously waits for completion. That model cannot safely support remote processes, disconnections, duplicate messages, delayed results, or task reassignment.

Phase 1 adds the missing control-plane primitives without rewriting the current system.

### 2.1 Existing concepts that remain unchanged

- `Samgita.Domain.Project` remains the project aggregate.
- `git_url` remains the canonical project identifier in this phase.
- `Samgita.Project.Orchestrator` and its fixed SDLC phases remain available.
- `Samgita.Agent.Worker` remains the legacy local RARV worker.
- `Samgita.Domain.AgentRun` remains a legacy local worker/run metric record.
- `SamgitaProvider.Synapsis` remains an outbound provider adapter. It is not the Agent Hub transport.
- `Samgita.Events` remains the PubSub/webhook broadcasting facade.

### 2.2 New concepts

- Registered Agent identity.
- Agent credential and connection session.
- Explicit Project-Agent association.
- Agent Hub task execution mode.
- Task Attempt separated from logical Task.
- Lease and fencing token.
- Versioned Agent Protocol over Phoenix Channels.
- Durable inbound-message deduplication.
- Append-only domain event audit journal.

---

## 3. Goals and Non-Goals

### 3.1 Goals

1. Allow an operator to create and manage registered agents.
2. Allow a long-running Synapsis daemon to authenticate and maintain a WebSocket connection.
3. Allow an operator to bind selected agents to a project.
4. Allow an operator or API client to create Agent Hub tasks.
5. Match tasks to connected agents by project authorization, capabilities, and capacity.
6. Atomically lease tasks so no task has two valid active attempts.
7. Accept idempotent status messages from an agent.
8. Recover safely from agent disconnection, Samgita restart, retries, and duplicate messages.
9. Reject stale completion messages after a task has been reassigned.
10. Expose task, attempt, connection, and event state through API and LiveView.
11. Preserve the current PRD orchestration path.

### 3.2 Non-goals

Phase 1 does not implement:

- GitHub Issue ingestion.
- Repository synchronization beyond the existing project `git_url` behavior.
- Branch, worktree, commit, or pull request lifecycle.
- Multi-step workflow definitions.
- Agent-to-agent delegation.
- Automated review, merge, or release.
- General-purpose event sourcing.
- Kafka, NATS, or another external message broker.
- Browser user accounts or a multi-tenant permission model.
- OpenClaw-compatible gateway or channel protocols.
- Automatic management of remote agent processes.
- Large binary artifact transfer over the Agent Protocol.

---

## 4. Architectural Principles

### 4.1 PostgreSQL is authoritative

Runtime processes coordinate transient activity, but the durable truth for agents, projects, tasks, attempts, leases, credentials, connections, message receipts, and domain events is PostgreSQL.

### 4.2 Persist before broadcast

Any user-visible or workflow-relevant event follows this order:

```text
validate command/message
  -> update aggregate state and append domain event in one transaction
  -> commit
  -> broadcast through Phoenix PubSub
```

PubSub is an acceleration and presentation mechanism, not a reliability boundary.

### 4.3 Agent messages are proposals

An agent does not set `Task.status`. It submits messages such as `task.started.v1` or `task.completed.v1`. Samgita verifies identity, attempt ownership, lease validity, fencing token, sequence, and state-machine legality before applying a transition.

### 4.4 Pull claim provides correctness

Samgita may send a best-effort `work.available.v1` wake-up, but agents claim work by sending `work.request.v1`. Lost wake-ups cannot lose tasks.

### 4.5 Task and Attempt are separate

A Task describes the desired result. A Task Attempt records one execution by one agent. Retries create new attempts rather than mutating execution history.

### 4.6 Leases are fenced

Every active attempt has an expiring lease and a monotonically increasing fencing token. Only the current active attempt with the current fencing token may submit a terminal result. Lease tokens are deterministic HMAC values derived by Samgita so assignment ACKs can be replayed without storing plaintext tokens.

### 4.7 Legacy execution is isolated

The new dispatcher only claims tasks where `execution_mode == :agent_hub`. Existing task creation continues to default to `:legacy_local` unless the new Tasking API explicitly selects Agent Hub execution.

### 4.8 Protocol messages are versioned

Every message type includes a version suffix, and every envelope contains `protocol_version`. Backward-incompatible changes require a new protocol version.

### 4.9 External runtime and provider integration are different layers

The existing Synapsis provider lets a local Samgita worker invoke Synapsis as an LLM/tool provider. The Agent Hub protocol lets an independently running Synapsis daemon register, claim work, and report execution state. These paths must not be conflated.

---

## 5. System Context

```text
┌─────────────────────────────────────────────────────────────────┐
│                     Operator / API Client                       │
│                                                                 │
│ create agent, project, binding, task; cancel/retry; inspect     │
└───────────────────────────────┬─────────────────────────────────┘
                                │ HTTPS / LiveView
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Samgita Control Plane                      │
│                                                                 │
│  Agents Context       Tasking Context       Dispatch Context    │
│  Credentials          State Machines        Matcher/Claimer     │
│  Connections          Attempts              Lease Reaper        │
│  Project Bindings     Domain Events         Protocol Handler    │
│                                                                 │
│  PostgreSQL ───── Oban ───── PubSub ───── LiveView/API          │
└───────────────────────────────┬─────────────────────────────────┘
                                │ Phoenix Channel / WebSocket
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Synapsis Long-Running Daemon                   │
│                                                                 │
│  connection client      local run state       local outbox      │
│  heartbeat              task executor         tools/memory      │
│                                                                 │
│ accepted / started / progress / completed / failed / cancelled  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.1 Samgita responsibilities

- Own registered Agent identity.
- Issue and revoke Agent credentials.
- Own Project-Agent authorization.
- Own logical Task and Task Attempt state.
- Match eligible work to agents.
- Derive lease token and generate fencing token.
- Validate all agent messages.
- Decide retry, cancellation, and terminal status.
- Preserve audit history.
- Provide operational UI and API.

### 5.2 Agent runtime responsibilities

- Maintain a long-running connection.
- Report runtime identity, version, capabilities, and capacity.
- Persist received assignments locally before acknowledging them.
- Execute the task using its own model, tools, memory, and workspace.
- Renew active leases through heartbeat.
- Persist outbound status messages until acknowledged.
- Stop work when cancellation or lease invalidation is received.
- Reconcile local active attempts after reconnect.

---

## 6. Logical Components

### 6.1 `Samgita.Agents`

Owns registered-agent state and project associations.

Responsibilities:

- Create, update, enable, disable, and list agents.
- Issue, rotate, and revoke credentials.
- Authenticate Agent Socket connections.
- Open, heartbeat, replace, and close connection records.
- Bind and unbind agents from projects.
- Compute effective capabilities.
- Report derived online/idle/busy state.

### 6.2 `Samgita.Tasking`

Owns Agent Hub task lifecycle.

Responsibilities:

- Create Agent Hub tasks.
- Validate project, preferred agent, and capabilities.
- Apply task and attempt transitions.
- Store progress, result, and error data.
- Cancel and retry tasks.
- List task attempts and event history.
- Keep legacy task functions in `Samgita.Projects` unchanged.

### 6.3 `Samgita.Dispatch`

Owns assignment and lease mechanics.

Responsibilities:

- Match pending tasks to requesting agents.
- Atomically claim tasks.
- Create attempts and lease secrets.
- Renew leases.
- Expire stale attempts.
- Requeue retryable tasks with backoff.
- Emit best-effort work-available notifications.

### 6.4 `Samgita.AgentProtocol`

Owns protocol validation and message dispatch.

Responsibilities:

- Parse and validate protocol envelopes.
- Authenticate message ownership.
- Enforce idempotency.
- Enforce per-attempt sequence ordering.
- Route message types to Agents, Tasking, or Dispatch.
- Build deterministic ACK responses.
- Restore prior ACKs for duplicate messages.

### 6.5 `Samgita.DomainEvents`

Owns append-only audit events.

Responsibilities:

- Append versioned domain events inside caller transactions.
- Query events by aggregate or correlation ID.
- Enforce idempotency keys.
- Provide data for task timelines and diagnostics.

It is not a full event-sourcing framework. Aggregate tables remain the current-state source of truth.

### 6.6 `SamgitaWeb.AgentSocket` and `SamgitaWeb.AgentChannel`

Own transport concerns only.

Responsibilities:

- Authenticate connection parameters.
- Join `agent:<agent_id>` only for the authenticated agent.
- Register the active connection.
- Subscribe to agent-specific control/wake-up PubSub topics.
- Forward inbound protocol messages to `Samgita.AgentProtocol`.
- Return ACKs or protocol errors.
- Mark the connection disconnected on termination.

Business transitions do not belong in Channel callbacks.

---

## 7. Data Model

All IDs use UUID/binary IDs and existing Ecto conventions.

## 7.1 `agents`

Represents a stable logical agent identity.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | string | Required, unique for operator convenience |
| `runtime` | string | `synapsis`, `codex`, `claude_code`, or future runtime |
| `enabled` | boolean | Defaults to true |
| `capabilities` | text array | Operator-approved capability ceiling |
| `labels` | JSONB | Region, host class, environment, custom scheduling labels |
| `max_concurrency` | integer | Positive, defaults to 1 |
| `last_seen_at` | UTC datetime | Updated by accepted heartbeat |
| `metadata` | JSONB | Runtime-neutral extension data |
| timestamps | UTC datetime | Existing convention |

Derived runtime state is not stored as a manually edited enum. It is computed from `enabled`, the active connection, heartbeat age, and active-attempt count.

## 7.2 `agent_credentials`

Stores revocable machine credentials.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `agent_id` | UUID FK | Required, cascade delete |
| `token_prefix` | string | Non-secret display prefix |
| `token_hash` | binary | SHA-256 of a cryptographically random 256-bit token |
| `expires_at` | UTC datetime | Nullable |
| `last_used_at` | UTC datetime | Nullable |
| `revoked_at` | UTC datetime | Nullable |
| timestamps | UTC datetime | |

The plaintext token is returned only once. Authentication uses constant-time comparison.

## 7.3 `agent_connections`

Records each daemon connection session.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Connection ID |
| `agent_id` | UUID FK | Required |
| `credential_id` | UUID FK | Credential used |
| `instance_id` | string | Unique per daemon boot |
| `protocol_version` | integer | Phase 1 requires `1` |
| `runtime_version` | string | Reported by client |
| `reported_capabilities` | text array | Capabilities available in this runtime instance |
| `labels` | JSONB | Dynamic runtime labels |
| `max_concurrency` | integer | Reported capacity, capped by Agent configuration |
| `samgita_node` | string | Node accepting the socket |
| `connected_at` | UTC datetime | Required |
| `last_heartbeat_at` | UTC datetime | Required after hello |
| `disconnected_at` | UTC datetime | Nullable while active |
| `disconnect_reason` | string | Nullable |
| `metadata` | JSONB | Transport metadata |

Use a PostgreSQL partial unique index to allow only one active connection per Agent:

```text
UNIQUE(agent_id) WHERE disconnected_at IS NULL
```

Opening a new connection closes the previous record transactionally. The previous channel is asked to disconnect through an agent-specific PubSub control topic.

## 7.4 `project_agents`

Explicitly authorizes an Agent for a Project.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `project_id` | UUID FK | Required |
| `agent_id` | UUID FK | Required |
| `enabled` | boolean | Defaults to true |
| `role` | string | `worker`, `reviewer`, `primary`, or custom label |
| `priority` | integer | Lower values are preferred |
| `allowed_capabilities` | text array | Optional further restriction |
| `metadata` | JSONB | |
| timestamps | UTC datetime | |

Constraints:

- Unique `(project_id, agent_id)`.
- Project and Agent must exist.
- Disabled binding is ineligible for new claims.

Effective capabilities for a project are:

```text
agent.capabilities
INTERSECT connection.reported_capabilities
INTERSECT project_agent.allowed_capabilities when non-empty
```

## 7.5 Changes to `tasks`

Preserve all existing fields and legacy behavior. Add:

| Column | Type | Notes |
|---|---|---|
| `title` | string | Required for new Agent Hub tasks; nullable for legacy rows |
| `description` | text | Required for new Agent Hub tasks; nullable for legacy rows |
| `execution_mode` | enum | `legacy_local` or `agent_hub`; default `legacy_local` |
| `required_capabilities` | text array | Defaults to empty |
| `preferred_agent_id` | UUID FK | Nullable |
| `available_at` | UTC datetime | Earliest claim time |
| `timeout_seconds` | integer | Defaults to 900 |
| `max_attempts` | integer | Defaults to 3 |
| `current_attempt_id` | UUID FK | Most recently created Attempt; may be terminal and is replaced by the next claim |
| `progress` | JSONB | Current progress projection |
| `idempotency_key` | string | Nullable; unique per project when non-null |
| `cancel_requested_at` | UTC datetime | Nullable |
| `lock_version` | integer | Optimistic lock, defaults to 1 |

Do not repurpose the existing string `agent_id` field. It remains part of the legacy execution path. Agent Hub ownership is represented by `current_attempt_id -> task_attempts.agent_id`.

### 7.5.1 Task statuses

Retain existing statuses and add `cancelled`:

```text
pending
blocked
assigned
running
completed
failed
cancelled
skipped
dead_letter
```

For Agent Hub tasks:

- `pending` means dispatchable when `available_at <= now`.
- `assigned` means an active leased attempt exists.
- `running` means the current attempt has started.

No new `ready` status is required in Phase 1.

## 7.6 `task_attempts`

Represents one execution attempt by one registered Agent.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `task_id` | UUID FK | Required |
| `agent_id` | UUID FK | Required |
| `connection_id` | UUID FK | Connection that accepted assignment; nullable until accepted |
| `attempt_no` | integer | Starts at 1, unique per task |
| `status` | enum | See below |
| `lease_token_hash` | binary | Hash only; deterministic opaque token is returned to the agent and can be re-derived by Samgita |
| `fencing_token` | bigint | Monotonic per Task |
| `leased_at` | UTC datetime | Required |
| `accepted_at` | UTC datetime | Nullable |
| `started_at` | UTC datetime | Nullable |
| `last_heartbeat_at` | UTC datetime | Nullable |
| `accept_deadline_at` | UTC datetime | Required while status is `leased`; assignment must be accepted before this time |
| `lease_expires_at` | UTC datetime | Required for active attempt |
| `finished_at` | UTC datetime | Nullable |
| `last_sequence` | bigint | Defaults to 0 |
| `progress` | JSONB | Latest progress |
| `result` | JSONB | Terminal result |
| `error` | JSONB | Terminal error |
| `metadata` | JSONB | Runtime metrics and extension data |
| timestamps | UTC datetime | |

Attempt statuses:

```text
leased
accepted
running
succeeded
failed
expired
rejected
cancelled
```

Active statuses are `leased`, `accepted`, and `running`.

Constraints and indexes:

- Unique `(task_id, attempt_no)`.
- Partial unique index on `task_id` for active attempt statuses.
- Index `(agent_id, status)`.
- Index `lease_expires_at` for active statuses.
- Terminal attempts are immutable except for explicitly allowed metadata enrichment.

## 7.7 `agent_inbox`

Provides protocol message deduplication and deterministic ACK replay.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `agent_id` | UUID FK | Required |
| `message_id` | UUID | Client-generated idempotency ID |
| `message_type` | string | Versioned type |
| `attempt_id` | UUID FK | Nullable |
| `sequence` | bigint | Nullable for non-attempt messages |
| `payload_hash` | binary | Detect conflicting reuse of a message ID |
| `ack_payload` | JSONB | Canonical non-secret ACK descriptor; assignment lease tokens are re-derived at response time |
| `processed_at` | UTC datetime | Required |
| timestamps | UTC datetime | |

Constraints:

- Unique `(agent_id, message_id)`.
- Unique `(attempt_id, sequence)` when both are non-null.
- Reusing a message ID with a different payload is a protocol error.
- `ack_payload` must never contain plaintext credentials or lease tokens.

## 7.8 `domain_events`

Append-only operational audit journal.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Event ID |
| `aggregate_type` | string | `agent`, `connection`, `project_agent`, `task`, `task_attempt` |
| `aggregate_id` | UUID | Aggregate identifier |
| `event_type` | string | Versioned event type |
| `source` | string | `operator`, `agent`, `system` |
| `correlation_id` | UUID | Usually Task ID for task lifecycle |
| `causation_id` | UUID | Nullable prior event ID |
| `idempotency_key` | string | Nullable unique source key |
| `payload` | JSONB | Versioned event payload |
| `occurred_at` | UTC datetime | Source-provided or server time |
| `recorded_at` | UTC datetime | Server time |

Indexes:

- `(aggregate_type, aggregate_id, recorded_at)`.
- `(correlation_id, recorded_at)`.
- Unique `(source, idempotency_key)` where non-null.

---

## 8. State Machines

## 8.1 Derived Agent runtime state

```text
disabled  <- agent.enabled == false

offline   <- no active connection or heartbeat stale
idle      <- active connection and active_attempts == 0
busy      <- active connection and active_attempts > 0
draining  <- connection metadata marks drain; no new claims
unhealthy <- connection exists but protocol/health threshold exceeded
```

Only `enabled` and optional drain state are operator-controlled. Online state is derived.

## 8.2 Task state machine for Agent Hub tasks

```text
blocked
   │ dependencies resolved
   ▼
pending
   │ claim succeeds
   ▼
assigned
   │ task.started.v1 accepted
   ▼
running
   ├── task.completed.v1 ──> completed
   ├── task.failed.v1 ─────> pending | failed | dead_letter
   ├── cancellation ───────> cancelled
   └── lease expiry ───────> pending | dead_letter

pending ── cancellation ──> cancelled
assigned ─ cancellation ──> cancelled
```

The existing `skipped` state remains available to legacy workflows and future dependency policies.

## 8.3 Attempt state machine

```text
leased
   ├── task.accepted.v1 -> accepted
   ├── task.rejected.v1 -> rejected
   ├── ACK timeout      -> expired
   └── cancellation     -> cancelled

accepted
   ├── task.started.v1  -> running
   ├── lease expiry     -> expired
   └── cancellation     -> cancelled

running
   ├── task.progress.v1  -> running
   ├── task.completed.v1 -> succeeded
   ├── task.failed.v1    -> failed
   ├── lease expiry      -> expired
   └── cancellation      -> cancelled
```

Terminal statuses are immutable:

```text
succeeded failed expired rejected cancelled
```

## 8.4 Transition enforcement

Implement transition rules as pure functions in `Samgita.Tasking.StateMachine`. The transition function returns either:

```text
{:ok, transition_effects}
{:error, reason}
```

Database effects are applied by context functions using `Ecto.Multi`. Do not spread status checks across controllers, channels, and workers.

---

## 9. Agent Connection Protocol

## 9.1 Transport

- Phoenix Socket path: `/agent/socket`.
- Transport: WebSocket only in Phase 1.
- Topic: `agent:<agent_id>`.
- Protocol version: `1`.
- Serialization: JSON.
- Maximum inbound protocol message size: 256 KiB.
- The connection is always authenticated, even when admin API keys are not configured.

Do not use Distributed Erlang, direct PostgreSQL access, or SSH as the control protocol.

## 9.2 Socket authentication

Connection parameters:

```json
{
  "agent_id": "agent-uuid",
  "token": "samgita_agent_secret",
  "instance_id": "daemon-boot-uuid",
  "protocol_version": 1
}
```

Authentication verifies:

1. Agent exists and is enabled.
2. Credential belongs to Agent.
3. Credential is not expired or revoked.
4. Token hash matches in constant time.
5. Protocol version is supported.

The socket assigns authenticated identity to the socket. Channel join payload cannot replace it.

## 9.3 Hello and welcome

After joining, the client pushes `agent.hello.v1`:

```json
{
  "message_id": "uuid",
  "runtime": "synapsis",
  "runtime_version": "x.y.z",
  "reported_capabilities": ["role:implement", "language:elixir", "tool:git"],
  "labels": {"platform": "linux", "region": "ams"},
  "max_concurrency": 2,
  "active_attempts": [
    {
      "attempt_id": "uuid",
      "fencing_token": 4,
      "last_acked_sequence": 7
    }
  ]
}
```

Samgita responds with `agent.welcome.v1`:

```json
{
  "connection_id": "uuid",
  "protocol_version": 1,
  "server_time": "2026-09-04T10:00:00Z",
  "heartbeat_interval_seconds": 15,
  "lease_duration_seconds": 120,
  "accepted_capabilities": ["role:implement", "language:elixir", "tool:git"],
  "resume_attempts": [],
  "invalid_attempts": []
}
```

The hello transaction:

1. Closes any previous active connection row.
2. Creates the new connection row.
3. Updates Agent `last_seen_at`.
4. Appends `agent.connected.v1`.
5. Commits.
6. Broadcasts replacement control to an older channel.

## 9.4 One active connection per Agent

Phase 1 models one logical Agent with one active daemon connection. `max_concurrency` controls tasks inside that daemon; it does not create multiple active instances.

When a new instance connects:

- The new connection wins.
- The old connection row is closed with reason `replaced`.
- The old channel receives `agent.connection_replaced.v1` and terminates.
- Existing attempts remain owned by the logical Agent and are reconciled during hello.

A future phase may split logical Agent and Agent Instance.

## 9.5 Heartbeat

The agent sends `agent.heartbeat.v1` every 15 seconds:

```json
{
  "protocol_version": 1,
  "message_id": "uuid",
  "type": "agent.heartbeat.v1",
  "agent_id": "uuid",
  "connection_id": "uuid",
  "occurred_at": "2026-09-04T10:00:15Z",
  "payload": {
    "free_slots": 1,
    "active_attempts": [
      {
        "attempt_id": "uuid",
        "lease_token": "opaque",
        "fencing_token": 4
      }
    ],
    "runtime": {"memory_mb": 640, "load": 0.3}
  }
}
```

For every valid active attempt in the heartbeat, Samgita extends `lease_expires_at` to `now + lease_duration`. A stale or invalid attempt is returned in the heartbeat ACK and must be stopped by the client.

An Agent is considered offline after 45 seconds without a valid heartbeat. Offline detection does not immediately reassign work; lease expiry controls reassignment.

---

## 10. Protocol Envelope and ACK

## 10.1 Inbound envelope

Every non-hello message uses:

```json
{
  "protocol_version": 1,
  "message_id": "uuid",
  "type": "task.progress.v1",
  "agent_id": "uuid",
  "connection_id": "uuid",
  "attempt_id": "uuid",
  "lease_token": "opaque",
  "fencing_token": 4,
  "sequence": 3,
  "occurred_at": "2026-09-04T10:03:00Z",
  "payload": {}
}
```

Rules:

- `agent_id` must match socket identity.
- `connection_id` must be the active connection.
- Attempt messages require `attempt_id`, `lease_token`, `fencing_token`, and `sequence`.
- `sequence` starts at 1 and strictly increases for an attempt.
- `message_id` is globally unique per Agent.
- `occurred_at` is informational; server time controls lease and transition decisions.

## 10.2 ACK

Every accepted or duplicate message returns a deterministic ACK:

```json
{
  "message_id": "uuid",
  "accepted": true,
  "duplicate": false,
  "domain_event_id": "uuid",
  "task_status": "running",
  "attempt_status": "running",
  "last_sequence": 3,
  "lease_expires_at": "2026-09-04T10:05:00Z",
  "server_time": "2026-09-04T10:03:00Z"
}
```

A duplicate `message_id` with the same payload returns the stored ACK with `duplicate: true`. Reuse with a different payload returns `message_id_conflict`.

## 10.3 Protocol errors

Stable error codes:

```text
unsupported_protocol_version
unauthenticated
agent_disabled
connection_not_current
invalid_message
message_id_conflict
invalid_sequence
attempt_not_found
attempt_not_current
attempt_terminal
invalid_lease_token
stale_fencing_token
lease_expired
illegal_transition
task_cancelled
capacity_exceeded
no_eligible_work
```

Error responses include a machine-readable code and a concise message. They must not expose credential hashes or internal stack traces.

---

## 11. Task Creation

New tasks are created through `Samgita.Tasking.create_agent_hub_task/2` and the corresponding API.

Required fields:

```text
title
description
type
```

Optional fields:

```text
priority                 default 10; lower is more important
required_capabilities    default []
preferred_agent_id       default nil
available_at             default now
max_attempts             default 3
timeout_seconds           default 900
payload                   default %{}
idempotency_key           recommended
```

Creation transaction:

1. Lock or read the Project and ensure it exists.
2. Preserve current Project validation, including canonical `git_url` behavior.
3. When a preferred Agent is provided, verify an enabled Project-Agent binding.
4. Validate positive timeout/max-attempt values.
5. Create Task with `execution_mode: :agent_hub` and `status: :pending`.
6. Append `task.created.v1`.
7. Commit.
8. Broadcast task update and best-effort wake-ups to eligible online agents.

The unique `(project_id, idempotency_key)` index returns the existing Task on repeated creation.

---

## 12. Task Dispatch

## 12.1 Pull claim with wake-up

```text
Task created or requeued
  -> Samgita broadcasts work.available.v1 to eligible connected agents
  -> an agent with a free slot sends work.request.v1
  -> Samgita atomically claims up to requested slot count
  -> assignments are returned in the request ACK
```

The wake-up is best-effort. Agents also request work:

- after hello;
- after a task completes;
- when heartbeat reports newly available capacity;
- after a configurable idle polling interval.

## 12.2 Work request

```json
{
  "protocol_version": 1,
  "message_id": "uuid",
  "type": "work.request.v1",
  "agent_id": "uuid",
  "connection_id": "uuid",
  "occurred_at": "2026-09-04T10:01:00Z",
  "payload": {
    "free_slots": 2,
    "project_ids": []
  }
}
```

An empty `project_ids` means all enabled bindings. The server caps `free_slots` by effective connection capacity minus active attempts.

## 12.3 Eligibility

A Task is eligible when all are true:

1. `execution_mode == :agent_hub`.
2. `status == :pending`.
3. `available_at` is null or not in the future.
4. Attempts are below `max_attempts`.
5. Project-Agent binding exists and is enabled.
6. Agent and connection are enabled/current.
7. Effective capabilities contain all `required_capabilities`.
8. `preferred_agent_id` is nil or equals the requesting Agent.
9. The Agent has a free concurrency slot.

## 12.4 Ordering

Use deterministic ordering:

1. Tasks pinned to the requesting Agent.
2. `project_agents.priority` ascending.
3. Task `priority` ascending.
4. Task `available_at` ascending.
5. Task `inserted_at` ascending.
6. Task ID as final tie-breaker.

No probabilistic or LLM-based scheduling is required.

## 12.5 Atomic claim transaction

For each assignment:

1. Select one eligible Task using `FOR UPDATE SKIP LOCKED`.
2. Re-check capacity and active-attempt constraints.
3. Compute `attempt_no = existing attempt count + 1`.
4. Compute `fencing_token = previous maximum + 1`.
5. Derive an opaque lease token using HMAC over immutable Attempt/Task/Agent identifiers and the fencing token with the configured Agent Hub lease-signing key.
6. Store only the lease token hash; the deterministic token can be re-derived for an idempotent assignment replay without persisting plaintext.
7. Create `TaskAttempt(status: :leased)`.
8. Update Task to `status: :assigned`, set `current_attempt_id`, increment attempt projection, and apply optimistic lock.
9. Append `attempt.leased.v1` and `task.assigned.v1`.
10. Store a canonical non-secret assignment descriptor in the Agent Inbox ACK.
11. Commit, rehydrate the derived lease token into the transport response, and return the assignment.

The assignment contains:

```json
{
  "task_id": "uuid",
  "attempt_id": "uuid",
  "attempt_no": 1,
  "fencing_token": 1,
  "lease_token": "opaque-secret",
  "lease_expires_at": "2026-09-04T10:03:00Z",
  "task": {
    "project_id": "uuid",
    "title": "Implement task protocol",
    "description": "...",
    "type": "implement",
    "priority": 10,
    "payload": {},
    "timeout_seconds": 900,
    "required_capabilities": ["language:elixir"]
  }
}
```

If the response is lost, retrying the same `work.request.v1` message returns the same assignment. The Inbox stores only the non-secret descriptor; the protocol layer re-derives the lease token from immutable Attempt data and the server-side signing key. Hello/resume also reports the active attempt.

---

## 13. Lease and Fencing Semantics

### 13.1 Defaults

| Setting | Default |
|---|---:|
| Agent heartbeat interval | 15 seconds |
| Agent offline threshold | 45 seconds |
| Assignment accept timeout | 20 seconds |
| Attempt lease duration | 120 seconds |
| Lease renewal target | every 30 seconds or faster |
| Lease reaper cadence | no slower than 60 seconds |
| Progress minimum interval | 2 seconds |
| Task default timeout | 900 seconds |
| Task default max attempts | 3 |

All defaults are configurable.

### 13.2 Lease validation

An attempt-scoped message is accepted only when:

- The attempt belongs to the authenticated Agent.
- The attempt is Task `current_attempt_id`.
- Attempt status is active.
- Lease token hash matches.
- Fencing token equals the current attempt token.
- Lease has not expired according to server time.
- Task has not been cancelled.
- Sequence is the next expected sequence.

### 13.3 Why fencing is mandatory

```text
Agent A receives fencing token 1
Agent A disconnects
lease expires
Task is assigned to Agent B with fencing token 2
Agent A later sends completed with token 1
Samgita rejects it as stale_fencing_token
```

Without fencing, a delayed result from a dead or partitioned Agent can overwrite the result of a valid reassignment.

### 13.4 Lease reaper

`Samgita.Workers.LeaseReaperWorker` runs durably through Oban.

For each expired active Attempt:

1. Lock Attempt and Task.
2. Re-check expiration.
3. Mark Attempt `expired` and `finished_at`.
4. Clear Task `current_attempt_id`.
5. If Task is cancelled, keep `cancelled`.
6. If attempts remain, set Task `pending` with exponential backoff in `available_at`.
7. Otherwise set Task `dead_letter`.
8. Append attempt/task domain events.
9. Commit and wake eligible Agents when requeued.

---

## 14. Agent Status Messages

## 14.1 `task.accepted.v1`

Meaning: the Agent persisted the assignment locally and accepts responsibility.

Transition:

```text
Attempt leased -> accepted
Task remains assigned
```

The connection ID is recorded on the Attempt.

## 14.2 `task.rejected.v1`

Meaning: the Agent cannot execute the assignment.

Payload includes a structured reason and optional retry delay.

Transition:

```text
Attempt leased -> rejected
Task -> pending or dead_letter
```

Samgita, not the Agent, decides whether to requeue.

## 14.3 `task.started.v1`

Transition:

```text
Attempt accepted -> running
Task assigned -> running
```

`started_at` is server time. Agent `occurred_at` is preserved in the domain event payload.

## 14.4 `task.progress.v1`

Payload:

```json
{
  "phase": "implementing",
  "percent": 35,
  "message": "Added task-attempt schema and migration",
  "metrics": {"tokens": 1200},
  "checkpoint": {"kind": "text", "value": "optional small checkpoint"}
}
```

Rules:

- Attempt must be `accepted` or `running`.
- `percent` is optional and, when present, must be 0..100.
- Progress is a projection, not terminal proof.
- Samgita may rate-limit updates more frequent than the configured interval.
- Large logs and binary data are out of scope.

## 14.5 `task.completed.v1`

Payload:

```json
{
  "summary": "Implemented the requested task",
  "result": {},
  "metrics": {
    "duration_ms": 123456,
    "tokens_used": 8000
  },
  "artifacts": []
}
```

Transaction:

1. Validate current lease and sequence.
2. Mark Attempt `succeeded` and set terminal data.
3. Mark Task `completed`, copy result projection, keep `current_attempt_id` pointing at the terminal Attempt for inspection, and set `completed_at`. A later claim overwrites the pointer.
4. Append `attempt.completed.v1` and `task.completed.v1`.
5. Store deterministic ACK.
6. Commit, broadcast, and wake Agent for more work.

## 14.6 `task.failed.v1`

Payload:

```json
{
  "error": {
    "class": "execution_error",
    "message": "Tests failed",
    "details": {}
  },
  "retryable": true,
  "retry_after_seconds": 30,
  "partial_result": {}
}
```

The Agent's `retryable` field is advisory. Samgita applies the Task retry policy.

Possible outcomes:

```text
Attempt -> failed
Task -> pending with backoff
Task -> failed
Task -> dead_letter
```

## 14.7 Cancellation

For a pending Task:

```text
Task -> cancelled immediately
```

For an assigned/running Task:

1. Set `cancel_requested_at` and Task `cancelled` in a transaction.
2. Mark active Attempt `cancelled` or record cancellation requested according to implementation detail.
3. Append cancellation events.
4. Broadcast `task.cancel.v1` to the Agent.
5. Reject any later completion for that Attempt.

The Agent replies with `task.cancelled.v1` after stopping local execution. Repeated replies are idempotent.

---

## 15. Reconnect and Resume

The Agent must keep a local durable record of:

- Attempt ID.
- Task ID.
- Lease token.
- Fencing token.
- Last acknowledged sequence.
- Unacknowledged outbound protocol messages.

On reconnect, `agent.hello.v1` includes local active attempts. Samgita classifies each as:

### Resumable

- Attempt is current.
- Attempt belongs to Agent.
- Status is active.
- Lease has not expired, or the server explicitly allows a short reconnect grace window.

Samgita returns the authoritative sequence and renewed lease expiration.

### Invalid

- Attempt is terminal.
- Task was reassigned.
- Fencing token is stale.
- Task is cancelled.
- Lease expired and reaper already processed it.

The Agent must stop invalid attempts and must not emit new task events for them.

A client replays unacknowledged messages in sequence. `agent_inbox` ensures duplicates return the original ACK.

---

## 16. Transactions and Event Flow

Use `Ecto.Multi` for every state-changing command.

Example completion transaction:

```text
load and lock Attempt
load and lock Task
validate identity/lease/fencing/sequence
apply pure transition
update Attempt
update Task
insert DomainEvent attempt.completed.v1
insert DomainEvent task.completed.v1
insert AgentInbox receipt with ACK
commit
broadcast task/attempt updates
```

A database rollback means no event is broadcast and no ACK reports success.

### 16.1 Domain event naming

Initial event catalog:

```text
agent.created.v1
agent.enabled.v1
agent.disabled.v1
agent.credential_issued.v1
agent.credential_revoked.v1
agent.connected.v1
agent.heartbeat.v1
agent.disconnected.v1

project_agent.bound.v1
project_agent.unbound.v1
project_agent.enabled.v1
project_agent.disabled.v1

task.created.v1
task.assigned.v1
task.started.v1
task.progressed.v1
task.completed.v1
task.failed.v1
task.requeued.v1
task.cancelled.v1
task.dead_lettered.v1

attempt.leased.v1
attempt.accepted.v1
attempt.rejected.v1
attempt.started.v1
attempt.progressed.v1
attempt.completed.v1
attempt.failed.v1
attempt.expired.v1
attempt.cancelled.v1
```

### 16.2 PubSub topics

Suggested topics:

```text
agents
agent:<agent_id>
agent-control:<agent_id>
project:<project_id>
task:<task_id>
```

The Agent Channel subscribes to `agent:<agent_id>` and `agent-control:<agent_id>`. LiveViews subscribe to the relevant aggregate topics.

---

## 17. Cluster and Process Model

### 17.1 No durable connection state in Registry

A Phoenix Channel process is local to the node that owns the socket. Do not use a PID as durable Agent identity.

The active connection row in PostgreSQL is authoritative. Cross-node wake-ups and control messages use Phoenix PubSub topics, allowing any Samgita node to notify the node holding the socket.

### 17.2 Horde usage

Keep existing Horde registrations for legacy orchestrators and local agent workers. The new external Agent protocol does not require a new Horde DynamicSupervisor for remote agents.

A small local registry may be used for transport diagnostics, but correctness must not depend on it.

### 17.3 Supervision additions

Core application additions should remain minimal:

```text
Samgita.Application
├── existing children
├── Samgita.Dispatch.Notifier          # optional, only if a process is required
└── existing Oban instance             # runs LeaseReaperWorker

SamgitaWeb.Endpoint
└── /agent/socket
    └── SamgitaWeb.AgentChannel per connection
```

Prefer stateless context modules and Oban workers over adding long-lived processes without a lifecycle requirement.

---

## 18. API Surface

Admin endpoints remain under the existing `/api` pipeline and its API key/rate-limit behavior.

### 18.1 Agents

```text
POST   /api/agents
GET    /api/agents
GET    /api/agents/:id
PATCH  /api/agents/:id
POST   /api/agents/:id/enable
POST   /api/agents/:id/disable
POST   /api/agents/:id/credentials
DELETE /api/agents/:agent_id/credentials/:credential_id
GET    /api/agents/:id/connections
```

Credential creation returns plaintext once and should set `cache-control: no-store`.

### 18.2 Project-Agent binding

```text
PUT    /api/projects/:project_id/agents/:agent_id
PATCH  /api/projects/:project_id/agents/:agent_id
DELETE /api/projects/:project_id/agents/:agent_id
GET    /api/projects/:project_id/agents
```

### 18.3 Tasks

Extend current task routes:

```text
POST   /api/projects/:project_id/tasks
GET    /api/projects/:project_id/tasks
GET    /api/projects/:project_id/tasks/:id
POST   /api/projects/:project_id/tasks/:id/cancel
POST   /api/projects/:project_id/tasks/:id/retry
GET    /api/projects/:project_id/tasks/:id/attempts
GET    /api/projects/:project_id/tasks/:id/events
```

The create endpoint defaults `execution_mode` to `agent_hub` only for this new endpoint/controller action. Existing internal callers keep legacy defaults.

### 18.4 Agent transport

```text
WS /agent/socket
```

No HTTP polling fallback is required in Phase 1.

---

## 19. LiveView Surface

### 19.1 Agents page

The existing `/agents` page should evolve to show registered Agents rather than only legacy AgentRun records.

Minimum fields:

- Name and runtime.
- Enabled/disabled.
- Online/idle/busy/offline derived state.
- Effective capability count.
- Current active attempts / capacity.
- Last heartbeat.
- Current connection instance/version.

Legacy AgentRun information may remain on Project detail or a separate section.

### 19.2 Agent detail

- Configured capabilities and labels.
- Current connection.
- Recent connection history.
- Bound projects.
- Active and recent attempts.
- Credential metadata and revoke/rotate actions; never display token again.

### 19.3 Project detail

Add:

- Bound Agents and effective capabilities.
- Create Agent Hub Task form.
- Task table filtered by status/execution mode.
- Current Attempt and progress.

### 19.4 Task detail

- Logical Task fields.
- Attempt history.
- Current lease status and expiration.
- Progress.
- Result/error.
- Append-only event timeline.
- Cancel/retry actions when legal.

Use existing DuskMoon components and operational dashboard style.

---

## 20. Security Model

Samgita remains intentionally single-tenant at the browser level. Do not add browser accounts or role-based access control.

The Agent Protocol is different: every connection must have a dedicated machine credential.

Required controls:

1. Generate Agent credentials with at least 256 bits of entropy.
2. Store only a hash and a non-secret prefix.
3. Compare hashes in constant time.
4. Allow multiple credentials per Agent for rotation.
5. Reject revoked/expired credentials immediately.
6. Never log plaintext tokens or lease tokens.
7. Authenticate socket identity before channel join.
8. Restrict an Agent to explicitly bound Projects.
9. Use effective capability intersection, not client claims alone.
10. Rate-limit invalid authentication and malformed protocol messages.
11. Limit protocol payload size.
12. Redact secret-like values from error responses and event payloads.
13. Use `wss://` outside trusted localhost/VPN deployment.
14. Load a dedicated Agent Hub lease-signing key from runtime secret configuration; do not derive it from the web application at runtime or persist it in PostgreSQL.

Lease tokens are attempt-scoped secrets. Derive them using a dedicated server-side `:agent_lease_signing_key`, store only their hashes, and never expose them in UI, logs, Inbox rows, or domain events. The signing key must remain stable across Samgita restarts; rotating it invalidates active leases.

---

## 21. Failure and Recovery Matrix

| Failure | Required behavior |
|---|---|
| WebSocket disconnect | Mark connection closed; retain attempts until lease expiry |
| Agent heartbeat stops | Derive Agent offline; do not immediately duplicate work |
| Assignment response lost | Same work-request message ID replays the canonical assignment; lease token is re-derived, not stored |
| Agent accepts then crashes | Lease expires; reaper requeues or dead-letters |
| Samgita restarts | Agent reconnects; database state is sufficient for reconciliation |
| Duplicate progress/completion | Return stored ACK; do not duplicate transitions/events |
| Out-of-order sequence | Reject with `invalid_sequence` and return authoritative sequence |
| Old Agent result after reassignment | Reject by current-attempt and fencing checks |
| Two Agents claim simultaneously | `FOR UPDATE SKIP LOCKED` and active-attempt unique index prevent duplication |
| Task cancelled while running | Notify Agent; reject later completion |
| Credential revoked | New messages/connections rejected; active socket closed through control broadcast |
| New connection replaces old | New connection wins; old channel closes |
| Lease reaper runs twice | Row locks and terminal-state checks make operation idempotent |
| PubSub notification lost | Agent pull request eventually discovers pending work |
| Domain transaction fails | No success ACK and no post-commit broadcast |

---

## 22. Observability

### 22.1 Telemetry events

Emit telemetry for:

```text
[:samgita, :agent, :connected]
[:samgita, :agent, :disconnected]
[:samgita, :agent, :heartbeat]
[:samgita, :dispatch, :claim]
[:samgita, :dispatch, :no_work]
[:samgita, :attempt, :transition]
[:samgita, :attempt, :lease_expired]
[:samgita, :protocol, :message]
[:samgita, :protocol, :rejected]
```

Metadata must include IDs and result codes, not secrets.

### 22.2 Metrics

Minimum metrics:

- Connected agents.
- Online/idle/busy agents.
- Pending Agent Hub tasks.
- Active attempts.
- Claim latency.
- Task queue age.
- Attempt duration.
- Lease renewals and expirations.
- Retry and dead-letter counts.
- Duplicate protocol messages.
- Rejected stale messages.
- Protocol errors by code.

### 22.3 Logging

Use structured metadata:

```text
agent_id
connection_id
project_id
task_id
attempt_id
message_id
fencing_token
protocol_type
```

Do not log token or result payloads by default.

---

## 23. Compatibility and Rollout

### 23.1 Execution-mode isolation

- Existing Task rows migrate to `execution_mode = :legacy_local`.
- Existing `Samgita.Project.Orchestrator` creates legacy tasks unless explicitly changed in a future phase.
- New API-created Agent Hub tasks use `execution_mode = :agent_hub`.
- New dispatcher only sees Agent Hub tasks.
- Existing `AgentTaskWorker` continues to process legacy tasks.

### 23.2 Existing AgentRun

Do not migrate or repurpose `agent_runs`. Its current semantics are legacy local RARV worker metrics. `task_attempts` is a separate aggregate with different invariants.

### 23.3 Existing Synapsis provider

Do not modify `SamgitaProvider.Synapsis` to carry task-control messages. It remains an outbound provider implementation. The Agent Hub protocol belongs in core/web contexts and Phoenix Channels.

### 23.4 Feature flag

Add a runtime setting:

```text
config :samgita, :agent_hub_v1_enabled, false
```

When false:

- Agent Socket rejects connection with `feature_disabled`.
- Admin UI can hide create/bind actions.
- Legacy orchestration remains unaffected.

Enable by default in development/test only after integration tests pass.

---

## 24. Code Placement

Recommended additions:

```text
apps/samgita/lib/samgita/
├── agents.ex
├── agents/
│   ├── credential.ex                 # token generation/hash helpers
│   ├── connection_state.ex           # derived runtime state
│   └── capability.ex                 # normalization/intersection
├── tasking.ex
├── tasking/
│   ├── state_machine.ex
│   ├── transition.ex
│   └── retry_policy.ex
├── dispatch.ex
├── dispatch/
│   ├── matcher.ex
│   ├── claimer.ex
│   ├── lease.ex
│   └── notifier.ex
├── agent_protocol.ex
├── agent_protocol/
│   ├── envelope.ex
│   ├── validator.ex
│   ├── handler.ex
│   └── ack.ex
├── domain_events.ex
├── domain/
│   ├── agent.ex
│   ├── agent_credential.ex
│   ├── agent_connection.ex
│   ├── project_agent.ex
│   ├── task_attempt.ex
│   ├── agent_inbox.ex
│   └── domain_event.ex
└── workers/
    └── lease_reaper_worker.ex

apps/samgita_web/lib/samgita_web/
├── channels/
│   ├── agent_socket.ex
│   └── agent_channel.ex
├── controllers/
│   ├── agent_controller.ex
│   ├── agent_credential_controller.ex
│   ├── project_agent_controller.ex
│   └── agent_hub_task_controller.ex
└── live/
    ├── agents_live/
    └── task_detail_live/
```

Keep application dependency direction unchanged. `samgita_web` may call public functions in `samgita`; core code must not depend on web modules.

---

## 25. Testing Architecture

### 25.1 Pure unit tests

- Capability normalization and subset checks.
- Task and Attempt transition matrices.
- Retry policy.
- Lease token hashing and validation.
- Protocol envelope validation.
- Matcher ordering.

### 25.2 Data/context tests

- Agent and credential lifecycle.
- Project-Agent uniqueness and restrictions.
- Agent Hub Task creation and idempotency.
- Atomic claim.
- Active-attempt unique constraint.
- Fencing behavior.
- Sequence and message-id deduplication.
- Lease expiry and requeue/dead-letter.
- Cancellation and retry.
- Domain event insertion in the same transaction.

### 25.3 Channel tests

- Authentication success/failure.
- Agent identity cannot be changed by join payload.
- Hello/welcome.
- Connection replacement.
- Heartbeat and lease renewal.
- Work request and assignment replay.
- Status messages and ACKs.
- Malformed and oversized messages.

### 25.4 Concurrency tests

At minimum:

- Two agents concurrently claim one task; exactly one succeeds.
- Two reaper executions process one expired attempt once.
- Completion races with cancellation; only one legal terminal outcome commits.
- Old completion races with reassignment; stale result is rejected.

### 25.5 End-to-end fake agent

Add a test-only fake WebSocket agent or Channel client that can:

1. Connect and hello.
2. Request work.
3. Accept/start/progress/complete.
4. Disconnect and reconnect.
5. Replay messages.
6. Submit a stale fencing token.

Do not require a real LLM or Synapsis instance for Samgita CI.

---

## 26. Companion Synapsis Contract

Implementation in the Synapsis repository is a separate workstream. Samgita should provide a protocol conformance document and test fixture, but must not add Synapsis runtime code to this repository.

The Synapsis daemon needs:

```text
Samgita connection client
credential persistence
reconnect with exponential backoff
hello/heartbeat/work request
local active-attempt store
local outbound outbox
status message replay
cancellation handling
task execution adapter into the existing long-running daemon/QueryLoop
```

The daemon remains the single long-running execution control plane inside Synapsis. Heartbeat, scheduled work, dreams/reflection, and Samgita assignments should enter that same supervised runtime rather than creating separate agent systems.

---

## 27. Architectural Decisions

| Decision | Choice | Reason |
|---|---|---|
| Agent transport | Phoenix Channel/WebSocket | Native to stack, bidirectional, real-time |
| Dispatch reliability | Pull claim plus best-effort wake-up | Lost WebSocket messages cannot lose work |
| Durable queue/state | PostgreSQL + Oban | Existing operational stack; sufficient for Phase 1 |
| Agent access | Explicit Project-Agent binding | Prevent accidental cross-project execution |
| Scheduling key | Dynamic capabilities | Hard-coded Agent Type is too restrictive |
| Execution history | Separate TaskAttempt | Retries and ownership must be immutable/auditable |
| Duplicate handling | Durable Agent Inbox | Supports deterministic ACK replay |
| Split-brain defense | Lease plus fencing token | Rejects late results after reassignment |
| Event model | Append-only audit events, not full event sourcing | Adds traceability without redesigning all aggregates |
| Legacy coexistence | Task execution mode | Minimal-risk rollout |
| Active Agent instances | One connection per logical Agent | Reduces Phase 1 ambiguity |
| Project identity | Preserve current `git_url` | Repository guideline and compatibility |
| Browser auth | None added | Existing single-tenant deployment model |

---

## 28. Implementation Guardrails for Codex

1. Read and follow the repository root `AGENTS.md` before modifying code.
2. Keep PostgreSQL as the source of truth.
3. Use Oban for durable lease-expiry work.
4. Use PubSub only after a successful database commit.
5. Preserve the umbrella dependency direction.
6. Do not add a browser authentication/account system.
7. Do not rename or repurpose the existing `Samgita.Agent.Worker` or `AgentRun` semantics.
8. Do not route the control protocol through `SamgitaProvider.Synapsis`.
9. Do not make the new dispatcher see legacy tasks.
10. Do not implement GitHub, workflow, PR, review, merge, or release behavior in this phase.
11. Keep state transition logic centralized and testable.
12. Never persist or log plaintext Agent credentials or lease tokens.
13. Keep request/channel callbacks thin; external or slow work stays out of request paths.
14. Add scoped tests with every change and avoid unrelated refactors.
15. Stop at the acceptance criteria defined in `prd.md` and `plan.md`.

---

## 29. Phase 1 Completion Boundary

Architecture is complete when the following works reliably without a real LLM:

```text
create registered Agent
issue credential
connect fake/Synapsis Agent
create Project using existing project rules
bind Agent to Project
create Agent Hub Task
claim leased Attempt
accept and start
report progress
complete or fail
inspect Task, Attempt, Connection, and Event history
recover after duplicate messages, disconnect, and restart
expire and safely reassign a stale lease
reject a stale result by fencing token
```

Everything after that belongs to a later workflow/GitHub phase.
