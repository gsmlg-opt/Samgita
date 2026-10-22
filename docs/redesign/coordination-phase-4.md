# Durable coordination phase

This phase implements the latest authorized event-coordination scope on P3 commit `bc032369`. Samgita persists facts, routes notifications and reconciles delivery. The responsible registered Agent chooses whether to reason, delegate or request a validated management transition. No LLM engine, PRD decomposition, fixed lifecycle, session start or tool invocation is added.

The broader P4 plan also proposes a GitHub App integration. That integration, public signed GitHub ingress, installation tokens, UI and real Sigma/Synapsis conformance are **not implemented by this phase**. External facts currently enter through the existing operator API-key/infrastructure boundary. Do not point unsigned public GitHub hooks at this API or claim native GitHub integration from it.

## Ownership and persisted flow

1. A Project/Task/Attempt command commits its state, command receipt, immutable `domain_events`, `event_deliveries` and Oban wakeups in one PostgreSQL transaction. Failure to enqueue rolls back the mutation. Socket state/PubSub is not the outbox.
2. Operators explicitly select one enabled Project member with the `manager` role and approved/advertised `project_events.v1`. Implementation names confer no privilege. Routing is a revisioned `event_subscriptions` record with `purpose=responsible`; no recipient is inferred from Synapsis, Sigma or Codex.
3. A delivery freezes the subscription revision, Agent ID, endpoint/protocol/credential-reference digest and a UUID `operation_id`. A claim commits a numbered attempt, lease ID, monotonic fence and authority epoch. Network I/O starts after the transaction releases its locks.
4. The generic `Samgita.Connector` implementation negotiates only native `project_events.v1` on an authenticated `/app-server` WebSocket and calls receive or status. It never calls execution-session methods. A response is persisted only while the local handler still owns the unexpired fence/epoch and the current membership/target remain valid.
5. Durable acknowledgements and processing reports are separate append-only records. Delivery results do not create an execution Attempt, release work holds, review a Task or accept work. A Task still needs its existing explicit review and acceptance commands.

Identifiers have different scopes:

| Identity | Contract |
| --- | --- |
| `event_id`, `created_at`, schema version | Original immutable event UUID/time/version, preserved across every retry and administrative replay |
| Project UUID, optional Task UUID | Stable management references; never inferred from `git_url` or a connection name |
| `correlation_id`, optional `causation_id` | Command/source correlation and a prior Project event; manual/external API references are validated |
| `source`, `source_id` | Domain command, manual trigger, external source/delivery ID or schedule occurrence UUID |
| Delivery UUID, `operation_id` | Logical notification to one frozen target; stable through retries and recovery on that delivery |
| Delivery attempt UUID | One receive/status wire attempt; changes on every call |
| Lease ID, fence, epoch | Local handler authority, never a credential or remote work grant; lease ID is excluded from API projections |

The wire envelope is P2 schema `1.0`; sequence, source and resource facts live in its payload. Native read-only status uses the original operation as correlation and addresses the original event ID. Only receive uses that operation as `command_id`. A receiver must keep deduplication/status records across connections; the bounded P2 connection cache alone is insufficient.

## Delivery semantics and recovery

| State | Meaning and automatic behavior |
| --- | --- |
| `pending` / `retry_wait` | Eligible receive; bounded exponential delay, same event/operation, new wire-attempt ID |
| `delivering` | One locally leased receive/status handler; another handler cannot settle its result |
| `reconciling` | Read-only status query due; never an implicit execution/session restart |
| `accepted` | Agent reports durable notification acceptance; processing can remain pending |
| `completed` | Agent reports completed/failed/rejected processing; inspect `processing_status`; no Task acceptance implied |
| `uncertain` | Remote durability/outcome cannot be safely established; automatic sending stops |
| `authentication_failed` | Authentication/credential resolution failed; explicit repair/recovery required |
| `dead_letter` | Permanent rejection or exhausted known-failure retries; no automatic retry |
| `cancelled` | Local sending/callback ownership cancelled; already sent remote effects may still be unknown |
| `legacy_unreviewed` | Preserved P3 intent lacking approved P4 target semantics; never sent automatically |

A transport receipt (`acceptance=received`) is recorded but does not establish durability. Only `acceptance=durable` sets durable acceptance. Processing completion remains separate from that acknowledgement and from Project/Task acceptance. Reports are authenticated as the current responsible Agent and check operation, version, fence and epoch. Stale/expired/cancelled/reassigned reporters cannot commit.

Delivery is **at least once**, not exactly-once external execution. Receive timeout, malformed mutation replies, handler loss and ambiguous disconnect move to status reconciliation. Status/not-found permits a receive retry only when the operator has explicitly recorded the Agent's persistent event/operation idempotency guarantee. The default is false. Without that guarantee, absence after an ambiguous send becomes `uncertain`. Never infer that nothing happened from a reconnect, elapsed timeout, process crash or an empty connection cache.

Each recovery cycle allows eight network attempts, including status calls. Backoff starts at five seconds and doubles, capped at one hour. A bounded `Retry-After` can extend it; 429 is retryable failure and is never an acknowledgement. Authentication, permanent, retryable and ambiguous outcomes remain distinct. Unsupported capabilities/methods fail explicitly. Reconciliation failures also exhaust into inspectable uncertainty rather than endless polling. Oban retries unexpected local failures, while the durable delivery row controls network eligibility; Oban uniqueness does not promise exactly once.

Handler leases last 60 seconds. Renewal is explicit and capped at five minutes from attempt start. The connector's bounded connect/request deadlines fit inside the lease. Expiry records an unknown attempt and increments the fence before another handler can query status. Authority closure fences active delivery handlers as well as Task Attempts. Maintenance can expire execution ownership into existing unresolved-effect holds, but cannot restart or reassign execution. Paused/archived Projects close new receives while allowing status-only reconciliation; closed platform admissions permit no outbound traffic.

Operator recovery requires a command UUID, expected delivery version and a reason. `reconcile` and `redeliver` also require an evidence reference. Redelivery after any send without an idempotency guarantee requires explicit `risk_acknowledged=true`, even after a previously successful delivery. Recovery appends a separate administrative record, keeps all attempts/ACKs/results and preserves event/time/operation identity. Cancellation invalidates local ownership and records uncertainty when a send may have occurred; it does not pretend to undo remote execution.

Changed endpoints, credentials references or memberships do not silently retarget a delivery. To use a new responsible subscription, the operator explicitly selects its ID/revision and original event via the event redelivery API, supplies the source delivery/evidence/reason and acknowledges duplicate-effect risk after any prior send. This creates a new delivery/operation linked to the previous delivery, preserves the original event/time, and leaves the old history/outcome intact. Results from the old subscription cannot commit. Actual external effects still need reconciliation; choosing a new recipient does not prove that the old Agent stopped.

Authenticated paginated event reads expose per-Project sequence/high-watermark cursors. A responsible Agent's cursor ACK cannot pass a delivery without durable acceptance. Filtered/unsubscribed audit events do not invent required deliveries. Duplicate cursor ACKs are safe; regressing/out-of-range/gap ACKs fail. Historical notification ACKs confer no current execution authority.

## Sources and schedules

The versioned source catalog adds `manual.triggered`, `external.received` and `schedule.check`; routing and schedule configuration have non-notifying audit events (`event.routing_configured`, `schedule.created`, `schedule.updated`). Processing reports and recovery history do not recursively notify the Agent. Existing P3 Project/Task/Attempt mutations already append their domain events and now produce transactional wakeups for approved subscriptions.

External source identity is unique within `(project_id, source, external_id)`. Identical content returns the original event, even with a different command ID; changed content under that identity conflicts. Operator-authenticated ingestion is the trust boundary for these generic facts. API payloads allow bounded strings `reason`, `summary`, `reference`, `subject`, `external_ref`, `status`, `repository_id`, `task_id`, `check` and bounded string `labels`; arbitrary credentials, prompts and tool output are not part of this profile. Task and causation references must belong to the Project. Repository IDs in generic external facts are descriptive metadata, not verified GitHub identity or an authorization grant.

Schedules default to `Etc/UTC`, persist an IANA timezone, numeric five-field Oban cron expression, enabled state, payload, revision/version and last scanned absolute UTC minute. Aliases such as `@reboot`, seconds and named months/weekdays are unsupported. Oban's constrained day-of-month and day-of-week fields match conjunctively. The first evaluation is the minute after `start_at` (default current UTC minute).

A minute Cron wakeup scans at most 100 schedules, 1,440 UTC minutes and 100 emitted occurrences per schedule. It catches up missed real occurrences in successive bounded batches, advancing the cursor atomically with each occurrence/event/job. The cursor remains visible as backlog evidence. Unique `(schedule_id, revision, due_at)` prevents duplicate logical occurrences across scanners/restarts. Repeated DST local minutes correspond to separate UTC instants; nonexistent minutes emit nothing. Disabled or inactive-Project schedules emit nothing. Revision updates reset the cursor to the current UTC minute unless an operator explicitly supplies `start_at` for intentional catch-up; old revisions/occurrences are retained. A schedule emits a check fact, not a predetermined development action.

## API surface and security

All paths below start with `/api/projects/:project_id` and retain existing operator API-key/rate-limit policy:

| Method/path | Operation |
| --- | --- |
| `GET /events?after=<sequence>&limit=<1..100>` | Ordered event facts and cursor/high watermark |
| `POST /events/trigger` | Manual fact |
| `POST /events/external` | Operator-authenticated external inbox fact |
| `GET`, `PUT /event-routing` | Inspect/configure responsible Agent |
| `POST /events/:event_id/redeliver` | Explicit replay to a selected current subscription |
| `GET /deliveries`, `GET /deliveries/:id` | Delivery state, attempts, acknowledgements and administrative history |
| `POST /deliveries/:id/recover` | Cancel, reconcile or explicitly redeliver |
| `GET`, `POST /schedules`; `PATCH /schedules/:id` | Read/create/revise schedules |

The machine equivalents under `/api/agent/projects/:project_id` require Bearer credentials, current connection and Project membership. They support event/routing/delivery/schedule reads, manager manual triggers, `POST /event-routing/:subscription_id/ack` and `POST /deliveries/:id/report`. Schedule/routing configuration, external ingestion and recovery remain operator-only. Project context includes routing and allowed event operations. Capability advertisement grants no role.

Outbound connections require two separate operator inputs. `SAMGITA_EVENT_DESTINATIONS` maps stable Agent UUIDs to an exact URL and approved IP address strings, optionally `allow_insecure=true` for loopback test services. Only `/app-server` is supported. Every DNS result must remain approved; dialing uses a pinned address while retaining the original TLS hostname/SNI. WSS is mandatory remotely. Redirects, URL credentials/query/fragment, unapproved hosts/ports/paths and DNS changes fail closed.

`SAMGITA_EVENT_CREDENTIALS` maps outbound `credential_ref` names to runtime service tokens. No plaintext token enters PostgreSQL, events, receipts, projections or safe failure codes. References must be immutable/versioned: rotate by installing a new reference and explicitly reviewing the changed routing/replay. Changing the secret behind an existing name is unsupported because it could change remote deduplication scope without a database-visible identity change. Inbound machine credentials are separately digest-only and remain subject to revocation/current-connection checks. Registering an Agent alone neither approves egress nor launches a worker/session.

Agent row locks use `FOR NO KEY UPDATE`: identity keys are immutable, capacity/credential updates remain serialized, and foreign-key `KEY SHARE` from a Project's atomic outbox can proceed without reversing the Agent -> Project lock order. Authority locks remain outermost. No database transaction spans a remote call. Messages are limited to 256 KiB, connections to one pending request/eight buffered messages, and requests/connects have bounded deadlines. The protocol core remains independent of Phoenix, Repo and platform configuration; address pinning and HTTP upgrade details are optional transport features.

## Migration, legacy isolation and rollback

Only additive migration `20261022000002_add_durable_coordination.exs` is new. Existing event IDs, creation times/data, Project UUIDs, `git_url` provenance, subscriptions, delivery IDs, receipts, historical hooks and migrations remain. Correlation is backfilled from the original command UUID. P3 delivery intents become `legacy_unreviewed` without fabricating operations or sending anything. An operator may explicitly replay an original event to an approved current subscription after review; no initial migration is replaced or Project rekeyed.

Only exact new worker/queue pairs are admitted: EventDeliveryWorker on `hub_events`, ScheduleTickWorker on `hub_schedules`, and CoordinationMaintenanceWorker/AttemptExpiryWorker on `hub_maintenance`. Only schedule and maintenance Cron wakeups are installed. Unknown/historical nonterminal Oban jobs still block platform activation; using a new queue name does not bless an old worker. Legacy RARV, recovery, provider and webhook executors remain absent.

The compatibility `Webhooks.dispatch` preserves old webhook IDs and argument shape, enqueues only into disabled `legacy_webhooks`, and returns a quarantined result. Any insertion error rolls back the entire batch and reaches the caller as `enqueue_failed`; the old `Enum.each` failure swallowing is removed. No old HMAC/body/URL is rewritten or sent. Translation, old-job disposition and actual legacy-writer exclusion are explicit deployment gates.

Rollback closes admissions/increments the authority epoch, stops new queues/Cron and retains the additive schema/history. Use a compatible binary for read-only inspection and reconciliation. Down migrations raise rather than destroy coordination history. A database rollback cannot undo remote notifications/effects. Never reopen an old executor as fallback or replay retained hook jobs automatically.

## Verification and remaining gates

Run only the scoped coordination, affected authority/authorization/lease tests and independent protocol tests recorded in this phase. Use the named local scratch database `samgita_redesign_coordination_final_test` (or another explicitly matching `samgita_redesign_*_test`), never a shared/production database. Preservation rehearsals create additional uniquely named scratch databases and retain them for inspection.

The core test scope covers rollback/enqueue failure, lost wakeup, a killed worker after committed claim/before wire send, duplicate delivery, ACK loss and status-only recovery, received-vs-durable state, unavailable Agent, 429 delay, authentication/permanent errors, retry exhaustion, renewal/expiry/fencing, target changes, explicit retarget replay, stale callback reports, Task acceptance isolation, cursor gaps, cancellation and real concurrent PostgreSQL transactions (distinct backend PIDs). Scheduler checks cover fixed clocks, DST gaps/repeats, bounded catch-up, disable/revision, concurrent scanners and scoped Task references. API checks cover retained operator and machine boundaries. Fake-Agent WebSocket tests are local wire evidence, not real-service durability/security evidence.

P3 -> P4 rehearsal seeds events/subscriptions/intents and checks unchanged IDs, content and timestamps, inert migrated delivery state, no new jobs and repeat migration safety. The original legacy/memory sentinel and migration hash manifest checks remain. Full production data inventory, pgvector/dual-Repo backup/restore, legacy-producer fencing, key management and compatible release/restart/rollback rehearsals remain B1/B2/B4 gates. Real Agent idempotency, authentication and supported protocol need B3/B6 evidence. GitHub App/signature/install-scope integration and real destination approval remain B5 gates. No production migration, external repository change, push, deployment or UI phase is authorized here.

Final scoped verification completed on 2026-10-23 (Asia/Shanghai):

| Check | Result |
| --- | --- |
| Root coordination and affected authority/API scope below | **92 tests, 0 failures**: 75 core and 17 web, seed `388086` |
| Standalone optional WebSocket package | **24 tests, 0 failures**, seed `917460` |
| Protocol core in a temporary copy outside the repository | **30 tests, 0 failures**, seed `147389` |
| Standalone consumer in that outside copy | **1 test, 0 failures**, seed `856545` |
| Root `MIX_ENV=test mix compile --warnings-as-errors` | Passed |
| Explicit changed-file `MIX_ENV=test mix format --check-formatted` | Passed for 44 Elixir files; pinned historical sources excluded |
| Standalone optional transport compile with warnings as errors and format check | Passed |

Root test command (the socket-only PostgreSQL instance and its data are local scratch resources):

```sh
devenv shell --no-tui --no-reload -- env \
  MIX_ENV=test PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 \
  POSTGRES_USER=gao SAMGITA_TEST_DATABASE=samgita_redesign_coordination_final_test \
  mix test \
  apps/samgita/test/samgita/events \
  apps/samgita/test/samgita/connectors \
  apps/samgita/test/samgita/schedules_test.exs \
  apps/samgita/test/samgita/workers \
  apps/samgita/test/samgita/webhooks_test.exs \
  apps/samgita/test/samgita/legacy_isolation_test.exs \
  apps/samgita/test/samgita/migration/coordination_preservation_test.exs \
  apps/samgita/test/samgita/migration/preservation_test.exs \
  apps/samgita_web/test/samgita_web/controllers/coordination_api_test.exs \
  apps/samgita/test/samgita/agents_test.exs \
  apps/samgita/test/samgita/projects_test.exs \
  apps/samgita/test/samgita/platform_test.exs \
  apps/samgita/test/samgita/attempts_test.exs \
  apps/samgita/test/samgita/tasks/ownership_race_test.exs \
  apps/samgita/test/samgita/security_race_test.exs \
  apps/samgita_web/test/samgita_web/controllers/domain_api_test.exs
```

Independent package commands:

```sh
devenv shell --no-tui --no-reload -- env \
  -C apps/samgita_protocol_websocket MIX_ENV=test mix test
devenv shell --no-tui --no-reload -- python \
  apps/samgita_protocol/scripts/verify_standalone.py
```

The standalone script also compiles with warnings as errors and checks formatting in the outside copy. The optional transport has its own compile/format checks. Root compilation and formatting use the verified test build; an initial dev-profile formatter invocation encountered a pre-existing corrupt `_build/dev` telemetry/type-check cache before formatting. That unrelated cache was not repaired, and dev-profile compilation is not claimed. No full umbrella/legacy test baseline, assets/browser check, managed-service restart or external-service probe was performed.
