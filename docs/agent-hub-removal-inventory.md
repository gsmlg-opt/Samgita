# Agent Hub Rebuild Removal Inventory

Status: implementation boundary for the approved clean rebuild in
`docs/agent-hub-rebuild-design.md`. This document classifies the repository; it
does not authorize database destruction, deployment, or removal of unrelated
working-tree changes.

Inventory basis: tracked files at commit
`3f380e3421609c0002897e4ab7557f7fd7536234` on 2026-09-07. The snapshot contains
387 tracked files, including 42 under `apps/samgita_memory`, 16 under
`apps/samgita_provider`, 17 timestamped main-repository migrations, and 20
imported reference files. Paths added by the rebuild are outside this legacy
count.

## Classification rules

- **Remove** means the path has no milestone-one runtime or documentation role.
- **Retain** means the path can remain materially unchanged, apart from mechanical
  formatting or regenerated lock metadata.
- **Rewrite** means retain the path/name where useful, but replace legacy behavior
  and tests with the Agent Hub contract. A rewrite is not permission to preserve
  an old API for compatibility.
- A directory rule covers every tracked descendant unless an exception is named.
- Removal happens only after the replacement foundation compiles and its focused
  tests pass. No old production data is migrated; operators must explicitly
  select a new database for rebuild validation.

## Umbrella applications

| Boundary | Classification | Notes |
|---|---|---|
| `apps/samgita_memory/**` | Remove entire directory | Removes the second Repo, pgvector types and migrations, memory/PRD schemas and caches, MCP tools, formation telemetry, memory Oban instance and workers, and all tests. Do not copy any table or migration into the new domain. |
| `apps/samgita_provider/**` | Remove entire directory | Removes Claude Code/API, Codex and Synapsis adapters, provider sessions, behavior modules, health checks, and tests. Milestone one talks to external agents over the Agent Hub protocol; it does not execute an LLM locally. |
| `apps/samgita/**` | Retain app boundary; rewrite internals below | Becomes the only domain/runtime app and owns the single `Samgita.Repo`. |
| `apps/samgita_web/**` | Retain app boundary; rewrite surfaces below | Remains the Phoenix HTTP, LiveView, API-key and WebSocket edge. |

The resulting release must contain exactly `samgita` and `samgita_web` as
umbrella applications.

## Core application

### Retain

- `apps/samgita/.formatter.exs`
- `apps/samgita/lib/samgita/repo.ex`
- `apps/samgita/priv/repo/migrations/.formatter.exs`
- `apps/samgita/priv/repo/seeds.exs` (currently intentionally empty; add no
  milestone-one seed dependency)

### Rewrite in place

- `apps/samgita/mix.exs`: remove the two in-umbrella dependencies and legacy
  execution dependencies; declare only dependencies used directly by the new
  core.
- `apps/samgita/lib/samgita.ex`: expose Agent Hub health/domain entry points, not
  memory health.
- `apps/samgita/lib/samgita/application.ex`: start the Repo, PubSub and the new
  durable task-dispatch runtime only. Remove DNSCluster/libcluster, Finch, cache,
  Codex supervisors, Horde, provider session/health children, circuit breaker and
  project recovery.
- `apps/samgita/lib/samgita/domain/project.ex`
- `apps/samgita/lib/samgita/domain/task.ex`
- `apps/samgita/lib/samgita/events.ex`
- `apps/samgita/lib/samgita/projects.ex`
- `apps/samgita/lib/samgita/release.ex`: load and migrate only `Samgita.Repo`.
- `apps/samgita/lib/samgita/telemetry.ex`

The rewrite adds the other approved schemas and contexts for agents,
credentials, connections, bindings, attempts, protocol receipts and domain
events. Those are new paths, not renamed legacy schemas.

### Remove

Remove these directories and every descendant:

- `apps/samgita/lib/samgita/agent/**`
- `apps/samgita/lib/samgita/codex_app_servers/**`
- `apps/samgita/lib/samgita/project/**`
- `apps/samgita/lib/samgita/provider/**`
- `apps/samgita/lib/samgita/quality/**`
- `apps/samgita/lib/samgita/tasks/**`
- `apps/samgita/lib/samgita/workers/**`
- `apps/samgita/priv/references/**`
- `apps/samgita/priv/gettext/**`

Remove these individual modules:

- `apps/samgita/lib/samgita/cache.ex`
- `apps/samgita/lib/samgita/codex_app_servers.ex`
- `apps/samgita/lib/samgita/features.ex`
- `apps/samgita/lib/samgita/git.ex`
- `apps/samgita/lib/samgita/git/worktree.ex`
- `apps/samgita/lib/samgita/mailer.ex`
- `apps/samgita/lib/samgita/notifications.ex`
- `apps/samgita/lib/samgita/oban_client.ex`
- `apps/samgita/lib/samgita/prds.ex`
- `apps/samgita/lib/samgita/references.ex`
- `apps/samgita/lib/samgita/webhooks.ex`

Under `apps/samgita/lib/samgita/domain/`, remove every tracked schema except
`project.ex` and `task.ex`: `agent_message.ex`, `agent_run.ex`, `artifact.ex`,
`chat_message.ex`, `feature.ex`, `memory.ex`, `notification.ex`, `prd.ex`,
`snapshot.ex`, `task_dependency.ex`, and `webhook.ex`.

Remove all 17 timestamped files under
`apps/samgita/priv/repo/migrations/20*.exs`. The rebuild starts with fresh
migrations for exactly the nine approved tables; it does not edit, reorder or
reuse a legacy migration.

## Core tests

### Rewrite

- `apps/samgita/test/samgita_test.exs`
- `apps/samgita/test/samgita/domain/project_test.exs`
- `apps/samgita/test/samgita/domain/task_test.exs`
- `apps/samgita/test/samgita/events_test.exs`
- `apps/samgita/test/samgita/projects_test.exs`
- `apps/samgita/test/samgita/telemetry_test.exs`
- `apps/samgita/test/samgita/e2e/umbrella_integration_test.exs`
- `apps/samgita/test/support/data_case.ex`
- `apps/samgita/test/test_helper.exs`

The rewritten suite must cover database constraints, state transitions,
idempotent receipt processing, one-live-connection enforcement and durable
event ordering. `DataCase` must own only the main Repo sandbox.

### Remove

Remove every test below these directories:

- `apps/samgita/test/samgita/agent/**`
- `apps/samgita/test/samgita/git/**`
- `apps/samgita/test/samgita/project/**`
- `apps/samgita/test/samgita/provider/**`
- `apps/samgita/test/samgita/quality/**`
- `apps/samgita/test/samgita/tasks/**`
- `apps/samgita/test/samgita/workers/**`

Also remove `benchmark_test.exs`, `cache_test.exs`,
`codex_app_servers_test.exs`, `features_test.exs`, `notifications_test.exs`,
`prds_test.exs`, `references_test.exs`, `webhooks_test.exs`,
`e2e/project_lifecycle_test.exs`, every old domain test except the two rewrite
targets above, and `apps/samgita/test/support/mocks.ex`.

## Web application

### Retain

- `apps/samgita_web/.formatter.exs`
- `apps/samgita_web/lib/samgita_web.ex`
- `apps/samgita_web/lib/samgita_web/application.ex`
- `apps/samgita_web/lib/samgita_web/gettext.ex`
- `apps/samgita_web/lib/samgita_web/telemetry.ex`
- `apps/samgita_web/lib/samgita_web/controllers/changeset_json.ex`
- `apps/samgita_web/lib/samgita_web/controllers/error_html.ex`
- `apps/samgita_web/lib/samgita_web/controllers/error_json.ex`
- `apps/samgita_web/lib/samgita_web/controllers/fallback_controller.ex`
- `apps/samgita_web/lib/samgita_web/plugs/rate_limit.ex`
- `apps/samgita_web/priv/gettext/**`

Retained modules still require compile verification after the domain API is
replaced; classification does not guarantee zero import edits.

### Rewrite in place

- `apps/samgita_web/mix.exs`
- `apps/samgita_web/lib/samgita_web/endpoint.ex`
- `apps/samgita_web/lib/samgita_web/router.ex`
- `apps/samgita_web/lib/samgita_web/components/layouts.ex`
- `apps/samgita_web/lib/samgita_web/components/layouts/app.html.heex`
- `apps/samgita_web/lib/samgita_web/components/layouts/root.html.heex`
- `apps/samgita_web/lib/samgita_web/controllers/health_controller.ex`
- `apps/samgita_web/lib/samgita_web/controllers/info_controller.ex`
- `apps/samgita_web/lib/samgita_web/controllers/project_controller.ex`
- `apps/samgita_web/lib/samgita_web/controllers/project_json.ex`
- `apps/samgita_web/lib/samgita_web/controllers/task_controller.ex`
- `apps/samgita_web/lib/samgita_web/controllers/task_json.ex`
- `apps/samgita_web/lib/samgita_web/plugs/api_auth.ex`
- all files under `live/agents_live/**`, `live/dashboard_live/**`,
  `live/project_form_live/**`, and `live/project_live/**`

`ApiAuth` must retain API-key protection but replace ordinary membership
comparison with constant-time secret comparison. Browser pages remain
single-tenant and have no application-level account/authentication system. New
WebSocket channel/socket modules implement `/agent/socket`; they must not reuse
provider sessions or agent workers.

### Remove

Remove controller and JSON modules for `agent_run`, `artifact`, `feature`,
`notification`, `page`, `prd`, and `webhook`, including
`controllers/page_html/**`. Remove all files under `live/mcp_live/**`,
`live/prd_chat_live/**`, `live/references_live/**`, and `live/skills_live/**`.

## Web tests

Retain the existing error HTML, error JSON, fallback controller, and rate-limit
tests. Rewrite the health, info, project and task controller tests; API-auth
tests; Agents, Dashboard, Project Form and Project LiveView tests; ConnCase; and
the web test helper. `ConnCase` must sandbox only `Samgita.Repo`.

Remove controller tests for agent runs, artifacts, features, notifications,
pages, PRDs and webhooks. Remove LiveView tests for MCP, PRD chat, references and
skills. Add focused socket/channel tests for authentication, registration,
heartbeat, request/response correlation, duplicate receipt replay, reconnect
and terminal task outcomes.

## Mix dependencies and release graph

### Rewrite

- Root `mix.exs`: the release app map becomes exactly `samgita` and
  `samgita_web`.
- Root `mix.lock`: regenerate only through dependency resolution after both app
  manifests are final.
- `apps/samgita/mix.exs`: retain Ecto/Postgrex, PubSub, Oban and JSON support as
  directly used. Remove `samgita_memory`, `samgita_provider`, Horde,
  libcluster/DNS clustering, bcrypt, Earmark, Swoosh, Finch, core Gettext,
  Phoenix Ecto and provider-test/Mox dependencies unless a new direct use is
  introduced by an approved milestone-one path.
- `apps/samgita_web/mix.exs`: retain Phoenix, LiveView, Bandit,
  Phoenix Ecto/HTML/Gettext, DuskMoon, Bun/Tailwind and web telemetry. Move
  telemetry dependencies here explicitly if the web app uses them directly.

Dependency gates: `mix app.tree` must show only the two umbrella apps; neither
dependency tree nor lockfile may contain the removed umbrella apps, Horde,
libcluster, pgvector, provider SDKs or local-agent execution packages.

## Configuration, database and seeds

Rewrite `config/config.exs`, `config/dev.exs`, `config/test.exs` and
`config/runtime.exs` around one Repo and one Oban instance. Remove the memory
Repo and memory queues; embeddings; provider selection and mock configuration;
Anthropic/Claude environment variables; project recovery; workspace/git
execution settings; and DNS cluster configuration. Keep API keys, database URL,
endpoint, PubSub and release-secret configuration. Retain `config/prod.exs` if a
compile check confirms it remains generic.

`apps/samgita/priv/repo/seeds.exs` remains a no-op in milestone one. Fake-agent
fixtures belong in tests or a dedicated development script, not durable seed
data.

## Frontend assets

### Retain

- `apps/samgita_web/assets/css/app.css`
- `apps/samgita_web/tsconfig.json`
- `apps/samgita_web/bunfig.toml`
- Phoenix TypeScript declarations and static icons under the web app
- the existing DuskMoon/Tailwind packages that are actually imported by the
  rewritten interface

### Rewrite or remove

- Rewrite `apps/samgita_web/assets/js/app.ts` to remove PRD-chat-only hooks such
  as `MarkdownInputWithSend` and `AutoScroll` and add only Agent Hub hooks that
  are justified by LiveView behavior.
- Rewrite `apps/samgita_web/assets/js/custom-elements.ts` to import only rendered
  components.
- Stage 1 may remove `apps/samgita_web/assets/js/heavy-elements.ts` and its
  separate build target when the empty foundation has no consumer. If the new
  Task UI deliberately uses rendered Markdown later, rewrite this entrypoint and
  retain only packages actually imported by that new surface.
- Rewrite `apps/samgita_web/package.json` and regenerate
  `apps/samgita_web/bun.lock` after imports settle.
- Root `package.json`, root `bun.lock`, and root `bunfig.toml` are candidates for
  removal only after Docker, CI and local asset commands are proven to install
  directly from `apps/samgita_web`. Do not delete the root workspace boundary
  while any consumer still relies on it.

## Tooling, containers, CI and deployment

- Retain and verify `.formatter.exs`, `.gitignore`, `.dockerignore`, `LICENSE`,
  `.envrc`, `devenv.yaml` and generic repository metadata. Credo and Dialyzer
  are configured through tracked Mix files; this snapshot has no tracked root
  `.credo.exs` or `.dialyzer_ignore.exs` to classify.
- Rewrite `devenv.nix` to remove the pgvector extension and obsolete pnpm setup;
  retain PostgreSQL, the selected Elixir/OTP toolchain and Bun. Regenerate
  `devenv.lock` only if its inputs change.
- Rewrite `.env.example` to contain one database/pool configuration, API keys,
  endpoint/release secrets and no memory, Claude, Anthropic, workspace or DNS
  cluster settings.
- Rewrite `Dockerfile` and `docker-compose.yml`: copy/build only two app
  manifests, use ordinary PostgreSQL, remove the pgvector init mount, and remove
  provider/memory/workspace variables. Retain Git in the runtime image only if a
  new approved runtime path demonstrably invokes it; the milestone-one server
  does not.
- Remove `deployment/postgres/init.sql`; its only rebuild-relevant effect would
  be enabling pgvector.
- Retain `deployment/docker/entrypoint.sh`, the nginx reverse-proxy structure,
  and generic build/deploy/rollback scripts, but rewrite their app lists,
  environment contracts and health checks. Verify nginx forwards WebSocket
  upgrades for `/agent/socket` and does not strip `Authorization`.
- Rewrite `deployment/README.md`, `deployment/scripts/README.md`,
  `deployment/scripts/health-check.sh`, `deployment/scripts/smoke-test.sh`,
  `deployment/systemd/README.md`, and `deployment/systemd/samgita.service` for
  the one-Repo/two-app release.
- Rewrite `.github/workflows/ci.yml` to use ordinary PostgreSQL, remove Anthropic
  settings, install assets only from the web asset directory, align Elixir/OTP
  with the release image and devenv, run fresh migrations, and add a legacy
  reference scan.
- Rewrite `.github/workflows/cd.yml`; automatic deployment of the partial rebuild
  stays disabled until the two-app release, fresh-database migration, WebSocket
  smoke test and HTTP health check all pass and deployment is separately
  authorized.

The current toolchain is inconsistent: CI declares Elixir 1.17/OTP 26 while the
Docker image declares Elixir 1.18/OTP 27 and the local devenv currently runs
Elixir 1.18.5. Select and pin one supported pair before treating CI as a gate.

## Documentation and repository guidance

- Retain `docs/agent-hub-rebuild-design.md` as the approved source of truth and
  this inventory as its deletion/rewrite boundary.
- Rewrite `docs/plan.md` to make the rebuild sequence and acceptance gates
  authoritative.
- Rewrite `docs/prd.md` and legacy product, architecture, development and
  deployment documentation that describes autonomous PRD execution, local
  Claude/Codex providers, RARV, swarms/phases, Horde, pgvector memory, MCP/skills
  browsing or auto-cloned Git worktrees. Do not leave those claims presented as
  current behavior.
- Rewrite `.specify/memory/constitution.md`; its no-auth wording, automatic Git
  clone, pgvector, RARV and Horde requirements contradict the approved design.
  The replacement must distinguish no browser accounts from API/agent
  authentication.
- Rewrite `README.md` for Agent Hub. During the transition it may explicitly say
  implementation is in progress and link the approved design; final milestone
  documentation must describe only tested behavior.
- Rewrite `CLAUDE.md` and `AGENTS.md` to remove legacy architecture mandates and
  preserve repository workflow/safety guidance. These files are owned by the
  documentation-guidance pass, not by removal implementation.
- Remove `suggest.md` and `examples/claude_agent_example.exs`.
- Retain generic `.specify/templates/**` and `.specify/scripts/**`, except rewrite
  scripts that enforce numeric branch names or can overwrite `AGENTS.md` or
  `CLAUDE.md` without an explicit review step.

Do not add archive directories for removed implementation or docs. Git history
is the archive, and copying legacy material would keep contradictory search
results alive.

## Sequencing and acceptance gates

1. Land the approved design, plan, guidance rewrite and this inventory. Gate:
   repository search returns one unambiguous current architecture.
2. In one atomic Stage 1 integration boundary, remove the classified legacy apps,
   callers and tests while rewriting manifests, configuration, the one-Repo
   runtime, initial Oban migration, health/dashboard surfaces and test support.
   Do not commit a state where removed modules still have callers. Gate: the two
   app foundation compiles with warnings as errors; `samgita_hub_dev` and
   `samgita_hub_test` create/migrate without legacy product tables; focused
   health, info, dashboard and plug tests pass; assets build; removed-module
   references are absent from application source and configuration. Final
   documentation/deployment scans belong to stage 6.
3. Add the nine-table domain, credentials and transactional commands, followed by
   protocol, dispatch, recovery/race handling, API and UI in the stage order in
   `docs/plan.md`. Gate each stage only with the focused files that exist at that
   stage.
4. Prove the real WebSocket fake-agent vertical slice. Gate: a Task advances from
   `pending` to `completed`, its Attempt advances to `succeeded`, and persisted
   receipt/domain-event evidence proves replay-safe processing. Failure-path
   checks use the specified error/expiry transitions; there is no task-rejection
   protocol in milestone one.
5. Rebuild assets, CI, release and deployment surfaces. Gate: production asset
   build, release assembly, fresh-database migration, HTTP health and WebSocket
   smoke tests pass before CD is enabled.

No destructive database command is an acceptance gate. Use a separate explicitly
named rebuild database; do not infer permission to reset an existing database.

## Verified scope and baseline commands

The following read-only commands reproduce the inventory counts and expose
concurrent user changes before implementation:

```bash
git rev-parse HEAD
git ls-files | wc -l
git ls-files 'apps/samgita_memory/**' | wc -l
git ls-files 'apps/samgita_provider/**' | wc -l
git ls-files 'apps/samgita/priv/repo/migrations/20*.exs' | wc -l
git ls-files 'apps/samgita/priv/references/**' | wc -l
git status --short
```

Run these non-destructive structure gates after the foundation rewrite:

```bash
git ls-files 'apps/*/mix.exs'
devenv shell --no-reload -- mix app.tree --format plain
devenv shell --no-reload -- mix deps.tree --format plain
rg -n 'SamgitaMemory|SamgitaProvider|Horde|DNSCluster|pgvector|RARV|ClaudeCode|ClaudeAPI' \
  apps config deployment .github Dockerfile docker-compose.yml mix.exs mix.lock devenv.nix .env.example
git diff --check
```

The first baseline `mix app.tree` attempt on this snapshot did not reach tree
output: compilation failed while ParallelChecker inspected
`ThousandIsland.Logger.detach_logger/1` under local Elixir 1.18.5. Treat this as
a baseline/toolchain blocker to resolve before dependency-tree comparison, not
as evidence about the target tree.

Foundation and release verification should then use:

```bash
devenv shell --no-reload -- mix deps.get
devenv shell --no-reload -- mix compile --warnings-as-errors
devenv shell --no-reload -- mix ecto.create
devenv shell --no-reload -- mix ecto.migrate
devenv shell --no-reload -- mix test apps/samgita_web/test/samgita_web/controllers/health_controller_test.exs apps/samgita_web/test/samgita_web/controllers/info_controller_test.exs apps/samgita_web/test/samgita_web/live/dashboard_live_test.exs apps/samgita_web/test/samgita_web/plugs
devenv shell --no-reload -- mix assets.build
MIX_ENV=prod devenv shell --no-reload -- mix release
```

These database commands assume Stage 1 has already configured the exact plan
names `samgita_hub_dev` and `samgita_hub_test`; the integration suite uses
`samgita_hub_integration_test`. Creation failure must not be converted into an
implicit reset. Run only the focused files present at each stage, then run both
replacement app suites at the final integration gate. Release assembly and
startup smoke tests must use the validated runtime secrets specified by the
implementation plan; this document does not provide placeholder production
credentials.
