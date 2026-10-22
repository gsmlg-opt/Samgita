# Samgita agent-neutral platform implementation plan

Date: 2026-10-22. Status: design-phase deliverable; stages P1–P6 are not started or authorized by this commit.

**Goal:** preserve existing Projects, Tasks and history while moving execution decisions to registered Agents and establishing repository associations, a reusable app-server implementation, GitHub connections and durable events.

**Architecture:** keep the existing Ecto/Phoenix umbrella. Add an independently consumable `samgita_app_server` package, neutral core contexts and an exclusive execution fence. Adopt legacy work explicitly after a guarded drain; do not implement a second Sigma server or a Backplane protocol dependency.

**Stack:** Elixir/OTP, Ecto/PostgreSQL, Oban, Phoenix LiveView, Tailwind 4, Bun/TypeScript and existing DuskMoon assets. No new account framework, embedded LLM runtime or component library.

Read [design](design.md) and [acceptance](acceptance.md) first. Source paths below are repository-relative. Proposed files/tests do not exist yet; commands using them become executable only in their owning stage. Each future change starts with its specified failing behavioral check, adds the smallest implementation, reruns only the scoped checks, and makes a logical Conventional Commit. Do not use the former `docs/plan.md` deletion stages.

## 1. Delivery contract and dependencies

| Stage | Dependency | Ownership | Gate / suggested commit units |
| --- | --- | --- | --- |
| P0: this phase | Current local HEAD | Documentation owner; parallel read-only audits | Four-file document review/checks and scoped commit; STOP. |
| P1: preservation harness and bridge | Separate authorization; P0 accepted | One runtime/migration owner | Isolated legacy fixture, complete writer guard, classified jobs and guarded restart; `test(migration)`, `feat(runtime)` commits. |
| P2: standalone app-server | P0 contracts accepted; independent of P1 after profile scope freezes | Protocol owner; no shared config/migration edits | Independent consumer, schema fixtures, real transport/fake-host conformance; `feat(protocol)` commits. |
| P3: neutral identities/state and mappings | P1 fence; P2 token/receipt contracts before claims | Core owner + migration owner | Stable IDs, resumable mappings, adoption, fenced state/claim races; `feat(projects)`, `feat(agents)`, `feat(tasks)` commits. |
| P4: events/GitHub/schedules | P3 Project/repository/authorization contracts | Event owner, integration owner, migration owner | Transactional outbox, signed GitHub ingress, deterministic occurrences; separate event/GitHub/schedule commits. |
| P5: management API/UI and fake Agent | P2/P3; P4 for event journey | Web owner + protocol-fixture owner | Real operator journey and WebSocket proof without LLMs; `feat(api)`, `feat(ui)`, `test(integration)` commits. |
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
- [ ] Configure an explicit future `SAMGITA_TEST_DATABASE` override for **both** test Repos. Refuse rehearsal targets outside a dedicated `samgita_redesign_*_test` naming allowlist. Current source does not honor this variable; implement/verify wiring before using the commands below.
- [ ] Use manual Oban testing and disable all autonomous recovery/formation/pruning in this harness. Fail closed if the test authority row is missing. Do not let `mix test`'s create/migrate alias touch a default/shared database.
- [ ] Make the manifest enumerate both migration directories, table/row/ID/FK counts, payload digests, orphan/ambiguous mappings and named Oban instances. Output IDs/counts/digests only; no secret values or raw prompts.
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

Owner: protocol owner; root dependency wiring goes through migration/integration owner.

Create:

- `apps/samgita_app_server/mix.exs`
- `apps/samgita_app_server/lib/samgita_app_server.ex`
- `apps/samgita_app_server/lib/samgita_app_server/{codec,profile,capabilities,connection,handler,transport,error}.ex`
- `apps/samgita_app_server/lib/samgita_app_server/profiles/{hub_v1,codex_0_163}.ex`
- `apps/samgita_app_server/priv/schemas/` selected reference and Hub schema files with provenance/license notice
- `apps/samgita_app_server/test/{codec,negotiation,connection,capabilities,conformance}_test.exs`
- `apps/samgita_app_server/test/fixtures/consumer/mix.exs` and `test/consumer_test.exs`
- `apps/samgita_app_server/test/fixtures/protocol/` named valid/invalid request/response/event fixtures

- [ ] Freeze B6: selected Codex version/schema hashes and exact supported method/notification subset; Hub profile version and `samgita/*` schemas; request IDs versus durable command IDs; error/timeout/size limits; lease derivation/rotation and receipt descriptors. Unsupported groups remain unadvertised.
- [ ] First write parse/serialize fixtures including the observed Codex envelope without a required `jsonrpc` field, malformed JSON/IDs, unknown methods, unsupported profiles and initialize ordering. Test parse failure emits no host callback.
- [ ] Implement codecs/registry/handler contracts without Repo, Phoenix, providers, Backplane, umbrella config or automatic listeners. A fake handler owns domain decisions; the package does not synthesize Task state.
- [ ] Implement request correlation, duplicate response handling, bounded outstanding requests/event buffers, disconnection/gap semantics and explicit host callbacks. Never auto-replay a side-effecting turn on reconnect.
- [ ] Implement Hub capability discovery separately from the exact upstream Codex initialize contract. Tests assert the registered handler set equals advertised support.
- [ ] Compile/test a separate consumer using a path dependency and its own config/build directory. Assert Samgita/Repo/web/provider/Backplane are absent from started applications and no listener/Agent process appears.
- [ ] Run fake-host real WebSocket round trips for initialization, a session/turn, a permission request/response, error and reconnect. Pin a real supported client round trip before claiming Codex compatibility. A fake profile test is insufficient for B3/B6.

Run `devenv shell --no-tui -- mix test` with working directory `apps/samgita_app_server`, then the same command from its independent consumer fixture. These are scoped package tests, not a request to run the umbrella suite. No sibling-service code is in scope; unsupported Sigma/Synapsis integration remains blocked rather than launching a substitute server.

## 5. P3 — Stable identities, migration mapping and authoritative commands

Migration owner creates:

- `apps/samgita/priv/repo/migrations/20261022000001_expand_agent_neutral_domain.exs`
- `apps/samgita/lib/samgita/migration/{project_repository_mapping,state_mapping,backfill}.ex`
- `apps/samgita/test/samgita/migration/{project_repository_mapping,state_mapping,backfill}_test.exs`

Core owner adapts `domain/{project,task}.ex`, `projects.ex` and creates:

- `apps/samgita/lib/samgita/{repositories,agents,tasks,attempts}.ex`
- `apps/samgita/lib/samgita/tasks/{transitions,capabilities}.ex`
- `apps/samgita/lib/samgita/agents/credentials.ex`
- `apps/samgita/lib/samgita/protocol/{receipts,lease_proof}.ex` (Hub persistence/security, not the reusable wire package)
- `apps/samgita/lib/samgita/domain/` schemas for repositories/aliases/associations, Agents/credentials/connections/bindings, Attempts, receipts, mappings and the minimal domain-event/subscription/delivery tables
- `apps/samgita/test/samgita/{repositories,agents,tasks,attempts}_test.exs`
- `apps/samgita/test/samgita/tasks/{ownership_race,reconnect,execution_hold}_test.exs`
- `apps/samgita/test/samgita/events/transaction_test.exs`

Adapt `apps/samgita/lib/samgita/events.ex` in P3 for transactional event/delivery-intent insertion only. P3's expansion migration owns those foundation tables; P4 extends them with external sources/schedules and implements delivery. Do not defer the atomic event foundation until after Task commands.

Freeze context inputs first: authenticated principal, stable resource UUID, `command_id`, expected version, connection generation where machine-authenticated, and typed payload. New commands must not call legacy `start_project/enqueue_task/retry_task` internally. Legacy read adapters may continue projecting preserved fields.

- [ ] Write migration tests for every mapping row/status in design §8, SSH/HTTPS aliases, duplicate normalized URLs, repository rename/transfer, local/unreachable paths, zero/multiple repository associations, opaque refs and conflicting dependencies.
- [ ] Add nullable neutral columns and new tables without rewriting/dropping old migrations or values. Preserve existing UUID/parent/task links and integer history keys. Keep mapped states inert until the authority switch.
- [ ] Implement resumable mapping ledger/upserts and dry-run reports; a rerun produces identical mappings and no additional records/events. Source digest changes require review instead of overriding a prior decision.
- [ ] Keep all legacy Tasks unadopted. Adoption preserves ID, checks same-Project relationships and effect-resolution evidence, and records an explicit event. Enforce `adopted && !execution_hold` in every claim path.
- [ ] Implement pure transition/capability/cycle checks, expected versions and atomic context commands. Project archive cannot cascade-delete history or assert remote stop.
- [ ] Freeze the initial event catalog/envelopes from design §5 and implement same-transaction event/subscription-delivery inserts. Prove rollback leaves no receipt/event/delivery intent before adding any network dispatcher in P4.
- [ ] Implement Agent registration, one-time non-cacheable credentials, scoped grants and neutral endpoint descriptors. Old worker IDs/endpoint maps are historical only; no automatic Synapsis registration.
- [ ] Implement receipts in the correct order: authenticate/authorize current session/epoch, replay matching receipt, then evaluate mutable preconditions for new commands. Different semantics with the same command ID conflict.
- [ ] Implement serialized capacity, leased Attempts, fences, starts/reports/renewals and explicit reconnect/rebind. Enforce execution deadlines and count unresolved effects against capacity. Expiry and operator closure create holds; reopen cannot clear a hold.
- [ ] Test lost claim/start/report/rebind responses, terminal receipt replay, revoked/replaced connections, lease-key rotation and current/old proof behavior without persisting tokens.
- [ ] Run independent-transaction claim/revoke/epoch/expiry races and reject cross-Project nested resources and relationship cycles. Do not use one shared sandbox connection as locking evidence.

Gate: core/mapping/ownership portions of A01–A05/A11, using P2's protocol fixtures where needed. UI/direct-host A07 and post-Hub A09 are completed in P5/P6; they are not prerequisites for finishing P3. B2/B4/B6 must be cleared for claims on a production target; passing fixture tests is not that operational clearance.

Scoped tests after P1 wiring:

```sh
devenv shell --no-tui -- env MIX_ENV=test SAMGITA_TEST_DATABASE=samgita_redesign_domain_test mix test apps/samgita/test/samgita/migration apps/samgita/test/samgita/repositories_test.exs apps/samgita/test/samgita/agents_test.exs apps/samgita/test/samgita/tasks_test.exs apps/samgita/test/samgita/attempts_test.exs apps/samgita/test/samgita/tasks/ownership_race_test.exs apps/samgita/test/samgita/tasks/reconnect_test.exs apps/samgita/test/samgita/tasks/execution_hold_test.exs apps/samgita/test/samgita/events/transaction_test.exs
```

## 6. P4 — Durable events, GitHub and schedules

Migration owner creates `apps/samgita/priv/repo/migrations/20261022000002_add_events_github_schedules.exs` and the corresponding Domain schemas for GitHub connections/external deliveries and schedules/occurrences, extending P3's event foundation without recreating it. Event owner adapts `events.ex`, `webhooks.ex`, `workers/webhook_worker.ex`; creates `event_delivery.ex`, `schedules.ex`, `workers/{event_delivery,schedule_tick,attempt_expiry}_worker.ex`. Integration owner creates `github.ex`, `github/{client,signature,ingress}.ex` and `apps/samgita_web/lib/samgita_web/controllers/github_webhook_controller.ex`; adjusts only raw-body/route transport wiring in `endpoint.ex` and `router.ex` through the shared owner.

Tests:

- `apps/samgita/test/samgita/events/{transaction,delivery}_test.exs`
- `apps/samgita/test/samgita/{github,schedules}_test.exs`
- `apps/samgita/test/samgita/workers/{event_delivery,schedule_tick,attempt_expiry}_worker_test.exs`
- `apps/samgita_web/test/samgita_web/controllers/github_webhook_controller_test.exs`
- Retained `apps/samgita/test/samgita/{events,webhooks}_test.exs` and `workers/webhook_worker_test.exs` only where their active behavior is adapted

- [ ] Prove a rolled-back Task transaction leaves no event/outbox/delivery. Crash after commit and before send; restart delivers the same event ID once logically, potentially more than once on the wire.
- [ ] Implement explicit Project-scoped subscriptions, revisioned targets, cursor reads and duplicate/gap ACKs. No subscriber/recipient is created from an implementation name.
- [ ] Move new delivery/maintenance to dedicated queues; retain old hook jobs/signature semantics until explicit translation/redelivery decisions are recorded. Simulate timeout/429/5xx/permanent failure and lost ACK; no retry may alter Task state.
- [ ] Implement operator-configured GitHub App references, short-lived token handling and verified repository-ID associations using a fake GitHub server. Do not request real secrets in test fixtures or store them in receipts/logs.
- [ ] Test raw-body signature verification before parsing, delivery duplicates/conflicts, repository/install scope, suspension, unsupported event types and persistence failure. No unsigned request enters the event inbox.
- [ ] Test schedule revision/disable/restart, two concurrent scanners, bounded catch-up and DST occurrences using fixed clocks. Every absolute due time emits at most one logical event; backlog remains inspectable.
- [ ] Prove push/issue/schedule events create no PRD, Agent worker, tool invocation, automatic Task decomposition or workflow dispatch.

Gate: event/GitHub/scheduler portions of A06/A10/A11/A12 against fakes. Real GitHub/network use waits for B5; fake-server tests can proceed independently. UI and actual-service security evidence belongs to P5/the separately authorized integration. Run only the test paths listed for this stage with `SAMGITA_TEST_DATABASE=samgita_redesign_events_test` and manual Oban isolation.

## 7. P5 — Management transports, operator UI and reference Agent

Web owner adapts `apps/samgita_web/lib/samgita_web/{router,endpoint}.ex`, existing Project/Task/Agent JSON/controllers and dashboard/project/Agent LiveViews/templates. Create `app_server/{socket,handler}.ex`, machine Agent/connection/repository/event/schedule controllers, and `live/{agent_form_live,task_live,repository_live,events_live,schedules_live}/` as the management journey requires. Do not preserve unsupported legacy execution controls as working buttons.

Protocol-fixture owner creates `apps/samgita_web/test/support/fake_agent.ex`, `apps/samgita_web/test/samgita_web/integration/{agent_journey,direct_host_routing,restart_reconcile}_test.exs`, and fixtures under `test/fixtures/redesign/`.

- [ ] Write protected API tests for registration/binding/one-time credentials, repository associations, versioned Task commands, event reads and schedule controls. Operator routes keep current API-key/rate-limit boundaries; machine routes require machine identity even when the operator key list is empty.
- [ ] Preserve old UUID read routes/legacy-history projections. Disable legacy start/restart/PRD generation/retry/local-Codex actions explicitly after the fence; do not redirect them into external execution.
- [ ] Build accessible, paginated DuskMoon forms/lists for registration, repository/GitHub status, Task relationships/state/Attempt/effect holds, event delivery and historical records. Validation errors must name fields; failures/empty states and migration conflicts must be visible.
- [ ] Keep Project creation independent of PRDs, Git URLs, cloning and runtime launch. Replace the static swarm catalog with registered identities/capabilities and no implementation-specific defaults.
- [ ] Run a real WebSocket fake Agent: register/bind -> create Task -> claim/start -> delegate a child -> report -> inspect history; exercise reconnect/receipt replay/hold resolution. No provider CLI, LLM or sibling server is required.
- [ ] Run a separate fake runtime host using the protocol package while Samgita is stopped. A direct client completes a session/turn there; only an explicit authenticated callback when Samgita is available changes its Task state. Assert no Sigma process/listener is created.
- [ ] Browser-proof the same operator journey, refresh/reconnect behavior, keyboard controls, visible validation, desktop/mobile layouts and console errors on a named isolated endpoint. Record served asset hashes to tie browser evidence to this build.

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

B1–B6 in [design §9](design.md#9-implementation-gates-and-unresolved-blockers) are the implementation blocker ledger. They do not block a reviewed P0 documentation commit. Clear each only with the specified evidence; do not convert an assumption into a checked acceptance box. Host/credential/subscriber selection remains explicit operator configuration, not an agent-chosen deployment decision.

For every authorized stage, report changed paths/commit, scoped checks and results, preserved data/effect evidence, remaining blockers and the next unexecuted gate. If an out-of-scope test fails, list it and stop without repair. When the in-scope checklist and tests pass, stop at that stage boundary.
