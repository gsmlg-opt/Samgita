# Agent Hub Rebuild Implementation Plan

> **For agentic workers:** Use the subagent-driven-development or executing-plans workflow task by task. Parallel work is already authorized by repository guidance; assign disjoint file ownership after shared contracts are frozen. Steps use checkbox syntax for tracking.

**Goal:** Replace all legacy Samgita product code with an external Agent Hub, including operator UI and a tested fake Agent.

**Architecture:** Two umbrella apps, `samgita` and `samgita_web`. PostgreSQL owns state, transactional receipts/events, leases, and fencing; Phoenix Channels carry authenticated agent messages, LiveView provides the operator UI, and Oban maintains expired Attempts.

**Tech Stack:** Existing Elixir/Phoenix/Ecto, PostgreSQL, Oban, PubSub, DuskMoon, Tailwind, Bun, and TypeScript. Keep compatible installed dependency versions unless removal or a verified requirement necessitates a change.

Date: 2026-09-07
Status: Implementation plan ready; application implementation has not started.
Approved scope: [rebuild design](agent-hub-rebuild-design.md).
Contracts: [PRD](prd.md), [architecture](architecture.md).
Deletion boundaries: [removal inventory](agent-hub-removal-inventory.md).

---

## Execution boundary

This is a clean start inside the existing repository. No legacy execution mode, data migration, dual runtime, provider app, memory app, PRD engine, or old migration history remains in the final source tree. Old code is recoverable through Git.

The user approved UI in the first milestone and a fake reference Agent sufficient for integration. Cancellation/manual retry and real Synapsis integration are deferred. Publishing PRs, pushing, deploying, and deleting existing databases are not part of this plan.

All paths below are relative to the worktree root. Resolve them against that root before editing. Use `.trees/codex/agent-hub-rebuild` for implementation and base it on the local HEAD containing the documentation changes. Never base on an older remote revision that loses the user's documentation commit.

The checklist describes work to perform, not tests already passed.

Planning preflight observation: the inventory's `mix app.tree` attempt triggered dependency compilation and failed in ThousandIsland/Elixir's ParallelChecker with `binary_to_atom` / `:badarg`. No application-tree baseline was obtained. Before stage 1, verify the selected toolchain and worktree-local dependency build; do not treat this observation as evidence that the new design or tests fail. No dependency repair was performed during planning.

A separate transport exploration using `mix run --no-start` also stopped at a legacy `Samgita.Quality.InputGuardrails` compilation error. The approved removal inventory retires that module; no unrelated repair was attempted. The Authorization-header bridge therefore has source-inspection evidence only and still requires the stage 0 real-transport proof.

## Delivery stages and ownership

| Stage | Depends on | Owner boundary | Exit evidence |
|---|---|---|---|
| 0. Handoff and fixtures | Approved docs | Integrator | Worktree, exact inventory, transport/field contracts |
| 1. Two-app foundation | 0 | Integrator only for shared configuration | Boot, fresh schema infrastructure, health, assets |
| 2. Domain and credentials | 1 | One schema owner; pure modules may parallelize | Context and database invariant tests |
| 3. Execution and protocol | 2 | Transaction owner + transport owner + fixture owner | Real WebSocket happy path and replay |
| 4. Recovery and races | 3 | Transaction owner + independent test owner | Expiry/reconnect/revocation/race proof |
| 5. Operator API and UI | 2–4 contracts | API owner + LiveView owner | Complete browser journey and REST parity |
| 6. Integration and removal audit | 1–5 | Integrator | Replacement suite, release smoke, legacy scan |

Do not wait until stage 6 to create the fake Agent or run race tests. UI components may be prepared against frozen contexts while stages 3–4 finish, but stage 5 is accepted only against the real contexts and protocol.

Stop at each bounded stage after its in-scope checks pass. Record the result and next stage. Do not turn an unrelated failure into an unplanned repair.

## Stage 0 — Prepare an implementation handoff

Files: the five documents linked above, `AGENTS.md`, and Git/worktree metadata only.

- [ ] Read the current design, requirements, architecture, and removal inventory completely.
- [ ] Inspect `git status --short --branch`, `git log -3 --oneline`, and `git worktree list --porcelain`.
- [ ] Ensure approved documentation is present at the implementation base. Preserve unrelated dirty changes; do not use a blanket stash/reset.
- [ ] Verify `.trees/` is ignored with `git check-ignore .trees/codex/agent-hub-rebuild`. If necessary add the scoped ignore entry.
- [ ] Create the implementation worktree using `git worktree add .trees/codex/agent-hub-rebuild -b codex/agent-hub-rebuild HEAD`, only if neither target exists.
- [ ] Compare the inventory with `git ls-files` in that worktree. Resolve every tracked deletion target before applying edits. Leave ignored build outputs and local data alone.
- [ ] Confirm available Elixir/OTP/PostgreSQL/Bun versions using the repository environment. Verify dependency constraints before changing toolchain pins.
- [ ] Confirm the installed Phoenix transport hook for capturing the Authorization header. The architecture defines the intended solution; its real transport test is mandatory.
- [ ] Record the exact two fresh databases in configuration: `samgita_hub_dev` and `samgita_hub_test`. Preserve optional test partition suffixes. Integration tests use `samgita_hub_integration_test`. Do not drop the old `samgita_dev`/`samgita_test` databases.

Commit checkpoint: `docs(agent-hub): define clean-start implementation contract`.

## Stage 1 — Replace the application foundation

This stage is deliberately one integration boundary: deleting legacy modules before removing their callers/configuration must not be left as a committed broken application.

### Task 1.1 — Remove legacy source and callers

Remove exactly the tracked legacy product files enumerated in the inventory:

- Entire tracked contents of `apps/samgita_provider/` and `apps/samgita_memory/`.
- Core Agent, project orchestration, provider, quality, legacy workers, DAG, Git/worktree, references, notification, webhook, feature, PRD, artifact, snapshot, and legacy Codex code.
- Their dedicated tests, old domain schemas other than the Project/Task files being rewritten, all old main migrations, legacy seeds, and imported runtime reference material.
- Legacy web controllers/JSON modules/LiveViews and their tests; replace shared routes/layout navigation in the same change.
- Legacy hooks and UI text in retained asset entrypoints.

- [ ] Expand inventory groups to actual tracked files and review the removal list.
- [ ] Apply file deletions with patches; do not recursively remove broad directories containing ignored local data.
- [ ] Rewrite `apps/samgita/lib/samgita.ex` as the Agent Hub module documentation and replace any old facade callers.
- [ ] Replace `apps/samgita_web/lib/samgita_web/router.ex` with browser dashboard and public health/info routes initially, plus the retained protected API pipeline.
- [ ] Replace dashboard content with a functional empty Agent Hub landing page and remove navigation to deleted surfaces.
- [ ] Remove obsolete PageHTML/home scaffolding only if its routes are removed; retain error rendering, Gettext, layouts, CSRF/session handling, and static assets.
- [ ] Remove legacy tests with removed behavior. Keep/rewrite health, API protection, layout, and error tests for retained behavior.

### Task 1.2 — Wire two applications and one Repo

Modify:

- `mix.exs`, `mix.lock`
- `apps/samgita/mix.exs`, `apps/samgita_web/mix.exs`
- `apps/samgita/lib/samgita/application.ex`
- `apps/samgita/lib/samgita/release.ex`
- `apps/samgita_web/lib/samgita_web/application.ex`
- `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs`, `config/prod.exs`
- `apps/samgita/test/support/data_case.ex`, `apps/samgita/test/test_helper.exs`
- `apps/samgita_web/test/support/conn_case.ex`, `apps/samgita_web/test/test_helper.exs`
- `devenv.nix`, Docker/Compose, CI/CD, release overlays, and formatter/analysis config as enumerated in the inventory.

- [ ] Remove the deleted umbrella apps from dependencies and release applications.
- [ ] Remove unused direct dependencies only after inspecting retained imports. Remove pgvector, Horde, provider/LLM/mail dependencies and configuration; retain JSON/crypto used by the new protocol.
- [ ] Start Repo, PubSub, and configured Oban in core; telemetry and Endpoint remain in web.
- [ ] Replace legacy Oban queues with one `maintenance` queue. Initially use no scheduled worker until stage 4 adds its module.
- [ ] Configure only `Samgita.Repo`; remove memory sandbox, Postgrex types, Mox provider setup, and old recovery flags.
- [ ] Use Oban manual testing for deterministic worker tests; disable production scheduling in tests.
- [ ] Add a new initial Oban migration at `apps/samgita/priv/repo/migrations/20260907000000_create_oban.exs` using the installed Oban migration API.
- [ ] Make seeds empty of legacy/demo product data and credentials.
- [ ] Replace the legacy README body with actual two-app setup and current implementation status; keep the approved docs as the target contract. Confirm CLAUDE.md and the repository constitution continue to point at the current guidance.
- [ ] Update release migration helpers to target only the main Repo.
- [ ] Remove pgvector from devenv and container/CI database services; align their database credentials with the options actually read by test config.
- [ ] Remove provider secrets/CLI installation from CI and release tooling. Keep unrelated dependency upgrades out of this stage.
- [ ] Install remaining dependencies using the existing installers, then update lockfiles only for resulting dependency changes.

Target core supervision shape:

```elixir
children = [
  Samgita.Repo,
  {Phoenix.PubSub, name: Samgita.PubSub},
  {Oban, Application.fetch_env!(:samgita, Oban)}
]
Supervisor.start_link(children, strategy: :one_for_one, name: Samgita.Supervisor)
```

Retain telemetry only where it measures Agent Hub or the underlying runtime. Remove legacy DNSCluster/libcluster setup in this milestone; remote Agent ownership and PostgreSQL coordination do not depend on a local-worker cluster.

### Task 1.3 — Prove the foundation

Rewrite tests:

- `apps/samgita_web/test/samgita_web/controllers/health_controller_test.exs`
- `apps/samgita_web/test/samgita_web/controllers/info_controller_test.exs`
- `apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs`
- Keep focused API-auth/rate-limit tests.

The health route returns a bounded JSON status with no provider/memory lookup. Info reports the Agent Hub product without legacy agent-type counts. Dashboard renders successfully against the fresh schema.

- [ ] Run `devenv shell -- mix compile --warnings-as-errors`; expect a successful two-app compile.
- [ ] Run `devenv shell -- mix ecto.create` and `devenv shell -- mix ecto.migrate` against the explicitly configured fresh database.
- [ ] Run `devenv shell -- mix test apps/samgita_web/test/samgita_web/controllers/health_controller_test.exs apps/samgita_web/test/samgita_web/controllers/info_controller_test.exs apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs apps/samgita_web/test/samgita_web/plugs`; expect zero failures.
- [ ] Run `devenv shell -- mix assets.build`; expect CSS and JS outputs.
- [ ] Check changed-file formatting and `git diff --check`.
- [ ] Review the complete staged deletion diff before committing.

Commit checkpoint: `refactor(agent-hub): replace legacy runtime with two-app foundation`.

## Stage 2 — Domain, credentials, and transactional commands

### Task 2.1 — Create the fresh domain schema

Create:

- `apps/samgita/priv/repo/migrations/20260907000001_create_agent_hub.exs`
- `apps/samgita/lib/samgita/domain/agent.ex`
- `apps/samgita/lib/samgita/domain/agent_credential.ex`
- `apps/samgita/lib/samgita/domain/agent_connection.ex`
- `apps/samgita/lib/samgita/domain/project_agent.ex`
- `apps/samgita/lib/samgita/domain/task_attempt.ex`
- `apps/samgita/lib/samgita/domain/protocol_receipt.ex`
- `apps/samgita/lib/samgita/domain/domain_event.ex`

Rewrite `domain/project.ex` and `domain/task.ex` under the same core source directory. Architecture is authoritative for fields, constraints, defaults, statuses, and foreign-key deletion policy.

Tests: `apps/samgita/test/samgita/domain/agent_hub_schema_test.exs`.

- [ ] Write tests proving positive capacity/timeout/attempt limits, capability validation, required Task fields, and all unique constraints.
- [ ] Run that test file to record failure before adding the schema.
- [ ] Create tables in FK-safe order. If Task holds a current-Attempt FK, add it after both tables exist.
- [ ] Add partial unique indexes for active connection/Attempt, and indexes for pending eligibility and lease/start/execution deadlines.
- [ ] Use immutable event/receipt write APIs and changesets that do not permit arbitrary terminal Attempt rewrites.
- [ ] Apply the migration to an empty database and rerun the schema test to zero failures.

Required database cases include two active Attempts rejected for one Task, a terminal Attempt coexisting with a new active one, duplicate Attempt sequence rejected, and dependent Project deletion rejected.

### Task 2.2 — Implement pure domain rules

Create:

- `apps/samgita/lib/samgita/agents/capability.ex`
- `apps/samgita/lib/samgita/tasks/state_machine.ex`
- `apps/samgita/lib/samgita/tasks/matcher.ex`
- `apps/samgita/lib/samgita/tasks/retry_policy.ex`

Tests mirror these paths under `apps/samgita/test/samgita/`.

- [ ] Write a table-driven test of every legal/illegal Task/Attempt transition in the architecture.
- [ ] Write capability tests for normalization, intersection, absent versus empty binding restriction, and subset matching.
- [ ] Write matcher tests for disabled/offline/unbound Agents, capability mismatch, capacity, and retry availability.
- [ ] Write retry tests for three total Attempts, server-owned error classification, and bounded backoff.
- [ ] Run these four test files to record their failures.
- [ ] Implement pure functions with explicit state and time inputs; no Repo, process state, or PubSub.
- [ ] Rerun all four files to zero failures.

Fixed retry calculation:

```elixir
def delay_seconds(attempt_no) when is_integer(attempt_no) and attempt_no > 0 do
  min(5 * Integer.pow(2, min(attempt_no - 1, 4)), 60)
end
```

The clamp avoids exponent growth for malformed/extreme stored counters while preserving the approved delay. Expose this as `Samgita.Tasks.RetryPolicy.delay_seconds/1`; test values 1 -> 5, 2 -> 10, 3 -> 20, 4 -> 40, and 5+ -> 60.

### Task 2.3 — Build public contexts and safe credentials

Create/rewrite:

- `apps/samgita/lib/samgita/projects.ex`
- `apps/samgita/lib/samgita/agents.ex`
- `apps/samgita/lib/samgita/agents/credentials.ex`
- `apps/samgita/lib/samgita/tasks.ex`
- `apps/samgita/lib/samgita/events.ex`
- `apps/samgita/test/support/agent_hub_fixtures.ex`

Tests: `projects_test.exs`, `agents_test.exs`, `tasks_test.exs`, `events_test.exs`, and `agents/credentials_test.exs` under `apps/samgita/test/samgita/`.

- [ ] Write Project CRUD and dependent-deletion tests.
- [ ] Write Agent registration/edit/enable/disable and unique binding tests.
- [ ] Write task creation/idempotency tests, including identical key+input replay and conflicting key+input rejection.
- [ ] Write credential issue/authenticate/expiry/revoke/rotation-overlap tests and prove plaintext is absent from ordinary reads and events.
- [ ] Write a rollback test that forces event insertion failure and proves its aggregate change also rolls back.
- [ ] Implement the context surface and return/error forms defined in architecture; do not let web consumers use schemas to bypass contexts.
- [ ] Generate high-entropy machine secrets using `:crypto.strong_rand_bytes/1`, store hashes only, and expose plaintext only in the issue result.
- [ ] Implement bounded pagination and preload current Agent/Attempt relations for list/detail reads.
- [ ] Run the five context files and credentials file; expect zero failures.

Commit checkpoints: `feat(agent-hub): add durable domain and constraints`, then `feat(agent-hub): add projects agents and task commands`.

## Stage 3 — Real transport and atomic execution

### Task 3.1 — Freeze fixtures and authenticate real connections

Create:

- `apps/samgita/lib/samgita/protocol.ex`
- `apps/samgita/lib/samgita/protocol/envelope.ex`
- `apps/samgita/lib/samgita/agents/connections.ex`
- `apps/samgita_web/lib/samgita_web/agent_socket.ex`
- `apps/samgita_web/lib/samgita_web/agent_channel.ex`
- `apps/samgita_web/lib/samgita_web/agent_socket_auth.ex` (HTTP-upgrade header bridge; stage 0 proves its adapter wiring).
- `apps/samgita_web/test/support/fake_agent.ex`
- `apps/samgita_web/test/fixtures/agent_protocol/` with one named JSON fixture per message/response and invalid examples.

Modify `apps/samgita_web/lib/samgita_web/endpoint.ex`, runtime/test config, and the web test-only dependency list if a WebSocket client is required.

Tests: `apps/samgita/test/samgita/protocol/envelope_test.exs`, `apps/samgita_web/test/samgita_web/channels/agent_channel_test.exs`, and `apps/samgita_web/test/samgita_web/integration/agent_transport_test.exs`.

- [ ] Write envelope fixtures using architecture's canonical Phoenix frame mapping and error catalog.
- [ ] Write a real HTTP-upgrade test for Authorization authentication, missing/invalid credentials, and no secret query parameters.
- [ ] Write join-topic identity, protocol-version, hello-required, and same-channel hello replay tests.
- [ ] Implement transport extraction, socket authentication, and thin channel delegation.
- [ ] Implement hello/welcome with one current connection and a channel-scoped hello identity; replacing connections is transactional.
- [ ] Add payload byte limits before business processing and bounded authentication-failure handling.
- [ ] Make FakeAgent connect/join/hello over a real WebSocket; expose deterministic send, receive, disconnect, reconnect, and message replay helpers.
- [ ] Run the three scoped files. The integration test must bind a loopback endpoint and use a dedicated database, not silently replace a running development endpoint.

### Task 3.2 — Implement receipts and replay before mutating messages

Create `apps/samgita/lib/samgita/protocol/inbox.ex`.
Tests: `apps/samgita/test/samgita/protocol/inbox_test.exs`.

- [ ] Test identical message replay, conflicting semantic payload, reconnect with changed connection identity, sequence conflict/gap, and failed transaction retry.
- [ ] Implement deterministic semantic hashing per architecture. Connection authorization is rechecked separately; replacing a transport connection must not make an otherwise identical semantic message conflict.
- [ ] Persist response descriptors without credentials/lease tokens.
- [ ] Authenticate current sender before replay, then replay committed receipts before checking mutable Attempt state.
- [ ] Make simultaneous identical messages serialize without duplicate events or Attempts.
- [ ] Run the Inbox test file to zero failures.

### Task 3.3 — Claim and complete a Task

Create:

- `apps/samgita/lib/samgita/tasks/claim.ex`
- `apps/samgita/lib/samgita/tasks/lease.ex`
- `apps/samgita/lib/samgita/tasks/transitions.ex`

Tests: `apps/samgita/test/samgita/tasks/claim_test.exs`, `lease_test.exs`, `transitions_test.exs`, and `apps/samgita_web/test/samgita_web/integration/agent_execution_test.exs`.

- [ ] Write one integration scenario: create Project/Agent/credential/binding/Task, connect, request work, start, progress, complete, read Task/Attempt/events.
- [ ] Test unauthorized claims, no eligible work, capacity, deterministic task ordering, and lost assignment response.
- [ ] Implement Agent-first locking and indexed Task selection with `SKIP LOCKED`.
- [ ] Derive versioned lease tokens from stable Attempt facts and runtime keyring; compare hashes/tokens safely and never persist response plaintext.
- [ ] Implement start/progress/complete/fail with receipt+state+event atomicity.
- [ ] On throttled progress, commit sequence/receipt as a no-op without a progress event.
- [ ] On completion, require running state and valid lease/fence; duplicate completion replays the original ACK after terminal state.
- [ ] Extend FakeAgent with a deterministic executor that returns a fixture result and never invokes an LLM.
- [ ] Run the three core files and execution integration file; expect the complete fake-Agent workflow to pass.

Commit checkpoints: `feat(protocol): authenticate and reconcile agent connections`, `feat(protocol): persist idempotent receipts`, `feat(tasks): execute fenced task attempts`.

## Stage 4 — Recovery, deadlines, and concurrency

Create `apps/samgita/lib/samgita/workers/lease_reaper.ex`.
Modify `Agents.Connections`, `Agents.Credentials`, `Tasks.Lease`, `Tasks.Transitions`, `AgentChannel`, and Oban configuration.

Tests:

- `apps/samgita/test/samgita/workers/lease_reaper_test.exs`
- `apps/samgita/test/samgita/tasks/concurrency_test.exs`
- `apps/samgita_web/test/samgita_web/integration/agent_recovery_test.exs`
- `apps/samgita_web/test/samgita_web/integration/agent_security_test.exs`

- [ ] Test a leased Attempt missing `start_due_at`, an expired ownership lease, and a running Attempt reaching `execution_deadline_at`.
- [ ] Implement heartbeat renewal bounded by current deadline and include valid/invalid reconciliation in its response.
- [ ] Schedule reaping every minute on the maintenance queue. Fetch bounded candidates without out-of-order locks, then lock/revalidate in the global order.
- [ ] Test repeated worker delivery creates one expiry transition and retry availability; exhausted budget becomes failed.
- [ ] Implement reconnect rebind for valid Attempts, stop responses for invalid Attempts, and credential/Agent invalidation.
- [ ] Test an old socket cannot mutate after replacement/revocation even if PubSub disconnect delivery is lost.
- [ ] Test a lost terminal ACK can replay after reconnect without changing the terminal event.
- [ ] Test simultaneous Agent claims for one Task, simultaneous requests for one Agent slot, authorization changes versus claim, replacement versus status, and renewal versus reaping using independent transactions.
- [ ] Test restart by stopping/restarting a dedicated application instance while preserving its database and FakeAgent durable pending-message fixture.
- [ ] Test signing-key rollover: old key remains usable for its existing Attempt, new Attempts use the current key.
- [ ] Capture logs and inspect events/receipts for planted credential and token canaries.
- [ ] Run the four files to zero failures; keep short deadlines controlled by test inputs/fixtures instead of minute-long sleeps.

Concurrency tests cannot use a single shared sandbox connection as evidence of locking. Use a separate integration database and independent connections, with deterministic fixture cleanup in that database only.

Commit checkpoint: `feat(agent-hub): recover expired and disconnected work safely`.

## Stage 5 — Operator API and UI

### Task 5.1 — REST surface

Rewrite Project/Task controllers and JSON serializers. Create Agent, Credential, Connection, Binding, Attempt, and Event read/control endpoints with the exact route table in architecture. Update router, changeset/fallback JSON only for the new context results.

Owning directory: `apps/samgita_web/lib/samgita_web/controllers/`.
Tests: corresponding files in `apps/samgita_web/test/samgita_web/controllers/`, plus retained plug tests.

- [ ] Write request tests for every approved route and each command's validation/conflict/not-found errors.
- [ ] Prove API credentials/rate limiting protect new admin endpoints while Agent sockets have independent mandatory machine auth.
- [ ] Implement controllers delegating only to the public contexts.
- [ ] Return one-time credential plaintext only from issue, with `Cache-Control: no-store`.
- [ ] Bound pagination and reject cross-Project detail access when URL identifiers disagree.
- [ ] Assert deleted PRD/legacy execution routes return not found.
- [ ] Run the controller and plug directories; expect zero failures.

### Task 5.2 — Complete the LiveView journey

Rewrite:

- `apps/samgita_web/lib/samgita_web/live/dashboard_live/index.ex` and template
- `apps/samgita_web/lib/samgita_web/live/agents_live/index.ex` and template
- `apps/samgita_web/lib/samgita_web/live/project_form_live/index.ex` and template
- `apps/samgita_web/lib/samgita_web/live/project_live/index.ex` and template

Create Agent detail, Project list, Task form, and Task detail LiveViews under `live/agent_live/`, `live/projects_live/`, `live/task_form_live/`, `live/task_live/`, each with `index.ex` and `index.html.heex`.

Modify router and layouts. Limit CSS/TypeScript edits to required DuskMoon behavior and removal of legacy hooks.

Tests mirror each LiveView under `apps/samgita_web/test/samgita_web/live/`.

- [ ] Write the complete operator journey with real contexts: register, issue credential, bind Project, create Task, observe fake Agent progress/result.
- [ ] Implement dashboard counts, Agent presence/history, capability/capacity editing, bindings, Task form/detail, and audit pagination.
- [ ] Implement one-time credential presentation without URL/session persistence; clear it when dismissed or leaving the view.
- [ ] Add subscription/reload behavior after successful commits. Reconnect reads current state from PostgreSQL.
- [ ] Render eligibility/retry reasons, validation errors, and empty states; omit deferred action controls.
- [ ] Use accessible DuskMoon components and responsive operational layouts.
- [ ] Run `devenv shell -- mix test apps/samgita_web/test/samgita_web/live` and `devenv shell -- mix assets.build`.
- [ ] Verify the entire browser journey at desktop and narrow viewport sizes against the real fake-Agent connection. Record endpoint and evidence.

Commit checkpoints: `feat(api): expose agent hub operations`, `feat(web): deliver agent hub operator workflow`.

## Stage 6 — Replacement-system verification and handoff

Modify only files needed for the approved rebuild: CI/CD, Docker/release overlays, README/CLAUDE guidance, and any in-scope defects exposed by these checks. Current approved docs remain authoritative.

- [ ] Run a retained-dependency audit; remove unused packages only when no retained/new module consumes them.
- [ ] Scan tracked runtime/config/test/assets/tooling paths for `SamgitaMemory`, `SamgitaProvider`, `Horde`, `AgentRun`, `Project.Orchestrator`, `CodexAppServers`, `pgvector`, and old queues. Expected zero operational references; historical removal docs may mention them.
- [ ] Verify no hidden CLAUDE/skill commands, release app lists, seeds, scripts, or README links invoke the removed product.
- [ ] Run `devenv shell -- mix format --check-formatted`.
- [ ] Run `devenv shell -- mix compile --warnings-as-errors`.
- [ ] Run `devenv shell -- mix test apps/samgita/test apps/samgita_web/test`, including the dedicated real-transport integration profile defined in test config.
- [ ] Run `devenv shell -- mix credo --strict` and `devenv shell -- mix dialyzer`; report actual outcomes and any blocker rather than claiming unrun checks.
- [ ] Run `devenv shell -- mix assets.deploy`.
- [ ] Build `devenv shell -- env MIX_ENV=prod mix release samgita` and boot the resulting release against an explicitly fresh database on a non-conflicting loopback port. Prove migration, health response, one fake-Agent execution, and clean shutdown.
- [ ] Measure work-request latency with 100 fake connections and 1,000 pending Tasks on the test environment. Use a warmed run and report p50/p95; target p95 <= 500 ms excluding network latency, with no invariant violations.
- [ ] Record migrations, routes, modules, tests, runtime evidence, dependency removal, and limitations in the final handoff.
- [ ] Stop. No real Synapsis, GitHub workflows, cancellation/manual retry, providers, memory, or artifact implementation follows automatically.

Commit checkpoint: `test(agent-hub): verify clean-start release and recovery`.

## Requirement-to-stage traceability

| Approved requirement | Stage and decisive test |
|---|---|
| Two apps; no legacy source/runtime | 1 and 6: compile, source scan, release boot |
| Fresh database; nine domain tables | 2: migration and schema constraints |
| Project identity and safe CRUD | 2 and 5: context/controller/LiveView journey |
| Credentials, binding, capacity, capabilities | 2–4: auth, eligibility, concurrent capacity |
| One active connection and Attempt | 2–4: unique indexes plus replacement/claim races |
| Lease/fence/start/execution deadlines | 3–4: stale result and three independent deadlines |
| Receipt replay and ordering | 3–4: conflict, no-op progress, lost ACK/reconnect |
| Atomic events and post-commit refresh | 2–5: rollback and LiveView reload |
| Retry exhaustion and restart recovery | 4: reaper/restart integration |
| UI and API usable without direct DB access | 5: complete operator journey |
| Fake Agent; no LLM requirement | 3–6: real transport fixture execution |
| Secret protection | 2–5: canary scans, issue response, revocation |
| Release/dev/CI no legacy requirements | 1 and 6: plain PostgreSQL and two-app artifact |

## Handoff format

For each completed stage report:

1. Scope completed and exact commit(s), if created.
2. Files/modules removed, rewritten, and added.
3. Migrations and public/protocol contracts implemented.
4. Commands run and results; distinguish tests from inspection.
5. Known blockers or unrelated failures.
6. Next bounded stage and its owner boundary.

Document-only planning does not count as implementation completion. Check off tasks only after their observable verification gate passes.
