# Repository Guidelines

## Approved Product Direction

Samgita is becoming an agent-neutral, single-tenant project and task management platform. It registers Agents and Projects, connects repositories and GitHub, validates authoritative task state, and emits scheduled and external events. Registered Agents own reasoning, planning, delegation, and execution. Synapsis, Sigma, and Codex have the same registration and authorization rules.

The authoritative requirements are:

- `docs/redesign/design.md`: domain ownership, protocol boundaries, subsystem inventory, migration mapping, and security contracts.
- `docs/redesign/implementation-plan.md`: bounded stages, file ownership, rollback, blockers, and verification gates.
- `docs/redesign/acceptance.md`: review checklist and executable acceptance scenarios.

These documents supersede conflicting clean-start, deletion, unique-`git_url`, fixed-lifecycle, and centralized-transport requirements in `docs/prd.md`, `docs/architecture.md`, `docs/plan.md`, `docs/agent-hub-rebuild-design.md`, and `docs/agent-hub-removal-inventory.md`. Those files remain historical proposals; do not execute their removal checklists.

The current authorized phase is design and migration planning only. Do not implement the redesign, migrate production, delete historical data, or start the next stage automatically. Existing records and references must be preserved. Retiring legacy execution behavior does not authorize deleting its data or migration history.

Merged baseline: `d6e9eca` combines redesign documentation `3a344f5` with the separately authorized clean-start source refactor `811eeb9`. That refactor removed legacy source and migration files; the checkout now contains only the two-app foundation, without the planned domain/protocol implementation. This merge is not evidence of a database migration, historical-data deletion, or history continuity. Legacy evidence is pinned to `2bc3765ac94e1faea50f061b6938c0ef51e6f92b` in the design. Resolve its B0 source/migration reconciliation gate before implementing the redesign; do not automatically restore removed runtime code or apply the historical P1 callsite list.

## Target Umbrella

- `apps/samgita_app_server` (planned): independently reusable app-server protocol, schemas, capability profiles, request/event handling, and host/transport contracts. No dependency on Samgita core, its Repo, web application, providers, or Backplane; no automatic endpoint or Agent runtime startup.
- `apps/samgita`: Ecto Repo, Projects, repositories/GitHub, Agents, Tasks/Attempts, events, schedules, and durable delivery/maintenance with Oban.
- `apps/samgita_web`: existing Phoenix endpoint, REST API, protocol host adapter, GitHub ingress, and DuskMoon LiveView operator UI.

Dependency direction is web -> core and web -> app-server protocol. Core must never depend on web. Protocol consumers can use the protocol package without starting Samgita. Actual Sigma/Synapsis endpoints remain in their existing services; do not create another Sigma server process or require all traffic to pass through Samgita.

The redesign inventory describes the historical baseline; its legacy runtime and migration paths are absent from the merged checkout. Where a deployment still runs that legacy system, fence and drain PRD orchestration, local workers, RARV, swarms, automatic DAG execution, quality councils, provider sessions, and local Codex launchers before cutover. Preserve historical PRDs, runs, messages, artifacts, snapshots, memory records and their references. B0 must reconcile the removed source/migrations with the required preservation/read path before further changes; do not copy dead source into archive directories.

## Architecture Rules

- PostgreSQL is authoritative for durable state. Channels and PubSub cannot confer work ownership.
- A Task is logical work; an Attempt is one execution. Keep their states separate.
- Samgita enforces ownership and legal management transitions; it does not prescribe development phases, choose an Agent's reasoning loop, or automatically decompose PRDs.
- Use pure functions for transitions, capability matching, and retry calculations. Create processes only for a runtime need.
- Claims serialize Agent capacity and lock eligible Tasks. Use leases and monotonic fencing tokens, with database uniqueness for active Attempts.
- Follow the authority fence and global lock order in `docs/redesign/design.md` for all competing commands. Legacy and new execution must never be active simultaneously.
- Commit aggregate changes, audit events, and protocol receipts atomically. Broadcast only after commit.
- Use Oban for durable scheduling, delivery, and expiry maintenance; PubSub is best-effort notification. A scheduled or external event does not itself authorize execution or a Task transition.
- Keep core commands out of Channel/controller callbacks. Transport delegates to contexts.
- Keep existing Project UUIDs canonical and unchanged. Repository identity and URL aliases belong to separate repository associations; `git_url` is preserved legacy provenance, not the new Project identity.
- Use additive migrations and resumable, audited mappings. Do not replace initial migrations, rekey Projects, merge Projects by URL, or silently replay legacy work.
- Future integration gates require an operator journey, a real-WebSocket fake Agent, protocol-package isolation, and migration/rollback rehearsals. No external LLM is needed for those checks.

## Security and Scope

The deployment is single-tenant. Do not add browser accounts, authentication, organizations, or RBAC. Browser access is protected by infrastructure; retain REST API key protection and rate limits. Agent transport always requires machine credentials.

Never persist or log plaintext Agent credentials or lease tokens. Credential creation responses are one-time and non-cacheable. Protocol/audit logging uses allowlisted metadata. Validate connection ownership even on replay.

GitHub repository connection and event ingestion are in the redesign; GitHub Actions/workflow execution is not implied. Real Agent-service integration requires explicit protocol and security conformance gates. Embedded providers/execution, memory retrieval, new artifact storage, and a browser account system are outside this redesign. Historical records remain accessible under existing infrastructure boundaries.

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

The redesign plan defines when these paths exist and which tests belong to each stage. This documentation phase uses document, link, scope, and diff checks only. Do not run full legacy tests as a redesign baseline. Use focused tests for each authorized implementation stage and the new/retained integration suite only at its final gate.

The audited legacy system had main and memory Repos sharing a database; the merged foundation has only the main Repo and a new Oban migration. Dual-Repo coverage and historical-reader requirements apply to migration sources, not existing checkout applications. B0 must account for both historical migration sets and their data before defining the implementation/test wiring. Concurrency tests must exercise independent database transactions; a shared sandbox connection does not prove locking correctness. WebSocket/restart/migration tests use explicitly isolated databases and endpoints with legacy side effects disabled.

Use explicitly named scratch databases and sanitized legacy fixtures/copies for migration rehearsals. Never run `mix ecto.reset` against an unresolved or shared target. No production migration or historical-data deletion is authorized by the documentation phase.

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
