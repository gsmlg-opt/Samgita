# Current Samgita architecture

This describes the current agent-neutral implementation. The authority is
[redesign/design.md](redesign/design.md), with delivery gates in the
[implementation plan](redesign/implementation-plan.md) and
[acceptance ledger](redesign/acceptance.md). The previous clean-start
architecture is preserved in
[Git history at deff380](https://github.com/gsmlg-opt/Samgita/blob/deff380/docs/architecture.md);
its data-deletion and fixed-lifecycle proposals are superseded.

The approved [dependency modernization](redesign/dependency-modernization.md)
replaces the asset build pipeline with DuskmoonBundler, inbound servers with
Gaoxy, durable runtime jobs with Styx and GitHub HTTP with http_fetch. The
2026-11-07 update adopts DuskmoonBundler 10.1.2, phoenix_duskmoon 10.1.0,
Gaoxy HTTP 0.15.1 and the HTTP 1.0.0-rc.5 cohort. Published http_web_socket
APIs now replace both production Mint WebSocket clients; Mint remains a test-only
raw-wire oracle. The 2026-11-08 clarification removes Oban and Bandit from all
production, test and release dependencies, including Oban migration sources
and the old Bandit telemetry test. Pin/TLS/authentication/security checks remain
unrun; functional results and deletion of the old test do not close A11 or
full compatibility gates. Earlier build/browser results belong to their
recorded revisions and do not qualify this removal.

The web UI uses Duskmoon Web 2.0 RC via `duskmoon_phoenix` on Hex and npm.
Duskmoon Phoenix, Core CSS and React components share the same Web release.
DuskmoonBundler has its own release series.

## Ownership and dependencies

```text
Browser -> samgita_web LiveViews -> Samgita.Management reads / domain commands
REST    -> samgita_web controllers -> authenticated domain commands
                                      |
                                      v
                           samgita -> PostgreSQL + Styx
                                      |
                                      v
                              samgita_protocol

Durable delivery -> optional WebSocket client -> existing external /app-server
External Agent  -> Samgita /app-server -> confirmed device -> native event socket
External Agent  -> authenticated REST callbacks -> Samgita management authority
```

The explicit umbrella contains `samgita` and `samgita_web`. Core never depends on
web. The protocol and driver projects under `apps/` own separate build/dependency/
configuration paths and are independently consumable:

| Project | Boundary |
| --- | --- |
| `samgita_protocol` | Pure native v1 schema, codec, capability negotiation, correlation, handler contract and bounded replay |
| `samgita_protocol_websocket` | Optional authenticated `/app-server` transport and explicitly started in-memory fake |
| `samgita_protocol_codex` | Pinned Codex 0.163.0 native schema/wire layer and selected neutral convenience mappings; no native project-event compatibility |
| `samgita_codex_driver` | Explicitly started Codex sessions, owned/borrowed transports, complete wire delivery and explicit interactions; behavioral qualification remains incomplete |

No protocol library starts listeners or a platform runtime. Actual Agent services
keep their existing endpoints. Samgita does not launch a second Sigma server,
embedded providers, LLM workers or a central reasoning loop. A direct consumer
can communicate with its chosen runtime host while Samgita is stopped; only an
explicit authenticated callback changes Samgita's durable management state.

An ordinary Agent may explicitly bind its already started Codex driver to a
running fenced Attempt. `Samgita.CodexRuntime` persists encrypted native intents,
one-use dispatch tickets, events and thread/turn links. Its bridge sends outside
transactions and reauthorizes settlement; registration and event delivery start
no native execution. Uncertain effects block resolved reporting. See the
[native runtime contract](codex-app-server/platform-integration.md) for APIs,
key configuration, recovery and additive migration/forward rollback boundaries.

For interactive chat, Codex owns the transcript and running turn. On a new
host connection generation, the open LiveView pauses sending and reloads its
thread. It merges buffered updates into the returned history. Finalized turns
take precedence over earlier deltas. When an in-flight delta overlaps an
active item or the buffer exceeds its bounds, the view reads again. After two
automatic retries it offers a manual restore. The next user message steers a
running turn or starts a new turn according to the recovered state.

## Durable domain

`Samgita.Projects`, `Agents`, `Repositories`, `Tasks` and `Attempts` own domain
commands. Project UUIDs remain canonical. Repository identities and aliases are
separate associations; legacy `git_url` is provenance. Stable Agent identity,
authenticated connection generation, external execution session and execution
Attempt are separate records. Project memberships grant roles; capabilities
advertise supported operations and never grant authority.

A `manager` (the coordinator Agent or an operator) explicitly assigns an open
Task to a named executor with `assign` (`tasks.assignee_agent_id`, event
`task.assigned`); only that assignee can claim it, and `GET .../tasks?assignee_agent_id=`
lets an executor poll its work. Samgita validates the assignee's membership,
`worker` role and capabilities but never chooses an executor.

PostgreSQL is authoritative. Claims serialize capacity and eligible Tasks,
enforce unique active Attempts, and use leases with monotonic fencing. Domain
changes, audit events and command receipts commit atomically. PubSub may notify
after commit but confers no ownership. `command_id` identifies a stable command;
`expected_version` prevents stale writes. Current authorization and epoch checks
precede receipt replay. Matching retries return the original result; conflicting
reuse fails.

An Attempt records one execution. Its successful report with
`effects_resolved: true` submits the Task to `awaiting_review`. A report with
unresolved effects leaves the Task `blocked` with an execution hold, even if its
outcome succeeded. Review and acceptance are explicit separate decisions.
Progress, artifact references, transport ACKs and implementation labels cannot
accept a Task. Timeout, reconnect, cancellation and reopening cannot prove that
remote effects stopped; unresolved effects retain the execution hold until an
authorized resolution with evidence. Resolution is an operator or former-owner
reconciliation operation; the Agent supplies the former-owner proof rather than
using a current-owner execution callback. It clears resolved holds without
automatically submitting the Task for review or accepting it.

A coordinator can read the terminal report identified by an `attempt.reported`
event, including after a later retry. Task detail also exposes the latest
reported Attempt to Project managers, reviewers and operators. The
[management API](redesign/management-api.md) defines the report fields.

## Events, scheduling and GitHub

`Events`, `EventDelivery` and `Schedules` persist event identity/time, explicit
responsible-Agent routing, delivery attempts, acknowledgements, recovery and
schedule revisions. Enabled Styx queues are `hub_events`, `hub_schedules`,
`hub_maintenance` and `hub_github`. Legacy execution queues remain excluded and
old hooks enter a disabled quarantine queue.

Styx stores jobs in `styx_jobs`; Platform admission/status inventories this
store only. Oban has no dependency, compatibility module, release entry or
active migration source. Removing its two migration files does not drop
existing `oban_jobs` tables or other historical database objects, and does not
certify that old deployments are drained. Their inventory and reconciliation
remain separately authorized cutover work. Cron remains a wakeup for durable domain scanners;
queue completion cannot confer Task acceptance. No historical job is converted
or automatically replayed. Pruning and orphan-job rescue are explicitly disabled.

The web app uses `Gaoxy.PhoenixAdapter` and the optional protocol server uses
`Gaoxy.HTTP`, with the Gaoxy-compatible WebSock adapter. DuskmoonBundler owns
TypeScript, CSS, the integrated Tailwind pipeline, package installation and
asset manifests. The existing DuskMoon components and CSS utility semantics
remain. Production reads manifests through the runtime package without starting
the development build toolchain.

Delivery is at least once. The outbound native `project_events.v1` connector
authenticates, initializes, sends one receive/status operation and closes. It
does not start a thread/turn or automatically replay a mutation. Lost replies
require stable-operation status reconciliation. Transport receipt, durable
acceptance, processing completion and Task acceptance remain separate facts.

Agents may instead initiate a WebSocket to Samgita's `/app-server`. An initial
`agent/connect` bootstrap requests device confirmation on `/agents`; the client
automatically creates and retains its device token, so no credential is manually
configured. Confirmation persists only its digest in the existing
`agent_credentials` table and binds the device to a new or operator-selected
Agent. The selected Agent uses endpoint transport `inbound_websocket`; it needs
no outbound URL, destination approval or service-credential reference. Device
confirmation and Project membership remain separate decisions.

`Samgita.AgentIngress` tracks bounded pending requests and live socket handles.
Those handles are disposable routing state; PostgreSQL remains authoritative for
trusted credentials, connection generations, membership and durable delivery.
After confirmation or automatic device restoration, native
`connection/initialize` negotiates `project_events.v1`; the durable connector
sends receive/status requests over the existing inbound socket and preserves
the same correlation and ambiguous-outcome handling. A device is ready for event
delivery only after that negotiation. Socket replacement or reconnect creates
no execution and does not transfer an Attempt. Changing an existing Agent's
connection direction requires refreshing its event subscriptions; active or
unresolved execution prevents converting an outbound Agent.

The GitHub App verifies signatures against raw bytes and approved installation/
repository-to-Project mappings before atomic inbox/event/job persistence. Current
facts and immutable source evidence are separate. Text is untrusted. Credentials
are external versioned references and API destinations are pinned. Integration
performs repository-restricted reads; only token acquisition may POST remotely.
GitHub facts do not confer Task acceptance. The GitHub App has read-only access.
The [operator PAT console](superpowers/specs/2026-11-20-github-pat-dashboard-design.md)
uses a separate connection and worker for explicit Issue and PR actions.

## Operator surface and security

LiveViews cover dashboard, Agent catalog/detail, Project catalog/detail and Task
detail. `Samgita.Management` supplies bounded operator-only projections; mutations
use existing context commands. Pagination, errors and persisted refreshes expose
durable state. Availability describes disabled/offline/stale/activity-observed
evidence; no heartbeat establishes health. Historical UUID reads retain restricted
legacy evidence without restoring old executors.

Browser security remains infrastructure protection plus CSRF and secure headers.
Operator REST uses configured API keys/rate limits; Agent REST requires Bearer
credentials and `x-agent-connection` after connect. No browser account/org system
is added. Inbound credentials are either supplied by the operator or generated
and retained by a client whose device the operator confirms. Only their digests
are stored; plaintext values are never returned to the browser. Revoking the
existing device credential prevents automatic restoration; disconnecting a
socket alone does not forget the device. Proof retrieval is explicit,
current-owner-only and `no-store`; proofs
and plaintext credentials never enter ordinary projections, audit or receipts.
Outbound exact URLs, approved addresses and external service-credential references
are distinct from inbound credentials and database-external lease keys.

## Evidence and operating limits

The foundation and preservation scope are documented in
[P3](redesign/domain-phase-3.md); coordination and GitHub contracts are in
[P4 coordination](redesign/coordination-phase-4.md) and
[P4 GitHub](redesign/github-phase-4.md). Protocol isolation is documented in
[P2](redesign/protocol-phase-2.md). The
[management API](redesign/management-api.md) and
[capability matrix](redesign/capability-matrix.md) describe the current boundary.

Deterministic loopback fake-Agent tests do not certify live sibling-service or
Codex compatibility, production TLS/egress, real App authorization or target data
preservation. Local history fixtures are not a real memory/pgvector backup
rehearsal. Production inventory, legacy-writer exclusion, preservation, restart,
rollback and actual-service gates retain their separate evidence requirements.
Current CI builds/tests and assembles a local release; CD is disabled and no
package publication workflow establishes a released/deployed artifact.
The separate manually dispatched pinned-Codex workflow runs selected actual-binary
and platform scenarios plus a strict full-manifest evidence gate. Its selected
scenario success cannot override missing evidence, A11 or release/cutover gates.
