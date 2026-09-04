# Product Requirements Document: Samgita Agent Hub Phase 1

**Status:** Ready for implementation  
**Target repository:** `gsmlg-opt/Samgita`  
**Target path:** `docs/agent-hub-v1/prd.md`  
**Related document:** `architecture.md`  
**Release name:** Agent Hub v1 Foundation

---

## 1. Product Summary

Samgita Agent Hub Phase 1 allows long-running external agents to connect to Samgita, receive project-scoped tasks, and report execution state through a reliable protocol.

The release provides the first end-to-end control-plane workflow:

```text
connect agent
  -> create project
  -> bind agent to project
  -> create task
  -> dispatch task
  -> receive progress
  -> complete/fail/cancel/retry task
```

This release is intentionally smaller than the future autonomous software-development system. It does not integrate GitHub or implement PR/review/release workflows. Its purpose is to establish the durable Agent and Task contract that those future workflows will use.

---

## 2. Problem Statement

Samgita currently orchestrates local workers around PRDs and fixed project phases. It does not have a durable mechanism for an independently running agent daemon to:

- register as a stable Agent;
- prove its identity;
- advertise capabilities and capacity;
- be authorized for selected projects;
- claim work atomically;
- keep work ownership alive during execution;
- report ordered and idempotent progress;
- recover after network or process failure;
- safely reject late results after reassignment.

Without these capabilities, Samgita cannot become a distributed Agent event hub. A direct WebSocket push or synchronous local process call would create duplicate execution and stale-result risks.

---

## 3. Product Vision

> Samgita is the authoritative control plane for projects and tasks. Connected agents are durable execution workers that claim bounded work, execute it independently, and report evidence and state through a versioned protocol.

Phase 1 should feel operationally simple:

- The operator sees which agents are connected.
- The operator decides which projects an agent may access.
- Creating a task makes it available to eligible agents.
- The task page shows the current attempt and progress.
- Failures, disconnects, retries, and duplicate messages do not corrupt state.

---

## 4. Users and Actors

### 4.1 Operator

A trusted user who can access the self-hosted Samgita deployment. The operator creates Agents, Projects, bindings, and Tasks; monitors execution; cancels or retries work; and rotates Agent credentials.

### 4.2 Agent Runtime

A long-running daemon, initially Synapsis, that connects to Samgita using a machine credential. It advertises capabilities, requests work, executes assignments, and reports status.

### 4.3 Samgita System Worker

Internal Oban jobs that perform durable maintenance such as lease expiry and task requeueing.

---

## 5. Goals

### G-001: Reliable Agent connection

A configured Synapsis daemon can authenticate, establish a long-running connection, heartbeat, disconnect, and reconnect.

### G-002: Explicit project authorization

An Agent can claim tasks only for Projects to which it is explicitly bound.

### G-003: Capability-based dispatch

Samgita dispatches work only when the Agent's effective capabilities satisfy all Task requirements.

### G-004: Exactly one valid active attempt

A Task may be retried, but it must never have more than one valid active Task Attempt.

### G-005: Idempotent state updates

Duplicate Agent messages produce the same ACK and do not create duplicate transitions or events.

### G-006: Safe failure recovery

Agent disconnection, Samgita restart, lease expiry, and late results are handled without corrupting Task state.

### G-007: Operational visibility

Operators can inspect registered Agents, connections, task attempts, progress, failures, and event history.

### G-008: Backward compatibility

Existing PRD orchestration and local Agent Worker behavior continue to work without being claimed by the new dispatcher.

---

## 6. Non-Goals

The release must not include:

- GitHub App or webhook integration.
- Issue import or synchronization.
- Repository checkout/worktree management for external agents.
- Pull request creation.
- Automated review, merge, deployment, or release.
- Generic workflow definitions or DAG execution changes.
- Agent-to-agent communication.
- Multi-tenant accounts, organizations, or browser RBAC.
- External brokers such as Kafka or NATS.
- General binary artifact upload.
- Automatic remote process provisioning.
- Replacement of the existing PRD Orchestrator.
- OpenClaw compatibility work.

---

## 7. Product Constraints

1. Samgita is an Elixir umbrella application.
2. PostgreSQL remains the source of truth.
3. Oban is used for durable background work.
4. Phoenix PubSub is used for post-commit real-time updates.
5. Phoenix Channels/WebSocket is used for Agent transport.
6. The browser UI remains single-tenant and infrastructure-protected.
7. Agent machine connections always require credentials.
8. Existing Project `git_url` behavior remains canonical in this phase.
9. Existing `Samgita.Agent.Worker`, `Project.Orchestrator`, and `AgentRun` semantics remain intact.
10. Existing tasks default to legacy execution; only new Agent Hub tasks enter the new dispatcher.

---

## 8. Primary User Journeys

## 8.1 Create and connect an Agent

1. Operator opens Agents.
2. Operator creates an Agent with name, runtime, approved capabilities, labels, and maximum concurrency.
3. Operator creates a credential.
4. Samgita displays the plaintext credential exactly once.
5. Operator configures the Synapsis daemon with Agent ID, token, and Samgita URL.
6. Synapsis connects and sends hello.
7. Samgita shows the Agent as online and idle.

## 8.2 Create a Project and bind an Agent

1. Operator creates a Project through the existing project flow, including canonical `git_url`.
2. Operator opens the Project Agent section.
3. Operator selects an Agent, role, priority, and optional capability restriction.
4. Samgita shows the Agent as eligible for the Project.

## 8.3 Create and execute a Task

1. Operator creates an Agent Hub Task with title, description, type, priority, and required capabilities.
2. Task enters `pending`.
3. An eligible Agent is awakened or requests work.
4. Samgita leases the Task and creates Attempt 1.
5. Agent accepts, starts, and reports progress.
6. Task becomes `completed` when the Agent submits a valid terminal result.
7. Operator can inspect the result, Attempt history, and event timeline.

## 8.4 Recover from Agent failure

1. Agent starts a Task and loses connectivity.
2. Samgita shows it as offline after the heartbeat threshold.
3. The Task remains owned until its lease expires.
4. Lease reaper expires Attempt 1 and requeues the Task.
5. Another eligible Agent receives Attempt 2 with a higher fencing token.
6. A late completion from Attempt 1 is rejected.

## 8.5 Cancel a Task

1. Operator cancels a pending or running Task.
2. Pending work becomes `cancelled` immediately.
3. Running work receives a cancellation control message.
4. Any later completion from the cancelled Attempt is rejected.
5. The event timeline records the cancellation.

## 8.6 Retry failed work

1. A Task fails or reaches dead-letter state.
2. Operator selects Retry.
3. Samgita validates that the Task is retriable.
4. A new Attempt number and fencing token are used.
5. Previous Attempts remain immutable and visible.

---

## 9. Functional Requirements

## 9.1 Agent Registry

### FR-A001 — Create Agent

The system shall allow an operator to create an Agent with:

- name;
- runtime;
- approved capabilities;
- labels;
- maximum concurrency;
- optional metadata.

**Acceptance:** A valid Agent is persisted and emits `agent.created.v1`.

### FR-A002 — Validate Agent

Agent name shall be required, and maximum concurrency shall be a positive integer.

**Acceptance:** Invalid input returns changeset/API validation errors and creates no event.

### FR-A003 — Enable and disable Agent

The operator shall be able to enable or disable an Agent.

**Acceptance:** A disabled Agent cannot authenticate a new connection or claim new work.

### FR-A004 — List and inspect Agents

The API and UI shall show configured fields plus derived runtime state, last seen time, active connection, active attempt count, and effective capacity.

### FR-A005 — Preserve logical identity

An Agent ID shall remain stable across daemon restart and connection replacement.

---

## 9.2 Agent Credentials

### FR-C001 — Issue credential

The operator shall be able to issue more than one credential for an Agent to support rotation.

### FR-C002 — Display plaintext once

The plaintext credential shall be returned only by the successful creation response and shall never be retrievable later.

### FR-C003 — Store only hash

The database shall store a token hash and display prefix, not the plaintext token.

### FR-C004 — Revoke credential

The operator shall be able to revoke a credential.

**Acceptance:** A revoked credential cannot authenticate, and an active socket using it is closed.

### FR-C005 — Expire credential

An optional expiration time shall be enforced during connection authentication.

### FR-C006 — Protect credential responses

Credential creation responses shall not be cached and shall not include the token in logs or events.

---

## 9.3 Agent Connection

### FR-CON001 — WebSocket endpoint

Samgita shall expose an Agent WebSocket endpoint at `/agent/socket`.

### FR-CON002 — Mandatory machine authentication

The Agent Socket shall always require Agent ID and credential, independent of admin API-key configuration.

### FR-CON003 — Protocol version

The connection shall require protocol version `1`; unsupported versions shall be rejected with a stable error code.

### FR-CON004 — Hello handshake

After join, the Agent shall send runtime version, capabilities, labels, maximum concurrency, and local active-attempt state.

### FR-CON005 — Welcome response

Samgita shall return connection ID, timing configuration, accepted capabilities, and resume/invalid-attempt decisions.

### FR-CON006 — One active connection

Only one active connection shall exist per logical Agent. A newer valid connection replaces the older connection.

### FR-CON007 — Connection history

Every connection and disconnection shall be persisted and visible to the operator.

### FR-CON008 — Heartbeat

The Agent shall send heartbeat messages at the configured interval. Accepted heartbeat updates connection and Agent last-seen timestamps.

### FR-CON009 — Derived offline state

The UI shall consider an Agent offline after the configured heartbeat threshold without requiring a manually persisted offline state transition.

### FR-CON010 — Lease renewal

A valid heartbeat shall renew leases for listed active Attempts.

### FR-CON011 — Invalid attempt response

Heartbeat and hello ACKs shall identify attempts the Agent must stop because they are stale, cancelled, terminal, or reassigned.

### FR-CON012 — Reconnect

An Agent shall be able to reconnect after network or Samgita restart and reconcile active attempts.

---

## 9.4 Project-Agent Association

### FR-PA001 — Bind Agent to Project

The operator shall be able to bind an Agent to an existing Project.

### FR-PA002 — Unique binding

A Project-Agent pair shall have at most one binding.

### FR-PA003 — Binding configuration

A binding shall support enabled state, role, dispatch priority, optional allowed capabilities, and metadata.

### FR-PA004 — Explicit authorization

An Agent shall not claim work for an unbound Project.

### FR-PA005 — Disable binding

Disabling a binding shall stop new assignments but shall not silently invalidate an active Attempt. Operators may separately cancel active Tasks.

### FR-PA006 — Unbind safety

Unbinding an Agent with active Attempts shall either be rejected with a clear error or require explicit cancellation; it shall not orphan active work.

### FR-PA007 — Effective capabilities

Dispatch shall use the intersection of configured Agent capabilities, connection-reported capabilities, and binding restrictions.

---

## 9.5 Project Creation

### FR-P001 — Reuse current Project model

The existing Project creation flow and validation shall remain the canonical Phase 1 project flow.

### FR-P002 — Preserve `git_url`

`git_url` shall remain required/canonical according to existing repository rules.

### FR-P003 — No automatic orchestration

Creating a Project shall not automatically start the legacy PRD Orchestrator when the operator only intends to create Agent Hub Tasks.

### FR-P004 — Project view

The Project view shall expose bound Agents and Agent Hub Tasks without removing existing PRD and legacy orchestration views.

---

## 9.6 Task Creation

### FR-T001 — Create Agent Hub Task

The API/UI shall allow creation of a Task with:

- title;
- description;
- type;
- priority;
- required capabilities;
- optional preferred Agent;
- optional payload;
- timeout;
- maximum attempts;
- optional idempotency key.

### FR-T002 — Execution-mode isolation

New Agent Hub Tasks shall have `execution_mode = :agent_hub`. Existing internal/legacy task callers shall continue to default to `:legacy_local`.

### FR-T003 — Initial status

A valid, unblocked Agent Hub Task shall start in `pending` with `available_at` set to now unless supplied.

### FR-T004 — Validate preferred Agent

A preferred Agent must have an enabled binding to the Project.

### FR-T005 — Task idempotency

Repeated create requests using the same non-null `(project_id, idempotency_key)` shall return the existing Task rather than create a duplicate.

### FR-T006 — List and filter Tasks

The operator shall be able to filter by execution mode, status, Agent, type, and creation time.

### FR-T007 — Task detail

Task detail shall show current state, current Attempt, all prior Attempts, progress, result/error, and event timeline.

### FR-T008 — Preserve legacy fields

The new implementation shall not repurpose the existing string `agent_id` field used by legacy tasks.

---

## 9.7 Dispatch and Matching

### FR-D001 — Pull claim

Agents shall request work using `work.request.v1`; assignments shall be returned in the request ACK.

### FR-D002 — Best-effort wake-up

Samgita shall send `work.available.v1` to potentially eligible online Agents after Task creation/requeue, but correctness shall not depend on delivery.

### FR-D003 — Capacity enforcement

The number of active Attempts shall not exceed effective Agent connection capacity.

### FR-D004 — Project eligibility

Only Tasks from enabled Project-Agent bindings shall be eligible.

### FR-D005 — Capability eligibility

All Task required capabilities must exist in the Agent's effective capabilities.

### FR-D006 — Preferred Agent

A Task with a preferred Agent shall not be assigned to another Agent in Phase 1.

### FR-D007 — Deterministic ordering

Eligible Tasks shall be ordered by pinned preference, binding priority, Task priority, availability time, creation time, and ID.

### FR-D008 — Atomic claim

Claim shall use database locking so concurrent Agents cannot lease the same Task.

### FR-D009 — Create Attempt

Every successful claim shall create a new Task Attempt with a monotonic attempt number and fencing token.

### FR-D010 — Active-attempt uniqueness

A Task shall have at most one active Attempt enforced by both application logic and database constraint.

### FR-D011 — Assignment replay

Repeating the same work-request message ID after a lost response shall return the same canonical assignment. The lease token shall be re-derived from immutable Attempt data and a server-side signing key rather than stored in the Inbox.

### FR-D012 — No eligible work

When no eligible Task exists, the Agent shall receive a successful empty assignment response, not a server error.

---

## 9.8 Lease and Fencing

### FR-L001 — Lease token

Every Attempt shall receive an opaque HMAC-derived lease token bound to the Attempt, Task, Agent, and fencing token. Only its hash is stored; the token can be re-derived for idempotent assignment replay.

### FR-L002 — Lease expiration

Every active Attempt shall have `lease_expires_at` based on server time.

### FR-L003 — Lease renewal

Valid Agent heartbeat shall extend the lease for current Attempts.

### FR-L004 — Fencing token

Every new Attempt for a Task shall have a fencing token greater than all previous Attempts for that Task.

### FR-L005 — Validate all Attempt messages

Attempt-scoped messages shall validate Agent, current connection, Attempt ownership, current Task Attempt, lease token, fencing token, lease time, sequence, and Task cancellation.

### FR-L006 — Reject stale result

A result carrying an old fencing token or non-current Attempt ID shall be rejected and shall not modify Task state.

### FR-L007 — Durable lease reaper

An Oban worker shall expire stale Attempts and requeue or dead-letter Tasks idempotently.

### FR-L008 — Accept timeout

An Agent that does not accept an assignment within the configured timeout shall lose the Attempt through expiry/reaper processing.

---

## 9.9 Agent Status Protocol

### FR-S001 — Versioned envelope

Every message shall contain protocol version, message ID, type, Agent ID, connection ID, source time, and payload. Attempt messages also require Attempt ID, lease token, fencing token, and sequence.

### FR-S002 — Accept Task

`task.accepted.v1` shall transition Attempt from `leased` to `accepted`.

### FR-S003 — Reject Task

`task.rejected.v1` shall terminate the Attempt and let Samgita decide requeue/dead-letter behavior.

### FR-S004 — Start Task

`task.started.v1` shall transition Attempt to `running` and Task to `running`.

### FR-S005 — Report progress

`task.progress.v1` shall update the latest progress projection and append an audit event.

### FR-S006 — Complete Task

`task.completed.v1` shall atomically mark Attempt succeeded and Task completed when all lease/state checks pass.

### FR-S007 — Fail Task

`task.failed.v1` shall atomically mark Attempt failed and apply Samgita retry policy.

### FR-S008 — Report cancellation

`task.cancelled.v1` shall idempotently acknowledge local stop behavior for a cancelled Task.

### FR-S009 — Sequence enforcement

Attempt message sequence shall be strictly increasing. Duplicate message IDs replay ACK; conflicting or out-of-order messages are rejected.

### FR-S010 — Deterministic ACK

Every accepted message shall return an ACK containing the resulting Task/Attempt status, current sequence, server time, and event ID.

### FR-S011 — Payload limits

Messages exceeding the configured size or progress rate shall be rejected or throttled with a stable error.

### FR-S012 — Server authority

Agent-provided source timestamps and retry suggestions shall be preserved as metadata but shall not override server lease time or retry policy.

---

## 9.10 Retry, Expiry, and Dead Letter

### FR-R001 — Retry policy

A failed, rejected, or expired Attempt may requeue the Task when attempts remain and the Task is not cancelled.

### FR-R002 — Backoff

Requeued Tasks shall use configurable exponential backoff through `available_at`.

### FR-R003 — Maximum attempts

When maximum attempts are exhausted, the Task shall enter `dead_letter` unless an explicit terminal-failure policy selects `failed`.

### FR-R004 — Manual retry

The operator shall be able to retry `failed` or `dead_letter` Agent Hub Tasks.

### FR-R005 — Immutable history

Manual retry shall create a new Attempt later; it shall not delete or reset prior Attempt records.

### FR-R006 — Illegal retry

Completed, cancelled, assigned, and running Tasks shall not be retried.

---

## 9.11 Cancellation

### FR-X001 — Cancel pending Task

The operator shall be able to cancel a pending Agent Hub Task immediately.

### FR-X002 — Cancel active Task

The operator shall be able to cancel an assigned/running Task, and Samgita shall send a best-effort cancellation control message to its Agent.

### FR-X003 — Terminal authority

Once a Task is cancelled, terminal completion/failure from the old Attempt shall not alter it.

### FR-X004 — Idempotent cancellation

Repeated cancel commands shall return the already-cancelled state without duplicate events.

### FR-X005 — Agent stop acknowledgement

The Agent may report `task.cancelled.v1`; this shall be idempotent and visible in Attempt history.

---

## 9.12 Domain Events and Audit

### FR-E001 — Append-only events

Every accepted state-changing operator command or Agent message shall append one or more versioned domain events.

### FR-E002 — Same transaction

Aggregate updates and their domain events shall commit in the same database transaction.

### FR-E003 — Correlation

Task lifecycle events shall share a correlation ID so the full execution can be queried.

### FR-E004 — Persist before broadcast

PubSub and outgoing webhook notifications shall happen only after commit.

### FR-E005 — Event timeline

Task detail shall show chronological events for the Task and Attempts.

### FR-E006 — No secrets

Domain event payloads shall never include plaintext Agent credentials or lease tokens.

### FR-E007 — Not full event sourcing

Current aggregate tables remain authoritative; replay/rebuild of all aggregate state is not a release requirement.

---

## 9.13 Protocol Inbox and Idempotency

### FR-I001 — Store message receipt

Every accepted Agent message shall create an Agent Inbox receipt with a canonical non-secret ACK descriptor. Assignment lease tokens shall be re-derived only when serializing the ACK response.

### FR-I002 — Duplicate replay

A duplicate `(agent_id, message_id)` with the same payload shall return the stored ACK.

### FR-I003 — Conflict detection

A duplicate message ID with different payload shall be rejected as `message_id_conflict`.

### FR-I004 — Sequence uniqueness

An Attempt sequence number shall be processed at most once.

### FR-I005 — Transactional receipt

Inbox receipt, aggregate state, and domain events shall commit atomically.

---

## 9.14 API Requirements

### FR-API001 — Agent APIs

Provide create/list/show/update/enable/disable endpoints.

### FR-API002 — Credential APIs

Provide issue and revoke endpoints. Credential issue returns plaintext once.

### FR-API003 — Connection APIs

Provide Agent connection/history inspection endpoints.

### FR-API004 — Binding APIs

Provide list/create/update/delete Project-Agent binding endpoints.

### FR-API005 — Task APIs

Provide Agent Hub Task create/list/show/cancel/retry, Attempts, and events endpoints.

### FR-API006 — Existing protection

Admin endpoints shall use the existing API authentication and rate-limit pipeline.

### FR-API007 — Stable errors

API errors shall provide stable machine-readable codes and useful validation details.

---

## 9.15 UI Requirements

### FR-UI001 — Registered Agents list

Show registered Agent state, runtime, capacity, active Attempts, and last heartbeat.

### FR-UI002 — Create Agent

Provide an operational form to create an Agent and then issue a credential.

### FR-UI003 — One-time secret presentation

Display the new credential once with a clear warning that it cannot be viewed again.

### FR-UI004 — Agent detail

Show configuration, connection history, project bindings, active/recent Attempts, and credential metadata.

### FR-UI005 — Project Agent management

Allow operator to bind, configure, disable, and safely unbind Agents from a Project.

### FR-UI006 — Agent Hub Task creation

Allow creation of a Task from the Project page with capability and preferred-Agent fields.

### FR-UI007 — Task status

Show status, progress, assigned Agent, current lease expiration, and Attempt number in real time.

### FR-UI008 — Task timeline

Show immutable Attempt and domain-event history.

### FR-UI009 — Task controls

Show cancel or retry only when legal.

### FR-UI010 — Existing design system

Use Phoenix LiveView and existing DuskMoon components. Do not add another UI library.

---

## 9.16 Legacy Compatibility

### FR-B001 — Legacy default

The Task schema shall default `execution_mode` to `legacy_local` so existing callers remain unchanged.

### FR-B002 — Dispatcher isolation

The new Dispatcher shall never claim `legacy_local` Tasks.

### FR-B003 — Existing worker isolation

The existing `AgentTaskWorker` shall not process `agent_hub` Tasks unless a future explicit adapter is implemented.

### FR-B004 — Preserve Orchestrator

No Phase 1 change shall alter the fixed project-phase behavior or task generation semantics of `Project.Orchestrator`.

### FR-B005 — Preserve AgentRun

`AgentRun` shall not be repurposed as Task Attempt.

### FR-B006 — Preserve provider adapter

`SamgitaProvider.Synapsis` shall not become the Agent Channel implementation.

---

## 10. Non-Functional Requirements

## 10.1 Durability

### NFR-DUR001

A committed Task, Attempt, message receipt, or domain event shall survive Samgita process/node restart.

### NFR-DUR002

A Task assignment shall be recoverable through repeated work request or reconnect even if the assignment response was lost.

### NFR-DUR003

Lease expiry shall be processed durably by Oban and remain safe under repeated execution.

## 10.2 Consistency

### NFR-CON001

A Task shall never have two database-valid active Attempts.

### NFR-CON002

Task and current Attempt statuses shall not contradict each other after a committed transition.

### NFR-CON003

Task, Attempt, Domain Event, and Inbox ACK changes for one protocol message shall be atomic.

### NFR-CON004

Stale fencing tokens shall never produce a successful terminal transition.

## 10.3 Availability and Recovery

### NFR-AVL001

Loss of PubSub messages shall not lose Tasks.

### NFR-AVL002

Agents shall reconnect with no operator action after transient disconnection.

### NFR-AVL003

Samgita shall recover authoritative state from PostgreSQL, not from socket process memory.

## 10.4 Performance

### NFR-PERF001

With up to 100 connected Agents and 1,000 pending Tasks, a work request should normally return within 500 ms excluding network latency under a healthy local PostgreSQL deployment.

### NFR-PERF002

Task progress updates shall not block other Agent connections on external work.

### NFR-PERF003

The dispatch query shall use indexed predicates and bounded locking.

### NFR-PERF004

The UI shall use batched queries/preloads and avoid per-Agent/Task N+1 patterns.

## 10.5 Security

### NFR-SEC001

Agent Socket authentication is mandatory.

### NFR-SEC002

Secrets shall not be stored or logged in plaintext. The Agent Hub lease-signing key shall be loaded from runtime secret configuration and remain stable across restarts.

### NFR-SEC003

An Agent shall be unable to operate on another Agent's Attempt.

### NFR-SEC004

An Agent shall be unable to claim an unbound Project.

### NFR-SEC005

Message size and authentication failure rates shall be bounded.

## 10.6 Observability

### NFR-OBS001

Connection, dispatch, attempt transition, lease expiry, duplicate, and rejection activity shall emit telemetry.

### NFR-OBS002

Logs shall carry correlation identifiers without secret payloads.

### NFR-OBS003

Operators shall be able to inspect why a Task is pending, ineligible, expired, failed, or dead-lettered.

## 10.7 Testability

### NFR-TST001

Samgita CI shall test the full protocol with a fake Agent and mock provider; a real Synapsis or LLM service is not required.

### NFR-TST002

State-machine and matcher logic shall be pure where practical.

### NFR-TST003

Concurrency tests shall verify claim, cancellation, reaper, and fencing races.

## 10.8 Maintainability

### NFR-MNT001

Business logic shall remain in core contexts, not Channel/controller callbacks.

### NFR-MNT002

The new implementation shall preserve umbrella dependency direction.

### NFR-MNT003

Protocol type strings and error codes shall be centralized.

---

## 11. Defaults and Configurability

| Configuration | Default |
|---|---:|
| `agent_hub_v1_enabled` | false in production until rollout |
| Protocol version | 1 |
| Lease signing key | Required secret in production; stable across restarts |
| Agent heartbeat interval | 15 seconds |
| Offline threshold | 45 seconds |
| Assignment accept timeout | 20 seconds |
| Lease duration | 120 seconds |
| Lease renewal target | 30 seconds |
| Lease reaper maximum cadence | 60 seconds |
| Task timeout | 900 seconds |
| Task maximum attempts | 3 |
| Progress minimum interval | 2 seconds |
| Maximum protocol payload | 256 KiB |
| Agent maximum concurrency | 1 |

Configuration belongs in runtime/application config and must be validated at startup where practical.

---

## 12. Success Metrics

The first release is successful when:

1. A fake or Synapsis Agent can remain connected for at least 24 hours with heartbeat and reconnect.
2. Duplicate assignment/status messages create no duplicate Attempts or terminal transitions.
3. Concurrent claim testing produces exactly one active Attempt for one Task.
4. A stale completion after reassignment is rejected in every test run.
5. Samgita restart during an active Attempt recovers through Agent reconnect.
6. Operators can identify current Agent, Attempt, progress, and failure reason from UI/API.
7. Legacy PRD orchestration tests remain passing.
8. No plaintext Agent or lease secret appears in database event rows, logs, or API reads.

---

## 13. Acceptance Scenarios

## AS-001 — Connect Agent

**Given** an enabled Agent and active credential  
**When** Synapsis authenticates, joins its Agent topic, and sends valid hello  
**Then** Samgita creates an active connection, returns welcome, and shows the Agent online.

## AS-002 — Reject invalid credential

**Given** an unknown, revoked, expired, or incorrect token  
**When** the client connects  
**Then** the socket is rejected, no active connection is created, and no secret is logged.

## AS-003 — Replace connection

**Given** Agent A has an active connection  
**When** another valid instance of Agent A connects  
**Then** the newer connection becomes current and the older connection is closed as replaced.

## AS-004 — Bind Agent

**Given** a Project and Agent  
**When** the operator creates a binding  
**Then** the binding is visible and unique for the pair.

## AS-005 — Prevent unauthorized claim

**Given** an Agent not bound to Project P  
**And** a pending Task in Project P  
**When** the Agent requests work  
**Then** the Task is not returned.

## AS-006 — Capability match

**Given** a Task requires `language:elixir` and `role:implement`  
**When** an Agent lacking one capability requests work  
**Then** it receives no assignment.

## AS-007 — Atomic claim

**Given** one pending Task and two eligible Agents  
**When** both request work concurrently  
**Then** exactly one receives an assignment and exactly one active Attempt exists.

## AS-008 — Complete Task

**Given** a valid current running Attempt  
**When** the Agent sends a valid next-sequence completion message  
**Then** Attempt becomes succeeded, Task becomes completed, events are appended, and ACK is stored atomically.

## AS-009 — Duplicate completion

**Given** a completion message was accepted  
**When** the Agent sends the same message ID and payload again  
**Then** Samgita returns the stored ACK and creates no new transition/event.

## AS-010 — Conflicting duplicate

**Given** a message ID was accepted  
**When** the Agent reuses it with a different payload  
**Then** Samgita rejects it as `message_id_conflict`.

## AS-011 — Lease expiry and reassignment

**Given** Attempt 1 stops heartbeating  
**When** its lease expires and the reaper runs  
**Then** Attempt 1 becomes expired and the Task is requeued when attempts remain.

## AS-012 — Reject stale completion

**Given** Attempt 2 is now current with fencing token 2  
**When** Attempt 1 sends completion with fencing token 1  
**Then** Samgita rejects it and leaves Attempt 2/Task unchanged.

## AS-013 — Reconnect and replay

**Given** an Agent has unacknowledged ordered status messages  
**When** it reconnects and replays them  
**Then** already accepted messages replay ACK and remaining messages apply once in sequence.

## AS-014 — Cancel running Task

**Given** a running Task  
**When** the operator cancels it  
**Then** Task is terminally cancelled, the Agent receives cancellation, and later completion is rejected.

## AS-015 — Manual retry

**Given** a dead-letter Task  
**When** the operator retries it  
**Then** it becomes pending without deleting prior Attempts and the next claim uses a higher fencing token.

## AS-016 — Legacy isolation

**Given** a pending legacy-local Task  
**When** an external Agent requests work  
**Then** the legacy Task is never returned.

## AS-017 — Restart recovery

**Given** an active Attempt  
**When** Samgita restarts and the Agent reconnects before lease expiry  
**Then** Samgita can resume the current Attempt from PostgreSQL state.

## AS-018 — Event atomicity

**Given** a database error during a transition  
**When** the transaction rolls back  
**Then** Task/Attempt state, Inbox receipt, and Domain Events remain unchanged and no success broadcast occurs.

---

## 14. Definition of Done

Agent Hub Phase 1 is complete only when all are true:

- [ ] Registered Agent CRUD and derived status are implemented.
- [ ] Secure credential issue/rotate/revoke is implemented.
- [ ] Agent Socket authentication and hello/welcome are implemented.
- [ ] One-active-connection replacement is implemented.
- [ ] Heartbeat, offline derivation, lease renewal, and reconnect reconciliation work.
- [ ] Project-Agent binding and capability restrictions work.
- [ ] Agent Hub Task creation is isolated from legacy tasks.
- [ ] Atomic pull-claim creates a Task Attempt, lease, and fencing token.
- [ ] Agent can accept, start, progress, complete, fail, reject, and acknowledge cancellation.
- [ ] Inbox deduplication and deterministic ACK replay work.
- [ ] Lease reaper safely requeues or dead-letters.
- [ ] Cancellation and manual retry work.
- [ ] Stale results are rejected.
- [ ] Aggregate changes and domain events commit atomically.
- [ ] API and minimum operational LiveViews are implemented.
- [ ] Fake-Agent end-to-end test passes without an external LLM.
- [ ] Concurrency and restart/reconnect tests pass.
- [ ] Existing scoped legacy orchestration tests remain passing.
- [ ] `mix format --check-formatted` passes for modified files.
- [ ] Scoped Credo/Dialyzer/test checks pass as defined by the implementation plan.
- [ ] No out-of-scope GitHub/workflow/release functionality is added.

---

## 15. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| New dispatcher claims legacy tasks | Mandatory `execution_mode` filter and tests |
| Duplicate execution during race | Row lock, active-attempt partial unique index, fencing |
| Lost assignment response | Durable Inbox ACK replay and hello resume |
| Agent lies about capabilities | Effective intersection with operator-approved capabilities |
| Stale socket keeps sending | Active connection ID check on every message |
| Database write volume from heartbeat/progress | Reasonable intervals, indexes, optional later coalescing |
| Channel becomes business-logic monolith | Thin transport; contexts and pure state machine own behavior |
| Credential leakage | One-time plaintext, hash storage, no logs/events, no-store response |
| Reaper double-processing | Locks, terminal checks, idempotent transactions |
| Phase scope expands into workflow/GitHub | Explicit non-goals and execution-plan stop boundary |
| Synapsis implementation blocks Samgita CI | Fake-Agent conformance client in Samgita tests |

---

## 16. Future Extensions

The following are enabled by, but not included in, Phase 1:

- Multiple repositories per Project.
- Logical Agent pools with multiple active instances.
- Managed local Codex/Claude Agents using the same Attempt protocol.
- Agent-created child Tasks.
- Workflow definitions and sagas.
- GitHub Issue-to-Task ingestion.
- PR creation and independent reviewer Agents.
- Merge/release policy engines.
- Artifact object storage and streaming logs.
- mTLS Agent identity.
- Fair-share and cost-aware scheduling.

No Phase 1 implementation should preemptively build these features.
