# Repository Guidelines

## Approved Product Direction

Samgita is becoming an agent-neutral, single-tenant project and task management platform. It registers Agents and Projects, connects repositories and GitHub, validates authoritative task state, and emits scheduled and external events. Registered Agents own reasoning, planning, delegation, and execution. Synapsis, Sigma, and Codex have the same registration and authorization rules.

The authoritative requirements are:

- `docs/redesign/design.md`: domain ownership, protocol boundaries, subsystem inventory, migration mapping, and security contracts.
- `docs/redesign/implementation-plan.md`: bounded stages, file ownership, rollback, blockers, and verification gates.
- `docs/redesign/acceptance.md`: review checklist and executable acceptance scenarios.

These documents supersede conflicting clean-start, deletion, unique-`git_url`, fixed-lifecycle, and centralized-transport requirements in `docs/prd.md`, `docs/plan.md`, `docs/agent-hub-rebuild-design.md`, and `docs/agent-hub-removal-inventory.md`. Those files remain historical proposals; do not execute their removal checklists. `docs/architecture.md` describes the current implementation and links to its historical version.

P5 management UI, local redesign qualification and the subsequent scoped reliability repair are recorded in `docs/redesign/qualification.md`. This repair includes fake-Agent journeys, isolated consumers, restart/rollback, populated-database repeats and required aggregate release checks. Commit and push the scoped result. Raw LiveView telemetry exposes secret parameters; real HTTP evidence also shows credential-bearing Bandit metadata before application Plugs. A11 remains blocked even when build checks pass; see `docs/codex-app-server/repair-qualification.md`. Moving a form into a controller or early Plug cannot close that boundary. Release only if applicable gates pass and an existing normal publication workflow succeeds; do not tag a failing build. See the phase records for the existing domain, coordination and read/event-only GitHub contracts. Do not provision a real GitHub App, enter real credentials, change remote permissions, create live webhooks, enable GitHub writes, edit sibling services, migrate production, delete historical data or deploy. Existing records and references must be preserved. Retiring legacy execution behavior does not authorize deleting its data or migration history.

Merged baseline: `d6e9eca` combines redesign documentation `3a344f5` with the separately authorized clean-start source refactor `811eeb9`. That refactor removed legacy source and migration files, leaving a two-app foundation. This merge is not evidence of a database migration, historical-data deletion, or history continuity. P3 restores only main migration sources verbatim from `2bc3765ac94e1faea50f061b6938c0ef51e6f92b`, accounts for memory migration sources in fixtures, and adds the neutral domain. Restore no legacy runtime. P3 clears B0 for its local fixture scope; actual deployment inventory, legacy-writer exclusion and full memory/backup rehearsal remain cutover gates. Do not apply the historical P1 callsite list to absent modules.

The current authorized goal is complete client/driver compatibility with immutable Codex `rust-v0.163.0`, as specified by `samgita-codex-full-compatibility-goal.txt` and its accompanying plan. This supersedes the previous Codex subset as the final target, while preserving the neutral platform and reliability contracts. Track all phases and entry-specific evidence in `docs/codex-app-server/`; schema forwarding, synthetic fixtures and passing old tests do not prove full behavior. Continue through the plan without phase approval. Use the existing branch; do not create branches/worktrees. Commit and push logical scoped units. Keep unavailable external/platform success profiles and A11 visibly incomplete; no fabricated full-compatibility, publication or production-readiness claim. Only explicitly owned disposable Codex processes and isolated synthetic fixtures are authorized during qualification; no paid or production tasks.

Current verification restriction from the user: do not run any security or permission-related tests. This includes credential/authentication/authorization/approval tests, audits and broad suites or automatic hosted workflows that execute them. Run only reviewed functional checks; preserve existing tests and required gates, record prohibited checks as unrun/incomplete, and suppress automatic CI when pushing under this restriction. It does not authorize weakening access controls or claiming blocked acceptance complete.

Ordinary owned Codex functional qualification launches default to fixed yolo configuration: `approval_policy="never"` and `sandbox_mode="danger-full-access"`. Keep permission behavior outside these checks; the verification restriction above still applies.

## Target Umbrella

- `apps/samgita_protocol`: independently reusable protocol core, versioned schemas, capability negotiation, correlation, client dispatch, handler contracts and bounded replay. No platform/Repo/Phoenix/Backplane dependency, configuration inheritance or automatic listener/runtime startup.
- `apps/samgita_protocol_websocket`: optional standalone authenticated WebSocket transport and explicitly started in-memory fake Agent at `/app-server`.
- `apps/samgita_protocol_codex`: independently reusable pinned Codex native wire/schema layer plus the existing neutral convenience adapter. Full behavior qualification is tracked separately; source/schema conformance does not establish full compatibility.
- `apps/samgita_codex_driver`: independently reusable, explicitly started Codex sessions and transports under implementation. No Repo, Phoenix, platform configuration, automatic execution or listener dependency. Borrowed service resources remain owned by their service.
- `apps/samgita`: Ecto Repo, Projects, repositories/GitHub, Agents, Tasks/Attempts, events, schedules, and durable delivery/maintenance with Oban.
- `apps/samgita_web`: existing Phoenix endpoint, REST API, protocol host adapter, GitHub ingress, and DuskMoon LiveView operator UI.

Dependency direction is web -> core -> protocol, with optional web -> transport integration. Core must never depend on web. The protocol and driver projects intentionally omit umbrella build/dependency/config inheritance; run their commands from their own directories. The root's explicit two-app list remains unchanged; core consumes the protocol as a path dependency. Protocol consumers can build outside this repository without starting Samgita. Actual Sigma/Synapsis endpoints remain in their existing services; do not create another Sigma server process or require all traffic to pass through Samgita.

The redesign inventory describes the historical baseline. Its runtime stays absent; its main migration sources are restored without executors. P4 enables only `hub_events`, `hub_schedules`, `hub_maintenance` and `hub_github`, with schedule/coordination/GitHub-read Cron wakeups. Legacy workers/queues remain excluded; old hooks enter a disabled quarantine queue and enqueue failures propagate. P3 intents without P4 approval remain inert. Where a deployment still runs legacy code, fence and drain its producers and external effects before cutover. Preserve historical PRDs, runs, messages, artifacts, snapshots, memory records and references; do not copy dead runtime source into archives.

## Architecture Rules

- PostgreSQL is authoritative for durable state. Channels and PubSub cannot confer work ownership.
- A Task is logical work; an Attempt is one execution. Keep their states separate.
- Attempt success submits a Task to `awaiting_review`; explicit review and acceptance decisions produce `accepted`. Reports, artifacts and capabilities cannot confer acceptance.
- Stable Agent identity, authenticated connection generation and external execution session are separate records. Roles belong to Project membership; capabilities never grant authorization.
- Samgita enforces ownership and legal management transitions; it does not prescribe development phases, choose an Agent's reasoning loop, or automatically decompose PRDs.
- Use pure functions for transitions, capability matching, and retry calculations. Create processes only for a runtime need.
- Claims serialize Agent capacity and lock eligible Tasks. Use leases and monotonic fencing tokens, with database uniqueness for active Attempts.
- Follow the authority fence and global lock order in `docs/redesign/design.md` for all competing commands. Legacy and new execution must never be active simultaneously.
- Commit aggregate changes, audit events, and protocol receipts atomically. Broadcast only after commit.
- Delivery is at least once. Lost ACKs/handler leases require stable-operation status reconciliation; no reconnect/timeout may launch execution. Explicit recovery keeps event identity/time and records duplicate-effect risk. Transport receipt, durable notification acceptance, processing completion and Task acceptance are separate.
- Use Oban for durable scheduling, delivery, and expiry maintenance; PubSub is best-effort notification. A scheduled or external event does not itself authorize execution or a Task transition.
- Keep core commands out of Channel/controller callbacks. Transport delegates to contexts.
- Keep existing Project UUIDs canonical and unchanged. Repository identity and URL aliases belong to separate repository associations; `git_url` is preserved legacy provenance, not the new Project identity.
- Use additive migrations and resumable, audited mappings. Do not replace initial migrations, rekey Projects, merge Projects by URL, or silently replay legacy work.
- Future integration gates require an operator journey, a real-WebSocket fake Agent, protocol-package isolation, and migration/rollback rehearsals. No external LLM is needed for those checks.

## Security and Scope

The deployment is single-tenant. Do not add browser accounts, authentication, organizations, or RBAC. Browser access is protected by infrastructure; retain REST API key protection and rate limits. Agent transport always requires machine credentials.

Never persist or log plaintext Agent credentials or lease proofs. P3 accepts operator-supplied credentials and returns only metadata, with `no-store`; there is no plaintext credential response. P4 outbound service credentials are external runtime references, separate from inbound machine credentials. Approve exact Agent URLs and pinned destination addresses; use WSS remotely. Credential reference names must be immutable/versioned; rotation requires a new reference and reviewed routing/replay. Proof retrieval is explicit, owner-authorized and non-cacheable; proofs never enter receipts/events. Runtime lease keys are external to the database. Protocol/audit logging uses allowlisted metadata. Validate current credentials, connection ownership, membership and execution epoch before replay.

GitHub integration verifies raw-body signatures and approved installation/repository-to-Project mappings before atomic inbox/event/job persistence. Payload Project/Agent IDs cannot select routing. Current external projections and immutable source evidence are separate; Issue/PR/check state never confers Task acceptance. Treat text as untrusted input. Keep GitHub code outside protocol packages. GitHub uses versioned external secret references and approved pinned API destinations; only token authentication may POST remotely, with repository-restricted read-only tokens. Comments, PR creation, merge and workflow execution remain disabled. Real GitHub/Agent-service integration requires explicit security/conformance gates. Embedded providers/execution, memory retrieval, new artifact storage, and a browser account system are outside this redesign. Historical records remain accessible under existing infrastructure boundaries.

## Frontend

Use Phoenix LiveView, Tailwind CSS 4, Bun, TypeScript, and the existing DuskMoon family.

- Prefer `phoenix_duskmoon` components and existing `@duskmoon-dev/*` assets.
- Do not introduce DaisyUI or another component library.
- Do not vendor or patch DuskMoon internals.
- Keep views operational, accessible, responsive, and consistent.
- Use pagination, preloads, empty/error states, and visible form validation.
- Verify UI changes with focused LiveView tests and `mix assets.build`; perform browser proof for the full operator journey.

## Commands and Tests

Run from the repository/worktree root. Use `devenv shell --` when the host lacks the required Elixir/OTP environment.

```bash
mix deps.get
mix compile --warnings-as-errors
mix ecto.create
mix ecto.migrate
mix phx.server
mix test apps/samgita/test/samgita/projects_test.exs
mix test apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs
mix assets.build
mix format --check-formatted
mix credo --strict
mix dialyzer
```

The redesign plan defines stage-specific tests. P3's scope is in `docs/redesign/domain-phase-3.md`; P4's scoped checks are in `coordination-phase-4.md` and `github-phase-4.md`. GitHub checks use deterministic signed fixtures, a loopback fake server and isolated PostgreSQL. Protocol tests still run independently from their own directories, with no database/platform/config dependency; the core's `scripts/verify_standalone.py` proves an outside consumer. This qualification phase also runs the retained aggregate CI/release checks against final code. Report unrelated failures without repairing them or weakening gates. Format changed Elixir files in the verified test environment, excluding the verbatim pinned migration sources.

The audited legacy system had main and memory Repos sharing a database; the current application has only the main Repo. P3's source hash manifest accounts for both migration sets. Its history rehearsal includes an opaque memory sentinel; it does not certify a real pgvector/dual-Repo deployment. Concurrency tests use independent transactions and verify distinct PostgreSQL backend PIDs. WebSocket/restart/migration tests use explicitly isolated databases/endpoints with legacy side effects disabled.

Use explicitly named scratch databases and sanitized legacy fixtures/copies for migration rehearsals. `SAMGITA_TEST_DATABASE` overrides must match `samgita_redesign_*_test` (optional numeric partition). Never run `mix ecto.reset` against an unresolved/shared target. All redesign phases authorize only isolated local test databases, with no production migration or historical-data deletion.

For each scoped stage, modify only listed files, run scoped tests, and stop when its checklist and tests pass. Report unrelated failures and stop rather than repairing outside scope. Remove obsolete tests only when their owning product behavior is removed; do not delete failing tests for retained behavior.

## Delivery and Parallelism

- Default to parallel agents for independent work, after shared contracts are fixed.
- Keep migrations/shared configuration under one owner.
- Give each agent non-overlapping file ownership.
- Use small bounded stages and logical commits; do not combine the rebuild into one opaque change.
- Keep the application bootable at integration checkpoints.
- Use `apply_patch` for edits and resolve tracked-file deletion targets before removing them.
- Preserve user changes, ignored local data, and unrelated worktrees.

## Git and Worktrees

Place worktrees in this project's `.trees/<branch-name>` directory; use the `codex/` branch prefix unless instructed otherwise. Base the redesign on the current local HEAD, including its documentation commits.

Use Conventional Commits. Do not include "Generated with Claude Code" or a "Co-Authored-By: Claude" trailer. Stage explicit logical units. Do not push, publish PRs, or deploy unless requested.

## Upstream Dependency Issue Routing

For dependency bugs or missing features in GitHub organizations `gsmlgorg`, `gsmlg-dev`, `duskmoon-dev`, `gsmlg-app`, `Gao-OS`, `gsmlg-opt`, `gsmlg-ci`, `gsmlg-games`, or `gsmlg-com`:

1. Identify the source repository from the package manifest or lockfile.
2. Create an issue with `gh issue create`, type `Bug` or `Feature`, label `internal request` (create if missing), and title `[internal] <concise description>`.
3. Include requesting repo and branch from Git, the need and reason, reproduction or expected behavior, and severity: `blocker`, `needed`, or `nice-to-have`.
4. For blockers, add `# TODO(upstream): org/repo#issue_number` at the callsite and stop that task. Continue only independently unblocked work; resume after the dependency is fixed and updated.
5. For non-blockers, mark a narrow temporary solution with `# WORKAROUND(upstream): org/repo#issue_number`.

Do not silently work around upstream defects.

## Coding Discipline

State assumptions, keep changes scoped, and prefer the smallest implementation satisfying the approved requirements. No speculative abstractions or unrelated refactoring. Format changed Elixir files. Remove only infrastructure/dependencies made obsolete by this rebuild; inspect shared consumers before deletion.

Verification must demonstrate behavior: state transitions, database effects, real protocol responses, and UI results. A successful compilation or running process alone does not establish milestone completion.

## Agent Note

Agent Note project: samgita

Use the shared `agent-note` skill for reviewer-first project engineering knowledge.
Before substantial design or debugging, recall relevant project notes.
At accepted decisions, significant implementation boundaries, or reproducible
blocker handoffs, evaluate durable findings and create/update notes only when the
skill's quality gate passes. For meaningful implementations, maintain a coherent
human-reviewable explanation of architecture, design rationale, actual behavior,
verification and limits; do not save a separate task-status note after each fix. This authorizes scoped capture, not whole-project curation or deletion.
No note is required for an ordinary completed task.
Contributors return candidates; the coordinating agent writes shared notes.
Apply recalled guidance only after checking its sources and target-version scope.
If the skill or MCP is unavailable, report the limitation without claiming a write.
