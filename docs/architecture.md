# Samgita Agent Hub architecture

**Status:** Implementation specification

**Authority:** Expands the user-approved `docs/agent-hub-rebuild-design.md`

**Milestone:** Clean-start Agent Hub with an operator UI and fake external Agent

**Compatibility:** None. The database starts empty and the former product is not retained.

## 1. Purpose and completion boundary

Samgita is a durable control plane for external Agent runtimes. It owns Projects,
Agent identity and authorization, requested Tasks, execution Attempts, protocol
decisions, and audit history. An Agent executes work but never writes Task state
directly. It proposes protocol messages; Samgita authenticates the current
connection and applies legal transitions in PostgreSQL transactions.

The first milestone is complete when this loop works through the operator UI and
a deterministic fake external Agent:

```text
create Project and Agent
  -> issue Agent credential
  -> bind Agent to Project
  -> Agent authenticates, joins, and sends hello
  -> operator creates Task
  -> Agent requests work
  -> Samgita atomically leases one Attempt
  -> Agent starts, reports progress, and completes or fails
  -> operator inspects Task, Attempt, connection, and event history
```

The system must recover from a lost response, duplicate messages, a replaced
connection, Samgita restart, lease expiry, and reassignment. A stale Agent must
not commit progress or a terminal result.

This milestone excludes cancellation, manual retry, Synapsis integration,
embedded model/provider execution, PRD orchestration, DAGs, artifacts, GitHub
automation, memory retrieval, multitenancy, browser accounts, and Agent-to-Agent
delegation.

## 2. Invariants

1. PostgreSQL is the durable source of truth. Processes hold transport state only.
2. An Agent message is a proposal. Only Samgita transitions Tasks and Attempts.
3. A Task describes requested work; an Attempt records one execution of it.
4. At most one active Attempt exists for a Task.
5. At most one active connection exists for an Agent.
6. Every Attempt has an expiring lease and a monotonically increasing per-Task
   fencing token.
7. Terminal Attempts are immutable.
8. A protocol message is applied at most once. An accepted duplicate receives the
   response produced by the original transaction.
9. Aggregate changes, Domain Events, and the Protocol Receipt commit together.
10. PubSub happens only after commit and is never required for correctness.
11. Server time controls leases and deadlines. Client time is audit metadata.
12. Credentials and lease tokens never enter logs, events, receipts, telemetry, or
    ordinary reads in plaintext.
13. `samgita_web` calls core public APIs. `samgita` never depends on web modules.

## 3. Applications and runtime

The umbrella contains exactly two applications:

```text
apps/
├── samgita
│   ├── Repo and nine domain tables
│   ├── Projects, Agents, Tasks, Protocol, and Events
│   └── Oban maintenance workers
└── samgita_web
    ├── Endpoint and operator REST API
    ├── AgentSocket and AgentChannel
    └── DuskMoon LiveViews
```

The minimum supervision trees are:

```text
Samgita.Application
├── Samgita.Repo
├── Phoenix.PubSub, name: Samgita.PubSub
└── Oban

SamgitaWeb.Application
├── SamgitaWeb.Telemetry
└── SamgitaWeb.Endpoint
```

No process is registered under an external Agent ID. A Channel PID is local and
replaceable. Durable connection identity is an `agent_connections` row. Horde,
provider sessions, local execution workers, and memory processes do not exist.

## 4. Context API boundaries

### 4.1 `Samgita.Projects`

Owns Project identity and lifecycle.

```elixir
create_project(attrs)
update_project(project_or_id, attrs)
delete_project(project_or_id)
get_project(id)
get_project_by_git_url(git_url)
list_projects(filters \\ %{}, page \\ %{})
```

Deletion succeeds only when no Project-Agent binding or Task references the
Project. Otherwise it returns `{:error, :has_history}`. History is never silently
cascade-deleted.

### 4.2 `Samgita.Agents`

Owns registered Agents, credentials, connections, Project authorization, and
derived presence.

Operator API:

```elixir
register_agent(attrs)
update_agent(agent_or_id, attrs)
enable_agent(agent_or_id)
disable_agent(agent_or_id)
get_agent(id)
list_agents(filters \\ %{}, page \\ %{})

issue_credential(agent_or_id, attrs \\ %{})
revoke_credential(agent_or_id, credential_id)
list_credentials(agent_or_id)
list_connections(agent_or_id, page \\ %{})

bind_agent(project_or_id, agent_or_id, attrs \\ %{})
update_binding(project_or_id, agent_or_id, attrs)
unbind_agent(project_or_id, agent_or_id)
list_project_agents(project_or_id)
```

`issue_credential/2` is the only API that returns plaintext:

```text
{:ok, %{credential: AgentCredential.t(), token: String.t()}}
```

Protocol-facing internal API:

```elixir
authenticate_token(token)
open_connection(authenticated_credential, transport_id, hello, now)
heartbeat(connection, active_attempts, now)
close_connection(connection_id, reason, now)
authorize_current_connection(connection_id, agent_id, now)
```

Capability normalization/intersection lives in the pure
`Samgita.Agents.Capability` module. Credential helpers live in
`Samgita.Agents.Credentials`; replacement, presence, and resume logic live in
`Samgita.Agents.Connections`.

Disabling an Agent or revoking the credential used by its connection closes that
connection transactionally and emits a post-commit stop notification. Attempts
expire through their existing deadlines; they are not immediately duplicated.
Disabling or removing a Project-Agent binding prevents new claims but does not
revoke already leased work.

### 4.3 `Samgita.Tasks`

Owns Task creation, matching, Attempts, leases, progress, terminal outcomes, and
automatic retry.

```elixir
create_task(project_or_id, attrs)
get_task(id)
list_tasks(filters \\ %{}, page \\ %{})
list_attempts(task_or_id, page \\ %{})
pending_reason(task_or_id)
reap_expired(now \\ DateTime.utc_now())
```

Protocol mutations are composed into the Inbox transaction by internal modules:

```text
Samgita.Tasks.Claim
Samgita.Tasks.Lease
Samgita.Tasks.Transitions
```

Pure decision modules contain no Repo or process calls:

```text
Samgita.Tasks.StateMachine
Samgita.Tasks.Matcher
Samgita.Tasks.RetryPolicy
```

### 4.4 `Samgita.Protocol`

Owns envelope validation, connection authorization, message identity,
deduplication, command routing, receipt insertion, and response rendering.

```elixir
handle_hello(auth, transport_id, envelope)
handle_message(connection_id, envelope)
disconnect(connection_id, reason)
```

`Samgita.Protocol.Envelope` validates wire input. `Samgita.Protocol.Inbox` owns
semantic hashing, receipt lookup, transaction composition, and replay. It composes
Task operations into one `Ecto.Multi`; no nested transaction may separate a
transition from its event and receipt.

### 4.5 `Samgita.Events`

`append/3` and `append_to_multi/4` build allowlisted Domain Events. They never
accept an unfiltered protocol body. `broadcast/1` publishes only the post-commit
effects returned by a successful transaction.

PubSub topics:

```text
projects
project:<project_id>
agents
agent:<agent_id>
agent-control:<agent_id>
task:<task_id>
```

LiveViews treat PubSub as invalidation and reload from PostgreSQL.
`work.available.v1` and `attempt.stop.v1` are hints; pull and lease validation
provide correctness.

## 5. Common data conventions

- Primary and foreign keys are UUIDs/Ecto `:binary_id`.
- Times are PostgreSQL `timestamptz(6)`/Ecto `:utc_datetime_usec`.
- Enums use lowercase strings through `Ecto.Enum`.
- A field whose contract says `default ...` is `NOT NULL`; only fields explicitly
  marked `nullable` accept null.
- JSONB fields accept JSON values only; arbitrary Erlang terms are rejected.
- Capability strings are trimmed, lowercased, 1..128 bytes, and match
  `[a-z0-9][a-z0-9._:-]*`; lists are deduplicated and sorted.
- Names and titles are trimmed and may not be empty.
- Pagination defaults to 50 rows and is capped at 200.
- Foreign keys restrict deletion unless explicitly stated otherwise.

Enforce encoded UTF-8 byte limits in core validation as well as transport:
Task description 16 KiB; Task payload and terminal result 64 KiB each; Agent
metadata, progress projection, failure details, and metrics 16 KiB each; event
payload 8 KiB. Bound the full inbound WebSocket frame and each operator JSON
request to 256 KiB. Object/array nesting is limited to 16 levels. These limits
apply to UI and API context calls too, so bypassing WebSocket cannot create an
unbounded stored object.

Exactly nine domain tables exist in addition to Oban's tables.

Unless a function above states a specialized result, mutations return
`{:ok, struct}` or `{:error, Ecto.Changeset.t() | stable_atom}`; singular reads
return `{:ok, struct}` or `{:error, :not_found}`; lists return a page containing
entries and cursor/count metadata. Web callers do not receive raw Repo errors.

## 6. Table contracts

### 6.1 `projects`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Generated by Samgita |
| `name` | varchar(255) | required | Trimmed, 1..255 bytes |
| `git_url` | text | required | Canonical unique identifier |
| `inserted_at` | timestamptz(6) | required | Server time |
| `updated_at` | timestamptz(6) | required | Server time |

`git_url` is trimmed and otherwise stored verbatim. It accepts an absolute local
path beginning `/`, an HTTP(S) URL with a host, or SCP-style SSH beginning `git@`
and containing `:`. Case, trailing slash, and `.git` suffix remain significant;
silent rewriting could merge distinct operator input.

```text
PRIMARY KEY (id)
UNIQUE (git_url)
CHECK (length(name) BETWEEN 1 AND 255)
```

### 6.2 `agents`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Stable logical Agent ID |
| `name` | varchar(255) | required | Unique operator-facing name |
| `runtime` | varchar(64) | required | Descriptive runtime family |
| `enabled` | boolean | default true | Gates connect, renewal, and claim |
| `capabilities` | text[] | default `[]` | Operator-approved ceiling |
| `max_concurrency` | integer | default 1 | Positive operator limit |
| `metadata` | JSONB | default `{}` | Operator-owned runtime-neutral metadata |
| `inserted_at` | timestamptz(6) | required | Server time |
| `updated_at` | timestamptz(6) | required | Server time |

`runtime` does not select a provider. Unknown non-empty strings are valid.

```text
PRIMARY KEY (id)
UNIQUE (name)
CHECK (length(name) BETWEEN 1 AND 255)
CHECK (length(runtime) BETWEEN 1 AND 64)
CHECK (max_concurrency > 0)
```

Presence is derived:

```text
disabled <- enabled == false
offline  <- no active connection or heartbeat older than threshold
idle     <- online and active Attempt count == 0
busy     <- online and active Attempt count > 0
```

### 6.3 `agent_credentials`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Credential metadata ID |
| `agent_id` | UUID FK | required | Agent, delete restricted |
| `token_prefix` | varchar(16) | required | Non-secret display prefix |
| `token_hash` | bytea | required | SHA-256 of complete token |
| `expires_at` | timestamptz(6) | nullable | Invalid at or after |
| `last_used_at` | timestamptz(6) | nullable | Successful socket authentication |
| `revoked_at` | timestamptz(6) | nullable | Revoked when non-null |
| `inserted_at` | timestamptz(6) | required | Server time |
| `updated_at` | timestamptz(6) | required | Server time |

Issuance:

```text
secret = 32 bytes from :crypto.strong_rand_bytes/1
token  = "sag_v1_" <> Base.url_encode64(secret, padding: false)
hash   = SHA-256(token)
prefix = first 16 bytes of token
```

The plaintext token is returned once, then discarded. Authentication hashes the
presented token and uses constant-time comparison. A 256-bit random secret makes
a fast hash suitable for this machine credential.

```text
PK (id)
FK (agent_id) -> agents ON DELETE RESTRICT
UNIQUE (token_hash)
INDEX (agent_id, revoked_at)
CHECK (octet_length(token_hash) = 32)
```

Credentials are revoked, never deleted. Overlap permits safe rotation.

### 6.4 `agent_connections`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Returned by welcome |
| `agent_id` | UUID FK | required | Authenticated Agent |
| `credential_id` | UUID FK | required | Handshake credential |
| `transport_id` | UUID | required | Server ID for one WebSocket |
| `instance_id` | UUID | required | Client ID for one daemon boot |
| `protocol_version` | integer | required | Exactly 1 |
| `runtime_version` | varchar(128) | required | Client-reported |
| `reported_capabilities` | text[] | default `[]` | Runtime capabilities |
| `reported_capacity` | integer | required | Positive hello capacity |
| `samgita_node` | varchar(255) | required | Socket-owning node |
| `connected_at` | timestamptz(6) | required | Accepted hello time |
| `last_heartbeat_at` | timestamptz(6) | required | Initially connected time |
| `disconnected_at` | timestamptz(6) | nullable | Null for current row |
| `disconnect_reason` | varchar(64) | nullable | Stable reason code |
| `inserted_at` | timestamptz(6) | required | Server time |
| `updated_at` | timestamptz(6) | required | Server time |

Reasons are `client_closed`, `transport_error`, `replaced`,
`credential_revoked`, `agent_disabled`, and `server_shutdown`. A node crash can
leave `disconnected_at` null; heartbeat age still derives offline and next hello
closes the row before inserting its replacement.

```text
PK (id)
FK (agent_id) -> agents ON DELETE RESTRICT
FK (credential_id) -> agent_credentials ON DELETE RESTRICT
UNIQUE (transport_id)
UNIQUE (agent_id) WHERE disconnected_at IS NULL
INDEX (agent_id, connected_at DESC)
CHECK (protocol_version = 1)
CHECK (reported_capacity > 0)
```

Effective capacity is `min(agent.max_concurrency, reported_capacity)`.

### 6.5 `project_agents`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Binding ID |
| `project_id` | UUID FK | required | Authorized Project |
| `agent_id` | UUID FK | required | Authorized Agent |
| `enabled` | boolean | default true | Gates new claims |
| `allowed_capabilities` | text[] | nullable | Additional ceiling |
| `inserted_at` | timestamptz(6) | required | Server time |
| `updated_at` | timestamptz(6) | required | Server time |

`allowed_capabilities` has distinct semantics:

```text
NULL <- no additional restriction
[]   <- binding permits no named capability; Tasks requiring `[]` still qualify
list <- only listed capabilities may be used for this Project
```

Effective capabilities are Agent configured intersect connection reported,
further intersected with binding allowed when non-null.

```text
PK (id)
FK (project_id) -> projects ON DELETE RESTRICT
FK (agent_id) -> agents ON DELETE RESTRICT
UNIQUE (project_id, agent_id)
INDEX (agent_id, enabled)
```

### 6.6 `tasks`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Logical work ID |
| `project_id` | UUID FK | required | Owning Project |
| `title` | varchar(255) | required | Operator-facing |
| `description` | text | required | Requested result |
| `type` | varchar(128) | required | Work classification |
| `payload` | JSONB | default `{}` | Runtime-specific input |
| `priority` | integer | default 10 | 0..100; higher claims first |
| `required_capabilities` | text[] | default `[]` | Required subset |
| `status` | enum/string | default `pending` | Task state |
| `available_at` | timestamptz(6) | default now | Earliest claim |
| `timeout_seconds` | integer | default 900 | Duration after start |
| `max_attempts` | integer | default 3 | Total Attempt budget |
| `attempt_count` | integer | default 0 | Incremented on claim |
| `last_fencing_token` | bigint | default 0 | Incremented on claim |
| `current_attempt_id` | UUID FK | nullable | Most recent Attempt |
| `idempotency_key` | varchar(255) | nullable | Unique per Project |
| `idempotency_hash` | bytea | nullable | Creation semantic hash |
| `inserted_at` | timestamptz(6) | required | Server time |
| `updated_at` | timestamptz(6) | required | Server time |

States are `pending`, `assigned`, `running`, `completed`, and `failed`.
`current_attempt_id` may point to a terminal Attempt for inspection. A later
automatic claim replaces it. Counts and fences are server projections only.

Task idempotency hashes normalized `project_id`, title, description, type,
payload, priority, required capabilities, requested availability, timeout, and
Attempt limit with the canonical algorithm in section 13. Requested availability
is either `{explicit, normalized_timestamp}` or the literal `default_now` marker.
The server-materialized current time used for an omitted `available_at` is not
hashed. Repeating a non-null key with the same hash therefore returns the Task
when both requests omit the field; a different hash returns
`:idempotency_key_conflict`.

```text
PK (id)
FK (project_id) -> projects ON DELETE RESTRICT
FK (current_attempt_id) -> task_attempts ON DELETE RESTRICT
UNIQUE (project_id, idempotency_key) WHERE idempotency_key IS NOT NULL
INDEX (status, priority DESC, available_at, inserted_at, id)
INDEX (project_id, status, inserted_at)
CHECK (length(title) BETWEEN 1 AND 255)
CHECK (length(description) > 0)
CHECK (length(type) BETWEEN 1 AND 128)
CHECK (priority BETWEEN 0 AND 100)
CHECK (timeout_seconds > 0 AND max_attempts > 0)
CHECK (attempt_count >= 0 AND attempt_count <= max_attempts)
CHECK (last_fencing_token >= 0)
CHECK ((idempotency_key IS NULL) = (idempotency_hash IS NULL))
```

Add the circular `current_attempt_id` FK after both tables exist. Transactions
also verify that it points to an Attempt for the same Task.

### 6.7 `task_attempts`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | One execution Attempt |
| `task_id` | UUID FK | required | Requested Task |
| `agent_id` | UUID FK | required | Logical owner |
| `connection_id` | UUID FK | required | Current transport owner |
| `attempt_no` | integer | required | Starts at 1 per Task |
| `status` | enum/string | default `leased` | Attempt state |
| `fencing_token` | bigint | required | Monotonic per Task |
| `signing_key_id` | varchar(64) | required | Runtime key ID |
| `lease_token_hash` | bytea | required | SHA-256 of derived token |
| `leased_at` | timestamptz(6) | required | Claim time |
| `start_due_at` | timestamptz(6) | required | Fixed latest start |
| `lease_expires_at` | timestamptz(6) | required | Renewable ownership |
| `started_at` | timestamptz(6) | nullable | Accepted start time |
| `execution_deadline_at` | timestamptz(6) | nullable | Fixed after start |
| `last_heartbeat_at` | timestamptz(6) | nullable | Last renewal |
| `finished_at` | timestamptz(6) | nullable | Terminal time |
| `last_sequence` | bigint | default 0 | Last accepted sequence |
| `progress` | JSONB | default `{}` | Latest persisted progress |
| `progressed_at` | timestamptz(6) | nullable | Rate-limit reference |
| `result` | JSONB | nullable | Successful terminal result |
| `error` | JSONB | nullable | Failure/expiry detail |
| `inserted_at` | timestamptz(6) | required | Server time |
| `updated_at` | timestamptz(6) | required | Server time |

States are `leased`, `running`, `succeeded`, `failed`, and `expired`. The first
two are active; the last three are terminal.

```text
PK (id)
FK (task_id) -> tasks ON DELETE RESTRICT
FK (agent_id) -> agents ON DELETE RESTRICT
FK (connection_id) -> agent_connections ON DELETE RESTRICT
UNIQUE (task_id, attempt_no)
UNIQUE (task_id, fencing_token)
UNIQUE (task_id) WHERE status IN ('leased', 'running')
INDEX (agent_id, status)
INDEX (lease_expires_at) WHERE status IN ('leased', 'running')
INDEX (start_due_at) WHERE status = 'leased'
INDEX (execution_deadline_at) WHERE status = 'running'
CHECK (attempt_no > 0 AND fencing_token > 0 AND last_sequence >= 0)
CHECK (octet_length(lease_token_hash) = 32)
CHECK (start_due_at > leased_at AND lease_expires_at > leased_at)
CHECK leased rows have no start/execution/finish time
CHECK running rows have start/execution but no finish time
CHECK terminal rows have finished_at
```

Terminal rows are immutable in application code; focused tests cover every
context and worker path.

Lease-token configuration contains a key ring and current key ID. Each secret is
at least 32 random bytes. Derivation is:

```text
facts = "samgita-agent-lease-v1" NUL
        attempt_id NUL task_id NUL agent_id NUL decimal(fencing_token)
mac   = HMAC-SHA-256(key_for(signing_key_id), facts)
token = "sal_v1_" <> signing_key_id <> "_" <>
        Base.url_encode64(mac, padding: false)
```

`connection_id` is intentionally absent so reconnect can rebind without changing
the token. The DB stores only SHA-256 of the token. Validation derives the
expected token and uses constant-time comparisons against presented token and
stored hash.

A signing key cannot be removed while a retained Attempt or assignment receipt
references it. Release startup fails clearly when a referenced key is missing.

Runtime configuration validates keyring shape and the current key without
database queries. Validate referenced key IDs after schema migrations and before
accepting Agent traffic. The migration entrypoint must work against an empty
database without requiring domain tables to exist already.

### 6.8 `protocol_receipts`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Receipt ID |
| `agent_id` | UUID FK | required | Message identity scope |
| `connection_id` | UUID FK | required | First committing connection |
| `message_id` | UUID | required | Client idempotency ID |
| `message_type` | varchar(128) | required | Versioned inbound type |
| `attempt_id` | UUID FK | nullable | Attempt message only |
| `sequence` | bigint | nullable | Attempt message only |
| `semantic_hash` | bytea | required | Section 12 hash |
| `response_type` | varchar(128) | required | Versioned outbound type |
| `response_descriptor` | JSONB | required | Immutable secret-free facts |
| `processed_at` | timestamptz(6) | required | Original commit time |
| `inserted_at` | timestamptz(6) | required | Server time |

```text
PK (id)
FK (agent_id) -> agents ON DELETE RESTRICT
FK (connection_id) -> agent_connections ON DELETE RESTRICT
FK (attempt_id) -> task_attempts ON DELETE RESTRICT
UNIQUE (agent_id, message_id)
UNIQUE (attempt_id, sequence) WHERE both are non-null
INDEX (processed_at)
CHECK (octet_length(semantic_hash) = 32)
CHECK ((attempt_id IS NULL) = (sequence IS NULL))
CHECK (sequence IS NULL OR sequence > 0)
```

Receipts are append-only and have no automatic deletion in milestone one.

### 6.9 `domain_events`

| Column | Type | Null/default | Contract |
|---|---|---|---|
| `id` | UUID | PK | Event ID returned in ACK |
| `aggregate_type` | varchar(64) | required | Aggregate kind |
| `aggregate_id` | UUID | required | Aggregate ID |
| `event_type` | varchar(128) | required | Versioned event |
| `source` | enum/string | required | operator, agent, system |
| `correlation_id` | UUID | nullable | Task ID for Task/Attempt lifecycle |
| `task_id` | UUID FK | nullable | Task timeline key |
| `attempt_id` | UUID FK | nullable | Attempt event key |
| `agent_id` | UUID FK | nullable | Agent timeline key |
| `causation_message_id` | UUID | nullable | Inbound message |
| `payload` | JSONB | default `{}` | Allowlisted metadata |
| `recorded_at` | timestamptz(6) | required | Server time |

```text
PK (id)
FK task_id/attempt_id/agent_id ON DELETE RESTRICT
INDEX (aggregate_type, aggregate_id, recorded_at, id)
INDEX (correlation_id, recorded_at, id) WHERE correlation_id IS NOT NULL
INDEX (task_id, recorded_at, id) WHERE task_id IS NOT NULL
INDEX (agent_id, recorded_at, id) WHERE agent_id IS NOT NULL
```

Events are audit, not event sourcing. Aggregate tables hold current state. Event
payloads omit credentials, tokens, complete Task payloads/results, and raw
protocol bodies. Task and Attempt events set `correlation_id` to their Task ID;
other lifecycle events may leave it null. Initial events cover
Project/Agent/credential/binding/connection
lifecycle and Task/Attempt leased, started, progressed, completed, failed,
expired, and requeued transitions. Routine heartbeats and throttled progress
no-ops create no Domain Event.

## 7. State machines

`Samgita.Tasks.StateMachine` exclusively defines transitions.

```text
Task:
pending  -> assigned   claim
assigned -> running    accepted start
assigned -> pending    lease/start expiry with budget
assigned -> failed     expiry without budget
running  -> completed  accepted completion
running  -> pending    retryable failure/expiry with budget
running  -> failed     non-retryable failure or exhausted budget

Attempt:
leased  -> running    accepted start
leased  -> expired    start or lease deadline
running -> succeeded  accepted completion
running -> failed     accepted failure
running -> expired    lease or execution deadline
```

Completed/failed Tasks and succeeded/failed/expired Attempts are terminal. There
is no cancellation or manual retry state.

Cross-row invariants after commit:

```text
Task assigned  <=> current Attempt leased
Task running   <=> current Attempt running
Task completed => current Attempt succeeded
Task pending   => no active Attempt
Task failed    => no active Attempt
```

## 8. Matching, claim, and capacity

Eligibility requires enabled Agent/current credential/current online connection,
enabled Project binding, required capabilities contained by effective
capabilities, pending Task available now, remaining Attempt budget, and free
Agent capacity.

Claim order is frozen to the PRD contract:

```text
priority DESC,
available_at ASC,
inserted_at ASC,
id ASC
```

Higher numeric priority is more important. No LLM or probabilistic scheduling is
used.

`work.request.v1.payload.free_slots` is a positive capacity hint. The server
still claims at most one Task per request in this milestone, and only when
effective capacity minus all active Attempts is positive. Active count includes
disconnected but unexpired work. No free capacity and no eligible work both
return a successful empty assignment list.

One request claims at most one Task in one transaction: lock Agent; lock current
credential, connection, and matching bindings; count active Attempts; select
one Task using bounded `FOR UPDATE SKIP LOCKED`; recheck eligibility; increment
its Task count/fence; insert the Attempt; update the Task; append events; insert one
receipt; commit; render tokens; then broadcast.

The Agent lock serializes concurrent claims for its slots. Task locks,
`SKIP LOCKED`, and the active-Attempt partial unique index serialize Task
ownership.

## 9. Deadlines and automatic retry

| Setting | Default |
|---|---:|
| heartbeat interval | 15 seconds |
| offline threshold | 45 seconds |
| lease duration | 120 seconds |
| start timeout | 20 seconds |
| execution timeout | 900 seconds |
| total Attempts | 3 |
| progress persistence interval | 2 seconds |
| maintenance schedule | every 60 seconds |
| maximum WebSocket frame | 256 KiB |

At claim:

```text
leased_at = now
start_due_at = now + 20 seconds
lease_expires_at = now + 120 seconds
started_at = NULL
execution_deadline_at = NULL
```

On accepted start:

```text
started_at = now
execution_deadline_at = now + task.timeout_seconds
lease_expires_at = min(now + lease duration, execution_deadline_at)
```

Heartbeat renewal sets `lease_expires_at` to the minimum of now plus lease
duration and the applicable fixed deadline: `start_due_at` while leased,
`execution_deadline_at` while running. It never extends a fixed deadline. A
message at or after a deadline rejects immediately even before reaping persists
expiry.

The Oban worker is scheduled every 60 seconds. This is not a hard processing SLA
during queue/database outages. It selects bounded candidate IDs without locks,
takes locks in global order, and revalidates server time.

Retry delay after Attempt `n` is `min(5 * 2^(n - 1), 60)` seconds. Samgita maps
`invalid_input` and `unsupported_task` failures to non-retryable; `execution_error`,
unknown classes, and expiry are retryable while budget remains. An Agent
`retryable` flag is advisory only. Retryable work returns pending at calculated
`available_at`; otherwise Task becomes failed.

## 10. Global row-lock order

Every multi-row transaction uses this heterogeneous table order:

```text
1. Agent
2. AgentCredential
3. AgentConnection
4. ProjectAgent
5. Task
6. TaskAttempt
```

Within one table, rows lock by UUID ascending. A transaction may skip a level but
never acquires an earlier table after a later one.

- Claim: Agent -> Credential -> Connection -> ProjectAgent -> Task -> Attempt.
- Heartbeat: pre-read IDs, then Agent -> Credential -> Connection -> Tasks by UUID
  -> Attempts by UUID; revalidate.
- Status: Agent -> Credential -> Connection -> Task -> Attempt.
- Replacement: Agent -> Credential -> old Connection -> Tasks -> active Attempts.
- Revocation: Agent -> Credential -> affected Connection.
- Binding change: Agent -> ProjectAgent; affects future claims only.
- Reaper: pre-read candidates, then Agent -> Credential -> Connection -> Task ->
  Attempt; revalidate.

Project deletion uses restrictive FKs and the no-history check. A concurrent FK
race maps to `:has_history`. Independent-transaction tests must prove lock order;
`Ecto.Multi` step order alone is insufficient.

## 11. Phoenix transport and authentication

The external wire contract is a WebSocket upgrade at `/agent/socket` carrying:

```http
Authorization: Bearer <Agent credential>
```

Long polling is disabled, frames are limited to 262,144 bytes, and credentials
are never accepted from the URL or Channel payload.

`SamgitaWeb.AgentSocket` is implemented at
`apps/samgita_web/lib/samgita_web/agent_socket.ex`; the Channel is
`apps/samgita_web/lib/samgita_web/agent_channel.ex`.

Installed Phoenix 1.8.13 limits normal socket `connect_info`: `:x_headers` exposes
only `x-*`, and its built-in `auth_token` option maps WebSocket credentials
through `Sec-WebSocket-Protocol`, not the approved `Authorization` header. Those
behaviors are visible in `deps/phoenix/lib/phoenix/endpoint.ex` and
`deps/phoenix/lib/phoenix/transports/websocket.ex`. The subprotocol mechanism was
evaluated and is not selected because it changes the approved external contract.

Stage 0 proved the narrow HTTP-upgrade bridge against Phoenix 1.8.13/Bandit
1.12.5 on Elixir 1.18.5/OTP 27 before protocol fixtures freeze. The application-owned
boundary is `SamgitaWeb.AgentSocketAuth` at
`apps/samgita_web/lib/samgita_web/agent_socket_auth.ex`; it extracts and validates
exactly one Bearer header and passes only the opaque token into socket
authentication. Phoenix injects socket dispatch before ordinary endpoint plugs,
so use the endpoint's overridable `call/2` to invoke this bridge before `super`.
On a rejected request return the halted connection without dispatching it.
On success remove the Authorization request header and put only the extracted
opaque token in `conn.private[:phoenix_transport_auth_token]`; socket
`connect_info: [:auth_token]` delivers it to authentication. Leave Phoenix's
native `auth_token` option disabled, since enabling it selects the rejected
subprotocol mechanism. This is version-sensitive integration with Phoenix's
private connection key, so preserve the real transport regression test across
dependency upgrades. No dependency patch or replacement transport is required.

Mount `socket "/agent", SamgitaWeb.AgentSocket` with websocket options
`path: "/socket"`, `connect_info: [:auth_token]`, `transport_log: false`, and
`max_frame_size: 262_144`, plus `longpoll: false`. This yields the exact approved
upgrade path `/agent/socket`, not the default `/agent/socket/websocket`. Disable
socket connection logging (`use Phoenix.Socket, log: false`) and keep protocol
logs allowlisted. Do not accept query, custom `x-*` or subprotocol credentials.

The isolated Stage 0 spike used a loopback Bandit endpoint and a synthetic
in-memory credential checker, not the future database-backed credential
context. Ten upgrade cases passed: valid Bearer yielded HTTP 101 and an actual
Phoenix heartbeat reply; missing, malformed-scheme, empty, malformed-token,
duplicate, query-only, custom-header-only and subprotocol-only credentials
yielded HTTP 401; a syntactically valid unrecognized credential yielded HTTP
403. It verified exact token delivery by hash, no token/subprotocol response
echo, and no plaintext credential in captured debug-level logs. This proves
transport wiring only, not persistent authentication or the Agent protocol.

The fake Agent must prove the final bridge over real Bandit. An injected Channel
test is insufficient.

Socket connect authenticates the hash, assigns `agent_id`, `credential_id`, and a
new server `transport_id`, but no connection ID. Only topic
`agent:<authenticated_agent_id>` may join. TLS is required outside localhost.

Phoenix mapping:

```text
topic                   agent:<agent_id>
inbound event           equals envelope.type
inbound payload         complete envelope
push reply response     complete outbound envelope
server push event       equals outbound envelope.type
server push payload     complete outbound envelope
```

Event/type mismatch rejects. Channel callbacks delegate and contain no business
transition.

## 12. Hello and connection replacement

A joined Channel begins `awaiting_hello`; only `agent.hello.v1` is accepted.

- Hello has no `connection_id`.
- First hello locks Agent/Credential, closes the prior active connection, inserts
  the new row and receipt, and reconciles Attempts in one transaction.
- Same hello ID on the same initialized Channel replays welcome without another
  replacement.
- A different hello on that Channel returns `already_initialized`.
- A new WebSocket has a new `transport_id` and must use a fresh hello ID. Reusing
  an old hello receipt from another transport returns `hello_message_reused`.

After commit, a control PubSub message terminates the former Channel. Before it
arrives, that Channel's next transaction fails current-connection authorization.

Replacement rebinds all still-active, unexpired Attempts owned by the Agent and
renews leases within fixed deadlines. Welcome returns complete resume assignments
with re-derived tokens. Reported stale/terminal Attempts appear in
`invalid_attempts`. Rebinding never creates an Attempt or changes its fence/fixed
deadline.

## 13. Protocol envelope and semantic hash

Protocol v1 uses JSON text frames. Unknown top-level fields are rejected.
Message-specific payload schemas also reject unknown fields except inside the
explicit JSON extension objects `payload`, `metrics`, `result`, `details`, and
Agent `metadata`. Common envelope fields are:

```json
{
  "version": 1,
  "message_id": "uuid",
  "type": "task.progress.v1",
  "connection_id": "uuid-after-hello",
  "attempt_id": "uuid-for-attempt-message",
  "lease_token": "opaque-for-attempt-message",
  "fencing_token": 2,
  "sequence": 3,
  "occurred_at": "2026-09-07T10:03:00.000000Z",
  "payload": {}
}
```

Authenticated Agent ID is never payload. UUIDs are canonical strings; lease token
is bounded to 256 bytes; fence/sequence are positive. `occurred_at` is optional.
When present it is RFC 3339 UTC audit metadata, is normalized to microseconds, and
must remain unchanged when the client replays that message.

Message ID is unique per Agent, not connection. After reconnect, the client may
replay an unacknowledged message by replacing only `connection_id`.

Processing order is critical:

1. Authenticate socket Agent.
2. Require envelope connection ID to match Channel assignment and current DB row.
3. Build semantic hash excluding connection ID.
4. Look up `(agent_id, message_id)`.
5. Same hash replays stored response before mutable Attempt/lease validation.
6. Different hash returns `message_id_conflict`.
7. No receipt proceeds to current-state validation and transaction.

This lets a committed completion ACK replay after terminal state while rejecting
a stale socket.

Semantic hash is SHA-256 of this validated deterministic term:

```text
{
  version,
  message_id,
  type,
  occurred_at_as_utc_microseconds_or_nil,
  attempt_id_or_nil,
  fencing_token_or_nil,
  sequence_or_nil,
  sha256(lease_token)_or_nil,
  canonical_json(payload)
}
```

It excludes connection ID, authenticated Agent/credential/transport identity,
Phoenix topic/event/refs, and server receive time. Authorization is checked
separately before replay.

`canonical_json/1` recursively sorts object string keys, preserves array order,
and preserves string/boolean/null/integer/float types distinctly, then uses
`:erlang.term_to_binary(term, minor_version: 2)`. Thus object key order is
irrelevant while `1` and `1.0` differ. Clients never calculate this hash. Raw
lease token is never placed in the canonical term or persisted. Before
canonicalizing payload, Envelope recursively replaces every schema-defined
`lease_token` field with its SHA-256 digest. This includes lease tokens nested in
hello and heartbeat `active_attempts`, not only the top-level Attempt envelope.
An unexpected field named `lease_token` is rejected rather than generically
rewritten.

Hello has no connection ID; its receipt additionally requires stored connection
`transport_id` to equal current socket `transport_id`.

## 14. Receipts and replay

For a new accepted message, Inbox authorizes, locks, validates, transitions,
appends events, and inserts the receipt in one transaction. After commit it
renders any derived lease token and broadcasts.

Only accepted messages get receipts. Expected errors such as `out_of_order` or
`lease_expired` consume neither message ID nor sequence. Accepted throttled
progress is an intentional no-op and does consume both.

The immutable `response_descriptor` holds response type/version, request ID,
original processing time, resulting states, event IDs, and assignment/welcome/
heartbeat facts excluding tokens. Token rendering uses Attempt facts and its
recorded signing key.

An accepted duplicate returns the same application response; no changing
`duplicate` field exists. Telemetry records replay.

Historical response is evidence of past processing, not current authority. A
replayed assignment can contain an expired lease. The Agent persists assignments,
reconciles on reconnect, validates a replay through fresh heartbeat, and waits for
a successful start ACK before external execution. Server checks remain final.

## 15. Message contracts

Inbound:

```text
agent.hello.v1
agent.heartbeat.v1
work.request.v1
task.started.v1
task.progress.v1
task.completed.v1
task.failed.v1
```

Outbound:

```text
agent.welcome.v1
work.available.v1
work.assignment.v1
attempt.stop.v1
ack.v1
error.v1
```

Hello payload requires daemon `instance_id`, `runtime_version`, normalized
reported capabilities, positive reported capacity, and `active_attempts` (default
`[]`). Resume entries contain Attempt ID, token, fence, and last acknowledged
sequence.

Welcome echoes request message ID and returns connection ID, server time,
heartbeat/lease settings, effective capacity/capabilities, resume assignments,
and `{attempt_id, code}` invalid entries.

Heartbeat payload is `{active_attempts: [{attempt_id, lease_token,
fencing_token}]}`. It renews valid entries independently, updates connection
heartbeat, and ACKs valid entries with lease expiry plus invalid entries with
reason. It appends no event. Heartbeats need not enter the client durable outbox.

Work request payload is `{free_slots: positive_integer}`. The response contains
zero or one assignment in this milestone:

```json
{
  "assignments": [{
    "task_id": "uuid",
    "attempt_id": "uuid",
    "attempt_no": 1,
    "fencing_token": 1,
    "lease_token": "opaque",
    "lease_expires_at": "RFC3339",
    "start_due_at": "RFC3339",
    "task": {
      "project_id": "uuid",
      "title": "Implement protocol",
      "description": "...",
      "type": "implement",
      "payload": {},
      "priority": 10,
      "required_capabilities": ["language:elixir"],
      "timeout_seconds": 900
    }
  }]
}
```

No work/capacity is successful with `[]`. Wake-up contains no assignment.

Start payload is `{}` and sequence must be 1. It moves Task/Attempt running and
sets server deadlines. ACK includes resulting states, sequence, lease/execution
deadlines, and event IDs.

Progress optional fields are phase (128 bytes), percent integer 0..100, message
(2,000 bytes), and metrics JSON object. Attempt must run. If two seconds elapsed,
persist projection/event. Otherwise accept no-op, advance sequence, store receipt,
and return no event IDs.

Completion requires summary (max 4,000 bytes) and accepts result/metrics JSON
objects. It succeeds Attempt, completes Task, and stores terminal data only on the
Attempt.

Failure requires `{error: {class, message, details?}, retryable?, metrics?}`;
message max 4,000 bytes. Agent retryability is advisory. Attempt fails and Task
requeues or fails by server policy.

`work.available.v1` and `attempt.stop.v1` are best effort and unacknowledged.

## 16. Attempt validation and errors

A new Attempt message requires current Agent/credential/connection, matching
Attempt owner and Task current pointer, legal active status, valid token/hash,
matching Attempt and Task fence, future lease/fixed deadline, and
`sequence == last_sequence + 1`.

Start is sequence 1. Each accepted progress/completion/failure increments one.
Rejected messages do not consume sequence. A committed duplicate bypasses mutable
state checks and returns its receipt response.

Stable errors:

```text
unauthorized invalid_envelope unsupported_version invalid_message_type
hello_required already_initialized hello_message_reused connection_not_current
message_id_conflict out_of_order attempt_not_found attempt_not_current
attempt_terminal invalid_lease stale_fence lease_expired
start_deadline_expired execution_deadline_expired illegal_transition
internal_retryable
```

Error envelopes include request ID when parseable, code, concise message,
retryable boolean, and allowlisted details such as expected sequence. They never
expose stack traces, DB errors, structs, secrets, or raw payloads.

## 17. Transaction contracts

Every state change and its events use `Ecto.Multi`.

- Register: insert Agent + event; commit; broadcast.
- Issue credential: lock Agent; insert hash; append secret-free event; commit;
  return plaintext once.
- Hello: lock identity; replace connection; lock/reconcile Attempts; append events;
  receipt; commit; terminate old socket and broadcast.
- Create Task: validate Project/idempotency; insert pending Task + event; commit;
  broadcast and wake eligible Agents.
- Status: authorize; replay receipt if present; lock Task/Attempt; validate; apply
  pure transition; update; events; receipt; commit; render/broadcast.
- Expiry: select candidates; lock in global order; recheck; expire; requeue/fail;
  events; commit; broadcast.

Rollback means no event, receipt, success response, or broadcast.

## 18. UI and REST

First-milestone LiveView modules are retained/created at:

```text
apps/samgita_web/lib/samgita_web/live/dashboard_live/index.ex
apps/samgita_web/lib/samgita_web/live/projects_live/index.ex
apps/samgita_web/lib/samgita_web/live/project_form_live/index.ex
apps/samgita_web/lib/samgita_web/live/project_live/index.ex
apps/samgita_web/lib/samgita_web/live/agents_live/index.ex
apps/samgita_web/lib/samgita_web/live/agent_live/index.ex
apps/samgita_web/lib/samgita_web/live/task_form_live/index.ex
apps/samgita_web/lib/samgita_web/live/task_live/index.ex
```

Routes:

```text
/                         dashboard
/projects                 Project list
/projects/new             Project create
/projects/:id/edit        Project edit
/projects/:id             bindings and Tasks
/projects/:id/tasks/new   Task create
/agents                   Agent list/register
/agents/:id               Agent edit/credentials/connections/bindings
/tasks/:id                Task/Attempt/progress/result/event detail
```

Dashboard shows Agent/work counts and recent failures. Pending Task reason is one
of delayed, no binding, no online Agent, capability mismatch, or capacity. No
cancellation/manual-retry controls render. DuskMoon components, accessible labels,
validation, empty states, responsive layouts, and bounded pagination are required.

REST mirrors context operations under existing API-key/rate-limit pipeline:

```text
POST   /api/projects
GET    /api/projects
GET    /api/projects/:id
PATCH  /api/projects/:id
DELETE /api/projects/:id
POST   /api/agents
GET    /api/agents
GET    /api/agents/:id
PATCH  /api/agents/:id
POST   /api/agents/:id/enable
POST   /api/agents/:id/disable
POST /api/agents/:id/credentials
POST /api/agents/:id/credentials/:credential_id/revoke
GET  /api/agents/:id/credentials
GET  /api/agents/:id/connections
PUT    /api/projects/:project_id/agents/:agent_id
PATCH  /api/projects/:project_id/agents/:agent_id
DELETE /api/projects/:project_id/agents/:agent_id
GET    /api/projects/:project_id/agents
POST /api/projects/:project_id/tasks
GET  /api/projects/:project_id/tasks
GET /api/tasks/:id
GET /api/tasks/:id/attempts
GET /api/tasks/:id/events
```

Credential creation sets `Cache-Control: no-store`; reads omit tokens/hashes.
Browser access is infrastructure-protected and single-tenant.

## 19. Security, failure, and observability

- Rate-limit failed socket auth by peer and malformed protocol by connection.
- Socket assigns Agent identity; topic/payload cannot override it.
- Client capabilities only narrow operator approval.
- Do not log Task payload/progress/result/error bodies by default.
- Event payload builders use per-event allowlists.
- Signing/API keys come only from runtime secret configuration.
- Fencing protects accepted Samgita state, not exactly-once external effects.

Required recovery behavior:

| Failure | Result |
|---|---|
| disconnect/node death | Heartbeat derives offline; Attempt lasts to deadline |
| replacement | New connection wins; Attempts rebind; old DB auth fails |
| lost hello/assignment/completion reply | Matching receipt replays response |
| reconnect changes only connection ID | New connection authorized; hash matches |
| changed semantic body with same ID | `message_id_conflict` |
| out of order | Reject without consuming ID/sequence |
| fast progress | Accepted no-op consumes sequence/receipt, no event |
| concurrent Task claim | Locks + SKIP LOCKED + unique index allow one |
| concurrent Agent slot claim | Agent lock + recount enforce capacity |
| stale result | Current pointer/fence reject |
| duplicate reaper | Lock + state recheck makes second no-op |
| DB failure | No success receipt/event/broadcast |
| PubSub loss | Pull and durable reload recover |
| missing referenced signing key | Release/startup validation fails |

Minimum telemetry covers Agent connect/disconnect, protocol message/duplicate/
rejection, Task claim, Attempt transition/expiry. Metadata contains IDs, type,
fence, outcome/code, and duration only.

At the target first-milestone scale of 100 registered Agents and 1,000 Tasks, a
warm-system end-to-end claim transaction has a p95 target at or below 500 ms under
representative concurrent polling. The fake-Agent integration suite records this
as a baseline; correctness tests do not use a brittle wall-clock assertion.

Receipts/events have no automatic deletion in milestone one. Production rollout
must define retention, signing-key retirement, and DB growth alerts without
silently shortening replay guarantees.

## 20. Code placement

```text
apps/samgita/lib/samgita/
├── projects.ex
├── agents.ex
├── agents/{capability,credentials,connections}.ex
├── tasks.ex
├── tasks/{state_machine,matcher,retry_policy,claim,lease,transitions}.ex
├── protocol.ex
├── protocol/{envelope,inbox}.ex
├── events.ex
├── domain/
│   ├── project.ex
│   ├── agent.ex
│   ├── agent_credential.ex
│   ├── agent_connection.ex
│   ├── project_agent.ex
│   ├── task.ex
│   ├── task_attempt.ex
│   ├── protocol_receipt.ex
│   └── domain_event.ex
└── workers/lease_reaper.ex

apps/samgita_web/lib/samgita_web/
├── endpoint.ex
├── agent_socket_auth.ex
├── agent_socket.ex
├── agent_channel.ex
├── controllers/
│   ├── project_controller.ex
│   ├── agent_controller.ex
│   ├── agent_credential_controller.ex
│   ├── project_agent_controller.ex
│   └── task_controller.ex
└── live/ (exact paths in section 18)

apps/samgita_web/test/support/fake_agent.ex
apps/samgita_web/test/fixtures/agent_protocol/*.json
```

Schemas cast/local-validate. Contexts own authorization/transactions. Pure modules
own decisions. Web translates transport only.

## 21. Verification and guardrails

Pure tests cover transition matrices, capabilities, deterministic priority order,
retry/deadline logic, token derivation, envelopes, and hashes including reordered
JSON and changed connection ID.

Database tests cover all constraints, Task idempotency replay/conflict,
event/receipt rollback, capacity, terminal immutability, and retry exhaustion.
Concurrency tests use independent DB connections for Task claims, Agent slots,
replacement/heartbeat, revocation/status, renewal/reaping, and stale completion.

Real WebSocket fake-Agent tests cover the approved Authorization Bearer upgrade,
hello, complete execution, lost replies, duplicate/conflicting messages,
reconnect, expiry, stale fence, revocation, and Samgita restart. They invoke no
LLM.

UI/API/browser tests prove the full operator journey and one-time credentials.
Assets and a two-app release build must pass. A release boots without provider,
memory Repo, pgvector, Horde, or legacy modules.

Use explicitly named fresh databases:

```text
samgita_hub_dev
samgita_hub_test
samgita_hub_integration_test
```

Parallel test partition suffixes are optional. Never infer permission to drop a
database from an environment variable.

Implementation guardrails:

1. Create fresh migrations; do not transform old rows.
2. Retain old implementation only in Git history, not archive directories.
3. Keep exactly the two application boundaries here.
4. Do not reintroduce providers, local execution, PRD orchestration, memory,
   Horde, or legacy state.
5. Never persist/log plaintext credentials or lease tokens except explicit
   one-time/transport responses.
6. Do not add cancellation or manual retry states, endpoints, or controls.
7. The fake external Agent is the protocol conformance reference.
8. Stop when this first-milestone loop and gates pass.
