# Samgita redesign acceptance contract

Date: 2026-10-23. This separates P0/P2/P3 evidence, bounded P4 coordination/GitHub implementation, persisted P5 UI/local qualification and target-specific cutover acceptance. A scenario passes only for evidenced assertions. [P4 coordination](coordination-phase-4.md) covers manual/external facts, schedules and delivery/recovery; [P4 GitHub](github-phase-4.md) covers signed ingestion, read-only facts and bounded reconciliation. [Qualification](qualification.md) records UI/integration/browser/consumer checks and the subsequent reliability repair. Aggregate build gates now pass locally; raw-telemetry A11, real App/service conformance, full historical backup/readers and production cutover remain open.

Authority: [design](design.md), [implementation plan](implementation-plan.md), and `AGENTS.md`. The older clean-start documents are historical proposals and cannot waive preservation or cutover tests.

Merged-baseline note: `d6e9eca` combines documentation `3a344f5` and the separately authorized source refactor `811eeb9`. P2 then added independent protocol packages. P3 restores 17 main migration sources verbatim from `2bc3765ac94e1faea50f061b6938c0ef51e6f92b`, retains the September Oban upgrade, pins main/memory migration hashes and adds neutral tables/columns. This reconciles B0 only for the local P3 fixture scope; it does not prove a production migration, full historical reader, backup restore or dual-Repo/pgvector preservation. Legacy runtime stays absent. P0 checks describe the original four-file documentation commit; historical P1 callsites remain a target-dependent recipe, not current source assignments. See [P3's contract/evidence](domain-phase-3.md).

## 1. Completed P0: document acceptance

P0 changed only `AGENTS.md` and these three redesign documents. Its scope excluded production migration, source/dependency changes, service restarts, schema resets, historical-data deletion, push, PR and deployment. P2's later authorized package scope and checks are recorded below and in [protocol phase 2](protocol-phase-2.md).

| Requirement | Review evidence |
| --- | --- |
| Agent-neutral ownership | Design §§1–3: Samgita validates/persists management; registered Agents reason/plan/delegate/execute. Synapsis/Sigma/Codex have identical authority rules. |
| Reusable protocol owned here | Design §4: independent package, capability/profile boundaries, source schema evidence, no Backplane ownership/dependency, no implicit server startup. |
| Existing endpoints/direct flow | Design §§3–4: actual sibling source endpoints, independent/direct traffic, explicit Task callback, no second Sigma process. |
| GitHub/scheduled/external events | Design §5: App installation scope, signed inbox, schedules, transactional delivery, explicit subscribers. |
| Stable Projects and preserved records | Design §8: existing UUIDs, repository associations/aliases, state adoption, opaque references, migration ledger. |
| Legacy inventory and exclusive execution | Design §§7–8: each subsystem disposition, bridge, all producers/jobs/processes, drain, holds and rollback. |
| Access boundaries/security | Design §6: single tenancy, infrastructure/browser/API boundaries, machine identity, secret handling, SSRF, host-owned approvals. |
| Executable phases/blockers | Plan P0–P6 and design B0–B6: merged-source reconciliation, owned scopes, dependencies, focused checks, abort/stop conditions and unresolved evidence. |

P0 completion checklist:

- [x] Read current repository guidance, relevant design/planning/Elixir/Git skills and audited source areas.
- [x] Keep source facts, proposed contracts and unverified deployment assumptions distinct.
- [x] Write design, implementation plan, acceptance strategy and conflicting AGENTS.md updates.
- [x] Complete independent migration/protocol review and correct actionable contradictions.
- [x] Check relative Markdown links/anchors, required file presence, four-file scope and whitespace.
- [x] Create one reviewable Conventional Commit containing only the four authorized paths.
- [x] Stop before P1. Report commit/branch, documents, verification and unresolved implementation gates.

## 2. Test isolation and evidence rules

These cases run only in their authorized stage. P2 needs no database. P3's `config/test.exs` wires the sole current main Repo to an explicit `SAMGITA_TEST_DATABASE` override and rejects names outside `samgita_redesign_*_test` with an optional numeric partition suffix. Use sanitized fixtures on an explicitly isolated PostgreSQL instance; never production or an unresolved database. The test alias creates/migrates its resolved target, so inspect it before execution. P3's migration test creates a separate uniquely named scratch database. Dual-Repo, complete memory-storage and vector-extension cases remain target-specific preservation gates; hash-pinned inactive memory migrations and an opaque `sm_memories` sentinel do not satisfy them or restore a memory runtime.

Unit tests cover pure transitions, matching, schedule occurrence calculations and codecs. Context tests prove database effects and transactional rollback. Locking tests use independent connections/transactions with deterministic barriers, not a shared sandbox connection. Oban runs manually except in explicitly isolated restart/scheduler tests. P2 real WebSocket tests use their own loopback endpoint/port and in-memory fake host with no database, LLM, tools or production credentials; later platform integration adds an explicitly isolated database. Browser proof records the endpoint/build/assets actually served.

Each case records test path/command, build/schema/profile version, database/port, observed assertions and any limitation. A fake service proves the local contract; it cannot certify real Sigma/Synapsis/GitHub authentication or compatibility. No automatic production changes follow a green test.

## 3. Behavioral acceptance scenarios

### A01 — Neutral registration and Project setup (P3/P5)

Given a trusted operator, create a Project without a PRD, Git URL, working path or provider. Register fake, Synapsis-named, Sigma-named and Codex-named Agents using the same API and bind selected Agents explicitly.

Pass when stable UUIDs are returned; zero/multiple repository associations work; implementation labels do not affect authorization/capacity; no Agent/provider/SSH/CLI process starts; and no default destination/subscription appears. Disable an Agent/binding and verify new claims and event access fail while history remains readable.

P3 tests: core `projects_test.exs`, `repositories_test.exs`, `agents_test.exs`, `legacy_isolation_test.exs` and web `controllers/domain_api_test.exs`. P4 event authorization and P5 LiveViews/`integration/agent_journey_test.exs` extend this evidence. The complete signed-event/Task-review journey runs twice with `Synapsis` and `Orion` names through identical registration and authorization.

### A02 — Identity, history and migration preservation (P1/P3/P6)

Given a fixture containing every historical table/status/reference, run expansion/backfill twice and compare before/after manifests.

Pass when all existing Project/Task/history IDs and FKs remain, UUID routes still resolve, payload/result/chat/memory/snapshot digests remain unchanged, and repeated backfill adds no duplicate mapping/association/event. Verify SSH/HTTPS aliases, rename/transfer, local paths, inaccessible repositories and duplicate normalized URLs. Never merge Projects. Missing/ambiguous opaque refs and array/edge conflicts appear as explicit unresolved ledger entries, not dropped data.

Verify Project-level URL uniqueness is relaxed only after old writers are fenced. A Project's repository rename, reassociation, URL change or shared repository never changes Project ID or transfers Task history. Archive cannot cascade-delete. The isolated restore reproduces the preservation manifest.

P3 tests: `migration/preservation_test.exs`, `migration/mapping_test.exs`, `repositories_test.exs` and web `controllers/domain_api_test.exs`; source hashes are in `test/fixtures/redesign/migration-sources.json`. The populated main-schema/content/chronology fixture and opaque memory sentinel are bounded local evidence. Complete backup/restore, live schema drift, full memory/pgvector/history readers and verified remote repository rename/transfer remain future gates.

### A03 — State mapping and explicit adoption (P3)

Given each legacy state, verify the full mapping table in design §8. Existing pending Tasks may project open but remain unadopted; assigned/running project as blocked/reconciliation-needed; skipped retains legacy-skipped provenance. Old status/phase/results/counters remain unchanged.

Pass when no legacy Task is claimable by default and no authenticated Agent/Attempt is fabricated from a worker string, PID or attempt count. Adoption keeps the same Task ID and requires same-Project relationships, reviewed content and resolved external effects. An unresolved mapping blocks adoption. Neutral state is inert before the authority switch and sole management authority afterward; no bidirectional lifecycle writes occur.

P3 tests: `migration/mapping_test.exs`, `tasks_test.exs` and `attempts_test.exs`, including unchanged source mapping checks, source-drift rejection and legacy-only hold resolution; these pass in the final root-owned suite.

### A04 — Authoritative state, capacity and stale writers (P3/P5)

Given an active Agent binding and an adopted open Task, race two independent claims and concurrent capacity/binding/credential changes. Exercise start, block, completion, failure, cancellation and explicit reopen.

Pass when exactly one active Attempt exists, configured capacity is never exceeded, each accepted state change has matching receipt/event/delivery intent, and version/scope/epoch/fence/expired-proof violations change nothing. A blocked relation or child Task never starts an executor or auto-completes its parent. Terminal Attempts remain immutable; appended resolution evidence cannot rewrite an outcome. Disconnect alone does not release ownership.

P3 tests: `tasks/task_transitions_test.exs`, `tasks/ownership_race_test.exs`, `security_race_test.exs`, `tasks_test.exs`, `attempts_test.exs`, `platform_test.exs` and web `controllers/domain_api_test.exs`. Race tests use independent transactions and assert distinct backend PIDs. P5 adds running-owner progress and real fake-WebSocket delivery with protected REST execution callbacks. A Samgita-hosted Task/lease WebSocket profile remains unimplemented and unadvertised; REST is the qualified management boundary.

### A05 — Receipts, reconnect and remote-effect holds (P2/P3/P5)

Lose claim/start/report/rebind responses and retry with the same command IDs. Repeat a completed command after its first execution changed version/state. Send different semantics with the same command ID and replace/revoke the connection.

Pass when current authentication/authorization/epoch checks precede receipt lookup, matching receipts precede mutable business preconditions, and retries produce one logical change with the original result/version/event IDs. Conflicting semantics fail. Historical ACKs never authorize new execution. No proof/credential appears in receipts, audit data or logs.

Reconnect as the same Agent: an explicit valid rebind increments fence and transfers only its existing unexpired Attempt to the new connection generation. Old connection/proof fails. A local execution journal prevents the Agent from starting the Attempt twice. Lost proof, expiry or uncertain effects takes the hold/reconciliation path.

Invalidate an Attempt while its fake remote tool is still running, then reopen the Task. Pass only if the execution hold prevents another claim and counts against Agent capacity until authenticated cessation/outcome or audited operator reconciliation clears it. Reopen, timeout and connection presence cannot clear it.

P3 context tests: `attempts_test.exs`, `platform_test.exs`, `projects_test.exs`, `security_race_test.exs` and web `controllers/domain_api_test.exs`, alongside P2 conformance. P5 adds a persistent fake journal, dropped ACK, status-only reconnect, actual application/fake-host restart, stale report rejection and retained effect holds in `integration/restart_reconcile_test.exs`. UI tests cover interrupted actions, original receipt identity, concurrent/stale drafts and cancellation. This proves process restart, not OS power-loss or a real provider journal.

### A06 — Event transaction, replay and explicit routing (P3 foundation/P4)

Roll back a Task transaction, crash after commit before send, lose a delivery ACK, replace a subscription target and restart the worker.

Pass when rollback leaves no event/outbox, restart delivers stable IDs without a second logical event, subscribers deduplicate, and cursor reads recover gaps in Project order. Zero subscribers is visible and does not choose Synapsis. Binding/subscription revocation prevents later delivery/access. Target revision changes require explicit redelivery choice, and delivery retries cannot mutate Tasks.

Existing generic hook jobs retain IDs/legacy signing until reviewed replacement; no mass resend occurs. Simulated legacy notification sends are labelled historical/simulated rather than proof of actual delivery.

P3 `events/transaction_test.exs` covers same-transaction receipt/event/subscriber-delivery insertion, command IDs, allowlisted before/after snapshots, receipt event IDs, rollback and matching receipt replay. P4 adds explicit responsible-Agent routing, cursor APIs, atomic Oban wakeups, delivery/recovery, local WebSocket evidence and scheduled checks. Tests include `events/{delivery,concurrency}_test.exs`, `workers/event_delivery_worker_test.exs`, `connectors/app_server_test.exs` and `webhooks_test.exs`. P3 intents remain inert until explicit reviewed replay; no retained hook is sent automatically.

### A07 — Independently reusable protocol and direct service routing (P2/P5)

Build a separate consumer with only `samgita_protocol` and declared dependencies, outside the repository/umbrella. Start the optional transport's fake host at its own `/app-server` endpoint without starting Samgita; initialize, create/resume a session, submit/steer/interrupt a turn, exchange a permission request and stream events. Independently exercise project-event receive/status/decision reporting and unsupported capability errors.

Pass when no Samgita Repo/web/provider/Backplane app or implicit listener starts; codecs/correlation/negotiation/buffering work; unsupported groups fail predictably; host callbacks decide execution; and no second Sigma process/listener exists. Base protocol fields do not require Hub IDs. Malformed input cannot invoke a handler.

Then bring up isolated Samgita and send an explicit authenticated Task callback. Only that accepted callback changes its Task. Direct conversation output never changes the database implicitly. Pin exact reference schemas and real-client conformance before advertising Codex compatibility; current Sigma/Synapsis adapters remain unadvertised until their own B3 evidence passes. Do not claim full Codex support from a tested subset.

P2 tests: core `test/{schema,fixtures,client,server,replay}_test.exs`, optional transport and pinned Codex adapter tests. P5's `scripts/verify_isolated_protocol.py` copies only core/transport packages to temporary directories outside the repository and builds two consumers without root configuration, lockfile, Repo or umbrella dependencies. The core consumer proves event receive/status/report, deduplication and unsupported sessions; the transport consumer proves direct thread/turn/steer/replay/approval-denial/interruption without Samgita or Sigma. The platform journey separately proves explicit protected Task callbacks. Real selected-client B3/B6 evidence remains separate.

### A08 — Legacy drain and complete mutual exclusion (P1/P6)

Seed available/scheduled/retryable/executing/snoozed/discarded jobs for every legacy worker, both Oban instances, retained webhook jobs, paused/running Projects, global Horde Agents, Codex Ports and fake remote sessions. Close admissions and drain under legacy-only ownership.

Pass when no new PRD/planning/Agent/Codex/provider dispatch occurs, recorded executing work can settle only at its epoch, and each job/process has an explicit drain/quarantine/resolution decision. Snapshot and memory pruning cannot delete history. Stopping a Project supervisor or cancelling an Oban job alone cannot pass the external-effect check. Shared-queue webhook work is not deleted or lost.

Owner-none/Hub switch refuses while an unguarded node or unknown active effect remains. After Hub activation, old API/UI/context/recovery/timer/cron/worker/retry/completion paths fail closed, including after node restart; no period allows old and new execution together. New execution never consumes a legacy Oban job as an external-Agent command.

Tests: `redesign/{legacy_guard,drain,restart}_test.exs`, independent old/new races; process/delivery inventory evidence in final rehearsal.

P3's narrower `legacy_isolation_test.exs` verifies disabled queues/plugins, absent legacy executors and pending-job activation refusal without changing job rows. `Platform.status/1` inventories pending jobs; there is no classification/quarantine API. This does not prove a guard-aware legacy deployment, old-node exclusion, named memory Oban state, external-effect cessation or a drain/restart rehearsal.

### A09 — Rollback without replay or data destruction (P1/P6)

Rehearse an abort before Hub writes and after an external fake execution begins. Include a delivered webhook and a simulated Git/tool side effect.

Pass when the only eligible rollback binary is guard-aware; admissions close, owner becomes none at a new epoch, unresolved work/capacity stays held, and history is read-only while effects reconcile. Additive schema, mappings, receipt/event history and all original IDs/data remain. No down/reset migration, PRD restart or automatic replay occurs. The result explicitly acknowledges external effects cannot be undone by restoring database state.

P3 `platform_test.exs` and `security_race_test.exs` cover local authority closure, epoch invalidation and retained holds. `redesign/rollback_test.exs`, release/restart reconciliation and the named backup/restore manifest remain P6; local closure is not an external-effect rollback rehearsal.

### A10 — Signed GitHub connection and ingress (P4)

Use a fake GitHub App/installation API and raw webhook bodies. Verify correct signature, invalid signature, whitespace/body changes, duplicate/conflicting delivery ID, revoked installation, unauthorized repository, unknown event and database failure.

Pass when short-lived tokens stay server-side, only approved immutable repository IDs route to associated Projects, bad signatures are rejected before persistence, and one accepted delivery yields one logical source event. Persistence failure remains retryable. No automatic Task creation/decomposition, tool call or workflow dispatch follows the event. A repository rename preserves Project IDs.

Local tests: core `github/{client,http,signature,payload,ingestion,reconciliation,concurrency}_test.exs`, `migration/github_preservation_test.exs` and web `controllers/{github,github_webhook}_controller_test.exs`. These add raw payload limits, explicit unsupported receipts, atomic enqueue rollback, current-state ordering, immutable historical text, credential/version fences, permission/rate-limit handling, missed-event scans and independent-transaction races. A loopback fake server exercises actual read-only HTTP/token traffic. Exact commands/evidence are in [the GitHub record](github-phase-4.md). Real connection remains blocked by B5 until approved installation/security evidence exists; no live setup or GitHub writes are authorized.

### A11 — Existing access boundaries and secret non-disclosure (P2–P5)

Verify infrastructure-protected browser routes retain CSRF/secure-header protections, configured operator API keys and rate limits still work, and no new account/org/RBAC system appears. Test machine routes with absent/invalid/revoked credentials even when operator API keys are intentionally empty. Test nested-resource Project mismatch, replay under another connection, malicious endpoint redirects and private-address targets lacking explicit approval.

Pass when authorization fails closed for machines and resource scope. P3 accepts operator-supplied credentials, persists only digests and returns metadata with `no-store`; no plaintext credential is issued. Explicit current-owner proof reads are non-cacheable; proofs never enter receipts/events. Captured DOM/API/events/receipts/logs/telemetry must exclude plaintext credentials and legacy endpoint secrets; intentional proof responses are tested separately. Runtime permission requests are bound to their original host/request; no codec auto-approval occurs. Missing downstream authentication blocks integration rather than being inferred from a sent Bearer header.

P3 tests: `agents_test.exs`, `projects_test.exs`, `attempts_test.exs`, `security_race_test.exs` and web `controllers/domain_api_test.exs`; retain existing `plugs/{api_auth,rate_limit}_test.exs`. P3 filters credential/proof parameters and validates stored endpoint descriptors but opens no remote connection. P4's connector/transport/API tests verify approved exact destinations, DNS/address pinning, redirect/plaintext rejection, safe failure projections, current machine membership and real authenticated loopback WebSockets. P5 captures credential-form logs, DOM, receipt/event data and digest-only persistence; browser markup excludes fixture secrets. Raw Phoenix telemetry contains framework event parameters/socket metadata before application handling; arbitrary raw export is not certified secret-free and no raw exporter is configured. This assertion remains open, as do deployed TLS/egress policy and actual-service credential/durability boundaries. See qualification for the instrumentation boundary; do not mark all A11 assertions passed.

### A12 — Durable scheduled events (P4)

Use fixed clocks and two independent scanners for a schedule, a revised schedule, disable/re-enable, restart during occurrence insertion and DST repeat/skip boundaries.

Pass when each actual absolute due instant has at most one occurrence, event/cursor changes commit together, missed occurrences catch up in bounded batches with visible backlog, and no duplicate comes from a retry/node race. Disabled schedules create no new events; emitted history is retained. Events go only to explicit subscriptions and never invoke planning/execution directly.

Tests: `schedules_test.exs`, `workers/schedule_tick_worker_test.exs`.

### A13 — Operator UI and real fake-Agent journey (P5)

In focused LiveView tests and a browser on an isolated build: register/authorize an Agent, create a Project and repository association, create/delegate a Task, observe claim/start/progress/result, inspect events/delivery/history and an unresolved execution hold. Refresh and disconnect/reconnect.

Pass when durable state and counts survive, forms expose field validation, lists paginate/preload, empty/error states are visible, keyboard/mobile operation works and console errors are absent. No PRD/phase/swarm/provider selection is required and no local process starts from Project creation. Historical UUID links resolve with restricted data projections. Record successful `mix assets.build` and the served asset hash; a listener/HTTP 200 alone is insufficient.

Tests: scoped affected/new LiveViews and `integration/agent_journey_test.exs`; browser evidence ties to the exact build/endpoint.

P5 local evidence is complete for the operator journey: persisted Agent/Project/repository/membership setup; routed event decision and execution callbacks; child, progress and artifact; separate review/acceptance; rejected transitions and cancelled/held execution; repeated submission and interrupted schedule draft recovery; refresh/navigation/reconnect, keyboard submission and mobile/desktop layout. Final console checks found no warnings/errors. [Qualification](qualification.md) records database/ports, record IDs, served hashes, screenshots and the inherited disconnected-toast accessibility limitation. The signed-webhook journey runs twice with `Synapsis` and `Orion` through identical APIs and native fake WebSockets. This does not establish a real provider or production UI deployment.

### A14 — Storage/runtime and isolated release safety (P1/P6)

Start the isolated bridge/new release with admissions closed and inspect application children, named Oban instances, queues, migration histories and history reads. Restore the legacy fixture and repeat after additive expansion.

Pass when main and memory migrations/storage are accounted for, no recovery/provider/Codex/memory-prune execution starts, retained history is readable, no default/shared database is touched and no ignored local workspace is removed. A supposedly retired dependency with a remaining reader blocks its removal.

P3 `migration/preservation_test.exs` and `legacy_isolation_test.exs` provide local source/content and inert-runtime evidence with the main Repo. Dual-storage backup/restore, isolated release smoke and guarded old/new restart remain P1/P6. No full legacy test baseline or production operation is required.

### A15 — Scope, blockers and phase stop (all stages)

For every stage, compare changed paths and behavior to its owning scope. Run scoped tests plus required checks; the current authorization explicitly includes aggregate release checks. Record unrelated failures without repairing them or weakening gates. Follow upstream issue routing for actual dependency blockers; do not silently patch/vendor them.

Pass when each active checklist is evidenced, applicable gates pass and blockers B0–B6 are honestly open/cleared. Cross-stage scenarios are checked only for current assertions. P0–P4 phase records remain historical evidence. The current scope completes persisted management/local qualification, commits and pushes; release requires all applicable gates and an existing successful publication workflow. Failing aggregate gates block release rather than being reclassified as passing. No live GitHub setup, repository writes, sibling-service changes, production migration, live credentials or deployment are authorized. Local qualification labels unresolved target manifests **not deployable**. Real cutover clears every applicable target-specific gate and requires separate authorization.

## 4. P2/P3/P4 and future gate records

For a later stage, record: stage/commit; database/endpoint/build/profile; exact scoped commands/results; preservation and external-effect evidence; each blocker's evidence or remaining owner/action; and the next unexecuted stage. Keep real credentials and sensitive payloads out of the record.

At the P2 boundary, package-owned portions of A05/A07/A11/A15 passed: schema/correlation/uncertainty/replay, independent consumer, real fake transport, authentication/approval boundaries, pinned Codex subset fixtures and scoped delivery. Exact commands/results and limitations are in [the phase record](protocol-phase-2.md#phase-record). P2 made no platform receipt, lease rebind, execution-hold, authoritative Task callback, production access or real Codex/Sigma/Synapsis compatibility claim. A01–A04/A06/A08–A10/A12–A14 and the integrating portions of A05/A07/A11 were future work at that boundary; P3's local portions are recorded next.

P3's final scoped suite and the commit containing this record establish the following local portions:

| Assertions | Implemented evidence | Remaining gate |
| --- | --- | --- |
| A01–A03: identity/preservation/adoption | Main migration source hashes, additive populated-history fixture, inert mappings/ledger, explicit adoption, unchanged source checks, stable UUIDs and repository associations | Full backup/memory/reader and real repository identity evidence |
| A04/A05: state/ownership/replay | Context/API tests, independent claim/capacity/version/revocation/authority races, lease/fence/epoch/rebind/hold/key-rotation cases | Real execution journal, remote effects and platform restart/WebSocket journey |
| A06: transactional foundation | Atomic command-linked event/snapshot/delivery-intent insertion, receipt event IDs and rollback/replay test | P4 subscriptions/cursors/dispatch/retry/GitHub/schedules |
| A08/A09/A14: local closed authority/isolation | Inert registration, disabled queues/plugins, retained pending-job refusal, closure/new epoch and durable holds | Classified jobs, guard-aware bridge/old-writer exclusion, dual-Repo/pgvector restore, release/drain/rollback rehearsal |
| A11/A15: access/scope | Protected operator/machine REST, role and cross-Project checks, explicit proof read, safe projections, paused-owner allowed operations, scratch DB allowlist and scoped commit | Browser/remote destination security and actual service credentials |

The root-owned final P3 run passed **87 tests (48 core, 39 web), 0 failures**, seed `197697`, on `samgita_redesign_p3_verified_test` using socket `/tmp/samgita-p3-pg/socket`, port `55443`, user `gao`. `MIX_ENV=test mix compile --warnings-as-errors` and scoped 66-file `mix format --check-formatted` also passed. The formatter excluded verbatim pinned migration sources/fixtures; the suite verified their hashes. The exact scoped command is in [plan §5](implementation-plan.md#5-p3--stable-identities-migration-mapping-and-authoritative-commands) and the [phase record](domain-phase-3.md). No P3 result clears live cutover, production key rotation, actual Synapsis/Sigma/Codex compatibility, GitHub ingress, network delivery, cron, UI or a Samgita-hosted platform WebSocket.

The current bounded P4 phase establishes these additional local portions:

| Assertions | Implemented evidence | Remaining gate |
| --- | --- | --- |
| A06: routing/outbox/delivery/replay | Atomic domain/event/Oban rollback, killed handler and lost wakeup recovery, duplicate/ACK-loss/status reconciliation, explicit responsible subscription and retarget replay, fenced concurrent results/cancellation, cursor gap checks | Real Agent persistent idempotency and deployment restart/effect reconciliation |
| A08/A09/A14: retained history and isolation | P3 event/subscription/delivery preservation rehearsal, inert unapproved intents, exact new worker/queue admission, old hook enqueue-error propagation into disabled quarantine, retained legacy/memory sentinel hashes | Legacy producer drain, full memory/backup restore and compatible release/rollback rehearsal |
| A11: connector/API boundaries | Authenticated local fake WebSocket, pinned destination dial, 429/authentication/permanent/ambiguous classification, bounded transport, protected operator/machine APIs | Actual-service TLS/authentication/durability and deployed egress controls |
| A12: scheduled facts | IANA timezone/DST, bounded missed-run catch-up, revisions/disable, scoped Task references and independent scanner races | Operational backlog monitoring and deployed timezone-data maintenance |
| A15: phase stop | Scoped tests, independent protocol checks, additive migration and reviewable coordination commit | Native GitHub integration and P5/P6 remain unexecuted |

P4's final scoped run passed **92 tests (75 core, 17 web), 0 failures**, seed `388086`, on `samgita_redesign_coordination_final_test`. Independent checks passed 24 optional transport tests, 30 protocol core tests and one outside-consumer test. Exact commands, build/format results, local migration evidence and remaining gates are in [the coordination phase record](coordination-phase-4.md). These results establish no real Synapsis/Sigma/Codex compatibility, GitHub ingress, production migration, deployment or browser journey.

## 5. P5 local qualification ledger

This is the original P5 ledger at `91567e5`. Section 6 supersedes its aggregate-failure and reused-database limits; its browser evidence remains historical.

This ledger supersedes the earlier phase-boundary descriptions only for the assertions below. Final retained/redesign tests: **158 core, 104 web cases, 0 failures, 1 excluded dedicated restart case**, seed `437312`, fresh `samgita_redesign_management_qualified_test`. The separate restart test passed (1 test, seed `157470`); independent package suites passed (30 core, 24 WebSocket, 13 pinned Codex), and both copied outside-umbrella consumers passed. Full commands, browser/build evidence and limitations are in [qualification](qualification.md).

| Scenario | Current local qualification | Remaining acceptance boundary |
| --- | --- | --- |
| A01 | Persisted neutral registration, Project/repository setup, explicit roles/routing; full signed-event journey with Synapsis and Orion names | Actual enabled Agent-service conformance |
| A02 | Additive fresh/populated fixtures, pinned migration sources, unchanged IDs/references/content and repeat mappings | Actual deployment inventory, full readers, dual-Repo/memory/pgvector backup/restore and verified remote repository identity |
| A03 | Legacy mapping, drift rejection, inert unadopted Tasks and explicit adoption tests retained | Target-specific unresolved ledger reconciliation before cutover |
| A04 | Independent PostgreSQL claim/capacity/version/auth races; protected progress/result callbacks; pending review then explicit acceptance | Real external executors and host-owned effect journals; no management WebSocket profile advertised |
| A05 | Command receipt/rebind/hold tests; lost ACK, status-only reconnect, actual application/fake-host restart; UI cancelled hold survives refresh/reconnect | Power-loss durability, real Agent journal/cessation guarantees |
| A06 | Atomic outbox/jobs, cursor replay, delivery/error/retry/exhaustion/cancellation/fencing tests; real fake WebSocket and persisted UI history | Actual selected Agent durability and target operational recovery |
| A07 | Core and direct runtime consumers copied outside umbrella; independent native methods, stream/approval/interruption and explicit REST callback boundary | Exact real-service/client conformance, optional adapter publication; no full Codex compatibility claim |
| A08 | Legacy executors absent, new queues allowlisted, retained jobs refuse activation; restart does not restore old workers | Full guard-aware old-node/process/dual-Oban inventory, drain and external-effect cessation |
| A09 | Closed authority/new epoch, stale results rejected, unknown effects retain holds and prevent activation after restart | Compatible guarded rollback binary, full backup restore and target-specific external-effect reconciliation |
| A10 | Deterministic raw signed/replayed/mismatched fixtures, read-only loopback HTTP/token/rate-limit/reconciliation tests, one durable logical source event | Real GitHub App/installation/permissions/security validation; no writes enabled |
| A11 | Existing API/machine/project auth, CSRF, filtered logs and safe DOM/receipt/event projections verified | Raw telemetry/export non-disclosure, target TLS/egress and real-service credential boundaries remain open |
| A12 | Fixed-clock timezone/DST/missed-run/concurrent-scanner tests; recovered/repeated UI schedule submission persists once | Operational backlog monitoring and target timezone-data maintenance |
| A13 | Persisted views, fake-Agent browser journey, error/hold/review states, keyboard/mobile, served asset hashes and no final console errors | Historical storage/readers and actual deployed build remain target-specific; inherited toast accessibility defect tracked upstream |
| A14 | Isolated scratch databases, preserved main/history fixtures, explicit protocol consumers and local release assembly | Full dual-storage restore, guarded old/new binary smoke/restart and cutover manifest |
| A15 | Scoped work and unchanged gates recorded; commit/push authorized; no production/live-service changes | Aggregate Credo/Dialyzer/legacy-reference/audit failures block release; normal publication workflow absent |

The entire redesign is **not certified deployable or releasable**. The persisted management phase is locally qualified within the stated boundaries; open assertions remain open. Repeated aggregate execution on the reused scratch database also exposed two inherited GitHub reconciliation fixture-isolation failures; the same seed passed on fresh databases. No failing tests were removed, unrelated code repaired or gate weakened.

## 6. Reliability repair qualification

The executable repair tree at `896fc4886f77e731c38077069fb2d4c7feb8a18a` passes the full retained suite twice on the same populated scratch database: **167 core tests and 110 web cases per run, zero failures, one separately run restart case excluded**, seed `437312`. The dedicated restart case passes; independent protocol suites pass **32/40/13** cases, and both outside-umbrella consumers pass. Compile, format, strict Credo, Dialyzer, precise legacy scan, Hex audits, clean frozen Bun install, assets and local production assembly pass. [Exact commands, regressions and limits](qualification.md#reliability-repair-qualification) distinguish these runs from the prior browser evidence and initial failures.

The first hosted repair run passed through assets, then exposed a missing-ripgrep dependency in the scanner; later hosted gates were skipped. Portability repair `d32a532` uses Git's inventory and passes a new regression with no ripgrep on PATH. The application/protocol tree is unchanged; hosted qualification must follow the final pushed revision.

[Hosted run 39900481097](https://github.com/gsmlg-opt/Samgita/actions/runs/39900481097) subsequently passed all steps at `dd2a82b483ffb6ce0807c5e01ff20fba32b96e15`, including Dialyzer, audit and production assembly. This clears the automated build gates for that tree. A11 and the target-specific integration/cutover boundaries below remain open; no release, publication or deployment occurred.

| Scenario | Newly verified repair assertions | Remaining gate |
| --- | --- | --- |
| A05/A07 | Server-request deadlines and once-only cleanup; late replies, disconnect/send failure and consumed control-byte accounting; mutation uncertainty preserved | Documented conservative aggregate socket-read cap; real service/client conformance and durable host policy |
| A06 | Inactive backlog cannot starve active wakeup; resume, lease expiry, ambiguity and retry/fencing cases retained | Actual Agent durability and operational recovery |
| A10 | Real Client/fake-HTTP object deletion tombstones only after exact access revalidation; duplicate/reappearance, sibling mapping, revocation, 429 and transient behavior | Live installation/permissions validation; GitHub writes remain disabled |
| A11 | Atomic supervised node-local quotas survive request death; concurrent boundary, expiry and bounded cleanup; actual canary verifies logs/DOM/metric projections | **Blocked:** raw LiveView start/stop metadata contains plaintext credential parameters. No raw exporter is configured; passing canary documentation does not clear non-disclosure. Target TLS/egress/credentials also remain open. |
| A12 | Canonical target-bound schedule receipts, unchanged same-target replay, safe legacy proof, missing/inaccessible targets and stale versions | Target scheduling operations/timezone-data maintenance |
| A15 | Prior static/security/install issues repaired without exclusions, sleeps, production-limit changes or fresh-only evidence; scoped commits and push authorized | A11 prevents release; no normal publication workflow, real integration or production cutover acceptance |

No tag, publication or deployment is justified by these local checks. The original six-hour Bun cancellation remains **not reproduced/cause unknown**; a separate reproduced Bun 1.4.4 asset-wrapper incompatibility is avoided by the verified 1.3.13 pin and matching frozen lock. No historical migration/data was deleted or applied to production.
