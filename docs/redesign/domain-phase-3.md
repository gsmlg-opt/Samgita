# Phase 3: persistent management domain

Status: implemented locally, 2026-10-22. This record narrows P3 and reconciles the merged foundation; it does not authorize deployment or the next phase.

## Reconciled baseline and migration

The foundation removed source files, not proven database contents. Restore the 17 main migration files verbatim from `2bc3765ac94e1faea50f061b6938c0ef51e6f92b`. Their original versions remain authoritative; the existing September Oban migration upgrades the historical Oban schema. Restore no legacy runtime. New additive migrations expand those tables for both fresh installations and databases with historical migration receipts. Preserve every historical column, ID, FK, row and raw value. Relax the legacy Project URL requirement/unique index for neutral projects; preserve raw URLs as provenance and map them to separate repository associations without merging Projects.

The three removed memory migrations are accounted for with pinned source hashes and fixture copies, outside the active migration path. Existing `sm_*` data/extensions are untouched. P3 does not install pgvector or reconstruct memory runtime. Unknown or drifted legacy layouts fail the migration rehearsal and require operator review.

New execution authority starts at `none`, admissions closed. Operator activation requires explicit fencing/effect-resolution evidence and configured lease keys. No source flag can fence an unmodified old binary: deployment still requires excluding old writers and completing B1/B4. `Platform.status/1` inventories pending legacy jobs without exposing their arguments; activation refuses while any nonterminal job remains. P3 has no job classification/drain API and never runs, retries or cancels those jobs. No registration, mapping, relationship or Task creation launches a process, schedules a job, or invokes a provider.

`LegacyMapping.preview/1` returns IDs, digests and bounded mapping classifications. `apply/2` requires owner `none` with admissions closed; it persists resumable mappings, inert neutral states and unverified repository associations. Unknown states, cross-Project/cyclic/disagreeing dependency forms and changed source digests require review. A changed source persists `source_changed` while retaining the original digest; Tasks stay held. Adoption and migrated claims validate the recorded source again. Original worker strings/counters cannot create an Agent or Attempt. Legacy Project names/URLs and Task parent references are frozen; added neutral descriptions/titles may change. Source digests exclude added fields and managed `updated_at`; its original value remains in ledger evidence. There is no conflict-override command in P3.

## Frozen implementation contracts

Root owns migrations, shared configuration/manifests, command/auth primitives, Agent/Project/repository/session contexts, event/receipt foundation, migration mapping, isolated database wiring and this record. Task owner owns Task/Attempt/Decision/Artifact schemas, contexts, pure transitions and domain tests. Web owner owns machine plug, API controllers/routes/projections and API tests. Preserve other owners' edits; serialize builds.

Contexts accept `%Samgita.Principal{kind: :operator | :agent, agent_id, credential_id, connection_id, generation}`. Operator identity is established by existing infrastructure/API-key boundaries. Machine identity is resolved from a supplied high-entropy credential; only its SHA-256 digest is stored. Capability claims never grant roles. Machine commands recheck enabled Agent/credential/current connection and Project membership inside their transaction, including receipt replay.

`Samgita.Commands.run(principal, project_id_or_nil, attrs, opts, callback)` returns `{:ok, result_map}` or `{:error, %Samgita.Error{code, message, details}}`. Attributes use string keys. Required `command_id` is a UUID. Options include `operation`, allowed `roles` (any match), and additional `agent_ids` to lock before the Project. The callback receives `%{principal: principal, command_id: command_id, project: locked_project_or_nil, authority: authority}`. `Commands.expect!(record, attrs)` enforces `expected_version`; `Commands.require_hub!(context)` gates execution. `Commands.fail!(code, details \\ %{})` aborts atomically. Context reads use `Commands.read(principal, project_id, roles, callback)` with the same current authorization, without command metadata.

Commands lock authority, sorted Agent IDs, Project, then subordinate resources/Tasks/Attempts. Successful receipts store sanitized results/digests and event IDs, never credentials or lease proofs. Current authentication/authorization precedes receipt replay; replay precedes mutable versions and lifecycle checks. Same command ID with different semantics conflicts. Events carry stable IDs/timestamps, Project sequence, actor/command/resource identity and allowlisted before/after state/version snapshots; an Attempt mutation also records its Task snapshots. Events and existing subscriber delivery intents commit with the change. The versioned catalog is in [design §5](design.md#5-github-schedules-and-event-delivery). P4 owns subscription APIs, durable cursors and dispatch.

Public commands return string-keyed, allowlisted maps, never Ecto structs. `%Samgita.Error{}` has stable codes `unauthorized`, `forbidden`, `not_found`, `invalid`, `conflict`, `stale_version`, `invalid_transition`, `execution_closed`, `ownership_lost`, `capacity_exceeded`. `Samgita.Projection` supplies safe record projections. Invalid changesets become safe field errors.

Roles are membership strings `observer`, `worker`, `manager`, `reviewer`. Observer reads; worker claims/reports its own Attempts; manager creates/edits/delegates Tasks and manages project context; reviewer reviews/accepts/rejects submitted work. Operator administers registration, membership and credential lifecycle. The Agent registry has no implementation-specific defaults or roles. Agent connections and execution sessions are separate persisted records; replacing a connection does not adopt an existing Attempt/session. Pausing blocks new claim/start, while existing-owner renew/report/reconciliation stays available. Context operation hints still require per-resource versions/ownership and current authority when invoked.

Task states: `open`, `in_progress`, `blocked`, `awaiting_review`, `accepted`, `failed`, `cancelled`. Successful execution closes its Attempt as `succeeded` and submits the Task to `awaiting_review`. A separate reviewer/operator decision accepts it. Neither a capability, completion report, artifact, nor protocol acknowledgement constitutes acceptance. Historical completed Tasks project to `awaiting_review` (unadopted), preserving their original status/result; no fabricated acceptance or Attempt.

Attempt states: `leased`, `running`, `succeeded`, `failed`, `expired`, `released`, `cancelled`. Agent capacity and one-active-Attempt-per-Task are serialized in PostgreSQL. Leases, monotonic fences, epoch and explicit connection generation reject stale owners. Unknown effects hold both Task eligibility and capacity. Reopen never clears a hold. Expiry never retries execution. Lease proofs use versioned HMAC keys supplied only in runtime configuration; only key identifiers are stored. Tests use dedicated test keys; a production key is not invented.

## Context surface

- `Agents.register/2`, `update/3`, `get/2`, `list/2`; `put_credential/3`, `revoke_credential/3`; `authenticate/1`, `connect/2`, `bind_connection/2`; `open_session/3`, `list_sessions/2`.
- `Projects.create/2`, `update/3`, `transition/3`, `get/2`, `list/2`, `context/3`; `put_member/3`.
- `Repositories.associate/3`, `list/2`.
- `Tasks.create/3`, `update/4`, `get/3`, `list/3`, `transition/4`, `adopt/4`, `decide/4`, `add_artifact/4`.
- `Attempts.claim/4`, `start/4`, `renew/4`, `report/4`, `rebind/4`, `resolve/4`, `expire/2` (operator maintenance command; no scheduler in P3).
- `Platform.status/1`, `activate/2`, `close/2`; migration dry-run/apply through `LegacyMapping`.

Read lists are bounded/paginated. Project context returns safe repository associations, membership roles, Task summaries and allowed operations. Machine routes never trust a posted Agent ID. New APIs archive and retain history instead of deleting aggregates. No UI, GitHub ingress, network delivery, automatic maintenance or external Agent server is implemented in P3.

## REST usage and boundaries

Operator routes under `/api` retain `x-api-key` protection when configured and existing rate limits. With no configured operator keys, access remains an infrastructure responsibility; an explicit Bearer request is rejected there rather than promoted to operator. Machine routes under `/api/agent` always require `Authorization: Bearer <credential>` and, except connect, `x-agent-connection: <current connection UUID>`. These are Project membership grants, not browser accounts.

| Surface | Routes and authorization |
| --- | --- |
| Registration | Operator `GET/POST /api/agents`, `GET/PATCH /api/agents/:id`; metadata only, no runtime launch. |
| Credentials | Operator `POST /api/agents/:id/credentials`, `POST /api/agents/:id/credentials/:credential_id/revoke`; caller supplies a random credential of at least 32 bytes. Only digest/reference/expiry are stored; responses contain metadata with `Cache-Control: no-store`. |
| Connection | Machine `POST /api/agent/connect` with a new command UUID; returns connection ID/generation. A replacement invalidates the former generation. Replaying the same connect command returns its historical receipt, not a fresh connection. |
| Projects | Operator `GET/POST /api/projects`; both principals may read/update granted Projects and `POST .../:id/transition`. Only operator creates Projects, grants `POST /api/projects/:id/members`, and restores an archive with a reason. |
| Context/repositories/sessions | `GET .../projects/:id/context`, `GET/POST .../:id/repositories`, `GET/POST .../:id/sessions`; membership plus manager/worker restrictions for writes. Sessions record external references and open no remote connection. |
| Tasks | `GET/POST .../projects/:id/tasks`, `GET/PATCH .../tasks/:task_id`, `POST .../:task_id/transition`, `/decisions`, `/artifacts`; manager manages work, reviewer records decisions, worker may attach its own Attempt's artifact. Adoption `/adopt` is exposed on the operator path only. |
| Attempts | Machine `POST .../tasks/:task_id/claim`, `POST .../attempts/:id/start`, `/renew`, `/report`, `/rebind`, `/resolve`; owner worker only, with version/proof/epoch checks. `GET .../attempts/:id/proof` is current-owner-only and `no-store`. Operator has explicit `/resolve`; expiry is a core maintenance command with no scheduler/REST route. |
| Authority | Operator `GET /api/platform`, `POST /api/platform/activate`, `/close`; explicit evidence/reason and expected authority version. Activation records authority only and starts nothing. |

For rows marked “both”, use `/api/...` for operator and `/api/agent/...` for machine; actual routes are in `SamgitaWeb.Router`. Single-resource responses use `{"data": ...}`; list responses use `{"data": [...], "limit": 50, "offset": 0}`. Errors use typed codes and safe field details; stale versions/conflicts/invalid transitions return 409, invalid inputs 400, missing scope 404, missing identity 401, denied grants 403. Path Project/resource IDs override submitted IDs.

Example operator registration body (IDs here are illustrative):

```json
{
  "command_id": "75cdcd66-95c6-4e40-aa6c-9ab67c86b451",
  "name": "Reference Agent",
  "protocol": "samgita",
  "protocol_version": "1.0",
  "advertised_capabilities": ["project_events.v1", "sessions.v1"],
  "approved_capabilities": []
}
```

Install the credential separately; grant explicit roles on a Project with its current `expected_version`. A responsible manager can then `POST /api/agent/projects/:id/tasks` with a new `command_id`, title and optional same-Project parent. A worker records its external session, claims the Task using the Task version/session ID, fetches its proof, then starts using the Attempt version. A resolved success report leaves the Task awaiting review. A reviewer sends two distinct versioned decision commands: `kind=review, verdict=approve`, then `kind=acceptance, verdict=approve`. An intervening Task edit invalidates the prior review.

Every mutation needs a new UUID command ID; updates also need the resource's current `expected_version`. A lost response is reconciled with the **same** ID and unchanged semantic body. A new ID after an ambiguous disconnect could execute another command and must not be an automatic retry. Historical success receipts grant no current ownership; changed/revoked credentials, membership or epoch are checked first. Lease proofs cover Attempt/Project/Task/Agent/session/connection/generation/fence/epoch/key/deadlines; renewal requires fetching the new proof. P3's REST commands do not claim to mount the reusable app-server transport on Samgita.

## Verification and remaining gates

Use explicitly named scratch databases on an isolated local PostgreSQL instance. Fresh and populated historical rehearsals compare IDs, references and content digests, replay mappings, and preserve unknown statuses as conflicts. Concurrency tests use independent real transactions. Domain/API tests cover current and revoked credentials/connections, Project roles/cross-Project IDs, stale writes/idempotency, review acceptance, ownership/holds and legacy isolation.

Local checks do not clear live inventory, backups, guard-aware bridge, unknown effects, actual-service authentication or production lease-key rotation. Those remain deployment blockers. Rollback closes admissions and advances epoch, keeps additive schema/history and serves management/history; it never starts legacy execution or runs destructive down migrations. Commit P3 and stop.

### Phase record

Baseline: `bce0308df5ad13db28c718d07ff6e1d82c2cd301`, on `main`. The commit containing this record is the P3 delivery. The three P2 protocol projects are unchanged; core consumes their native version/capability contract. No external repository or production service/database was changed.

The verification instance was PostgreSQL on Unix socket `/tmp/samgita-p3-pg/socket`, port `55443`, user `gao`; no TCP listener. The main scratch target was `samgita_redesign_p3_verified_test`, created explicitly with UTF-8 and `template0`. Historical expansion tests created separate random `samgita_redesign_p3_migration_*_test` databases and retained them as local artifacts. The temporary instance was stopped after verification; its data directory remains at `/tmp/samgita-p3-pg/data`. No reset/drop or production migration ran.

```sh
devenv shell --no-tui --no-reload -- env \
  MIX_ENV=test PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 \
  POSTGRES_USER=gao SAMGITA_TEST_DATABASE=samgita_redesign_p3_verified_test \
  mix test apps/samgita/test/samgita \
  apps/samgita_web/test/samgita_web/controllers/domain_api_test.exs \
  apps/samgita_web/test/samgita_web/controllers/fallback_controller_test.exs \
  apps/samgita_web/test/samgita_web/plugs/api_auth_test.exs \
  apps/samgita_web/test/samgita_web/plugs/rate_limit_test.exs

devenv shell --no-tui --no-reload -- env MIX_ENV=test mix compile --warnings-as-errors
```

Results: **87 tests, 0 failures** (48 core, 39 web), seed `197697`; compilation passed. Scoped `mix format --check-formatted` passed for all 66 changed Elixir files, excluding the verbatim historical migration sources and memory fixture copies. The suite verifies the pinned hashes instead. Whitespace and all 24 local document links/anchors passed. No UI/assets/browser or full legacy suite was run, because those behaviors are outside this phase.

The checks exercise populated historical content/IDs/references/chronology, all legacy state mappings, mapping reruns/source drift/dependency conflicts, explicit adoption, frozen legacy fields, distinct review/acceptance, credential/connection/membership scope, receipts and atomic audit/delivery intents, lease proofs/rebind/rotation/holds, and disabled legacy runtime/queues. Independent committed transactions use different PostgreSQL backend PIDs to race Agent capacity, same-Task claims, Project versions, credential revocation and authority closure. Context regressions verify that a paused Project still advertises existing-owner reconciliation operations while hiding claim/start, and that unmapped historical Projects cannot gain competing repository associations before mapping.

| Gate | P3 evidence and remaining work |
| --- | --- |
| B0 | Locally reconciled: restored pinned main sources, accounted-for inactive memory sources, additive schemas and preservation fixture. |
| B1/B2 | Actual deployment/node/process/job/schema inventory, complete memory/pgvector/history readers, restorable backup and target-specific mapping decisions remain open. The memory sentinel is deliberately bounded evidence. |
| B3/B5 | Actual Agent-service authentication/compatibility, approved remote destinations and GitHub App installation/ingress remain unverified and disabled here. Endpoint descriptors alone confer no network authority. |
| B4 | P3 has no legacy executors and refuses pending jobs, mapping conflicts and unresolved executions; it cannot exclude an old binary or drain external effects. Job classification, bridge/restart/rollback rehearsal and writer exclusion remain cutover work. |
| B6 | Local receipt/proof/rebind/rotation/epoch contracts pass. Production signing-key management, release integration and actual-service protocol conformance remain open. |

P4 event delivery/GitHub/schedules and P5 UI/platform transport remain unexecuted. No new authority is enabled outside isolated tests. This phase ends with its reviewable commit; it does not authorize push or deployment.
