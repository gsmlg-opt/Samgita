# Management API and operator UI

This is the implemented management boundary, not a promise of live external
service conformance. Read the [design](design.md), [P3 domain](domain-phase-3.md),
[P4 coordination](coordination-phase-4.md), [P4 GitHub](github-phase-4.md),
[capability matrix](capability-matrix.md) and [acceptance ledger](acceptance.md)
for ownership, preservation scope and evidence.

## Authentication and response contract

Operator JSON routes live under `/api` and accept `x-api-key` from configured
`SAMGITA_API_KEYS`. Production requires a nonempty configured key list. Local
empty-key operator mode does not grant machine authority: a Bearer request cannot
use it to become an operator. Protected routes retain a rate limit of 100
requests per 60 seconds. Browser routes use infrastructure protection, CSRF and
secure headers; there is no browser account or organization system.

Agent routes live under `/api/agent`. `Authorization: Bearer <machine credential>`
is required even when the operator API-key list is empty. `POST /api/agent/connect`
uses the current enabled credential and returns a connection record. Subsequent
machine calls also require `x-agent-connection: <connection UUID>`. Disabled or
revoked credentials, expired/replaced connections and disabled Project memberships
fail closed. A new connection generation does not transfer execution ownership
or prove remote effects stopped.

Send JSON objects with `Content-Type: application/json`. Successful single
resources use `{"data": {...}}`; list responses use
`{"data": [...], "limit": n, "offset": n}`. Event reads instead accept an
`after` sequence cursor and return `data`, `cursor`, `high_watermark` and `limit`.
New resources normally return 201,
other successful commands 200. Domain errors use
`{"errors":{"code":"...","detail":"...","fields":{...}}}` with 400 for
invalid fields, 401 unauthorized, 403 forbidden, 404 missing and 409 conflicts,
stale versions or illegal transitions. Authentication/rate-limit plugs may return
their own protected-boundary error shape. Use the returned code, never infer
permission from a successful TCP/HTTP/WebSocket connection.

## Command identity, versions and uncertainty

Every write carries a UUID `command_id`. Updates that act on an existing
aggregate also require its integer `expected_version`, except commands whose
specific domain contract creates a new independent record. Keep the exact
command body and ID while retrying an uncertain result. Matching authorized
retries return the original receipt result; changing semantics under the same
ID returns a conflict. A changed/new intent needs a new command ID and reviewed
current versions. Never blindly substitute a current version into a stale draft.

Commands authenticate and check ownership/membership/epoch before receipt lookup.
Receipts and audit events commit with the change. Native protocol request IDs,
connection IDs, stream cursors and external thread IDs are not management
idempotency keys. LiveView registration/update forms recover their hidden command
identity after reconnect. Credential inputs are never recovered: inspect credential
metadata and reconcile an interrupted write before re-entering a value.

Machine Attempt commands use current `expected_version` and an owner lease
`proof` where required. Retrieve the proof only through the explicit owner read;
retain it securely and never place it in event payloads, artifacts, URLs or logs.
Lease keys remain runtime configuration outside PostgreSQL. Rebind is an explicit
fenced operation for an existing unexpired Attempt, not a new execution.

## Operator routes

The table uses `:project_id` and resource UUID placeholders. All routes below are
relative to `/api`; route availability does not waive command preconditions.

| Resource | Routes |
| --- | --- |
| Agents | `GET/POST /agents`, `GET/PATCH /agents/:id` |
| Inbound credentials | `POST /agents/:agent_id/credentials`, `POST /agents/:agent_id/credentials/:credential_id/revoke` |
| Projects | `GET/POST /projects`, `GET/PATCH /projects/:id`, `POST /projects/:project_id/transition`, `GET /projects/:project_id/context` |
| Memberships | `POST /projects/:project_id/members` |
| Repositories | `GET/POST /projects/:project_id/repositories` |
| External sessions | `GET/POST /projects/:project_id/sessions` |
| Tasks | `GET/POST /projects/:project_id/tasks`, `GET/PATCH /projects/:project_id/tasks/:id` |
| Task decisions and evidence | `POST /projects/:project_id/tasks/:task_id/transition`, `/adopt`, `/decisions`, `/artifacts` |
| Effect resolution | `POST /projects/:project_id/attempts/:id/resolve` |
| Events | `GET /projects/:project_id/events`, `POST /projects/:project_id/events/trigger`, `/external`, `POST /projects/:project_id/events/:event_id/redeliver` |
| Responsible routing | `GET/PUT /projects/:project_id/event-routing` |
| Delivery | `GET /projects/:project_id/deliveries`, `GET /projects/:project_id/deliveries/:id`, `POST /projects/:project_id/deliveries/:id/recover` |
| Schedules | `GET/POST /projects/:project_id/schedules`, `PATCH /projects/:project_id/schedules/:id` |
| Authority fence | `GET /platform`, `POST /platform/activate`, `POST /platform/close` |
| GitHub configuration | `GET/POST /github/connections`, `GET/POST /projects/:project_id/github/repositories`, `PATCH /projects/:project_id/github/repositories/:id` |
| GitHub evidence | `GET /projects/:project_id/github/repositories/:id/facts`, `/observations/:observation_id`, `/deliveries/:delivery_id`; `POST /projects/:project_id/github/repositories/:id/reconcile` |

Signed GitHub ingress is separately exposed at
`POST /api/github/webhooks/:connection_id`. It verifies raw-body signatures and
approved routing, rather than accepting payload-supplied Project IDs. Its exact
headers and supported events are specified by [P4 GitHub](github-phase-4.md).

An Agent registration needs a name; native protocol/version defaults are
`samgita`/`1.0`. Capacity, advertised/approved capabilities, enablement and safe
endpoint descriptors are operator-managed. Approval must be a subset of the
advertised catalog. Descriptive `implementation` grants no authorization.

Credential registration takes an operator-supplied `credential` of 32–4096 bytes,
optional metadata reference/expiry and the current Agent version. It hashes the
credential, returns metadata only and marks the response `no-store`. Revocation
also revokes connections using that credential. The outbound `credential_ref`
is a separate external versioned reference name, never a raw secret.

## Agent callback routes

The following are relative to `/api/agent`. An authenticated Agent can only use
commands allowed by its current Project roles and execution ownership. Observe
the `allowed_operations` returned by Project context; it is advisory context,
while each command performs its own authoritative validation.

| Callback | Purpose |
| --- | --- |
| `POST /connect` | Register a new authenticated connection generation |
| `GET /projects`, `GET/PATCH /projects/:id`, `POST /projects/:project_id/transition`, `GET /projects/:project_id/context` | Role-scoped Project reads and management |
| `GET/POST /projects/:project_id/repositories`, `/sessions`, `/tasks` | Read/create authorized repository, session and Task records |
| `GET/PATCH /projects/:project_id/tasks/:id` | Scoped Task read/update |
| `POST /projects/:project_id/tasks/:task_id/transition`, `/decisions`, `/artifacts`, `/claim` | Legal management, decisions/evidence and execution claim |
| `POST /projects/:project_id/attempts/:id/start`, `/renew`, `/progress`, `/report`, `/rebind` | Current-owner fenced execution callbacks |
| `POST /projects/:project_id/attempts/:id/resolve` | Former-owner reconciliation with former proof and evidence |
| `GET /projects/:project_id/attempts/:id/proof` | Explicit current-owner proof read with `no-store` |
| `GET /projects/:project_id/events`, `POST /projects/:project_id/events/trigger` | Scoped events and manual attention request |
| `GET /projects/:project_id/event-routing`, `POST /projects/:project_id/event-routing/:subscription_id/ack` | Responsible subscription and durable cursor acknowledgement |
| `GET /projects/:project_id/deliveries`, `GET /projects/:project_id/deliveries/:id`, `POST /projects/:project_id/deliveries/:id/report` | Delivery reads and authorized responsible-Agent report |
| `GET /projects/:project_id/schedules` | Scoped schedule read |
| `GET /projects/:project_id/github/repositories`, `GET /projects/:project_id/github/repositories/:id/facts`, `/observations/:observation_id`, `/deliveries/:delivery_id` | Read approved GitHub facts/evidence |

`progress` requires a running owner Attempt and a bounded `payload.summary`; it
increments the Attempt version and appends `attempt.progress` evidence without
accepting the Task. A `report` with successful outcome and
`effects_resolved: true` submits `awaiting_review`. With unresolved effects the
Task becomes `blocked` and retains an execution hold, regardless of outcome.
An approved `kind: "review"` decision leaves it awaiting review; a distinct
approved `kind: "acceptance"` decision requires the current-version review and
produces `accepted`. Artifacts and external check states never perform acceptance.

An unresolved execution hold survives cancellation, reopen and reconnect. The
operator or owning Agent may reconcile it only under the existing explicit
evidence contract. An Agent's `/resolve` request requires its former-owner proof,
`effects_resolved: true` and an `evidence_ref`; it is not a current-owner execution
callback. Resolution clears a hold only when no unresolved Attempt remains and
does not automatically submit the Task for review or accept it. Never infer
cessation from a disconnected socket or expired lease. Delivery
recovery (`reconcile`, `redeliver`, `cancel`) is a separate domain: it retains
event identity and records evidence and duplicate-effect risk.

## Protocol, UI and verification boundary

Ordinary Agents registered with optional `runtime_driver: "codex"` and pinned
`runtime_version: "0.163.0"` may use the project-scoped
`/api/agent/projects/:project_id/codex-runtimes` journal APIs for an existing
running Attempt. Operator history, explicit replies and evidence-only recovery
use `/api/projects/:project_id/codex-runtimes`. The
[native runtime API table](../codex-app-server/platform-integration.md#apis-and-access-boundaries)
defines the exact methods, current authority checks and protected native reads.
Registration grants no role and launches nothing. Dispatch tickets are one-use;
lost acknowledgements require reconciliation, not another execution. All runtime
responses are non-cacheable, and plaintext native payloads never enter ordinary
receipts or audit projections. Native completion cannot accept a Task.

The native `/app-server` protocol carries events and optional runtime sessions
between clients and a chosen external host. Samgita's implemented outbound
connector uses `project_events.v1`; REST callbacks above carry authoritative
management transitions. There is no platform `/app-server` listener implied by
the standalone transport package. Do not send native runtime messages to a
management REST route or assume a Codex turn completion is Task acceptance.

The browser uses `/`, `/agents`, `/agents/:id`, `/projects`, `/projects/:id` and
`/projects/:project_id/tasks/:id`. `Samgita.Management` reads bounded safe
projections for these views; it is not another public REST mutation API. Agent
availability is explicitly unverified health based on persisted activity and
connection evidence. Refresh/reconnect reloads durable PostgreSQL state.

Run the phase-scoped LiveView/context/integration checks and the independent
protocol package checks. The acceptance ledger records the actual named build,
endpoint, database, assets and browser results. Local fake/fixture success must
not be represented as live Sigma/Synapsis/Codex integration or deployment.
