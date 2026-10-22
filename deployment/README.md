# Agent Hub deployment tooling

Stage 1 retains tooling for exactly two first-party release applications,
`samgita` and `samgita_web`, using only `Samgita.Repo` and PostgreSQL 16.
Agent transport and full operator behavior are not implemented yet.

Automatic CD is disabled. Deployment requires two-app release assembly, fresh
database migration, real Agent WebSocket smoke proof, HTTP health verification,
and separate explicit authorization. Building locally does not authorize
publishing images or deploying.

## Configuration

Copy `.env.example` and supply `DATABASE_URL`, `POOL_SIZE`,
`SECRET_KEY_BASE`, `PHX_HOST`, `PHX_SERVER=true`, `PORT`,
`SAMGITA_API_KEYS`, and `RELEASE_COOKIE`. Compose derives its database URL
from `DB_PASSWORD` and uses the new `samgita_hub_prod` database and
`hub_postgres_data` volume. Do not reuse or reset legacy databases/volumes.
Protect browser access at the infrastructure boundary.

## Local release verification

```sh
deployment/scripts/build-release.sh
# Supply an explicitly named isolated DATABASE_URL first.
_build/prod/rel/samgita/bin/samgita eval 'Samgita.Release.migrate()'
PHX_SERVER=true _build/prod/rel/samgita/bin/samgita start
deployment/scripts/health-check.sh localhost 3110
deployment/scripts/smoke-test.sh http://localhost:3110
```

Release and Docker installers run `bun install --frozen-lockfile` in
`apps/samgita_web`. The Docker entrypoint migrates the configured database
before startup. HTTP smoke checks prove foundation behavior only, not an Agent
WebSocket handshake or protocol exchange.

The retained nginx proxy forwards WebSocket upgrades for LiveView and
`/agent/socket`, and explicitly forwards `Authorization`. Configure its
hostname and TLS certificates before use. Keep credentials out of URLs.
See [systemd](systemd/README.md) and [scripts](scripts/README.md).
