# Samgita redesign acceptance contract

Date: 2026-10-22. This separates completed P0/P2 evidence, locally verified P3 awaiting its reviewable commit, and future platform/cutover acceptance. A scenario spanning stages passes only for the assertions evidenced by its owning stage.

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

P3 tests: core `projects_test.exs`, `repositories_test.exs`, `agents_test.exs`, `legacy_isolation_test.exs` and web `controllers/domain_api_test.exs`. Event access, LiveViews and `integration/agent_journey_test.exs` remain P4/P5.

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

P3 tests: `tasks/task_transitions_test.exs`, `tasks/ownership_race_test.exs`, `security_race_test.exs`, `tasks_test.exs`, `attempts_test.exs`, `platform_test.exs` and web `controllers/domain_api_test.exs`. Race tests use independent transactions and assert distinct backend PIDs. A real platform WebSocket/remote-execution journey remains P5.

### A05 — Receipts, reconnect and remote-effect holds (P2/P3/P5)

Lose claim/start/report/rebind responses and retry with the same command IDs. Repeat a completed command after its first execution changed version/state. Send different semantics with the same command ID and replace/revoke the connection.

Pass when current authentication/authorization/epoch checks precede receipt lookup, matching receipts precede mutable business preconditions, and retries produce one logical change with the original result/version/event IDs. Conflicting semantics fail. Historical ACKs never authorize new execution. No proof/credential appears in receipts, audit data or logs.

Reconnect as the same Agent: an explicit valid rebind increments fence and transfers only its existing unexpired Attempt to the new connection generation. Old connection/proof fails. A local execution journal prevents the Agent from starting the Attempt twice. Lost proof, expiry or uncertain effects takes the hold/reconciliation path.

Invalidate an Attempt while its fake remote tool is still running, then reopen the Task. Pass only if the execution hold prevents another claim and counts against Agent capacity until authenticated cessation/outcome or audited operator reconciliation clears it. Reopen, timeout and connection presence cannot clear it.

P3 context tests: `attempts_test.exs`, `platform_test.exs`, `projects_test.exs`, `security_race_test.exs` and web `controllers/domain_api_test.exs`, alongside P2 protocol conformance. These cover receipts, rebind, holds, expiry and key rotation without a remote runtime. The real execution journal/tool uncertainty and `integration/restart_reconcile_test.exs` remain P5/P6.

### A06 — Event transaction, replay and explicit routing (P3 foundation/P4)

Roll back a Task transaction, crash after commit before send, lose a delivery ACK, replace a subscription target and restart the worker.

Pass when rollback leaves no event/outbox, restart delivers stable IDs without a second logical event, subscribers deduplicate, and cursor reads recover gaps in Project order. Zero subscribers is visible and does not choose Synapsis. Binding/subscription revocation prevents later delivery/access. Target revision changes require explicit redelivery choice, and delivery retries cannot mutate Tasks.

Existing generic hook jobs retain IDs/legacy signing until reviewed replacement; no mass resend occurs. Simulated legacy notification sends are labelled historical/simulated rather than proof of actual delivery.

P3 `events/transaction_test.exs` covers same-transaction receipt/event/subscriber-delivery insertion, command IDs, allowlisted before/after snapshots, receipt event IDs, rollback and matching receipt replay. No dispatcher, cursor/subscription management API, network delivery or cron is implemented. P4 adds `events/delivery_test.exs`, `workers/event_delivery_worker_test.exs` and retained-hook compatibility tests after current absent-source scopes are reconciled.

### A07 — Independently reusable protocol and direct service routing (P2/P5)

Build a separate consumer with only `samgita_protocol` and declared dependencies, outside the repository/umbrella. Start the optional transport's fake host at its own `/app-server` endpoint without starting Samgita; initialize, create/resume a session, submit/steer/interrupt a turn, exchange a permission request and stream events. Independently exercise project-event receive/status/decision reporting and unsupported capability errors.

Pass when no Samgita Repo/web/provider/Backplane app or implicit listener starts; codecs/correlation/negotiation/buffering work; unsupported groups fail predictably; host callbacks decide execution; and no second Sigma process/listener exists. Base protocol fields do not require Hub IDs. Malformed input cannot invoke a handler.

Then bring up isolated Samgita and send an explicit authenticated Task callback. Only that accepted callback changes its Task. Direct conversation output never changes the database implicitly. Pin exact reference schemas and real-client conformance before advertising Codex compatibility; current Sigma/Synapsis adapters remain unadvertised until their own B3 evidence passes. Do not claim full Codex support from a tested subset.

P2 tests: core `test/{schema,fixtures,client,server,replay}_test.exs`, optional transport `test/*_test.exs`, pinned Codex adapter `test/*_test.exs`, standalone consumer test and temporary-copy build proof. `integration/direct_host_routing_test.exs` and authoritative Task callbacks remain P5; real selected-client B3/B6 evidence remains separate.

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

Tests: `github_test.exs`, `controllers/github_webhook_controller_test.exs`; real connection remains blocked by B5 until approved installation/security evidence exists.

### A11 — Existing access boundaries and secret non-disclosure (P2–P5)

Verify infrastructure-protected browser routes retain CSRF/secure-header protections, configured operator API keys and rate limits still work, and no new account/org/RBAC system appears. Test machine routes with absent/invalid/revoked credentials even when operator API keys are intentionally empty. Test nested-resource Project mismatch, replay under another connection, malicious endpoint redirects and private-address targets lacking explicit approval.

Pass when authorization fails closed for machines and resource scope. P3 accepts operator-supplied credentials, persists only digests and returns metadata with `no-store`; no plaintext credential is issued. Explicit current-owner proof reads are non-cacheable; proofs never enter receipts/events. Captured DOM/API/events/receipts/logs/telemetry must exclude plaintext credentials and legacy endpoint secrets; intentional proof responses are tested separately. Runtime permission requests are bound to their original host/request; no codec auto-approval occurs. Missing downstream authentication blocks integration rather than being inferred from a sent Bearer header.

P3 tests: `agents_test.exs`, `projects_test.exs`, `attempts_test.exs`, `security_race_test.exs` and web `controllers/domain_api_test.exs`; retain existing `plugs/{api_auth,rate_limit}_test.exs`. P3 filters credential/proof parameters and validates stored endpoint descriptors but opens no remote connection. Browser/telemetry capture, egress SSRF/redirect enforcement and actual-service boundary proof remain P4/P5/B3/B5.

### A12 — Durable scheduled events (P4)

Use fixed clocks and two independent scanners for a schedule, a revised schedule, disable/re-enable, restart during occurrence insertion and DST repeat/skip boundaries.

Pass when each actual absolute due instant has at most one occurrence, event/cursor changes commit together, missed occurrences catch up in bounded batches with visible backlog, and no duplicate comes from a retry/node race. Disabled schedules create no new events; emitted history is retained. Events go only to explicit subscriptions and never invoke planning/execution directly.

Tests: `schedules_test.exs`, `workers/schedule_tick_worker_test.exs`.

### A13 — Operator UI and real fake-Agent journey (P5)

In focused LiveView tests and a browser on an isolated build: register/authorize an Agent, create a Project and repository association, create/delegate a Task, observe claim/start/progress/result, inspect events/delivery/history and an unresolved execution hold. Refresh and disconnect/reconnect.

Pass when durable state and counts survive, forms expose field validation, lists paginate/preload, empty/error states are visible, keyboard/mobile operation works and console errors are absent. No PRD/phase/swarm/provider selection is required and no local process starts from Project creation. Historical UUID links resolve with restricted data projections. Record successful `mix assets.build` and the served asset hash; a listener/HTTP 200 alone is insufficient.

Tests: scoped affected/new LiveViews and `integration/agent_journey_test.exs`; browser evidence ties to the exact build/endpoint.

### A14 — Storage/runtime and isolated release safety (P1/P6)

Start the isolated bridge/new release with admissions closed and inspect application children, named Oban instances, queues, migration histories and history reads. Restore the legacy fixture and repeat after additive expansion.

Pass when main and memory migrations/storage are accounted for, no recovery/provider/Codex/memory-prune execution starts, retained history is readable, no default/shared database is touched and no ignored local workspace is removed. A supposedly retired dependency with a remaining reader blocks its removal.

P3 `migration/preservation_test.exs` and `legacy_isolation_test.exs` provide local source/content and inert-runtime evidence with the main Repo. Dual-storage backup/restore, isolated release smoke and guarded old/new restart remain P1/P6. No full legacy test baseline or production operation is required.

### A15 — Scope, blockers and phase stop (all stages)

For every stage, compare changed paths and behavior to its owning scope. Run only scoped tests plus required checks for that change. Record unrelated failures and stop without repairing them. Follow upstream issue routing for actual dependency blockers; do not silently patch/vendor them.

Pass when each active checklist is complete, its checks pass, blockers B0–B6 are honestly open/cleared with evidence, and work stops at the requested boundary. P2 reconciles independent packages; P3 reconciles restored main sources/schema and local fixtures, without clearing deployment history/storage/reader gates. Cross-stage scenarios are checked only for current-stage assertions. P0 ended with the documentation commit; P2 ended with the package/test/docs commit. P3 ends after its final scoped checks and reviewable commit, with no P4/P5, production migration, push or deployment. Local P6 may leave disabled-integration/live gates open and labels the manifest not deployable where applicable. Real cutover clears every applicable target-specific gate and requires separate authorization.

## 4. P2/P3 and future gate records

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

The root-owned final run passed **87 tests (48 core, 39 web), 0 failures**, seed `197697`, on `samgita_redesign_p3_verified_test` using socket `/tmp/samgita-p3-pg/socket`, port `55443`, user `gao`. `MIX_ENV=test mix compile --warnings-as-errors` and scoped 66-file `mix format --check-formatted` also passed. The formatter excluded verbatim pinned migration sources/fixtures; the suite verified their hashes. The exact scoped command is in [plan §5](implementation-plan.md#5-p3--stable-identities-migration-mapping-and-authoritative-commands) and the [phase record](domain-phase-3.md). P3 ends with this scoped commit. No P3 result clears live cutover, production key rotation, actual Synapsis/Sigma/Codex compatibility, GitHub ingress, network delivery, cron, UI or a Samgita-hosted platform WebSocket.
