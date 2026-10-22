# Samgita redesign acceptance contract

Date: 2026-10-22. This separates acceptance of the current documentation phase from evidence required for future implementation. An unchecked future case is planned work, not a claim that the feature exists.

Authority: [design](design.md), [implementation plan](implementation-plan.md), and `AGENTS.md`. The older clean-start documents are historical proposals and cannot waive preservation or cutover tests.

Merged-baseline note: `d6e9eca` combines documentation `3a344f5` and the separately authorized source refactor `811eeb9`. Legacy source/migrations were removed; only the two-app foundation is implemented, with one main Repo/Oban migration. This is not proof of a database migration, historical-data deletion or continuity. P0 checks below describe the original four-file documentation commit, not the separate source merge. B0 source/migration reconciliation must establish current file/test scopes and historical-source provenance before implementation; the legacy inventory, dual-Repo cases and P1 callsites are requirements against the pinned audit revision, not assertions that those files/readers exist now.

## 1. Current phase: document acceptance

Only `AGENTS.md` and these three `docs/redesign/*.md` files may change. No production migration, source/dependency change, service restart, schema reset, historical-data deletion, push, PR or deployment belongs to this phase.

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

## 2. Future test isolation and evidence rules

These cases run only in their authorized stage after B0 reconciles the merged foundation with historical schemas/readers and revises file scopes. Use explicitly named `samgita_redesign_*_test` databases with sanitized legacy fixtures/copies; never use production or an unresolved database. P1 must first implement/verify the test database wiring for every required migration source. Dual-Repo, both-migration-history and vector-storage cases describe the legacy preservation fixture; the current checkout has only the main Repo. B0 must account for those historical sources without assuming removed applications/readers are present or automatically restoring them.

Unit tests cover pure transitions, matching, schedule occurrence calculations and codecs. Context tests prove database effects and transactional rollback. Locking tests use independent connections/transactions with deterministic barriers, not a shared sandbox connection. Oban runs manually except in explicitly isolated restart/scheduler tests. Real WebSocket tests use a dedicated endpoint/port/database and a fake Agent/host, with no LLM, real tools or production credentials. Browser proof records the endpoint/build/assets actually served.

Each case records test path/command, build/schema/profile version, database/port, observed assertions and any limitation. A fake service proves the local contract; it cannot certify real Sigma/Synapsis/GitHub authentication or compatibility. No automatic production changes follow a green test.

## 3. Behavioral acceptance scenarios

### A01 — Neutral registration and Project setup (P3/P5)

Given a trusted operator, create a Project without a PRD, Git URL, working path or provider. Register fake, Synapsis-named, Sigma-named and Codex-named Agents using the same API and bind selected Agents explicitly.

Pass when stable UUIDs are returned; zero/multiple repository associations work; implementation labels do not affect authorization/capacity; no Agent/provider/SSH/CLI process starts; and no default destination/subscription appears. Disable an Agent/binding and verify new claims and event access fail while history remains readable.

Tests: core `repositories_test.exs`, `agents_test.exs`; focused registration/Project LiveView/controller tests and `integration/agent_journey_test.exs`.

### A02 — Identity, history and migration preservation (P1/P3/P6)

Given a fixture containing every historical table/status/reference, run expansion/backfill twice and compare before/after manifests.

Pass when all existing Project/Task/history IDs and FKs remain, UUID routes still resolve, payload/result/chat/memory/snapshot digests remain unchanged, and repeated backfill adds no duplicate mapping/association/event. Verify SSH/HTTPS aliases, rename/transfer, local paths, inaccessible repositories and duplicate normalized URLs. Never merge Projects. Missing/ambiguous opaque refs and array/edge conflicts appear as explicit unresolved ledger entries, not dropped data.

Verify Project-level URL uniqueness is relaxed only after old writers are fenced. A Project's repository rename, reassociation, URL change or shared repository never changes Project ID or transfers Task history. Archive cannot cascade-delete. The isolated restore reproduces the preservation manifest.

Tests: `redesign/preservation_manifest_test.exs`, `migration/*_test.exs`, retained UUID read/controller/history tests.

### A03 — State mapping and explicit adoption (P3)

Given each legacy state, verify the full mapping table in design §8. Existing pending Tasks may project open but remain unadopted; assigned/running project as blocked/reconciliation-needed; skipped retains legacy-skipped provenance. Old status/phase/results/counters remain unchanged.

Pass when no legacy Task is claimable by default and no authenticated Agent/Attempt is fabricated from a worker string, PID or attempt count. Adoption keeps the same Task ID and requires same-Project relationships, reviewed content and resolved external effects. An unresolved mapping blocks adoption. Neutral state is inert before the authority switch and sole management authority afterward; no bidirectional lifecycle writes occur.

Tests: `migration/state_mapping_test.exs`, `tasks_test.exs`, `tasks/execution_hold_test.exs`.

### A04 — Authoritative state, capacity and stale writers (P3/P5)

Given an active Agent binding and an adopted open Task, race two independent claims and concurrent capacity/binding/credential changes. Exercise start, block, completion, failure, cancellation and explicit reopen.

Pass when exactly one active Attempt exists, configured capacity is never exceeded, each accepted state change has matching receipt/event/delivery intent, and version/scope/epoch/fence/expired-proof violations change nothing. A blocked relation or child Task never starts an executor or auto-completes its parent. Terminal Attempts remain immutable; appended resolution evidence cannot rewrite an outcome. Disconnect alone does not release ownership.

Tests: `tasks/ownership_race_test.exs`, `tasks_test.exs`, `attempts_test.exs`, API/protocol authorization cases.

### A05 — Receipts, reconnect and remote-effect holds (P2/P3/P5)

Lose claim/start/report/rebind responses and retry with the same command IDs. Repeat a completed command after its first execution changed version/state. Send different semantics with the same command ID and replace/revoke the connection.

Pass when current authentication/authorization/epoch checks precede receipt lookup, matching receipts precede mutable business preconditions, and retries produce one logical change with the original result/version/event IDs. Conflicting semantics fail. Historical ACKs never authorize new execution. No proof/credential appears in receipts, audit data or logs.

Reconnect as the same Agent: an explicit valid rebind increments fence and transfers only its existing unexpired Attempt to the new connection generation. Old connection/proof fails. A local execution journal prevents the Agent from starting the Attempt twice. Lost proof, expiry or uncertain effects takes the hold/reconciliation path.

Invalidate an Attempt while its fake remote tool is still running, then reopen the Task. Pass only if the execution hold prevents another claim and counts against Agent capacity until authenticated cessation/outcome or audited operator reconciliation clears it. Reopen, timeout and connection presence cannot clear it.

Tests: protocol conformance/connection fixtures, `tasks/reconnect_test.exs`, `tasks/execution_hold_test.exs`, `integration/restart_reconcile_test.exs`.

### A06 — Event transaction, replay and explicit routing (P4)

Roll back a Task transaction, crash after commit before send, lose a delivery ACK, replace a subscription target and restart the worker.

Pass when rollback leaves no event/outbox, restart delivers stable IDs without a second logical event, subscribers deduplicate, and cursor reads recover gaps in Project order. Zero subscribers is visible and does not choose Synapsis. Binding/subscription revocation prevents later delivery/access. Target revision changes require explicit redelivery choice, and delivery retries cannot mutate Tasks.

Existing generic hook jobs retain IDs/legacy signing until reviewed replacement; no mass resend occurs. Simulated legacy notification sends are labelled historical/simulated rather than proof of actual delivery.

Tests: `events/{transaction,delivery}_test.exs`, `workers/event_delivery_worker_test.exs`, retained scoped webhook tests.

### A07 — Independently reusable protocol and direct service routing (P2/P5)

Build a separate consumer with only `samgita_app_server` and declared dependencies. Start a fake host at its own endpoint while Samgita is stopped; initialize, create/resume a session, submit/steer/interrupt a turn, exchange a permission request and stream events.

Pass when no Samgita Repo/web/provider/Backplane app or implicit listener starts; codecs/correlation/negotiation/buffering work; unsupported groups fail predictably; host callbacks decide execution; and no second Sigma process/listener exists. Base protocol fields do not require Hub IDs. Malformed input cannot invoke a handler.

Then bring up isolated Samgita and send an explicit authenticated Task callback. Only that accepted callback changes its Task. Direct conversation output never changes the database implicitly. Pin exact reference schemas and real-client conformance before advertising Codex compatibility; current Sigma/Synapsis adapters remain unadvertised until their own B3 evidence passes. Do not claim full Codex support from a tested subset.

Tests: standalone package/consumer tests, `integration/direct_host_routing_test.exs`; separate real selected-client evidence for B3/B6.

### A08 — Legacy drain and complete mutual exclusion (P1/P6)

Seed available/scheduled/retryable/executing/snoozed/discarded jobs for every legacy worker, both Oban instances, retained webhook jobs, paused/running Projects, global Horde Agents, Codex Ports and fake remote sessions. Close admissions and drain under legacy-only ownership.

Pass when no new PRD/planning/Agent/Codex/provider dispatch occurs, recorded executing work can settle only at its epoch, and each job/process has an explicit drain/quarantine/resolution decision. Snapshot and memory pruning cannot delete history. Stopping a Project supervisor or cancelling an Oban job alone cannot pass the external-effect check. Shared-queue webhook work is not deleted or lost.

Owner-none/Hub switch refuses while an unguarded node or unknown active effect remains. After Hub activation, old API/UI/context/recovery/timer/cron/worker/retry/completion paths fail closed, including after node restart; no period allows old and new execution together. New execution never consumes a legacy Oban job as an external-Agent command.

Tests: `redesign/{legacy_guard,drain,restart}_test.exs`, independent old/new races; process/delivery inventory evidence in final rehearsal.

### A09 — Rollback without replay or data destruction (P1/P6)

Rehearse an abort before Hub writes and after an external fake execution begins. Include a delivered webhook and a simulated Git/tool side effect.

Pass when the only eligible rollback binary is guard-aware; admissions close, owner becomes none at a new epoch, unresolved work/capacity stays held, and history is read-only while effects reconcile. Additive schema, mappings, receipt/event history and all original IDs/data remain. No down/reset migration, PRD restart or automatic replay occurs. The result explicitly acknowledges external effects cannot be undone by restoring database state.

Tests: `redesign/rollback_test.exs` (create in P6), restart/reconciliation integration and named scratch restoration manifest.

### A10 — Signed GitHub connection and ingress (P4)

Use a fake GitHub App/installation API and raw webhook bodies. Verify correct signature, invalid signature, whitespace/body changes, duplicate/conflicting delivery ID, revoked installation, unauthorized repository, unknown event and database failure.

Pass when short-lived tokens stay server-side, only approved immutable repository IDs route to associated Projects, bad signatures are rejected before persistence, and one accepted delivery yields one logical source event. Persistence failure remains retryable. No automatic Task creation/decomposition, tool call or workflow dispatch follows the event. A repository rename preserves Project IDs.

Tests: `github_test.exs`, `controllers/github_webhook_controller_test.exs`; real connection remains blocked by B5 until approved installation/security evidence exists.

### A11 — Existing access boundaries and secret non-disclosure (P2–P5)

Verify infrastructure-protected browser routes retain CSRF/secure-header protections, configured operator API keys and rate limits still work, and no new account/org/RBAC system appears. Test machine routes with absent/invalid/revoked credentials even when operator API keys are intentionally empty. Test nested-resource Project mismatch, replay under another connection, malicious endpoint redirects and private-address targets lacking explicit approval.

Pass when authorization fails closed for machines and resource scope, secrets appear only in one-time no-store issuance, and captured DOM/API/events/receipts/logs/telemetry contain no plaintext key/proof/legacy endpoint secret. Runtime permission requests are bound to their original host/request; no codec auto-approval occurs. Missing downstream authentication blocks integration rather than being inferred from a sent Bearer header.

Tests: retained `plugs/{api_auth,rate_limit}_test.exs`, machine/API/protocol security tests and captured serialization/log assertions; explicit actual-service boundary proof for B3.

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

Tests: preservation/boot/restart tests and isolated release smoke. No full legacy test baseline or production operation is required to accept P0.

### A15 — Scope, blockers and phase stop (all stages)

For every stage, compare changed paths and behavior to its owning scope. Run only scoped tests plus required checks for that change. Record unrelated failures and stop without repairing them. Follow upstream issue routing for actual dependency blockers; do not silently patch/vendor them.

Pass when each active checklist is complete, its checks pass, blockers B0–B6 are honestly open/cleared with evidence, and work stops at the requested boundary. B0 requires an approved comparison of merged and historical source/migrations/readers and revised implementation/test scopes before any redesign implementation; this documentation note does not clear it. Cross-stage scenarios are checked only for the assertions owned by the current stage until their final gate. P0 ends with only a four-file documentation commit. Local P6 may leave live/disabled-integration gates open and labels the manifest not deployable where applicable. Real cutover clears every target-specific gate and requires separate authorization.

## 4. Future gate record

For a later stage, record: stage/commit; database/endpoint/build/profile; exact scoped commands/results; preservation and external-effect evidence; each blocker's evidence or remaining owner/action; and the next unexecuted stage. Keep real credentials and sensitive payloads out of the record.

At this phase boundary no behavioral scenario A01–A14 is marked passed. They specify implementation acceptance; only the P0 documentation checklist can be completed now.
