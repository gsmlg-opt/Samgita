# Agent Hub systemd service

The service runs the two-app release from `/opt/samgita` as user `samgita`.
Prepare writable `var` and `tmp` directories. Keep secrets in
`/opt/samgita/etc/samgita.env`, readable only by the service user/root.

Set `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PHX_SERVER=true`,
`SAMGITA_API_KEYS`, and `RELEASE_COOKIE`; `POOL_SIZE` and `PORT` are optional.
Use a fresh explicitly named PostgreSQL 16 database. Before starting, run
`bin/samgita eval 'Samgita.Release.migrate()'` with the same environment.
Only `Samgita.Repo` is migrated.

Installation/start require deployment authorization. Automatic CD remains disabled
until release assembly, fresh migrations, real Agent WebSocket smoke proof and
HTTP health pass. Protect browser access through infrastructure.

Inspect `journalctl -u samgita` and run the foundation health script after an
authorized start. A running unit does not prove the Agent Hub milestone complete.
