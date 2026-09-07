# Repository Guidelines

## Approved Product Direction

Samgita is being rebuilt as an external Agent Hub control plane. The user approved an in-place clean start: the app has never been used, existing data does not need migration, and legacy product code must be removed safely.

The authoritative requirements are:

- `docs/prd.md`: first-milestone product requirements and acceptance scenarios.
- `docs/architecture.md`: domain, protocol, transaction, and transport contracts.
- `docs/plan.md`: bounded implementation stages and verification gates.
- `docs/agent-hub-rebuild-design.md`: approved design and scope decisions.
- `docs/agent-hub-removal-inventory.md`: inspected removal/retention boundaries.

The source tree may still contain the legacy implementation while the rebuild is in progress. Its presence does not require preserving its behavior. Do not reintroduce legacy compatibility requirements from Git history.

## Target Umbrella

- `apps/samgita`: Ecto Repo, Projects, Agents, Tasks, Protocol, Events, and durable maintenance with Oban.
- `apps/samgita_web`: Phoenix endpoint, REST API, Agent WebSocket/Channels, DuskMoon LiveView operator UI.

Dependency direction is web -> core. Core must never depend on web.

Remove `samgita_provider`, `samgita_memory`, PRD orchestration, local execution workers, Horde, provider sessions, RARV, swarms, DAG execution, quality councils, legacy Codex management, and their dedicated configuration, dependencies, migrations, tests, routes, and assets. Preserve Git history; do not retain dead source in archive directories.

## Architecture Rules

- PostgreSQL is authoritative for durable state. Channels and PubSub cannot confer work ownership.
- A Task is logical work; an Attempt is one execution. Keep their states separate.
- Use pure functions for transitions, capability matching, and retry calculations. Create processes only for a runtime need.
- Claims serialize Agent capacity and lock eligible Tasks. Use leases and monotonic fencing tokens, with database uniqueness for active Attempts.
- Follow the global lock order in `docs/architecture.md` for all competing commands.
- Commit aggregate changes, audit events, and protocol receipts atomically. Broadcast only after commit.
- Use Oban for durable expiry maintenance; PubSub is best-effort notification.
- Keep core commands out of Channel/controller callbacks. Transport delegates to contexts.
- Retain canonical Project `git_url`.
- Use fresh initial migrations. No execution-mode compatibility field or legacy backfill.
- The first milestone includes operator UI and a real-WebSocket fake reference Agent. It needs no external LLM or real Synapsis.

## Security and Scope

The deployment is single-tenant. Do not add browser accounts, authentication, organizations, or RBAC. Browser access is protected by infrastructure; retain REST API key protection and rate limits. Agent transport always requires machine credentials.

Never persist or log plaintext Agent credentials or lease tokens. Credential creation responses are one-time and non-cacheable. Protocol/audit logging uses allowlisted metadata. Validate connection ownership even on replay.

Cancellation, manual retry, real Synapsis integration, GitHub workflows, embedded providers/execution, memory retrieval, and artifact storage are outside milestone one.

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

The plan defines when these paths exist and which tests belong to each stage. Do not run full legacy tests as a rebuild baseline. Use focused tests for the active stage and the full replacement suite only at the final integration gate.

`Samgita.DataCase` and `SamgitaWeb.ConnCase` should use only the main Repo sandbox after foundation replacement. Concurrency tests must exercise independent database transactions; a shared sandbox connection does not prove locking correctness. WebSocket/restart tests use an explicitly isolated database and endpoint.

The fresh-start decision does not authorize dropping arbitrary databases. Use explicitly named new databases. Never run `mix ecto.reset` against an unresolved or shared target.

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

Place worktrees in this project's `.trees/<branch-name>` directory; use the `codex/` branch prefix unless instructed otherwise. Base the rebuild on the current local HEAD, including its documentation commit.

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
