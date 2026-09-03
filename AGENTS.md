# Repository Guidelines

## Project Overview

Samgita is an Elixir umbrella project for distributed multi-agent orchestration. It turns Product Requirements Documents into software by coordinating supervised agent workers on the BEAM. The runtime is built around OTP supervision, `:gen_statem` state machines, Oban queues, Horde process distribution, Phoenix PubSub, Phoenix LiveView, and PostgreSQL persistence.

Samgita is intentionally single-tenant. There is no account or authentication system for the browser UI; access control belongs at the infrastructure layer. The REST API can be protected with configured API keys.

## Umbrella Structure

- `apps/samgita_provider`: provider abstraction and adapters for Claude Code CLI, Claude API, Synapsis, Codex, plus provider sessions and health checks.
- `apps/samgita`: core business logic, `Samgita.Repo`, project orchestration, agent workers, Oban workers, Horde registry/supervisor integration, cache, quality gates, git worktree helpers, and domain schemas.
- `apps/samgita_memory`: standalone memory system with `SamgitaMemory.Repo`, pgvector-backed memory retrieval, PRD execution tracking, thinking chains, MCP tools, cache tables, and memory Oban workers.
- `apps/samgita_web`: Phoenix endpoint, router, LiveView pages, REST controllers, plugs, layouts, TypeScript hooks, and DuskMoon/Tailwind assets.

Dependency direction is `samgita_provider` and `samgita_memory` as standalone support apps, `samgita` depending on them, and `samgita_web` depending on `samgita`. Preserve that direction and avoid cross-app shortcuts that introduce cycles.

## Common Commands

Run commands from the repository root unless noted.

```bash
mix deps.get
mix ecto.setup
mix ecto.migrate
mix phx.server
iex -S mix phx.server

mix test
mix test apps/samgita/test/samgita/projects_test.exs
mix test apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs:10

mix format
mix format --check-formatted
mix credo --strict
mix dialyzer
mix precommit
```

Useful migration commands:

```bash
mix ecto.gen.migration name -r Samgita.Repo
mix ecto.gen.migration name -r SamgitaMemory.Repo
mix ecto.rollback -r Samgita.Repo
mix ecto.rollback -r SamgitaMemory.Repo
```

Asset commands are Mix aliases backed by Tailwind CSS 4 and Bun:

```bash
mix assets.setup
mix assets.build
mix assets.deploy
```

Use scoped tests for scoped changes. For PRD work, modify only files in the stated scope, run only scoped tests unless told otherwise, and stop when the in-scope checklist is complete and tests pass. If unrelated tests fail, report them and do not fix outside scope.

## Architecture Rules

- Keep PostgreSQL as the source of truth. Runtime processes may cache or coordinate transient state, but durable project, task, memory, PRD, notification, webhook, and artifact state belongs in Ecto schemas.
- Use `:gen_statem` for `Samgita.Agent.Worker` and `Samgita.Project.Orchestrator`; do not replace these with GenServers for organizational convenience.
- Use Oban for durable background work. Core queues are `agent_tasks`, `orchestration`, and `snapshots`; memory queues are `embeddings`, `compaction`, and `summarization` under the named `SamgitaMemory.Oban` instance.
- Use Horde for distributed registration and supervision via `Samgita.AgentRegistry` and `Samgita.AgentSupervisor`.
- Use Phoenix PubSub for real-time updates and cache invalidation.
- Preserve `git_url` as the canonical project identifier.
- Do not add a browser authentication/account system. If access control is needed, document infrastructure-level options or API key configuration.

## Core Runtime

`Samgita.Application` starts `Samgita.Repo`, DNSCluster/libcluster, PubSub, Finch, ETS cache, Horde registry/supervisor, circuit breaker, provider session registry, provider health checker, Oban, and project recovery.

`SamgitaMemory.Application` starts `SamgitaMemory.Repo`, memory/PRD ETS caches, formation telemetry supervisor, and the named memory Oban instance.

`SamgitaWeb.Application` starts telemetry and the Phoenix endpoint.

Agent workers follow the Reason-Act-Reflect-Verify cycle:

```text
:idle -> :reason -> :act -> :reflect -> :verify
          ^                              |
          +--------- on failure ---------+
```

Project orchestration advances through planning, bootstrap, discovery, architecture, infrastructure, development, QA, deployment, business, growth, and perpetual phases.

`Samgita.Agent.Types` currently defines 41 agent types across engineering, operations, business, data, product, growth, review, and planning swarms. Check that module before changing agent names, counts, model routing, or UI assumptions.

## Data Layer

- Main migrations live in `apps/samgita/priv/repo/migrations`.
- Memory migrations live in `apps/samgita_memory/priv/repo/migrations`.
- Core schemas live in `apps/samgita/lib/samgita/domain`.
- Memory schemas live under `apps/samgita_memory/lib/samgita_memory/memories` and `apps/samgita_memory/lib/samgita_memory/prd`.
- Use UUID/binary IDs and existing Ecto changeset patterns.
- Keep memory tables prefixed with `sm_`.
- pgvector requires `SamgitaMemory.PostgrexTypes`; preserve the custom Postgrex type setup.
- Ecto `update_all` is not suitable for multiplicative confidence decay; existing code uses raw SQL where needed.

## Provider Integration

`SamgitaProvider` owns provider behavior and adapters. Keep provider-specific request/response details inside `apps/samgita_provider`; core agent code should call the provider abstraction and session APIs.

Available backends include:

- `SamgitaProvider.ClaudeCode`
- `SamgitaProvider.ClaudeAPI`
- `SamgitaProvider.Synapsis`
- `SamgitaProvider.Codex`
- test/mock provider configuration

Provider sessions support `start_session/2`, `send_message/3`, `stream_message/3`, `close_session/1`, `capabilities/1`, and `health_check/1`, alongside legacy `query/2`.

## Web And API

Browser routes are LiveView-driven: dashboard, project form/detail, PRD chat/edit flows, agents, MCP, skills, and references.

REST API routes live under `/api`. Public health/info routes do not use the API pipeline. Protected API routes use `SamgitaWeb.Plugs.ApiAuth` and `SamgitaWeb.Plugs.RateLimit` with the configured 100 request / 60 second default.

When changing LiveViews or controllers, test the focused `apps/samgita_web/test` file. When changing API auth or rate limiting, include plug/controller coverage.

## Frontend And UI

This project uses Phoenix LiveView, Tailwind CSS 4, Bun, TypeScript, and the DuskMoon UI system.

- Prefer `phoenix_duskmoon` components for LiveView UI.
- Use `@duskmoon-dev/core`, `@duskmoon-dev/elements`, `@duskmoon-dev/css-art`, and `@duskmoon-dev/art-elements` assets already wired through `apps/samgita_web/assets/css/app.css` and TypeScript entrypoints.
- Do not add DaisyUI or another CSS component library.
- Do not expand or recreate Phoenix core component internals when a DuskMoon component fits.
- Do not vendor or patch DuskMoon package internals locally.
- Keep UI dense, operational, accessible, responsive, and consistent with the existing dashboard style.
- For asset changes, run the relevant LiveView tests and `mix assets.build` when practical.

If a DuskMoon package is missing needed behavior or has a bug, route it upstream instead of silently patching locally.

## Tests

- `Samgita.DataCase` and `SamgitaMemory.DataCase` manage Ecto SQL sandbox ownership.
- `SamgitaWeb.ConnCase` sets up both main and memory sandboxes for web tests.
- Many process-oriented tests are `async: false` because they touch Horde, ETS, Oban, Mox global stubs, or long-lived processes.
- Tests use Mox for `SamgitaProvider.MockProvider` and `Samgita.MockOban`.
- Oban is configured as inline in test.

Prefer tests under the owning app and mirror the module path. For process code, assert observable state, messages, database effects, and PubSub/Oban behavior rather than private implementation details.

## Coding Style

- Format Elixir with `mix format`; the root formatter delegates to umbrella apps.
- Match existing module boundaries and naming before adding abstractions.
- Keep state machines readable: transition logic belongs in the state machine; prompt assembly, parsing, context assembly, worktree operations, retry strategy, and broadcasting are already split into focused modules.
- Keep slow or failure-prone external work out of request paths.
- Persist before broadcasting when a user-visible event depends on durable state.
- Remove only imports, aliases, variables, or functions made unused by your own change.
- Do not refactor adjacent code, reformat unrelated files, or clean unrelated generated output.

## Git, Worktrees, And Commits

- Put manually created git worktrees under this repo's `.trees/<branch-name>` directory.
- Do not revert user changes or unrelated dirty worktree files.
- Use Conventional Commit style when committing, for example `feat(agent): add retry telemetry`, `fix(web): handle empty PRD`, or `test(memory): cover confidence decay`.
- Do not include `Generated with Claude Code` or `Co-Authored-By: Claude` in commit messages.

## Upstream Dependency Issue Routing

If a bug or missing feature is in a dependency hosted under `gsmlgorg`, `gsmlg-dev`, `duskmoon-dev`, `gsmlg-app`, `Gao-OS`, `gsmlg-opt`, `gsmlg-ci`, `gsmlg-games`, or `gsmlg-com`, do not silently work around it.

1. Identify the upstream repo from `mix.exs`, `package.json`, lockfiles, or other package manifests.
2. Create an upstream GitHub issue with `gh issue create`.
3. Use issue type `Bug` or `Feature`, label `internal request`, and title format `[internal] <concise description>`.
4. Include requesting repo/branch, what is needed and why, minimal reproduction or expected behavior, and severity: `blocker`, `needed`, or `nice-to-have`.
5. For blockers, add `# TODO(upstream): org/repo#issue_number` at the callsite and stop the blocked task.
6. For non-blocking temporary workarounds, add `# WORKAROUND(upstream): org/repo#issue_number` and keep the workaround narrow.

## Reference Docs

- `docs/prd.md` and `docs/product/PRD-V2.md`: product requirements and planned capabilities.
- `docs/plan.md`: implementation status and roadmap notes.
- `docs/development/CONSTITUTION.md`: security model and architectural constraints.
- `docs/architecture/claude-integration.md`: provider/session integration details.
- `docs/development/DEVELOPER-GUIDE.md` and `docs/development/GETTING-STARTED.md`: developer workflow details.
- `apps/samgita/priv/references/`: imported loki-mode reference material for agent behavior.
