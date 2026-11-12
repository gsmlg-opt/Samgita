#!/bin/bash
# Functional rehearsal of the failover scripts on one Docker host:
# init, switchover there and back, unplanned failover, divergence + pg_rewind
# rejoin, and guard refusals. Usage: rehearsal/run.sh <empty-work-dir>
# Uses only postgres:16, project names samgita-ms04/samgita-cloud and network
# samgita-rehearsal-link; removes them (and their volumes) at the end.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:?usage: run.sh <empty-work-dir>}"
mkdir -p "$WORK"
[[ -z "$(ls -A "$WORK")" ]] || { echo "work dir must be empty" >&2; exit 1; }
WORK="$(cd "$WORK" && pwd)"
pw() { openssl rand -hex 16; }
DB_PW="$(pw)" REPL_PW="$(pw)" MON_PW="$(pw)" REW_PW="$(pw)"

make_site() { # name peer self_ip peer_ip web_ip peer_web_ip
  local s="$WORK/$1/state"
  mkdir -p "$s/pg" "$s/node" "$s/proxy"
  cat >"$s/site.env" <<ENV
COMPOSE_PROJECT_NAME=samgita-$1
COMPOSE_FILE=compose.yml:rehearsal/compose.rehearsal.yml
SITE_NAME=$1
PEER_SITE_NAME=$2
PEER_SSH=
PEER_DIR=$HERE
PEER_STATE=$WORK/$2/state
WG_ADDR=$3
WEB_LINK_ADDR=$5
SELF_DB_HOST=$3
PEER_DB_HOST=$4
SELF_WEB_UPSTREAM=$5:4870
PEER_WEB_UPSTREAM=$6:4870
SAMGITA_HOST=samgita.rehearsal.invalid
SAMGITA_IMAGE=postgres:16
DB_PASSWORD=$DB_PW
REPLICATION_PASSWORD=$REPL_PW
MONITOR_PASSWORD=$MON_PW
REWIND_PASSWORD=$REW_PW
WEB_HEALTH_TIMEOUT=30
ENV
  echo "DATABASE_URL=postgresql://samgita:$DB_PW@samgita-$1-db-1:5432/samgita_hub_prod" >"$s/samgita.env"
  printf '*:5432:*:replicator:%s\n*:5432:*:samgita_rewind:%s\n' "$REPL_PW" "$REW_PW" >"$s/pg/pgpass"
  chmod 600 "$s/pg/pgpass"
  sudo chown 999:999 "$s/pg/pgpass"
}

ms04() { SAMGITA_FAILOVER_STATE="$WORK/ms04/state" "$HERE/scripts/$1.sh" "${@:2}"; }
cloud() { SAMGITA_FAILOVER_STATE="$WORK/cloud/state" "$HERE/scripts/$1.sh" "${@:2}"; }
check() { # description expected actual
  if [[ "$2" == "$3" ]]; then echo "PASS: $1"; else echo "FAIL: $1 (expected '$2', got '$3')"; exit 1; fi
}
refusal() { # site -> the guard's refusal reason, or "started"
  local out
  if out="$("$1" site web-start 2>&1)"; then echo started; else
    sed -n 's/.*refusing to start Samgita: //p' <<<"$out" | tail -1; fi
  "$1" site web-stop >/dev/null 2>&1
}
rows() { "$@" site sql "select string_agg(note, ',' order by id) from rehearsal_marker"; }
cleanup() {
  for p in samgita-ms04 samgita-cloud; do
    docker compose -p "$p" -f "$HERE/compose.yml" -f "$HERE/rehearsal/compose.rehearsal.yml" \
      --env-file "$WORK/${p#samgita-}/state/site.env" --project-directory "$HERE" down -v --remove-orphans >/dev/null 2>&1 || true
  done
  docker network rm samgita-rehearsal-link >/dev/null 2>&1 || true
  sudo rm -rf "$WORK/ms04" "$WORK/cloud"
}
trap cleanup EXIT

docker network create --subnet 10.88.0.0/24 --gateway 10.88.0.254 samgita-rehearsal-link >/dev/null
make_site ms04 cloud 10.88.0.1 10.88.0.2 10.88.0.11 10.88.0.12
make_site cloud ms04 10.88.0.2 10.88.0.1 10.88.0.12 10.88.0.11

echo "### dry run prints a plan and changes nothing"
ms04 init-primary | grep -q '^\[plan\]'
check "dry run left role unset" unset "$(ms04 site role)"

echo "### init"
ms04 init-primary --execute
ms04 site sql "create table rehearsal_marker (id serial primary key, note text)" >/dev/null
ms04 site sql "insert into rehearsal_marker (note) values ('a')" >/dev/null
cloud init-standby --execute
check "cloud is a standby" t "$(cloud site sql 'select pg_is_in_recovery()')"
check "ms04 isolated marker cleared" no "$(ms04 site status | sed -n 's/.*isolated=\([a-z]*\).*/\1/p')"
check "cloud upstream is ms04" "reverse_proxy 10.88.0.11:4870" "$(cat "$WORK/cloud/state/proxy/upstream.caddy")"

echo "### guard refuses web on the standby"
check "standby web refused" "site role is 'standby', not 'primary'" "$(refusal cloud)"

echo "### planned switchover ms04 -> cloud"
ms04 site sql "insert into rehearsal_marker (note) values ('b')" >/dev/null
cloud switchover --execute
check "cloud promoted" f "$(cloud site sql 'select pg_is_in_recovery()')"
check "ms04 follows cloud" t "$(ms04 site sql 'select pg_is_in_recovery()')"
check "no data lost" "a,b" "$(rows cloud)"
cloud site sql "insert into rehearsal_marker (note) values ('c')" >/dev/null
ms04 site wait-streaming 60 >/dev/null
sleep 2
check "ms04 replicates new primary" "a,b,c" "$(rows ms04)"
check "ms04 upstream is cloud" "reverse_proxy 10.88.0.12:4870" "$(cat "$WORK/ms04/state/proxy/upstream.caddy")"

echo "### planned switchover cloud -> ms04"
ms04 switchover --execute
check "ms04 primary again" f "$(ms04 site sql 'select pg_is_in_recovery()')"
check "cloud follows ms04" t "$(cloud site sql 'select pg_is_in_recovery()')"
check "data intact" "a,b,c" "$(rows ms04)"

echo "### unplanned failover: ms04 lost"
sleep 2
docker kill samgita-ms04-db-1 samgita-ms04-web-1 >/dev/null
cloud failover --execute --peer-is-down
check "cloud promoted after failover" f "$(cloud site sql 'select pg_is_in_recovery()')"
check "ms04 fenced to standby" standby "$(ms04 site role)"
cloud site sql "insert into rehearsal_marker (note) values ('d')" >/dev/null

echo "### old primary returns writable and diverges; guards refuse"
ms04 site db-start >/dev/null
ms04 site sql "insert into rehearsal_marker (note) values ('lost-on-ms04')" >/dev/null
check "old primary web refused (role standby)" "site role is 'standby', not 'primary'" "$(refusal ms04)"
ms04 site set-role primary
check "old primary web refused even if marked primary (peer writable)" \
  "peer database is also writable (two primaries); run status.sh" "$(refusal ms04)"

echo "### rejoin ms04 with pg_rewind"
ms04 rejoin --execute
check "ms04 standby after rejoin" t "$(ms04 site sql 'select pg_is_in_recovery()')"
sleep 2
check "divergent row rewound away" "a,b,c,d" "$(rows ms04)"
check "cloud isolated marker cleared" no "$(cloud site status | sed -n 's/.*isolated=\([a-z]*\).*/\1/p')"
check "cloud web still runs" running "$(cloud site status | sed -n 's/.*web=\([a-z]*\).*/\1/p')"

echo "### switch back to ms04 after rejoin"
ms04 switchover --execute
check "ms04 primary" f "$(ms04 site sql 'select pg_is_in_recovery()')"
check "final data" "a,b,c,d" "$(rows ms04)"
ms04 status
echo "REHEARSAL PASSED"
