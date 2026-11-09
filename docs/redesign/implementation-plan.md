# Samgita agent-neutral platform implementation plan

Date: 2026-10-23. Status: P0 accepted; P2–P4 implemented; P5 management UI and bounded local P6 qualification are recorded in [qualification](qualification.md). P1 target preservation/drain and applicable release/integration gates remain open. Commit/push this scope; do not deploy.

The subsequent [reliability repair](qualification.md#reliability-repair-qualification) fixes the demonstrated deletion, wakeup, protocol, schedule-identity and rate-limiter defects and clears the prior local static/security/build failures. Repeated populated-database and standalone checks now pass. Raw LiveView telemetry still blocks A11; real integration and target cutover gates remain open. This does not authorize a new product phase or deployment.

**Goal:** preserve existing Projects, Tasks and history while moving execution decisions to registered Agents and establishing repository associations, a reusable app-server implementation, GitHub connections and durable events.

**Architecture:** keep the existing Ecto/Phoenix umbrella, independently consumable `samgita_protocol` packages and neutral platform contexts. P3 adds durable execution authority starting closed; a deployed legacy system still needs a guarded drain before cutover. Adopt legacy work explicitly; do not implement a second Sigma server or a Backplane protocol dependency.

**Stack:** Elixir/OTP, Ecto/PostgreSQL, Styx, Phoenix LiveView, Gaoxy,
DuskmoonBundler/TypeScript and existing DuskMoon assets. The approved
[dependency modernization](dependency-modernization.md) owns this amendment,
including integrated Tailwind compilation, http_fetch and the 2026-11-07 production WebSocket migration to
http_web_socket 1.0.0-rc.5. Pin/TLS/authentication/security runtime checks remain
unrun; Gaoxy's pinned Abyss/Hell refresh is tracked in gsmlg-dev/gaoxy#22.
Historical phase records below retain their original stack and qualification evidence. No new
account framework, embedded LLM runtime or component library.

The 2026-11-08 user clarification supersedes the old Oban-migration and
test-only Bandit retention plan. Remove both dependencies from production,
test and release, the two Oban migration sources and the old Bandit raw-HTTP
telemetry test; add no shim. Platform admission/status reads Styx only. This
does not authorize deleting existing database rows or production migration.
Historical P3/P4 paths, hashes and results below describe their original
revisions; they do not require restoring Oban or establish new verification.

Final removal obligations: inspect all manifests/locks and assembled release
applications; compile without Oban/Bandit; run reviewed Styx/transaction/status
functional checks and fresh/populated-history migration rehearsals in isolated
databases; record the two intentional source removals in provenance expectations;
and recheck affected UI/assets on the supported builder. Record actual outcomes
in the amendment. Security/permission checks remain prohibited and A11 remains
unverified, including after deletion of the old Bandit test.

Read [design](design.md) and [acceptance](acceptance.md) first. Source paths below are repository-relative. P2/P3 paths exist; proposed later files/tests become executable only in their owning stage. Each future change starts with its specified failing behavioral check, adds the smallest implementation, reruns only scoped checks, and makes a logical Conventional Commit. Do not use the former `docs/plan.md` deletion stages.

Merged baseline: `d6e9eca` combines this design's `3a344f5` and the separately authorized source removal in `811eeb9`. P2 added the independent packages. P3 reconciles B0 for its local scope by restoring 17 main migration sources verbatim from `2bc3765ac94e1faea50f061b6938c0ef51e6f92b`, retaining the foundation's September Oban upgrade, pinning main/memory source hashes and adding the neutral schema. This does not prove a live migration, backup restore, complete historical reader or dual-Repo/pgvector preservation. P1's legacy callsites below remain a historical recipe against that pinned revision; many no longer exist. Do not restore legacy runtime or execute the old callsite lists. An actual legacy deployment still requires inventory, old-writer exclusion and target-specific preservation/cutover evidence. See [P3's reconciled contract](domain-phase-3.md).

## 1. Delivery contract and dependencies

| Stage | Dependency | Ownership | Gate / suggested commit units |
| --- | --- | --- | --- |
| P0: completed design phase | Historical baseline | Documentation owner; parallel read-only audits | Four-file document review/checks and scoped commit. |
| P1: preservation harness and bridge | Actual legacy deployment inventory and separate authorization | One runtime/migration owner | P3 supplies a bounded local fixture/authority foundation; full writer guard, job classifications, backup/dual-storage and guarded restart remain open. |
| P2: independent protocol, implemented | Bounded B0 reconciliation in phase record; P0 accepted; independent of P1 | Core, optional transport and adapter owners; no shared config/migration edits | Independent consumer, versioned schema fixtures, real transport/fake-host conformance; commit `bce0308`. |
| P3: neutral identities/state, mappings and REST APIs, implemented | Reconciled removed-source baseline; P2 contracts; isolated scratch databases | Core/shared migration owner, Task owner and web owner | Additive preservation, mapping/adoption, versioned commands, fenced independent-transaction races and protected APIs verified locally. |
| P4: events/GitHub/schedules | P3 Project/repository/authorization contracts | Event owner, integration owner, migration owner | Transactional outbox, signed GitHub ingress, deterministic occurrences; separate event/GitHub/schedule commits. |
| P5: management UI and fake Agent, current qualification | P2–P4 | Web/read-model + protocol-fixture owners | Persisted operator journey, real fake WebSocket event delivery, protected REST Task callbacks, independent direct-session host and browser proof. No management WebSocket profile is advertised. |
| P6: full rehearsal and retirement preparation | P1–P5 and local contract blockers cleared | Integrator/runtime owner | Preservation, drain, restart and rollback rehearsal; reviewed cutover manifest with live/disabled-integration gates explicit. Deployment still requires explicit authorization. |

Only the migration owner edits new migrations, shared configuration, root manifests/releases and test DB wiring. Parallel work begins after shared public types, context commands, profile methods and event schemas are frozen. Event and GitHub/schedule workers may be developed independently after the outbox contract exists; P5 views may use frozen context contracts while P4 finishes. Every agent has non-overlapping file ownership and preserves others' work.

## 2. P0 — Design and reviewable commit

Scope: `AGENTS.md`, `docs/redesign/design.md`, this file and `docs/redesign/acceptance.md` only.

- [x] Audit schemas/migrations/references, supervision, orchestration/workers, providers, schedules, hooks, APIs/UI and existing access boundaries.
- [x] Record source facts separately from proposed contracts, including actual sibling endpoints and Codex-generated schema evidence.
- [x] Define neutral ownership, independent protocol/capability groups and direct service routing.
- [x] Inventory legacy subsystems and map identity/state/history without destructive clean start.
- [x] Define bridge, in-flight handling, exclusive authority, security, rollback and unresolved blockers.
- [x] Verify document links, requirement coverage, scope and whitespace; review migration/protocol contracts.
- [x] Stage only these four paths and commit `docs(redesign): plan agent-neutral platform migration`.
- [x] Stop; do not start P1, change running services or apply a migration.

No Mix compilation, database test, dependency installation, asset build or browser run is needed for this four-file documentation change. Those checks could start legacy apps or migrate databases and provide no runtime proof for unimplemented contracts.

## 3. P1 — Preservation harness and guard-aware bridge

Historical scope: the main/memory Repos, their migration histories and legacy writer paths refer to migration sources at the audited revision. The merged checkout has neither the memory app nor those legacy callsites. P3 supplies main-source reconciliation, a populated additive-migration fixture, a memory sentinel and closed execution authority; it does not complete this bridge. The unchecked P1 lists below remain target-dependent requirements, not executable current file assignments. Reconcile any actual legacy deployment before approving replacement scopes.

### P1.1 Isolate test databases and measure legacy history

Owner: migration/runtime owner.

Create:

- `apps/samgita/test/support/redesign/legacy_fixture.ex`
- `apps/samgita/test/samgita/redesign/preservation_manifest_test.exs`
- `apps/samgita/test/samgita/redesign/authority_test.exs`
- `apps/samgita/lib/mix/tasks/samgita.redesign.rehearse.ex`
- `apps/samgita/lib/samgita/migration/manifest.ex`

Modify only the relevant wiring in `config/test.exs`, `config/runtime.exs`, `apps/samgita/lib/samgita/release.ex`, and the three apps' test helpers/DataCase/ConnCase. Preserve ordinary dev/prod database defaults.

- [ ] Write a fixture with every main/memory historical table, stable UUID links, integer notification IDs, all legacy statuses, conflicting dependency representations, secret-shaped redacted endpoint data, opaque memory references and mixed worker jobs. No real credentials or user workspaces.
- [ ] Configure and prove isolation for every actual deployment Repo. P3's `config/test.exs` implements the `SAMGITA_TEST_DATABASE` allowlist for the sole current main Repo; there is no current memory Repo. Full dual-Repo preservation remains open.
- [ ] Use manual Styx testing for the current harness and disable all autonomous recovery/formation/pruning. Historical Oban deployment inventory is an external cutover obligation; do not add its dependency or reader. Fail closed if the test authority row is missing. Do not let `mix test`'s create/migrate alias touch a default/shared database.
- [ ] Make the preservation manifest enumerate historical migration provenance, table/row/ID/FK counts, payload digests and orphan/ambiguous mappings. Separately account for any actual legacy job instances at cutover. Output IDs/counts/digests only; no secret values or raw prompts.
- [ ] Prove fixture backup/restore on the named scratch DB. Do not treat the existing release helper as proof of memory migration coverage.

Gate: the P1 fixture/backup/dual-storage portions of A02/A14 in [acceptance](acceptance.md): enumerate every table/reference, restore the fixture unchanged, verify both DB overrides and suppress autonomous side effects. State mapping/adoption A03 and post-expansion A02 run in P3; release portions of A14 run in P6. A failure outside the owned scope is reported and stops this slice.

### P1.2 Fence legacy writers and dispatch

Create `apps/samgita/priv/repo/migrations/20261022000000_add_platform_authority.exs`, `apps/samgita/lib/samgita/execution_authority.ex`, and tests under `apps/samgita/test/samgita/redesign/` for `legacy_guard_test.exs`, `drain_test.exs`, `restart_test.exs`.

Modify guard callsites only in:

- `apps/samgita/lib/samgita/{application,projects,prds,features,notifications,git}.ex` and `git/worktree.ex`
- `apps/samgita/lib/samgita/project/{orchestrator,recovery,supervisor}.ex`
- `apps/samgita/lib/samgita/agent/{worker,claude,worktree_manager}.ex`
- `apps/samgita/lib/samgita/workers/{bootstrap,planning,agent_task,quality_gate,snapshot}_worker.ex`
- `apps/samgita/lib/samgita/codex_app_servers{,/runtime}.ex`
- `apps/samgita_provider/lib/samgita_provider.ex` and adapter dispatch entrypoints
- `apps/samgita_memory/lib/samgita_memory/{application,memories,prd,formation/telemetry_handler}.ex`, `memories/thinking_chain.ex`, `mcp/{server,tools}.ex`, `workers/{embedding,summarize,compaction}.ex` and `apps/samgita_memory/lib/mix/tasks/samgita.mcp.ex`
- `apps/samgita_web/lib/samgita_web/controllers/{project,task,prd,notification}_controller.ex` and relevant `live/{project_live,project_form_live,prd_chat_live}/index.ex` admission callsites

The provider/memory files remain temporarily owned by this bridge; this task is a fence, not a redesign of those apps.

- [ ] Write failing independent-transaction tests for a guard switch racing old enqueue/start/completion/recovery/provider dispatch. Cover missing guard, stale epoch, retry/snooze/rescue and direct context callers.
- [ ] Implement `legacy -> closed admissions/drain -> none -> hub` ownership transitions with monotonic epochs and the design's lock order. Guard-aware code must boot safely before and after additive migrations; execution fails closed without the authority table/row.
- [ ] Persist dispatch intents for actual external invocations. Distinguish queued jobs from executing Horde/OS/remote work; do not mark unknown work completed or reset running Tasks.
- [ ] Test paused-project boot recovery and global Agent workers surviving Project.Supervisor termination. Neither may escape the fence.
- [ ] Stop destructive snapshot/memory cleanup while preserving data and migration history. Inventory all named Oban states by worker; keep legacy WebhookWorker deliveries available despite its shared queue.
- [ ] Quarantine direct legacy write/delete/send/execution entrypoints in main PRD/feature/notification/Git contexts and memory/PRD/thinking-chain/MCP contexts, including standalone MCP callers. Retained read-only history stays accessible; guarding only supervisors/workers is insufficient.
- [ ] Define per-job drain/quarantine/resolution records without deleting Oban rows. Complete already executing work only under legacy ownership and its recorded epoch; no new dispatch during drain.
- [ ] Prove a pre-bridge binary cannot retain writer access at cutover. The deploy manifest must enumerate nodes/processes/credentials, not rely on a feature flag in the new node.

Gate: P1 portions of A08/A14 (guarded admissions/drain/restart with fixture processes) and pre-Hub A09 abort (return only to the bridge with admissions closed; retain the new authority schema). Add these assertions to `authority_test.exs`/`restart_test.exs`; full post-Hub rollback is P6. The bridge must preserve legacy reads and remain bootable with admissions closed. Stop before switching any live deployment.

Scoped commands after P1.1 wiring exists, run from the worktree root:

```sh
devenv shell --no-tui -- env MIX_ENV=test SAMGITA_TEST_DATABASE=samgita_redesign_guard_test mix test apps/samgita/test/samgita/redesign/preservation_manifest_test.exs apps/samgita/test/samgita/redesign/authority_test.exs apps/samgita/test/samgita/redesign/legacy_guard_test.exs apps/samgita/test/samgita/redesign/drain_test.exs apps/samgita/test/samgita/redesign/restart_test.exs
```

## 4. P2 — Independent app-server implementation

Owner: protocol owner. P2 was explicitly authorized after `1574130`; its bounded B0 reconciliation and frozen native contract are in [protocol phase 2](protocol-phase-2.md). P2 left the root application list, configuration, dependencies, Repo, UI and runtime untouched; P3 later adds the core path dependency and platform domain.

Implemented paths:

- `apps/samgita_protocol/{mix.exs,lib,priv/schemas,test}`: dependency-free native version 1.0 schemas/validation, codec, errors, capabilities, client state, server callbacks and bounded replay.
- `apps/samgita_protocol/examples/consumer`: separate Mix consumer with one core path dependency and application/socket isolation checks.
- `apps/samgita_protocol/scripts/verify_standalone.py`: optional temporary-copy build proof outside the repository.
- `apps/samgita_protocol_websocket`: optional standalone authenticated RFC 6455 JSON-text client/server at `/app-server`, fake Agent and real loopback conformance tests.
- `apps/samgita_protocol_codex`: optional pure six-method/three-notification adapter with official pinned 0.163.0 schema sources, hashes, LICENSE/NOTICE and subset tests.
- `AGENTS.md` and `docs/redesign/*.md`: reconciled package naming, phase scope, semantics, evidence and remaining gates.

All three packages follow the repository's `apps/` layout but omit umbrella build/dependency/config inheritance. Core and provider adaptation contain no transport process; optional transport has no Phoenix or platform dependency.

- [x] Pin official Codex `rust-v0.163.0` / immutable commit `83086188ae0614bd882818ff1aa23f3194962012`, selected schemas/hashes and exact supported subset. Keep its handshake/fields separate from native schema.
- [x] Implement versioned schemas, strict validation, safe typed errors, negotiation, correlation, duplicate handling and explicit unsupported operations. Malformed input cannot call host handlers.
- [x] Separate project-event receive/status/decision-report operations from execution threads/turns/items/approvals/interruption. Preserve event identity/time across delivery attempts and distinguish receipt/durability/completion/management acceptance.
- [x] Implement bounded buffers, timeouts, disconnect uncertainty, explicit reconciliation, processed replay checkpoints, restoration and replay gaps. Never automatically retry a mutation.
- [x] Implement transport-independent client dispatch and bidirectional server callbacks. Handler registration must equal advertised request support; persistence, lifecycle decisions and permissions remain host-owned.
- [x] Compile/test the standalone consumer outside the repository without Repo/platform/Phoenix/Backplane or new listener handles.
- [x] Run real WebSocket fake-Agent initialization, event delivery/status/report, sessions/turns, approvals, errors, cancellation, disconnect/reconnect and overflow/replay checks.
- [x] Record scoped checks and limitations, make a reviewable `feat(protocol)` commit and stop before platform implementation.

Run `devenv shell --no-tui --no-reload -- mix test`, `mix compile --warnings-as-errors` and `mix format --check-formatted` separately from each package directory, and the consumer's checks from its own directory. Use `python3 scripts/verify_standalone.py` from core for the outside-repository proof. No umbrella suite, database or real LLM is required.

B6 is only partially satisfied: native/reference schema and isolated fake-transport evidence exist. P3 adds Hub receipts/lease-proof derivation and rotation tests; they are platform contracts, not native protocol claims or production key-management evidence. Live/full Codex and real Sigma/Synapsis compatibility remain unverified; no sibling endpoint or repository changes are in scope.

## 5. P3 — Stable identities, migration mapping and authoritative commands

Implemented and locally verified under the frozen [P3 contract](domain-phase-3.md). The removed-source baseline required a bounded reconciliation rather than restoring absent legacy executors. The domain REST API portion of P5 was explicitly brought forward into P3.

Implemented paths:

- `apps/samgita/priv/repo/migrations/`: 17 restored main migration files, retained September Oban upgrade, and additive `20261022000001_add_neutral_domain.exs`; no historical migration rewrite or destructive down migration.
- `test/fixtures/redesign/migration-sources.json` and `memory_migrations/`: pinned main/memory source hashes and three inactive memory migration copies. No memory application or pgvector runtime is restored.
- `apps/samgita/lib/samgita/{schema,principal,error,params,projection,commands,platform,legacy_mapping,projects,repositories,agents,tasks,task_transitions,attempts,events}.ex` and `domain/`: stable identities, associations, mapping/adoption, authorization, state, leases, receipts and transactional event/delivery intents.
- `apps/samgita_web/lib/samgita_web/controllers/{project,agent,repository,execution_session,task,attempt,platform}_controller.ex`, `controllers/domain_api.ex`, `plugs/agent_auth.ex`, `controllers/fallback_controller.ex` and `router.ex`: protected operator and machine REST APIs delegating to core contexts.
- `config/{config,runtime,test}.exs`, `apps/samgita/mix.exs` and `apps/samgita/test/support/{domain_fixtures,migration_repo}.ex`: sole-main-Repo isolation, external signing-key configuration, parameter filtering and inert Oban queues/plugins. The umbrella still runs only core/web; core consumes the independent protocol via a path dependency.

Implementation and local verification checklist:

- [x] Restore pinned main migration sources and add neutral columns/tables while preserving old IDs, fields, references and chronology in a populated scratch fixture. Keep fresh authority at `none`, admissions closed, with no fabricated Attempts.
- [x] Provide `LegacyMapping.preview/1` and `apply/2`, resumable per-record digests/statuses, inert state mappings and separate unverified repository associations. Repeated mapping adds no duplicate associations. Unknown statuses, source drift and relationship conflicts require review; no automatic merge by URL or adoption.
- [x] Require explicit audited adoption and unchanged recorded source mappings. Preserve Task identity/raw history; adopted, unheld work alone can be claimed after activation.
- [x] Implement versioned Projects, Agents, membership, sessions, Tasks, decisions and artifact references. A successful report submits `awaiting_review`; distinct review and acceptance decisions are required for `accepted`.
- [x] Authenticate current enabled credentials/connections and Project membership before receipt replay; reject changed semantics and stale execution epochs. Persist secret-free results/digests, command-linked events with allowlisted before/after snapshots, receipt event IDs and subscription delivery intents atomically.
- [x] Accept operator-supplied credentials, store digests only and return metadata with `no-store`. Retrieve lease proofs only through an explicit current-owner read; no proof enters receipts/events. Test lease-key rotation with dedicated runtime test keys.
- [x] Serialize capacity and active Attempts in PostgreSQL; use leases, deadlines, fences, epochs and explicit rebind. Expiry/closure preserve unresolved-effect holds and capacity; reopening does not clear uncertainty.
- [x] Provide operator API-key/rate-limit boundaries and mandatory machine credentials/current connection, including empty operator-key configuration, role checks, bounded pagination and nested-resource Project checks. Paused Project context advertises existing-owner renew/report/rebind/resolve/proof while hiding claim/start.
- [x] Add independent-transaction races for shared capacity, same-Task claims, expected versions, credential revocation and authority closure; assert distinct PostgreSQL backend PIDs. Keep expiry, reconnect and hold behavior in focused context tests.
- [x] Keep all queues/plugins disabled, verify legacy runtime modules stay absent, inventory pending legacy jobs and refuse activation without running, rewriting or cancelling them. There is no job classification/quarantine API or deployed bridge.
- [x] Complete the final root-owned scoped suite, warnings-as-errors compilation and scoped formatting checks, including the latest mapping hardening.
- [x] Complete the final scoped diff review; record P3 in this commit and stop.

Scoped tests, from the repository root against an explicitly isolated PostgreSQL instance:

```sh
devenv shell --no-tui --no-reload -- env MIX_ENV=test PGHOST=/tmp/samgita-p3-pg/socket POSTGRES_PORT=55443 POSTGRES_USER=gao SAMGITA_TEST_DATABASE=samgita_redesign_p3_verified_test mix test apps/samgita/test/samgita apps/samgita_web/test/samgita_web/controllers/domain_api_test.exs apps/samgita_web/test/samgita_web/controllers/fallback_controller_test.exs apps/samgita_web/test/samgita_web/plugs/api_auth_test.exs apps/samgita_web/test/samgita_web/plugs/rate_limit_test.exs
```

The root-owned final run passed **87 tests (48 core, 39 web), 0 failures**, seed `197697`, on the explicit socket/port/database above. `MIX_ENV=test mix compile --warnings-as-errors` and the scoped 66-file `mix format --check-formatted` passed. Verbatim pinned migrations/fixtures were excluded from formatting; their hashes passed in the suite. The test alias creates/migrates the selected database; inspect its resolved target before any rerun. `preservation_test.exs` creates another uniquely named `samgita_redesign_p3_migration_*_test` database for the historical expansion rehearsal. No reset/drop of an unresolved database is authorized. See the phase record for the final command and commit record.

Gate: the implemented core/mapping/REST/ownership portions of A01–A05/A06/A11/A14, plus A15. The source/hash and opaque memory sentinel checks are local preservation evidence only. Full memory/pgvector/dual-Repo backup rehearsal, verified GitHub identity/rename/transfer, complete history readers, bridge/job classification, restart/release/rollback and real remote effects remain future gates. P3 supplies no network dispatcher, cron, automatic expiry maintenance, UI, platform WebSocket adapter or external Agent integration. B1/B2/B4 and applicable B3/B5/B6 must clear for an actual target before production claims. Commit P3 and stop before P4/P5.

## 6. P4 — Durable events, GitHub and schedules

P4 is split into the accepted [coordination subset](coordination-phase-4.md) and the newly authorized [read/event-only GitHub subset](github-phase-4.md). Coordination supplies responsible-Agent routing, atomic outbox/Oban wakeups, fenced delivery/status/recovery, cursors, schedules and APIs through migration `20261022000002_add_durable_coordination.exs`. GitHub adds operator-configured references, verified repository associations, raw signed ingress, immutable evidence and bounded reconciliation through additive migration `20261023000001_add_github_fact_ingestion.exs`. P5 UI/platform WebSocket hosting remain separate. Legacy hooks remain quarantined with explicit enqueue failure propagation; their executor is not restored. Real GitHub setup/credentials/permissions/webhooks and repository writes remain unauthorized.

The shared owner maintains migrations/configuration and existing authority/receipt/outbox contracts. The GitHub context owns connection/repository/mapping/inbox/object/observation/sync models, verification and transactional events; its client owns read-only provider authentication/HTTP; pure signature/payload modules own normalization. Web controllers/raw-body plug delegate to contexts, using the existing endpoint. The dedicated `hub_github` queue admits only reconciliation/maintenance, with no execution worker. Protocol packages remain provider-neutral and unchanged. No old migration, Project/Task identity or historical row is replaced.

Coordination tests (the exact command also includes affected P3 authority/authorization checks):

- `apps/samgita/test/samgita/events/{transaction,delivery,concurrency}_test.exs`
- `apps/samgita/test/samgita/connectors/app_server_test.exs`
- `apps/samgita/test/samgita/schedules_test.exs`
- `apps/samgita/test/samgita/workers/{event_delivery,schedule_tick,attempt_expiry}_worker_test.exs`
- `apps/samgita/test/samgita/{webhooks,legacy_isolation}_test.exs`
- `apps/samgita/test/samgita/migration/coordination_preservation_test.exs`
- `apps/samgita_web/test/samgita_web/controllers/coordination_api_test.exs`
- Standalone optional transport tests and protocol outside-consumer proof

GitHub checks: `apps/samgita/test/samgita/github/`, `migration/github_preservation_test.exs` and web `controllers/{github,github_webhook}_controller_test.exs`, plus affected existing receipt/event/API/access/isolation tests. Exact commands and evidence are in the GitHub phase record. Local HTTP uses a loopback fake server; no real installation is selected.

- [x] Prove aggregate/event/outbox/job rollback and lost wakeup repair; kill a worker after committed claim/before wire send, then reconcile the original event/operation without blind receive replay. Notification delivery remains at least once.
- [x] Implement explicit Project-scoped subscriptions, revisioned targets, cursor reads and duplicate/gap ACKs. No subscriber/recipient is created from an implementation name.
- [x] Move new delivery/maintenance to dedicated queues; retain old hook jobs/signature semantics until explicit translation/redelivery decisions are recorded. Simulate timeout/429/5xx/permanent failure and lost ACK; no retry may alter Task state.
- [x] Implement operator-configured GitHub App references, repository-restricted read-only tokens and verified immutable repository associations using deterministic fakes and real loopback HTTP. No real secrets are supplied or stored in receipts/logs.
- [x] Test raw-body signature verification before parsing, delivery duplicates/conflicts, repository/install scope, suspension, unsupported event types and atomic enqueue failure. No unsigned request enters the event inbox.
- [x] Add immutable source observations, Project-scoped evidence reads, bounded scan/retry/cooldown checkpoints, scan-start overlap and stale/concurrent-result fencing. Explicitly document missed-history/default-branch/page-budget limits.
- [x] Test schedule revision/disable/repeated scanning, two concurrent scanners, bounded catch-up and DST occurrences using fixed clocks. Every absolute due time emits at most one logical event; backlog remains inspectable. Whole-release restart remains a deployment gate.
- [x] Prove manual/external/schedule/GitHub facts create no PRD, Agent execution worker, tool invocation, automatic Task decomposition or workflow dispatch. GitHub writes and push events remain outside the supported first set.

Current boundary: the coordination record preserves A06/A11/A12 evidence; the GitHub record adds the local A10/read-ingestion subset and affected preservation/access/isolation checks. Commit the GitHub phase and stop. Real App/service security/idempotency and installation conformance (B5), release restart/rollback, production preservation and UI require separate evidence and authorization. Local HTTP/signature/database tests do not clear those live gates.

## 7. P5 — Management transports, operator UI and reference Agent

Implemented paths are `samgita/management.ex`, `samgita_web/live/{agents_live,projects_live,tasks_live}/`, dashboard/layout/router and the Attempt progress callback. Existing domain commands remain the sole write boundary. P4 already owns event/schedule REST controls. Neutral event traffic connects to the Agent's authenticated WebSocket; authoritative callbacks use protected machine REST. The proposed Samgita-hosted management WebSocket has no defined profile and remains unimplemented/unadvertised; no Task/lease methods are invented in the neutral core.

Reference evidence lives in `test/support/fake_agent.ex`, web `integration/{agent_journey,restart_reconcile}_test.exs`, the independent transport consumer and `scripts/verify_isolated_protocol.py`. The fake is explicitly started and never calls an LLM, shell or external provider. [Qualification](qualification.md) records exact final checks and limits.

- [x] Retain registration/membership, digest-only credentials, protected event/schedule APIs and versioned Task commands; add bounded owner-authorized progress. Operator API-key/rate-limit and mandatory machine identity boundaries remain.
- [x] Preserve stable UUID routes and restricted legacy provenance; restore no absent legacy execution controls. Complete historical-storage readers remain a target gate.
- [x] Build persisted DuskMoon views for Agents, Projects/repositories/membership, Tasks/Attempts/decisions/artifacts, schedules and event delivery/recovery. Expose validation, rejection, stale/offline evidence, pending review, holds and retry exhaustion.
- [x] Keep Project creation independent of PRDs, Git URLs, cloning and runtime launch. No implementation name grants a default or authority.
- [x] Run a real WebSocket fake-Agent signed-event journey with both `Synapsis` and `Orion`, machine callbacks/delegation/progress/artifacts and separate review/acceptance; exercise restart, ACK loss and stale-result fencing.
- [x] Prove separate core and direct-runtime consumers outside the umbrella, with no Repo/platform app or Sigma process. Direct output confers no management acceptance.
- [x] Record final browser/aggregate results and delivery status in qualification; applicable failing gates remain open and prohibit release.

Gate: A01/A04–A07/A11/A13. Focused test scope is the new integration paths plus affected `controllers/{project,task,webhook}_controller_test.exs`, `plugs/{api_auth,rate_limit}_test.exs` and `live/{dashboard,project,project_form,agents}_live_test.exs`; add equivalent tests beside each new management LiveView/controller. Run `mix assets.build` only once UI code exists; run format checks on changed Elixir files. Stop after the scoped journey/checklist passes.

## 8. P6 — Rehearsal, compatible rollback and retirement preparation

Owner: integrator; no new product behavior. Scope is `apps/samgita/test/samgita/redesign/`, new integration tests, `apps/samgita/lib/mix/tasks/samgita.redesign.rehearse.ex`, `deployment/scripts/{deploy,rollback,smoke-test}.sh`, `deployment/README.md`, release migration wiring and the exact retired callsites proven by the inventory. Production execution of these scripts is separately authorized.

- [ ] Run the full **new and retained** redesign suite against a named isolated copy with legacy fixtures and both migration histories. Archive before/after manifests showing every preserved ID/reference/content digest; expected new columns/records are listed separately.
- [ ] Rehearse bridge install, closed admissions, all-worker/job/process inventory, legacy drain, owner-none backfill, Hub activation, old-node restart and stale callback rejection. Demonstrate retained hook jobs are neither lost nor implicitly resent.
- [ ] Leave a provider job/tool effect unknown intentionally: the switch must refuse. Resolve it through recorded evidence and repeat. Do not equate a cancelled Oban job with a stopped external process.
- [ ] Rehearse rollback before Hub writes and after a fake external execution begins. The latter closes admissions/increments epoch/holds unresolved work and serves read-only views; it never starts the pre-bridge executor or drops schema/data.
- [ ] Run the isolated release with closed admissions and no provider/memory execution children; prove migrations/readers/health/assets and fake-Agent protocol. Build/format/static checks cover changed/new code and retained consumers; do not repair unrelated legacy checks.
- [ ] Remove active legacy source/dependencies only in reviewed, bounded commits after searches and tests prove no live/historical consumer remains. Retain historical schemas/migrations/data and any necessary read-only reader. No mass directory deletion or archived dead source.
- [ ] Produce a cutover manifest: exact build/guard-aware rollback build, databases, node/process/queue inventory, backup/restore evidence, mapping decisions, target authorities/epochs, subscribers, approved endpoints, secret references, monitoring and operator abort criteria.
- [ ] Stop for deployment authorization. No automatic live migration, replay, rollout, PR publication or push.

Local rehearsal gate: A02/A08/A09/A14/A15 against isolated fixtures/fake services, with B2/B4 and the Hub-only B6 contract resolved. B1 live inventory, B3 real Sigma/Synapsis compatibility, B5 real GitHub/remote destinations and optional Codex compatibility may remain open when those integrations are disabled; mark the manifest **not deployable** for any uncleared applicable gate. Local P6 acceptance does not require selecting an external host or altering another service.

Real integration/live cutover gate: remeasure B1/B2/B4 for the actual target, clear B6 for the exact advertised profiles, and clear B3/B5 for every enabled integration/destination. Record intentionally disabled integrations explicitly. Require an operator-reviewed, fully evidenced target-specific manifest and separate deployment authorization. A successful local boot or schema migration alone cannot pass this gate.

## 9. Rollback/abort matrix and blocker ledger

| Failure point | Required action | Prohibited fallback |
| --- | --- | --- |
| Document or contract inconsistency | Correct only the four P0 files; repeat scoped review/checks | Begin implementation to resolve a design disagreement |
| Bridge incomplete / old node unguarded | Keep legacy sole owner or close all execution; finish inventory/fence | Enable Hub claims alongside old workers |
| Mapping/reference/backup mismatch | Keep owner none, preserve raw records, stop the slice and resolve manifest | Delete conflicts, rekey Projects, run reset/down migrations |
| Unknown in-flight execution/delivery | Hold affected work/capacity; obtain cessation/outcome or operator reconciliation | Replay/reassign because a timeout elapsed |
| Protocol/auth mismatch | Keep integration disabled; resolve with service/dependency owner | Start a substitute Sigma server or silently bypass authentication |
| Hub regression after activation | Close admissions, owner none/new epoch, reconcile effects, compatible guarded rollback or fix forward | Re-enable the old PRD executor against new work |

B0–B6 in [design §9](design.md#9-implementation-gates-and-unresolved-blockers) are the blocker ledger. P2 reconciled its independent package scope; P3 locally reconciles B0 for the restored main migration sources, neutral schema and fixture tests. Neither clears target-specific history/storage drift, backup/reader coverage, old-writer exclusion or other cutover gates. Clear each applicable gate only with its specified evidence; do not convert an assumption into a checked acceptance box. Host/credential/subscriber selection remains explicit operator configuration, not an agent-chosen deployment decision.

For every authorized stage, report changed paths/commit, scoped checks and results, preserved data/effect evidence, remaining blockers and the next unexecuted gate. If an out-of-scope test fails, list it and stop without repair. When the in-scope checklist and tests pass, stop at that stage boundary.

## 10. P7 — Codex host connections (design §11)

Authorized 2026-11-09 as the first delivery priority, ahead of the §10 delegation work. Work on the existing branch in three ordered stages; each stage ends with its scoped checks passing and a logical commit. Acceptance scenarios are A16 and A17.

### P7.0 Unpin Codex and track the latest release

Split on 2026-11-09 after evidence: the existing driver in `compatible` mode initializes and lists threads against the local Codex `0.167.0`, so connecting to the latest Codex does not depend on a snapshot refresh. The bundled snapshot also contains about twenty source-derived semantics files and many tests assert 0.163.0 specifics, so the refresh is a larger separate job.

- **P7.0a (done)**: remove exact-version checks and record the observed version. Additive migration `20261109000000_unpin_codex_runtime_version.exs` relaxes the `known_native_runtime` and `native_runtime_contract` constraints to any well-formed version and drops the `0.163.0` default; `Agents` accepts any well-formed Codex `runtime_version`; bindings record the Agent's `runtime_version`.
- **P7.0b (done)**: the snapshot refresh pipeline below.

Owner files: `apps/samgita_protocol_codex/{lib,priv,test,README.md}`, `apps/samgita_codex_driver/{lib,test,README.md}` where they name a version, `scripts/codex/fetch_pin.py` (renamed to a refresh script), `.github/workflows/codex-conformance.yml`, `apps/samgita/lib/samgita/{agents.ex,codex_runtime/authorization.ex,codex_runtime/native.ex,domain/native_runtime_binding.ex}` and their tests.

- [x] Move the bundled snapshot to `priv/upstream/current/` with `source.json` recording version, commit and digests; read the version from it everywhere.
- [x] Add a refresh script (`scripts/codex/refresh_snapshot.py`) that resolves the latest official release, verifies the published checksums, regenerates the schema with `codex app-server generate-json-schema` and copies the source files the schema modules read. `fetch_pin.py` stays and fetches the snapshot's release for conformance runs.
- [x] Refresh the snapshot to the latest release (`0.167.0`) and fix compile/test breakage in the protocol and driver packages.
- [x] Accept any well-formed `runtime_version` for `runtime_driver: "codex"`; record the version on bindings; remove exact `"0.163.0"` checks (P7.0a).
- [x] Point the conformance workflow at the current snapshot.

Checks: protocol and driver test suites from their own directories; `apps/samgita/test/samgita/codex_runtime*` and `agents_test.exs`; `rg '0\.163'` finds no live code (historical docs excepted).

Result (2026-11-09): relocation committed first with the 0.163.0 content unchanged (protocol 119 tests, `inventory.py --check`, script tests, and an identical driver failure set). Refresh to `rust-v0.167.0` (commit `086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a`): 502 requirements, 6,877 field/variant contracts, 477 synthetic messages. Reviewed upstream diffs of every guarded source (`common.rs`, `v1.rs`, `export.rs`, `v2/thread.rs`, `v2/thread_data.rs`, `v2/config.rs`, `v2/realtime.rs`, `models.rs`) and the parameter closures of every guarded method schema; the changes are new methods/fields, internal helpers and the `input_audio`/`UserInput` `fileId` variant, none of which alter a derived contract, so the guards were updated. The whole-file `Cargo.lock` guard was narrowed to the serde entry the decoder depends on. Protocol tests 119 pass after updating the surface counts (183 client requests, 88 server notifications, 64 stable); script tests and `inventory.py --check` pass; a strict-schema-mode session against the local Codex 0.167.0 initializes and answers `thread/list`/`model/list`. The driver suite (security-related files excluded) has the same 905 failures as before: 875 need the Linux `CODEX_BINARY`, the rest are Linux-only or the recorded macOS/header issues. Unverified: the native actual-binary driver and conformance suites against 0.167.0 (Linux CI, not run). The manifest kept implementation progress for 177 of 502 requirements; the rest returned to `missing` because their schema hash changed. `scripts/codex/check_ordinary.py`'s reviewed source fingerprint is stale and needs a reviewer before that selection runs again.

### P7.1 WebSocket Codex hosts

Owner files: new migration `*_create_codex_hosts.exs`; `apps/samgita/lib/samgita/{codex_hosts.ex,codex_hosts/}` (context, schema, supervisor, connection, status); `apps/samgita/lib/samgita/application.ex`; `config/{config,dev,test,runtime}.exs`; web controller/routes and the Codex section of `AgentsLive.Show`; their tests.

- [x] Additive `codex_hosts` table and schema with WebSocket and SSH fields (SSH fields unused until P7.2).
- [x] Operator commands configure/enable/disable with `command_id`, `expected_version`, receipts and `codex_host.*` audit events; secret values rejected, reference names only (`SAMGITA_CODEX_HOST_SECRETS` supplies token values).
- [x] `Samgita.CodexHosts.Runtime` Registry + DynamicSupervisor; one connection process per enabled host; boot-time start gated by `config :samgita, :codex_hosts, enabled:`.
- [x] Connection: open `Transport.WebSocket`, `initialize` + `initialized`, record server version and a new host generation, bounded backoff reconnect, PubSub status. Server notifications are drained and discarded until task bridging journals them.
- [x] Operator REST endpoints (`/api/codex-hosts`) and `/agents/:id` status panel with enable, disable and reconnect.

Result (2026-11-09): 14 core and 4 web tests pass against a loopback fake app-server; a manual check against a real isolated `codex app-server --listen ws://127.0.0.1:…` (Codex 0.167.0) reached `connected`, generation 1, server version `0.167.0`. Permission/forbidden-caller cases were not run under the verification restriction.

Checks: context/command tests, connection tests against a local fake app-server WebSocket (connect, reconnect with new generation, disable stops, auth rejection), application boot with the flag on and off, LiveView test for the status panel, `mix compile --warnings-as-errors`, `mix format --check-formatted`.

### P7.2 SSH Codex hosts

Owner files: `apps/samgita_codex_driver/lib/samgita_codex_driver/transport/command.ex` and tests; `apps/samgita/lib/samgita/codex_hosts/ssh.ex`; SSH branches of the P7.1 connection, configuration and UI; their tests.

- [x] Verify the proxy framing: `codex app-server proxy --sock` to a foreground `codex app-server --listen unix://…` (Codex 0.167.0) answers an HTTP WebSocket upgrade and a framed `initialize`. No daemon was installed for this check.
- [x] `Transport.Command` in the driver: WebSocket over an owned command's stdio via a private relay socket; exact environment; command killed after a grace period if it ignores EOF.
- [x] `Samgita.CodexHosts.Ssh`: fixed argument list, `-F /dev/null`, `BatchMode`, strict host-key checking against a private known-hosts file, forwarding and connection sharing disabled, minimal environment, shell-quoted remote command.
- [x] Private key resolved from a credential reference into a 0600 file in a 0700 directory for one connection attempt only.
- [x] Optional `ensure_daemon` runs `codex app-server daemon start` before the proxy session.
- [x] SSH settings validation (host, user, port, paths, public-key-only known hosts) and the transport switch in the `/agents/:id` form.
- [x] Remote command runs through the remote login shell like the Codex desktop app (`$SHELL -l -i`, `CODEX_INSTALL_DIR`/`~/.local/bin` on `PATH`), with a per-connection stdout marker that `Transport.Command` uses to skip login-shell output.

Result (2026-11-09): driver `transport_command_test.exs` 5 tests; core SSH tests 8 (including a regression for a Session leak when `initialize` fails, found and fixed in P7.1 code); web 5 Codex host tests; all affected suites pass. Real OpenSSH against local sshd: a wrong host key is refused before authentication ("REMOTE HOST IDENTIFICATION HAS CHANGED"), the correct key passes host verification and fails authentication without prompting (`BatchMode`). Login-shell follow-up: driver Command tests 7 (marker split across writes, client bytes held until the marker, missing marker fails); core SSH tests now execute the generated remote command with `/bin/sh` and a banner-printing profile; the launcher was also run locally under zsh, bash and tcsh with a stub `codex` (fish not installed). Unverified: a full real-SSH session to a real Codex daemon (needs authorized SSH credentials). Out-of-scope pre-existing failures recorded, not fixed: `transport_web_socket_test.exs` expects a lowercase `authorization` header but the updated `http_web_socket` sends `Authorization`; 9 `initialized_transport_test.exs` cases need the pinned `CODEX_BINARY` environment.

### P7.3 Codex in Agent management

Requested 2026-11-09, revised 2026-11-10: Codex is one kind of Agent, managed on the Agents page rather than a separate menu, and adding an Agent asks only for what the ChatGPT app asks for. Each machine (host environment) is one Agent running `codex app-server --listen ws://127.0.0.1:PORT`; other machines are reached by forwarding their port over SSH to a local port. Samgita starts and stops its connection, never the Codex process.

Owner files: `apps/samgita_web/lib/samgita_web/live/agents_live/index.{ex,html.heex}`, `apps/samgita/lib/samgita/codex_hosts.ex` (`list` adds the Agent name; `validate_settings/1`), `apps/samgita_web/test/samgita_web/live/{agents_live_test,agents_codex_live_test}.exs`.

- [x] The Agents list shows each Agent's type and address; Codex rows show live connection state, reported Codex version and errors, with Start (enable), Stop (disable) and Reconnect.
- [x] An "Add Agent" button opens a modal dialog (DuskMoon `dm_modal`); the list shows the newest Agents first.
- [x] "Add Agent" asks only for type (Codex or Samgita protocol Agent), name and address. Codex validates the address first, then registers the Agent, configures its WebSocket host and enables it, each with a stable `command_id`; a Samgita protocol Agent is registered with its endpoint and opened for further setup. Capabilities, capacity, credentials and SSH daemon settings stay on the Agent page.

Result (2026-11-10): Agents and Codex host LiveView tests pass (13 run, 4 authorization/credential cases skipped). Browser check on an isolated dev database (`samgita_redesign_ui_dev`, port 4871) against two local `codex app-server` 0.167.0 processes on 47811/47812: both added from the page and reached `connected`; Stop showed `stopped`, Start reconnected with a new generation; killing one Codex process showed `backoff` live and restarting it reconnected automatically.

### P7.4 Codex projects on the Agent page

Requested 2026-11-10: a Codex Agent (one per host environment) shows the projects open in Codex on that machine and can add one. Codex owns its projects (the same list the Codex app shows); Samgita reads them live and keeps no copy.

Owner files: `apps/samgita/lib/samgita/codex_hosts.ex` (`projects/2`, `create_project/3`), `codex_hosts/{connection,runtime}.ex` (live session access; initialize with `experimentalApi: true` because `project/*` is experimental in Codex 0.167.0), `apps/samgita_web/lib/samgita_web/live/agents_live/show.{ex,html.heex}`, `apps/samgita/test/support/fake_codex_server.ex`, `apps/samgita_web/test/samgita_web/live/agents_codex_projects_live_test.exs`.

- [x] Projects card on a Codex Agent page: `project/list` (paged, up to 1,000), name and folder, refresh, reloaded when the connection reconnects.
- [x] Add project: name and an absolute folder on that machine; `project/create` with the command ID as `idempotencyKey`, and a `codex_host.project_created` audit event.

Result (2026-11-10): `agents_codex_projects_live_test.exs` 2 tests pass (experimental initialize, listing, exact `project/create` params and audit event, relative folder refused before contacting Codex); Agent and Codex host LiveView tests (12) and filtered Codex host core tests (7) pass. Browser check against the local Codex 0.167.0 on 47811 listed its nine real projects. Adding a project was not exercised against the real Codex because it would change the user's Codex app project list.

### P7.5 One machine, one Codex Agent

Requested 2026-11-10: each machine should be one Agent; a duplicate must warn first. The Agents list shows the machine a Codex runs on, not the local forwarded `ws://` address.

Owner files: additive migration `20261110000000_add_codex_host_identity.exs` (`codex_hosts.installation_id`, `machine_name`); `codex_hosts.ex` (`check_new/2`, `same_machine_as` in `list/1`), `codex_hosts/{connection,runtime}.ex` (identity read on connect, one-shot `identify/1` under a probe Task.Supervisor); the Agents list/modal; `agents_codex_live_test.exs`.

- [x] On every connect, read `remoteControl/status/read` (experimental; `installationId` identifies one Codex home, `serverName` the machine) and record it; failure leaves the identity unset.
- [x] The list's Address column shows the machine name only; Agents on the same machine (same installation or same address) are flagged "Same machine as …".
- [x] Adding a Codex first probes the address; if that machine or address is already configured the modal warns and requires "Add anyway".

Result (2026-11-10): Agent and Codex LiveView tests (16) and filtered Codex host/management/preservation core tests (10) pass, including a regression for an unreachable probe (no installation ID) that crashed the duplicate query. Browser check: the local Mac shows as `mbp2021` and raven (reached through `ssh -L 47813:127.0.0.1:47811 raven`) as `raven`; adding `ws://127.0.0.1:47811` again warned "mbp2021 is already added as Codex local A" and was not created.

## 11. P8 — Coordinated delegation (design §10)

Authorized 2026-11-09 after P7. Work on the existing branch in ordered stages; each stage ends with its scoped functional checks passing and a logical commit. Acceptance scenario is A18. Under the verification restriction, cases that exercise role, membership, credential or separation-of-duties refusals are written and kept but recorded as unrun; functional cases (successful assignment, claim by the assignee, routing, delivery, acceptance by a separate reviewer) run.

### P8.1 Assignment and assigned claim

Owner files: additive migration `*_add_task_assignment.exs`; `apps/samgita/lib/samgita/{domain/task.ex,tasks.ex,attempts.ex,projection.ex}`; `apps/samgita_web/lib/samgita_web/{router.ex,controllers/task_controller.ex}` and the Task LiveView where it shows Task fields; new `apps/samgita/test/samgita/tasks/assignment_test.exs`; existing tests that claim a Task (assign it first; their assertions are otherwise unchanged); `docs/redesign/management-api.md`, `docs/architecture.md`.

- [x] Nullable `tasks.assignee_agent_id` (FK `agents`) and `tasks.assigned_at`, plus an index for the assignee filter.
- [x] `Tasks.assign/4` (`task.assign:<id>`, `manager`, `expected_version`, `command_id`): Project active, Task adopted and `open`, no active Attempt, no execution hold; a non-null assignee is enabled, an enabled `worker` member, with approved and advertised capabilities covering `required_capabilities`; null unassigns. Atomic Task version, receipt and `task.assigned` event (`assignee_agent_id`, `previous_assignee_agent_id`).
- [x] `claim` refuses unless `task.assignee_agent_id` is the claiming Agent (`invalid_transition`; existing capability and capacity checks unchanged).
- [x] `Tasks.list` accepts an `assignee_agent_id` filter; projections include `assignee_agent_id` and `assigned_at`.
- [x] `POST /api/.../tasks/:task_id/assign` in the operator and Agent scopes.

Result (2026-11-09): migration `20261109000002_add_task_assignment.exs`; new `tasks/assignment_test.exs` 5 functional tests pass (assignment receipt/event/replay, stale version, unassignment, state preconditions, assignee-only claim, list filter); its 2 authorization cases (membership/role/capability/disabled refusal, claim of another Agent's Task) are written and unrun. Existing claim tests now assign first; the same-Task race now races one assignee through two sessions. The filtered core suite (181 tests) and affected web tests pass except recorded pre-existing failures: `CODEX_BINARY` unset for one notification test and the Gaoxy `:invalid_endpoint` 429 connector test. The preservation rehearsal excludes the two new neutral columns and asserts they are null on historical rows.

### P8.2 Assignee notification

Owner files: `apps/samgita/lib/samgita/{events.ex,event_delivery.ex}`; the routing controller/routes and the Project LiveView routing section; new `apps/samgita/test/samgita/events/assignee_routing_test.exs`; `docs/redesign/management-api.md`.

- [x] Operator command configures one `assignee` subscription per (Project, Agent): explicit, revisioned, `project_events.v1` required, approved endpoint digest, `worker` role; reconfiguring disables the previous revision. Additive partial unique index.
- [x] Fan-out delivers `task.assigned` to an `assignee` subscription only when its Agent is the event's current or previous assignee, and other Task events only for Tasks assigned to that Agent. `responsible` fan-out is unchanged.
- [x] Delivery target checks accept an `assignee` subscription whose Agent is still an enabled `worker` member; its report and cursor commands accept the `worker` role for that subscription only.
- [x] Project page: assignee-notification form and list (Owner files extended to `apps/samgita/lib/samgita/management.ex`).

Result (2026-11-09): migration `20261109000003_add_assignee_subscriptions.exs`; `PUT .../event-routing/assignees`; `GET .../event-routing` adds `assignees`. New `events/assignee_routing_test.exs` 4 functional tests pass (revisioned configuration, current/previous-assignee fan-out with responsible unchanged, Attempt event delivery through dispatch/report/cursor by a `worker`, redelivery keeping the event identity); its 2 authorization cases are written and unrun. Filtered event/delivery/management/projects/coordination-preservation tests (32) and the affected web tests (12, including a new LiveView test) pass.

### P8.3 Separation of duties and acceptance visibility

Owner files: `apps/samgita/lib/samgita/tasks.ex`; the Project LiveView member list; their tests.

- [x] `decide` refuses an Agent that owned the Attempt that submitted the Task to `awaiting_review` (`forbidden`); operators are exempt.
- [x] The Project page shows which members hold `reviewer`, so automated versus human acceptance is visible.

Result (2026-11-09): `decide` refuses an Agent whose Attempt submitted the Task (`forbidden`, reason `own_submission`), after the existing review-order check. New `tasks/separation_of_duties_test.exs`: a separate reviewer Agent reviews and accepts (passes); the executor-holding-`reviewer` refusal is written and unrun. The Project page shows the acceptance mode (`#acceptance-mode`, delivered with P8.2). Filtered Task/Attempt/Codex runtime tests (28) and the journey/Task LiveView tests (8) pass.

### P8.4 Release observation — deferred (future TODO)

Deferred by user decision (2026-11-09): no further GitHub integration now; do not design or develop GitHub features. Release ingestion, its reconciliation and the `contents: read` permission change are a future TODO with no owner files in P8.

### P8.5 Outcome loop

Owner files: new `apps/samgita_web/test/samgita_web/integration/delegation_journey_test.exs`; `AGENTS.md` target-workflow status; `docs/redesign/design.md` §10 status.

- [x] With a fake coordinator and a fake executor over real WebSockets: issue event → coordinator creates child Tasks → assigns → executor is notified, claims, starts, reports → coordinator receives `attempt.reported` → a reviewer decision → `accepted`.

Result (2026-11-09): new `integration/delegation_journey_test.exs` passes: two `FakeAgent` endpoints (coordinator "Synapsis" with `manager reviewer`, executor "Codex" with `worker`) over real authenticated WebSockets; a signed `issues` delivery reaches only the coordinator; the coordinator creates parent and child Tasks and assigns the child; `task.assigned` reaches both; the executor finds the Task through the assignee filter, claims, starts and reports; `attempt.reported` reaches only the coordinator, which reviews and accepts.
