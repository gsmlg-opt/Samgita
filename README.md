# Samgita

Samgita is an agent-neutral, single-tenant project and task management platform.
It registers Agents and Projects, associates repositories, validates Task and
Attempt transitions, and delivers durable scheduled and external events.
Registered Agents own reasoning, planning, delegation and execution. An Agent's
implementation label does not change its authorization rules.

The [approved redesign](docs/redesign/design.md),
[implementation plan](docs/redesign/implementation-plan.md) and
[acceptance ledger](docs/redesign/acceptance.md) define the requirements and
delivery boundaries. The older PRD, plan, rebuild design and removal inventory
are historical proposals; their clean-start and deletion checklists do not
authorize deleting data or migrations.

## Current implementation

The two platform applications are `apps/samgita` (Ecto/domain commands, events,
schedules and Oban) and `apps/samgita_web` (Phoenix REST and DuskMoon LiveViews).
Three independently built packages provide a reusable protocol core, optional
WebSocket transport and a limited pinned Codex adapter. Loading the packages
starts no Agent or listener.

The operator journey is available at:

| Route | Purpose |
| --- | --- |
| `/` | Persisted counts, management authority and attention indicators |
| `/agents`, `/agents/:id` | Registration, approvals, enablement, endpoint descriptors, write-only credentials and history |
| `/projects`, `/projects/:id` | Project settings, repositories, memberships, routing, Tasks, schedules, events and delivery recovery |
| `/projects/:project_id/tasks/:id` | Task relationships, Attempts, progress, effects, artifact references, review and acceptance |
| `/api/health`, `/api/info` | HTTP health and build information |

See the [architecture](docs/architecture.md),
[management API](docs/redesign/management-api.md),
[capability matrix](docs/redesign/capability-matrix.md), and setup guides for
[Sigma](docs/redesign/integrations/sigma.md),
[Synapsis](docs/redesign/integrations/synapsis.md) and
[Codex](docs/redesign/integrations/codex.md).

Connection records and recent activity are evidence, not heartbeat-based health.
A successful Attempt report with `effects_resolved: true` produces
`awaiting_review`; unresolved effects leave the Task `blocked` with an execution
hold. Explicit review and a separate acceptance decision produce `accepted`.
Events do not themselves authorize work.

The local qualification uses deterministic fake Agents and isolated databases.
It does not establish live Sigma, Synapsis or Codex conformance, real GitHub App
setup, a production migration, publication or deployment. Consult the acceptance
ledger for actual evidence and remaining gates.

## Development

Use the repository's pinned devenv environment (Elixir/OTP, PostgreSQL 16, Bun
and Tailwind 4). Start PostgreSQL with `devenv up postgres` in a separate terminal.
For a deliberately selected local development database:

```sh
devenv shell --no-tui -- mix deps.get
devenv shell --no-tui -- mix ecto.create
devenv shell --no-tui -- mix ecto.migrate
devenv shell --no-tui -- mix assets.setup
devenv shell --no-tui -- mix assets.build
devenv shell --no-tui -- mix phx.server
```

The default development database is `samgita_hub_dev`; HTTP listens on port
3110. Inspect database and runtime configuration before running migrations.
Existing/shared databases require the separate preservation and cutover gates.
Never use `mix ecto.reset` against an unresolved database target.

Install the web manifest from `apps/samgita_web` using
`bun install --frozen-lockfile`. Serialize Mix/devenv commands. Use an explicitly
named scratch database matching `samgita_redesign_*_test` for redesign checks:

```sh
SAMGITA_TEST_DATABASE=samgita_redesign_local_test devenv shell --no-tui -- mix test apps/samgita_web/test/samgita_web/live/agents_live_test.exs
```

Run each protocol project's checks from its own directory; it intentionally
does not inherit umbrella configuration. The stage documents specify the
scoped test sets: [P2](docs/redesign/protocol-phase-2.md),
[P3](docs/redesign/domain-phase-3.md),
[P4 coordination](docs/redesign/coordination-phase-4.md), and
[P4 GitHub](docs/redesign/github-phase-4.md).

## Security and delivery

Browser access relies on infrastructure protection; no browser accounts,
organizations or browser RBAC are introduced. REST retains API-key and rate-limit
protection. Machine routes always require current Agent credentials and, after
connect, a current connection generation. Inbound machine credentials, outbound
service credential references and runtime lease keys are separate authorities.

GitHub integration is read/event-only: signed ingress, verified associations,
immutable evidence and bounded reconciliation. Comments, PR creation, merge and
workflow execution are disabled. No live webhook or real credential provisioning
is implied by the local fixture tests.

[Deployment tooling](deployment/README.md) describes the release boundary.
The current CI assembles a local production release; CD remains disabled. There
is no normal package publication/release workflow in this repository. Passing
local checks or assembling a release does not authorize deployment.
