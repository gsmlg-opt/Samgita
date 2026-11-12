# Two-site active/passive deployment (ms04 + cloud)

One Samgita authority with two entry points. Exactly one site — the
**primary** — runs Samgita against a writable PostgreSQL. The other site — the
**standby** — runs only an asynchronous streaming replica. Both sites run a Caddy
proxy for the same hostname and forward to the current primary over WireGuard.
LAN users reach ms04's proxy (split DNS); everyone else reaches the cloud proxy.

```
LAN ──split DNS──> ms04 Caddy ─┐                 ┌─ cloud Caddy <── Internet
                               ▼                 ▼
                 primary:  Samgita + PostgreSQL (writable)
WireGuard 10.88.0.0/24  ── streaming replication (async) ──>
                 standby:  PostgreSQL (hot standby), Samgita stopped
```

Switching the primary is **manual**. Two sites have no quorum, so automatic
failover could create two primaries during a network partition; that would let
two Samgita instances dispatch the same Tasks and break lease fencing.

These files do not authorize a deployment. Deployment still needs the release,
fresh-migration, real Agent WebSocket and health verification in
[../README.md](../README.md), and an explicit decision to deploy.

## Safety model

- `scripts/guard.sh` wraps the web container entrypoint. Samgita starts only if
  the site is marked `primary`, its database is writable, and the peer database
  is a standby. It may start with the peer unreachable only after a recorded
  isolated failover (`state/node/allow-isolated`).
- The guard runs only at container start. A primary whose web container
  restarts while the old primary's database is up and writable will refuse to
  start; run `rejoin.sh` on the old primary promptly after a failover.
- Shared secrets (`state/samgita.env` and the shared part of `state/site.env`)
  must be identical on both sites: session signing, API keys, lease and payload
  keys, Codex host secrets.
- Every Codex host, approved Agent destination, and the pinned addresses must be
  reachable from **both** sites (for example ms04's Codex over WireGuard).
- Browser access has no application login and gate A11 is open. Each proxy
  requires a `caddy/site.d/browser-gate.caddy`; the cloud example denies
  everything until you choose a real control. `/api/*` (machine credentials,
  API keys, GitHub signatures) bypasses the browser gate.
- Database and web ports publish only on the WireGuard address.

## Layout

| Path | Purpose |
| --- | --- |
| `compose.yml` | db, web (guarded), proxy for one site |
| `site.env.example`, `samgita.env.example` | copy to `state/` on each host |
| `postgres/` | `pg_hba.conf`, first-init roles and slot, standby configuration |
| `caddy/` | shared `Caddyfile`, per-site `site.d/` examples |
| `wireguard/wg0.conf.example` | site link |
| `scripts/site.sh` | operations on the local site; orchestrators call it on the peer over ssh |
| `scripts/{init-primary,init-standby,switchover,failover,rejoin,status}.sh` | orchestration |
| `rehearsal/` | one-host functional rehearsal of all flows |

`state/` is git-ignored and holds secrets and runtime markers:
`site.env`, `samgita.env`, `pg/pgpass`, `node/role`, `node/allow-isolated`,
`proxy/upstream.caddy`.

Every orchestrator prints its plan and changes nothing unless given `--execute`.
Any failed step stops the run.

## One-time setup (each host)

1. WireGuard: install `wireguard/wg0.conf.example` (swapped per host); start it
   before Docker so the published addresses exist.
2. Clone the repository at the same path on both hosts and set `PEER_DIR`.
3. Key-based ssh from each host to the other (`PEER_SSH`), usable with
   `BatchMode`.
4. `mkdir -p state/pg state/node state/proxy`; fill `state/site.env` and
   `state/samgita.env` from the examples; edit the subnet in
   `postgres/pg_hba.conf` if not `10.88.0.0/24`.
5. `state/pg/pgpass`, owned by the container's postgres user:
   ```sh
   printf '*:5432:*:replicator:%s\n*:5432:*:samgita_rewind:%s\n' "$REPLICATION_PASSWORD" "$REWIND_PASSWORD" > state/pg/pgpass
   chmod 600 state/pg/pgpass && sudo chown 999:999 state/pg/pgpass
   ```
6. `caddy/site.d/tls.caddy` and `caddy/site.d/browser-gate.caddy` from the
   per-site examples. ms04 cannot complete ACME HTTP-01 from the LAN; give it a
   certificate for the same hostname or use a DNS-01 Caddy build.
7. DNS: public record -> cloud; LAN resolver override -> ms04.
8. Agents connect to `https://<SAMGITA_HOST>`, never to a site address.

## Procedures

Check state first, from either host:

```sh
scripts/status.sh
```

### First deployment

```sh
# on the site that starts as primary (empty volume; runs migrations)
scripts/init-primary.sh --execute
# then on the other site (empty volume)
scripts/init-standby.sh --execute
scripts/status.sh   # standby shows receiver=streaming
```

Then start the proxy on each host: `docker compose --env-file state/site.env up -d proxy`.

### Planned switchover (no data loss)

Run on the **standby** that should become primary:

```sh
scripts/switchover.sh            # review the plan
scripts/switchover.sh --execute
```

It stops Samgita and PostgreSQL on the old primary, waits until the standby has
replayed the old primary's shutdown checkpoint, promotes, turns the old primary
into a standby, repoints both proxies, then starts Samgita on the new primary.
Agents reconnect through the hostname; downtime is the length of the run.
If the old primary does not resume streaming, Samgita stays stopped: run
`rejoin.sh` on the old primary, after which the guard lets the new primary start
(`site.sh web-start`).

### Unplanned failover (primary lost)

Run on the standby only after confirming the primary is really down:

```sh
scripts/failover.sh --execute --peer-is-down
```

Asynchronous replication means **commits after the standby's last replayed
transaction are lost** (the script prints that time). Those may include Attempt
claims, renewals, reports and Task transitions while Agents keep working.
Afterwards, treat affected work as duplicate-effect risk and reconcile through
the normal Attempt recovery and review paths; nothing replays automatically.

The script fences the old primary if its host still answers (stops its web,
marks it standby). If it returns later, its guard refuses to start Samgita
while the new primary is writable, and its proxy keeps returning errors until
it rejoins.

### Rejoin a former primary

Run on the former primary once the network is back:

```sh
scripts/rejoin.sh --execute
```

It stops its database, runs `pg_rewind` from the current primary (discarding
its divergent commits), configures it as a standby and points its proxy at the
primary. If `pg_rewind` fails, stop: move that site's database volume aside
(never delete it), then rebuild with `site.sh basebackup <primary-host>`,
`site.sh make-standby <primary-host>` and `site.sh db-start`.

### Standby down for a long time

The primary keeps WAL for the standby's slot up to `MAX_SLOT_WAL_KEEP_SIZE`
(default 20GB). Past that the slot is invalidated and the standby must be
rebuilt with a base backup into a fresh volume.

## Rehearsal

```sh
rehearsal/run.sh <new-empty-directory>
```

It needs Docker, `postgres:16` and sudo (for the pgpass owner). It creates
projects `samgita-ms04`/`samgita-cloud` and network `samgita-rehearsal-link`,
replaces Samgita with a guard-only stub and the WireGuard link with a Docker
network, and removes all of them, volumes included, on exit. It covers: dry run, init,
switchover there and back, unplanned failover, the old primary returning
writable and diverging, guard refusals (with their reasons), `pg_rewind` rejoin
and a final switchover. It does not exercise the Samgita image, Caddy, real
WireGuard, ssh, Agent reconnection or TLS.
