# Samgita Agent Hub Phase 1 Implementation Plan

**Status:** Codex execution plan  
**Target repository:** `gsmlg-opt/Samgita`  
**Target path:** `docs/agent-hub-v1/plan.md`  
**Required references:** `architecture.md`, `prd.md`, repository root `AGENTS.md`

---

## 1. Execution Objective

Implement the smallest production-quality Agent Hub loop in Samgita:

```text
registered Agent
  -> authenticated WebSocket connection
  -> Project-Agent binding
  -> Agent Hub Task creation
  -> atomic pull claim
  -> leased Task Attempt
  -> accepted/started/progress/completed or failed
  -> retry/cancel/expiry/reconnect
  -> API and operational UI
```

The plan is organized as six bounded PRs. Execute them in dependency order. Do not combine all work into one large PR.

---

## 2. Codex Operating Rules

Before starting:

1. Read `AGENTS.md` in the repository root.
2. Read `docs/agent-hub-v1/architecture.md` and `prd.md` completely.
3. Inspect current migrations, domain schemas, contexts, router, endpoint/socket setup, PubSub conventions, Oban config, and relevant tests.
4. Confirm the current branch/worktree is clean enough to work without overwriting user changes.
5. Put any manually created worktree under `.trees/<branch-name>`.

During implementation:

- Work only in the current PR scope.
- Preserve umbrella dependency direction.
- Do not introduce browser authentication/RBAC.
- Do not alter existing PRD Orchestrator behavior.
- Do not repurpose `AgentRun`, `Samgita.Agent.Worker`, the legacy Task `agent_id`, or `SamgitaProvider.Synapsis`.
- Persist before PubSub broadcast.
- Use PostgreSQL for authoritative state and Oban for durable background work.
- Add tests alongside every module/change.
- Avoid unrelated formatting, dependency updates, or refactors.
- Report unrelated failures rather than fixing them outside scope.
- Follow upstream issue-routing rules from `AGENTS.md` when blocked by an internal dependency.

After each PR:

```bash
mix format --check-formatted
mix test <scoped test paths>
mix credo --strict <when practical for the owning app>
```

Run broader checks only after scoped checks pass and at the final integration milestone.

---

## 3. Delivery Strategy

| PR | Name | Depends on | Primary result |
|---|---|---|---|
| 1 | Domain foundation | none | Schemas, migrations, contexts, pure state model |
| 2 | Agent connection protocol | PR 1 | Credentials, socket auth, hello, connection, heartbeat |
| 3 | Atomic dispatch and leases | PR 1–2 | Matcher, claim, TaskAttempt lease/fencing, reaper |
| 4 | Agent task status and recovery | PR 1–3 | Ordered/idempotent transitions, retry, cancel, resume |
| 5 | Admin API and LiveView | PR 1–4 | Operator workflows and real-time visibility |
| 6 | End-to-end hardening | PR 1–5 | Fake Agent, races, restart/reconnect, docs, release gate |

Do not begin GitHub, workflow, PR, review, merge, or release work after PR 6. That is a separate phase.

---

# PR 1 — Domain Foundation

## 4. Goal

Add the durable Agent Hub data model, migration-safe legacy isolation, core contexts, and pure state-machine definitions. No WebSocket and no live dispatch in this PR.

## 5. Branch and commit

Suggested branch:

```text
feat/agent-hub-domain
```

Suggested commits:

```text
feat(agent-hub): add registered agent domain
feat(tasking): add task attempts and execution mode
feat(events): add agent inbox and domain event journal
test(agent-hub): cover domain invariants
```

## 6. Tasks

### 6.1 Inspect existing state

Review at minimum:

```text
apps/samgita/lib/samgita/domain/project.ex
apps/samgita/lib/samgita/domain/task.ex
apps/samgita/lib/samgita/domain/agent_run.ex
apps/samgita/lib/samgita/projects.ex
apps/samgita/lib/samgita/events.ex
apps/samgita/priv/repo/migrations/
apps/samgita/test/
```

Document any schema/index naming conflicts before coding.

### 6.2 Create migrations

Create migrations in dependency-safe order for:

1. `agents`.
2. `agent_credentials`.
3. `agent_connections`.
4. `project_agents`.
5. `task_attempts`.
6. Alter `tasks` with new Agent Hub fields.
7. `agent_inbox`.
8. `domain_events`.

Required indexes/constraints:

- Unique Agent name.
- Credential token hash index and Agent index.
- One active connection per Agent partial unique index.
- Unique Project-Agent pair.
- Unique `(task_id, attempt_no)`.
- One active Attempt per Task partial unique index.
- Active Attempt lease-expiry index.
- Unique `(project_id, idempotency_key)` for non-null Task keys.
- Unique `(agent_id, message_id)` in Agent Inbox.
- Unique `(attempt_id, sequence)` where non-null.
- Domain-event aggregate/correlation indexes.
- Unique source/idempotency key where non-null.

Migration compatibility:

- `tasks.execution_mode` must default to `legacy_local`.
- Existing rows must backfill to `legacy_local`.
- New text fields may be nullable because legacy Tasks do not have them.
- Add `cancelled` to the Ecto status enum definition without rewriting existing stored values.
- Do not remove existing Task fields.

### 6.3 Add Ecto schemas

Add:

```text
Samgita.Domain.Agent
Samgita.Domain.AgentCredential
Samgita.Domain.AgentConnection
Samgita.Domain.ProjectAgent
Samgita.Domain.TaskAttempt
Samgita.Domain.AgentInbox
Samgita.Domain.DomainEvent
```

Update `Samgita.Domain.Task` with fields and associations from `architecture.md`.

Changesets must validate:

- Required fields.
- Positive concurrency, timeout, max attempts, attempt number, and fencing token.
- Capability arrays contain normalized non-empty strings.
- Attempt status enum.
- Foreign keys and unique constraints.

### 6.4 Add capability helper

Create `Samgita.Agents.Capability` with pure functions:

```text
normalize/1
valid?/1
effective/3
satisfies?/2
```

Normalization rules:

- Trim whitespace.
- Lowercase namespace/name.
- Require `<namespace>:<name>`.
- Deduplicate and sort.
- Reject empty or malformed values.

### 6.5 Add pure task state machine

Create `Samgita.Tasking.StateMachine` and transition data type/module.

Cover legal transitions for:

```text
Task: blocked, pending, assigned, running, completed, failed, cancelled, skipped, dead_letter
Attempt: leased, accepted, running, succeeded, failed, expired, rejected, cancelled
```

The module must not access Repo, PubSub, or current time. Callers supply current state and transition input.

### 6.6 Add retry policy

Create `Samgita.Tasking.RetryPolicy`:

- Determine whether a terminal Attempt requeues.
- Compute exponential backoff with a configurable cap.
- Select `pending`, `failed`, or `dead_letter`.
- Agent-provided retryability is advisory input.

### 6.7 Add contexts

Create minimal public contexts:

```text
Samgita.Agents
Samgita.Tasking
Samgita.DomainEvents
```

PR 1 context surface should support:

```text
Agents:
  create_agent
  get_agent
  list_agents
  update_agent
  enable_agent
  disable_agent
  bind_agent
  update_binding
  unbind_agent
  list_project_agents

Tasking:
  create_agent_hub_task
  get_task
  list_agent_hub_tasks
  list_attempts
  cancel_pending_task
  retry_terminal_task

DomainEvents:
  append (transaction-aware)
  list_for_aggregate
  list_for_correlation
```

Do not implement socket authentication or task claim yet.

### 6.8 Add domain events to new commands

Agent creation, enable/disable, binding changes, Task creation, pending cancellation, and manual retry must append Domain Events in the same `Ecto.Multi` transaction.

Broadcast only after transaction success. Reuse existing `Samgita.Events` topics/functions where appropriate, adding focused functions rather than broad unrelated refactoring.

## 7. PR 1 Tests

Add tests for:

- Agent validation and uniqueness.
- Capability normalization/intersection.
- Project-Agent uniqueness and safe unbind with active work.
- Agent Hub Task creation.
- Task creation idempotency.
- Legacy default execution mode.
- Agent Hub required title/description validation.
- State-machine full legal/illegal transition matrix.
- Retry/backoff decisions.
- Task/Attempt enum behavior.
- Database active-attempt partial unique constraint.
- Domain Event rolls back when aggregate update fails.
- No plaintext-token fields exist in domain event payload structures.

Suggested test locations:

```text
apps/samgita/test/samgita/agents_test.exs
apps/samgita/test/samgita/agents/capability_test.exs
apps/samgita/test/samgita/tasking_test.exs
apps/samgita/test/samgita/tasking/state_machine_test.exs
apps/samgita/test/samgita/tasking/retry_policy_test.exs
apps/samgita/test/samgita/domain_events_test.exs
```

## 8. PR 1 Acceptance

- Migrations apply on a database containing existing Tasks.
- Existing Tasks read as `legacy_local`.
- New Agent Hub Task is created as `pending` and cannot collide on idempotency key.
- Project-Agent binding is explicit and unique.
- One Task cannot have two active Attempts at the database level.
- New context tests pass.
- Existing focused Project/Task schema tests remain passing.

---

# PR 2 — Agent Connection Protocol

## 9. Goal

Implement credential lifecycle, Agent Socket authentication, hello/welcome, one-active-connection behavior, heartbeat, and derived online state. No Task claim yet.

## 10. Branch and commit

Suggested branch:

```text
feat/agent-hub-connection
```

Suggested commits:

```text
feat(agent): add machine credential lifecycle
feat(agent-protocol): add authenticated agent socket
feat(agent-protocol): add hello and heartbeat
test(agent-protocol): cover connection lifecycle
```

## 11. Tasks

### 11.1 Credential service

Add `Samgita.Agents.Credential` and context functions:

```text
issue_credential(agent, opts)
authenticate(agent_id, plaintext_token)
revoke_credential(agent_id, credential_id)
list_credentials(agent_id)
```

Requirements:

- Generate Agent credentials with at least 32 random bytes and encode them in a transport-safe format.
- Include a recognizable non-secret prefix.
- Store SHA-256 hash only for Agent credentials.
- Compare in constant time.
- Return plaintext once.
- Update `last_used_at` only after successful authentication.
- Emit issue/revoke events without plaintext.

### 11.2 Runtime config

Add validated settings for:

```text
agent_hub_v1_enabled
agent_protocol_versions
agent_heartbeat_interval_seconds
agent_offline_threshold_seconds
agent_lease_duration_seconds
agent_assignment_accept_timeout_seconds
agent_protocol_max_payload_bytes
agent_lease_signing_key
```

Use safe test/development defaults. Production remains disabled until final rollout.

### 11.3 Agent Socket

Add:

```text
SamgitaWeb.AgentSocket
SamgitaWeb.AgentChannel
```

Register socket in the Phoenix Endpoint at `/agent/socket`.

Socket `connect/3` must:

- Reject feature disabled.
- Parse Agent ID, token, instance ID, and protocol version.
- Authenticate through `Samgita.Agents`.
- Assign only non-secret identity/credential metadata to the socket.
- Never trust a later join payload to change Agent ID.

Channel topic must be exactly the authenticated `agent:<agent_id>`.

### 11.4 Protocol envelope foundation

Add:

```text
Samgita.AgentProtocol.Envelope
Samgita.AgentProtocol.Validator
Samgita.AgentProtocol.Ack
Samgita.AgentProtocol
```

PR 2 needs hello and heartbeat handlers. Later PRs add work/task handlers.

Centralize:

- Message type constants.
- Protocol version checks.
- Required-field validation.
- Stable error format.
- Payload hash computation.

### 11.5 Connection lifecycle

Add context functions:

```text
open_connection
heartbeat_connection
close_connection
get_active_connection
list_connections
connection_state
```

Opening a connection must use a transaction:

1. Lock Agent.
2. Close previous active connection as `replaced`.
3. Insert new active connection.
4. Update last seen.
5. Append domain event.
6. Commit.
7. Broadcast replacement control after commit.

Channel termination must best-effort close only the matching current connection. It must not close a newer replacement.

### 11.6 Hello handler

Implement `agent.hello.v1`:

- Validate runtime metadata.
- Normalize reported capabilities.
- Cap reported concurrency by configured Agent max.
- Compute accepted/effective capabilities.
- Persist connection metadata.
- Reconcile listed active Attempt IDs against current database state.
- Return welcome fields and resume/invalid arrays.

At this PR, active Attempt arrays can normally be empty, but the reconciliation interface and tests must exist for later use.

### 11.7 Heartbeat handler

Implement `agent.heartbeat.v1`:

- Validate active connection.
- Update last heartbeat and Agent last seen.
- Persist a compact heartbeat event according to architecture; avoid secrets.
- Return server time, derived state, and invalid attempts.
- Do not implement lease renewal until PR 3, but keep the response shape compatible.

### 11.8 Connection PubSub

Use topics:

```text
agents
agent:<agent_id>
agent-control:<agent_id>
```

Broadcast connection state only after commit.

## 12. PR 2 Tests

Add tests for:

- Credential entropy/prefix/hash storage.
- Successful and failed authentication.
- Revoked/expired credential.
- Plaintext is not retrievable.
- Socket feature flag.
- Unsupported protocol version.
- Topic identity enforcement.
- Hello/welcome.
- Effective capability intersection.
- One active connection and replacement.
- Old channel termination does not close new connection.
- Heartbeat updates timestamps.
- Derived online/offline/idle state.
- No secret in logs/events/serialized connection.

Suggested paths:

```text
apps/samgita/test/samgita/agents/credential_test.exs
apps/samgita/test/samgita/agents/connection_test.exs
apps/samgita/test/samgita/agent_protocol_test.exs
apps/samgita_web/test/samgita_web/channels/agent_socket_test.exs
apps/samgita_web/test/samgita_web/channels/agent_channel_test.exs
```

## 13. PR 2 Acceptance

- A test Agent authenticates and receives welcome.
- Invalid credentials never join.
- New connection replaces old across PubSub control flow.
- Heartbeat updates derived state.
- Connection history survives process restart.
- No dispatch behavior is present yet.

---

# PR 3 — Atomic Dispatch and Leases

## 14. Goal

Implement capability matching, work request, atomic claim, Task Attempt lease/fencing, lease renewal, work wake-up, and durable lease expiry.

## 15. Branch and commit

Suggested branch:

```text
feat/agent-hub-dispatch
```

Suggested commits:

```text
feat(dispatch): add capability matcher
feat(dispatch): atomically claim agent hub tasks
feat(dispatch): renew and expire task leases
test(dispatch): cover concurrency and fencing
```

## 16. Tasks

### 16.1 Pure matcher

Add `Samgita.Dispatch.Matcher` to evaluate and rank candidates.

Inputs:

```text
Agent
active AgentConnection
ProjectAgent binding
Task
active attempt/capacity counts
```

Outputs:

```text
eligible? + reason codes
sorting tuple
```

Reason codes must support operator diagnostics:

```text
agent_disabled
connection_offline
binding_missing
binding_disabled
capacity_full
capability_mismatch
preferred_agent_mismatch
not_available_yet
attempts_exhausted
legacy_execution_mode
```

### 16.2 Atomic claimer

Add `Samgita.Dispatch.Claimer` and public `Samgita.Dispatch.claim/3`.

Implement Task selection with `FOR UPDATE SKIP LOCKED` and indexed predicates.

Claim up to effective free slots, but bound the maximum per request to a safe configured number.

Each Task claim uses `Ecto.Multi` to:

- select and lock Task;
- compute Attempt number;
- compute next fencing token;
- derive and hash the lease token without persisting plaintext;
- create Attempt;
- set Task `assigned` and current Attempt;
- append Attempt and Task events;
- insert an Agent Inbox receipt containing a canonical non-secret assignment descriptor; rehydrate the deterministic lease token only in the transport response.

Do not persist or expose the plaintext lease token outside the Agent assignment transport response. Assignment replay re-derives the same token from the server-side signing key.

### 16.3 Work request handler

Add `work.request.v1` to Agent Protocol.

Rules:

- Require active hello-complete connection.
- Validate requested free slots.
- Recompute effective free capacity server-side.
- Return zero or more assignments.
- Empty result is successful.
- Duplicate message ID returns the same assignment set.

### 16.4 Work available notifier

Add `Samgita.Dispatch.Notifier` as a plain module unless a process is demonstrably required.

After Task creation or requeue:

- Find a bounded set of potentially eligible connected Agents.
- Broadcast `work.available.v1` to `agent:<agent_id>`.
- Include only Task/project IDs and capability hints; no lease or secret.
- Failure to notify must not roll back the committed Task.

### 16.5 Lease validation helper

Add `Samgita.Dispatch.Lease`:

```text
derive_token
hash_token
valid_token?
validate_attempt_lease
renew_attempts
```

Derive the opaque token using HMAC over immutable Attempt/Task/Agent identifiers and fencing token with the dedicated runtime signing key. Store only the token hash, re-derive the token for assignment replay, and use server time plus constant-time hash comparison.

### 16.6 Heartbeat lease renewal

Extend `agent.heartbeat.v1`:

- Validate every listed Attempt.
- Renew current valid leases.
- Return renewed expiration per Attempt.
- Return invalid/stale attempts separately.
- A bad Attempt entry must not invalidate unrelated valid renewals unless the envelope itself is invalid.

Use one transaction or carefully bounded per-attempt transactions with deterministic behavior; document the choice in code.

### 16.7 Lease reaper worker

Add `Samgita.Workers.LeaseReaperWorker`.

Use Oban for recurring durable execution. Configure cadence no slower than 60 seconds.

For each expired active Attempt:

- lock Attempt/Task;
- re-check expiration/status/current Attempt;
- mark Attempt expired;
- apply retry policy;
- keep `current_attempt_id` pointing at the most recent terminal Attempt for inspection; the next claim overwrites it;
- append events;
- commit;
- notify eligible Agents if requeued.

Worker must be idempotent and safe under overlapping invocations.

### 16.8 Attempt accept timeout

The same lease/reaper mechanism may expire an unaccepted `leased` Attempt after the shorter assignment-accept deadline. Store enough metadata to distinguish the deadline or calculate it from `leased_at` and configuration.

## 17. PR 3 Tests

Add tests for:

- Matcher eligibility and every reason code.
- Deterministic ordering.
- Preferred Agent behavior.
- Capacity cap.
- Agent bound to multiple Projects.
- Atomic claim creates Attempt and assigned Task.
- Lease token stored only as hash.
- Monotonic attempt number and fencing token.
- Duplicate work request returns same assignment.
- Two concurrent Agents claim one Task; exactly one assignment.
- One Agent requests multiple slots without exceeding capacity.
- Legacy task never claimed.
- Heartbeat renews valid lease.
- Invalid token/fencing is not renewed.
- Reaper expires and requeues.
- Reaper dead-letters when exhausted.
- Reaper double execution is harmless.
- Work-available loss does not affect later pull claim.

## 18. PR 3 Acceptance

- An authenticated Agent requests and receives an assignment.
- Exactly one active Attempt exists.
- Assignment contains the derived plaintext lease token; database and Inbox do not. Replaying the same request re-derives the same token.
- Heartbeat keeps Attempt alive.
- Expired Attempt is requeued or dead-lettered durably.
- Concurrent claim tests are stable.

---

# PR 4 — Task Status, Idempotency, Cancellation, and Recovery

## 19. Goal

Complete the Agent execution protocol: accept, reject, start, progress, complete, fail, cancel, ordered message processing, deterministic ACK replay, retry, and reconnect resume.

## 20. Branch and commit

Suggested branch:

```text
feat/agent-hub-task-protocol
```

Suggested commits:

```text
feat(agent-protocol): process ordered task status events
feat(tasking): add cancellation and retry lifecycle
feat(agent-protocol): resume attempts after reconnect
test(agent-protocol): cover duplicate and stale results
```

## 21. Tasks

### 21.1 Agent Inbox processor

Implement reusable processing flow:

1. Validate envelope shape and payload size.
2. Verify authenticated Agent and current connection.
3. Compute payload hash.
4. Look up `(agent_id, message_id)`.
5. If same hash exists, return stored ACK.
6. If different hash exists, reject conflict.
7. For Attempt messages, lock Attempt and Task.
8. Validate lease, fencing, current Attempt, status, cancellation, and sequence.
9. Apply pure state transition.
10. Update aggregates.
11. Append events.
12. Insert Inbox receipt with ACK.
13. Commit.
14. Broadcast after commit.

Centralize this pipeline. Do not duplicate it in each Channel callback.

### 21.2 Implement message handlers

Implement:

```text
task.accepted.v1
task.rejected.v1
task.started.v1
task.progress.v1
task.completed.v1
task.failed.v1
task.cancelled.v1
```

Payload validators should be separate and return stable errors.

### 21.3 Progress projection

- Accept progress for accepted/running Attempts.
- Validate optional percentage.
- Store latest progress on Attempt and Task.
- Append a compact event.
- Rate-limit excessive progress updates without losing terminal messages.
- Do not store unbounded logs.

### 21.4 Completion

On valid completion:

- Attempt -> succeeded.
- Task -> completed.
- Store result and metrics.
- Preserve Attempt history.
- Append both events.
- Return final ACK.
- Notify Agent that capacity is available for another work request.

### 21.5 Failure and rejection

On failure/rejection:

- Store structured error.
- Apply retry policy.
- Requeue with backoff or mark failed/dead-letter.
- Never let client override maximum attempts.
- Notify candidates after requeue.

### 21.6 Cancellation command

Extend `Samgita.Tasking.cancel_task/2`:

- Pending Task -> cancelled.
- Assigned/running Task -> cancelled and active Attempt invalidated/cancelled according to state model.
- Append events in one transaction.
- Broadcast `task.cancel.v1` after commit.
- Repeated cancel is idempotent.
- Later task status from that Attempt is rejected.

### 21.7 Manual retry

Implement retry for failed/dead-letter Agent Hub Tasks:

- Reject illegal statuses.
- Preserve previous Attempts.
- Reset current projection fields needed for a new execution.
- Keep attempt count/history so the next Attempt number/fencing token increases.
- Decide whether manual retry resets max-attempt budget; architecture recommends preserving history while allowing an explicit new execution. Document and test the selected rule. Default: reset dispatch eligibility without deleting attempts and treat operator retry as authorization for one new Attempt.

### 21.8 Reconnect resume

Extend hello reconciliation:

- Return resumable active Attempts with authoritative sequence and lease expiration.
- Return invalid Attempts with reason code.
- Renew resumable lease within configured reconnect grace policy.
- Do not resurrect expired/reassigned/cancelled Attempts.

### 21.9 Connection enforcement

Every task message must reject an old/replaced connection, even if Agent ID and lease token are otherwise valid.

## 22. PR 4 Tests

Add tests for:

- Legal accept/start/progress/complete lifecycle.
- Complete before start is rejected.
- Reject and failure retry policy.
- Progress percentage and rate limit.
- Duplicate message canonical ACK replay, with assignment secrets re-derived at response time.
- Conflicting message ID.
- Sequence gap and out-of-order sequence.
- Invalid lease token.
- Expired lease.
- Old connection ID.
- Attempt belongs to different Agent.
- Stale fencing token after reassignment.
- Cancellation versus completion race.
- Failed/dead-letter manual retry.
- Reconnect with resumable Attempt.
- Reconnect with stale Attempt.
- Aggregate/Event/Inbox atomic rollback.
- No secret in event/inbox serialization except encrypted/hashed fields as designed.

## 23. PR 4 Acceptance

- Fake Agent can execute the full status lifecycle.
- Duplicate messages are harmless.
- Out-of-order and stale messages are rejected.
- Cancellation is terminal and safe.
- Failure, expiry, and manual retry preserve history.
- Reconnect resume works from PostgreSQL state.

---

# PR 5 — Admin API and LiveView

## 24. Goal

Expose complete operator workflows through REST API and focused LiveView pages using existing design conventions.

## 25. Branch and commit

Suggested branch:

```text
feat/agent-hub-ui-api
```

Suggested commits:

```text
feat(api): expose registered agents and project bindings
feat(api): expose agent hub task lifecycle
feat(web): add agent and task operational views
test(web): cover agent hub workflows
```

## 26. Tasks

### 26.1 Router and controllers

Add protected admin routes defined in `architecture.md`.

Controllers stay thin and call core contexts.

Required response properties:

- Stable error codes.
- UUIDs and timestamps serialized consistently.
- Credential plaintext only in creation response.
- `cache-control: no-store` for credential creation.
- No lease token in admin API responses.

### 26.2 Agent APIs

Implement:

- create/list/show/update;
- enable/disable;
- credential issue/revoke/list metadata;
- connection history;
- active Attempt summary.

### 26.3 Project-Agent APIs

Implement:

- list bindings;
- bind/update/disable;
- safe unbind;
- effective capabilities and ineligibility diagnostics.

### 26.4 Task APIs

Implement:

- create Agent Hub Task;
- list/filter;
- show;
- cancel;
- retry;
- list Attempts;
- list Domain Events.

Do not change existing legacy API behavior unintentionally. Prefer a focused controller/action for Agent Hub creation when route ambiguity exists.

### 26.5 Registered Agents LiveView

Evolve `/agents` into a registered Agent operations page.

Minimum features:

- list with enabled/runtime/online state;
- active Attempts/capacity;
- last heartbeat;
- create Agent;
- Agent detail;
- issue/revoke credential;
- one-time credential modal/panel;
- connection history;
- project bindings.

Keep legacy local AgentRun data accessible in Project context or a distinct section; do not silently remove it.

### 26.6 Project detail additions

Add:

- bound Agents panel;
- bind/configure/unbind actions;
- create Agent Hub Task form;
- Agent Hub Task table and filters.

Preserve existing PRD/orchestrator panels.

### 26.7 Task detail

Show:

- Task status and fields;
- assigned Agent/current Attempt;
- lease expiration without token;
- progress;
- result/error;
- Attempt history;
- event timeline;
- legal cancel/retry controls.

### 26.8 Real-time subscriptions

Subscribe to post-commit PubSub topics for:

```text
agents
project:<project_id>
task:<task_id>
```

Always re-fetch authoritative data or apply carefully versioned projections; do not treat PubSub payload as durable truth.

## 27. PR 5 Tests

Add:

- Controller authorization pipeline coverage.
- Agent validation and credential no-store/no-secret behavior.
- Binding CRUD and active-attempt unbind safety.
- Task create/cancel/retry API.
- Attempts/events endpoints.
- Agents LiveView create/connection updates.
- Project binding and Task creation flows.
- Task detail progress/completion updates.
- No N+1 regression in obvious list paths.
- DuskMoon component/render consistency.

Run `mix assets.build` when asset changes are made.

## 28. PR 5 Acceptance

An operator can perform the complete Phase 1 journey without direct database access:

```text
create Agent
issue credential
observe connection
create Project
bind Agent
create Task
observe assignment/progress/completion
cancel or retry when legal
inspect history
```

---

# PR 6 — End-to-End Hardening and Release Gate

## 29. Goal

Prove the protocol under duplicate, race, disconnect, reconnect, and restart conditions; finalize documentation and rollout configuration.

## 30. Branch and commit

Suggested branch:

```text
feat/agent-hub-v1-hardening
```

Suggested commits:

```text
test(agent-hub): add fake agent protocol client
test(agent-hub): cover reconnect and race recovery
docs(agent-hub): finalize v1 protocol and operations
chore(agent-hub): add rollout configuration
```

## 31. Tasks

### 31.1 Fake Agent client

Create a test-support client that uses the real Agent Socket/Channel stack where practical.

Capabilities:

```text
authenticate and hello
heartbeat
request work
accept/start/progress/complete/fail/reject
persist/replay message IDs in test state
disconnect/reconnect
send stale lease/fencing/connection data
receive work-available/cancel controls
```

Do not require Synapsis or a real model.

### 31.2 Full happy-path integration test

Test:

```text
create Agent and credential
connect fake Agent
create Project
bind Agent
create Agent Hub Task
receive wake-up
request work
accept/start/progress/complete
assert Task/Attempt/Events/UI projection
```

### 31.3 Recovery tests

Add deterministic tests for:

- Assignment response lost, work request replayed.
- Agent disconnect and reconnect before lease expiry.
- Agent disconnect through lease expiry and reassignment.
- Samgita process/application restart simulation where practical.
- Duplicate completion.
- Old connection after replacement.
- Credential revoked while connected.
- Agent disabled while idle and while active.

### 31.4 Race tests

Use concurrent Tasks/processes and database barriers where needed:

- Two Agents claim one Task.
- Completion races cancellation.
- Heartbeat renewal races reaper.
- Reaper runs twice.
- Old Attempt completes while new Attempt is being claimed.
- Duplicate sequence messages arrive concurrently.

Assertions must target database invariants, not timing-sensitive sleeps alone.

### 31.5 Load smoke test

Add a non-default or tagged test/script that creates:

- 100 Agents/connections or simulated requesters;
- 1,000 pending Tasks;
- repeated claims and completions.

Measure query behavior and verify no duplicate active Attempts. Keep it out of normal fast unit tests if runtime is excessive.

### 31.6 Operational documentation

Document:

- runtime configuration;
- creating and rotating credentials;
- connecting Synapsis;
- interpreting Agent states;
- lease/retry behavior;
- cancelling and retrying Tasks;
- recovery after disconnection;
- useful telemetry/log fields;
- feature-flag rollout and rollback.

Add the new docs to `docs/INDEX.md` only after implementation matches them.

### 31.7 Synapsis protocol handoff

Create a concise protocol handoff document or issue for the Synapsis repository covering:

- socket parameters;
- hello/welcome;
- message envelope;
- work request/assignment;
- heartbeat/lease renewal;
- task status messages;
- ACK and replay;
- reconnect reconciliation;
- local durable outbox requirements.

Do not implement Synapsis code inside Samgita.

### 31.8 Rollout

- Keep production feature flag false by default until all release checks pass.
- Enable in development/test.
- Add migration/rollback notes.
- Verify legacy task processing with feature disabled and enabled.

## 32. PR 6 Test Commands

Run focused checks first, then final repository checks as supported by the current baseline:

```bash
mix format --check-formatted
mix test apps/samgita/test/samgita/agents_test.exs
mix test apps/samgita/test/samgita/tasking_test.exs
mix test apps/samgita/test/samgita/dispatch_test.exs
mix test apps/samgita/test/samgita/agent_protocol_test.exs
mix test apps/samgita_web/test/samgita_web/channels/agent_channel_test.exs
mix test apps/samgita_web/test/samgita_web/live/agents_live_test.exs
mix test
mix credo --strict
mix dialyzer
```

If the repository baseline has unrelated failures, document exact failures and demonstrate that all changed scopes pass. Do not broaden scope silently.

## 33. PR 6 Acceptance

All PRD Definition-of-Done items pass, including:

- happy path;
- duplicate messages;
- concurrent claim;
- lease expiry/reassignment;
- stale fencing rejection;
- cancellation race;
- reconnect/resume;
- legacy isolation;
- secret redaction;
- operator UI/API flow.

---

## 34. Parallelization Guidance

The PR sequence is serial, but tasks inside a PR may be parallelized carefully.

### After PR 1 schema contract is fixed

These can proceed in parallel branches if merge coordination is explicit:

```text
A: credential/auth helpers
B: protocol envelope/error types
C: pure matcher and retry policy tests
D: API response serializers
E: LiveView wireframes using context stubs
```

Do not parallelize migrations that edit the same Task table without one owner.

### During PR 3

Can run in parallel:

```text
Matcher implementation/tests
Lease helper implementation/tests
Claimer transaction implementation/tests
Reaper worker implementation/tests
```

Merge only after shared status/field names are frozen.

### During PR 5

Can run in parallel:

```text
Agent API
Project-Agent API
Task API
Agents LiveView
Project/Task LiveView
```

Each stream must use public contexts rather than reaching directly into another stream's schema internals.

---

## 35. Migration and Rollback Plan

### 35.1 Forward migration

1. Deploy additive tables and Task columns.
2. Backfill `execution_mode = legacy_local`.
3. Deploy code with feature flag disabled.
4. Verify legacy behavior.
5. Enable Agent Hub in a development/test deployment.
6. Connect one test Agent and execute synthetic Tasks.
7. Enable in the target self-hosted deployment.

### 35.2 Rollback

With feature flag disabled:

- No new external claims occur.
- Existing Agent Hub Tasks remain persisted.
- Legacy orchestration continues.

Code rollback must not drop additive tables immediately. Keep data-compatible schema until a later explicit cleanup migration. Revoke Agent credentials if the Agent Socket is being retired.

---

## 36. Required Database Invariants Checklist

Codex must verify these at both application and database levels:

- [ ] One active connection per Agent.
- [ ] One binding per Project-Agent pair.
- [ ] One active Attempt per Task.
- [ ] Unique Attempt number per Task.
- [ ] Monotonic fencing token per Task.
- [ ] Unique Agent message ID.
- [ ] Unique Attempt sequence.
- [ ] Unique Task idempotency key per Project.
- [ ] Agent Hub dispatcher filters execution mode.
- [ ] Terminal Attempt cannot transition again.
- [ ] Cancelled/completed Task cannot accept a stale terminal result.
- [ ] Aggregate/Event/Inbox changes are atomic.

---

## 37. Required Protocol Conformance Checklist

- [ ] Socket identity is authenticated before join.
- [ ] Join topic must match authenticated Agent ID.
- [ ] Protocol version is enforced.
- [ ] Hello is required before work/status messages.
- [ ] Active connection ID is checked on every message.
- [ ] Message ID deduplication returns deterministic ACK.
- [ ] Conflicting duplicate is rejected.
- [ ] Attempt sequence is ordered.
- [ ] Lease token is validated in constant time.
- [ ] Fencing token is current.
- [ ] Lease uses server time.
- [ ] Heartbeat renews only valid Attempts.
- [ ] Work request is pull-based and atomically claimed.
- [ ] PubSub wake-up is not required for correctness.
- [ ] Reconnect returns resumable and invalid Attempts.
- [ ] Plaintext credentials/lease tokens are never logged or persisted in events, Inbox rows, or aggregate tables.

---

## 38. Stop Conditions

Stop and report rather than expanding scope when:

- A required dependency has an upstream bug governed by the repository's upstream-routing policy.
- Existing legacy behavior would require a broad rewrite rather than additive isolation.
- A schema migration cannot be made backward-compatible without destructive changes.
- A security requirement would require storing plaintext secrets.
- The requested change starts implementing GitHub, workflow, review, merge, or release behavior.
- An unrelated failing test requires modifying unrelated modules.

A partial PR with passing scoped tests and a precise blocker report is preferable to an uncontrolled cross-repository rewrite.

---

## 39. Final Handoff Report Format

At the end of each PR, Codex should report:

```text
Scope completed
Files/modules added or changed
Migrations added
Public API added
State/invariants implemented
Tests run and results
Known unrelated failures
Security considerations
Compatibility notes
Remaining tasks for the next PR
```

The final Phase 1 handoff must also include a protocol compatibility summary for the Synapsis implementation team.
