#!/bin/bash
# Operations on THIS site only. The orchestrators call it locally and, through
# ssh, on the peer. Usage: site.sh <command> [args]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PGDATA_DIR=/var/lib/postgresql/data

sql() {
  compose exec -T db psql -v ON_ERROR_STOP=1 -U samgita -d samgita_hub_prod -tAXc "$1"
}

db_tool() {
  # One-off container on the stopped db volume, as the postgres user.
  local entry="$1"
  shift
  compose run --rm --no-deps -T --user postgres --entrypoint "$entry" db "$@"
}

db_running() { [[ -n "$(compose ps -q --status running db 2>/dev/null)" ]]; }
web_running() { [[ -n "$(compose ps -q --status running web 2>/dev/null)" ]]; }

wait_for() {
  local desc="$1" timeout="$2"
  shift 2
  local deadline=$((SECONDS + timeout))
  until "$@"; do
    ((SECONDS < deadline)) || { echo "error: timed out after ${timeout}s waiting for $desc" >&2; return 1; }
    sleep 2
  done
}

is_streaming() { [[ "$(sql "select status from pg_stat_wal_receiver" 2>/dev/null)" == "streaming" ]]; }
replayed() { [[ "$(sql "select pg_last_wal_replay_lsn() >= '$1'::pg_lsn" 2>/dev/null)" == "t" ]]; }
db_ready() { compose exec -T db pg_isready -q -U samgita -d samgita_hub_prod 2>/dev/null; }
web_healthy() {
  local id
  id="$(compose ps -q web)"
  [[ -n "$id" && "$(docker inspect -f '{{.State.Health.Status}}' "$id")" == "healthy" ]]
}

write_upstream() {
  local addr="$1"
  mkdir -p "$STATE/proxy"
  # Rewrite in place so the bind-mounted directory always sees the new content.
  printf 'reverse_proxy %s\n' "$addr" >"$STATE/proxy/upstream.caddy"
  if [[ -n "$(compose ps -q --status running proxy 2>/dev/null)" ]]; then
    compose exec -T proxy caddy reload --config /etc/caddy/Caddyfile
  fi
  echo "upstream -> $addr"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  sql) sql "${1:?query}" ;;
  role) cat "$STATE/node/role" 2>/dev/null || echo unset ;;
  set-role)
    [[ "${1:-}" =~ ^(primary|standby)$ ]] || die "set-role primary|standby"
    mkdir -p "$STATE/node"
    printf '%s\n' "$1" >"$STATE/node/role"
    ;;
  isolated)
    case "${1:-}" in
      on) mkdir -p "$STATE/node" && date -u +%FT%TZ >"$STATE/node/allow-isolated" ;;
      off) rm -f "$STATE/node/allow-isolated" ;;
      *) die "isolated on|off" ;;
    esac
    ;;
  upstream)
    case "${1:-}" in
      self) write_upstream "$SELF_WEB_UPSTREAM" ;;
      peer) write_upstream "$PEER_WEB_UPSTREAM" ;;
      *) die "upstream self|peer" ;;
    esac
    ;;
  web-stop) compose stop web ;;
  web-start)
    compose up -d web
    wait_for "web health" "${WEB_HEALTH_TIMEOUT:-240}" web_healthy ||
      { compose logs --tail 30 web >&2; exit 1; }
    ;;
  db-stop) compose stop -t 120 db ;;
  db-start)
    compose up -d db
    wait_for "database" 120 db_ready || exit 1
    ;;
  checkpoint-lsn)
    db_running && die "database must be stopped"
    db_tool pg_controldata "$PGDATA_DIR" | sed -n 's/^Latest checkpoint location: *//p'
    ;;
  wait-replay) wait_for "replay of ${1:?lsn}" "${2:-120}" replayed "$1" || exit 1 ;;
  wait-streaming) wait_for "streaming replication" "${1:-120}" is_streaming || exit 1 ;;
  promote)
    [[ "$(sql 'select pg_is_in_recovery()')" == "t" ]] || die "database is not a standby"
    [[ "$(sql 'select pg_promote(true, 60)')" == "t" ]] || die "promotion did not complete"
    ;;
  ensure-slot)
    sql "select pg_create_physical_replication_slot('samgita_standby')
         where not exists (select 1 from pg_replication_slots where slot_name = 'samgita_standby')" >/dev/null
    ;;
  drop-slot)
    sql "select pg_drop_replication_slot(slot_name) from pg_replication_slots
         where slot_name = 'samgita_standby' and not active" >/dev/null
    ;;
  rewind)
    db_running && die "database must be stopped"
    db_tool pg_rewind --target-pgdata="$PGDATA_DIR" --progress \
      --source-server="host=${1:?primary host} port=5432 user=samgita_rewind dbname=samgita_hub_prod"
    ;;
  make-standby)
    db_running && die "database must be stopped"
    db_tool /failover/make-standby.sh "${1:?primary host}"
    ;;
  basebackup)
    # Only into an EMPTY volume; this script never deletes database files.
    db_running && die "database must be stopped"
    db_tool bash -c '[[ -z "$(ls -A "$1")" ]] || { echo "data volume is not empty" >&2; exit 1; }
      pg_basebackup -h "$2" -U replicator -D "$1" -X stream -S samgita_standby -P' _ "$PGDATA_DIR" "${1:?primary host}"
    ;;
  status)
    echo "site=$SITE_NAME role=$(cat "$STATE/node/role" 2>/dev/null || echo unset)" \
      "isolated=$([[ -f "$STATE/node/allow-isolated" ]] && echo yes || echo no)" \
      "upstream=$(sed -n 's/^reverse_proxy //p' "$STATE/proxy/upstream.caddy" 2>/dev/null || echo unset)" \
      "web=$(web_running && echo running || echo stopped)"
    if db_running && db_ready; then
      if [[ "$(sql 'select pg_is_in_recovery()')" == "t" ]]; then
        echo "  db=standby $(sql "select 'receiver=' || coalesce((select status from pg_stat_wal_receiver), 'none')
          || ' replay_lsn=' || coalesce(pg_last_wal_replay_lsn()::text, '-')
          || ' last_replay=' || coalesce(pg_last_xact_replay_timestamp()::text, '-')")"
      else
        echo "  db=primary lsn=$(sql 'select pg_current_wal_lsn()')" \
          "replicas=$(sql "select coalesce(string_agg(application_name || ':' || state || ':lag=' || coalesce(replay_lag::text, '0'), ','), 'none') from pg_stat_replication")"
      fi
    else
      echo "  db=down"
    fi
    ;;
  *)
    die "unknown command '$cmd'"
    ;;
esac
