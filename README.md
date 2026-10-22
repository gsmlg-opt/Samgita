# Samgita Agent Hub

Samgita is being rebuilt as a single-tenant control plane for external Agents.
Stage 1 provides the database Repo, Phoenix endpoint, HTTP health/info endpoints,
and an empty operator dashboard. Agent registration, task execution, leases,
protocol handling, and the full operator journey remain planned work.

The authoritative requirements and gates are in [docs/prd.md](docs/prd.md),
[docs/architecture.md](docs/architecture.md), and [docs/plan.md](docs/plan.md).
See also the [approved design](docs/agent-hub-rebuild-design.md) and
[removal inventory](docs/agent-hub-removal-inventory.md).

## Development

The umbrella contains exactly two first-party applications:

- `apps/samgita`: PostgreSQL Repo and the future Agent Hub domain.
- `apps/samgita_web`: Phoenix REST, Agent transport, and LiveView operator UI.

Use the pinned devenv toolchain: Elixir 1.18.5, OTP 27.3.4.17, PostgreSQL 16, and Bun.
Start PostgreSQL with `devenv up postgres` in a separate terminal, then:

```sh
devenv shell -- mix deps.get
devenv shell -- mix ecto.create
devenv shell -- mix ecto.migrate
devenv shell -- mix assets.setup
devenv shell -- mix assets.build
devenv shell -- mix phx.server
```

Local databases are `samgita_hub_dev` and `samgita_hub_test`. Use fresh
explicitly named databases; existing databases are not migration targets.
The default HTTP port is 3110. The dashboard is at `/`; health and release
information are at `/api/health` and `/api/info`.

The web application owns the JavaScript manifest and lockfile. Install only from
`apps/samgita_web` using `bun install --frozen-lockfile`.
Run scoped tests for the active stage defined in the plan. The full replacement
suite belongs to the final integration gate.

## Security and delivery

Browser access is protected by infrastructure; there are no browser accounts or
RBAC. Protected REST routes retain API-key authentication and rate limits.
Future Agent connections require machine credentials.

[Deployment tooling](deployment/README.md) targets the two-app release.
Automatic CD is disabled until release assembly, fresh-database migration,
real Agent WebSocket smoke tests, and HTTP health are proven and deployment is
separately authorized. Stage 1 is not a completed Agent Hub.
