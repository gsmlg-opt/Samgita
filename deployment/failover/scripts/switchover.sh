#!/bin/bash
# Planned switchover: make THIS site (the healthy standby) the primary with no
# data loss. Run on the standby. Usage: switchover.sh [--execute]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_execute "$@"

[[ "$(self role)" == "standby" ]] || die "this site is not marked standby"
[[ "$(self sql 'select pg_is_in_recovery()')" == "t" ]] || die "local database is not a standby"
[[ "$(self sql 'select status from pg_stat_wal_receiver')" == "streaming" ]] ||
  die "local standby is not streaming; fix replication first"
[[ "$(peer role)" == "primary" ]] || die "peer $PEER_SITE_NAME is not marked primary"
[[ "$(peer sql 'select pg_is_in_recovery()')" == "f" ]] || die "peer database is not a primary"

fence_and_catch_up() {
  peer web-stop
  peer db-stop
  local lsn
  lsn="$(peer checkpoint-lsn)"
  [[ -n "$lsn" ]] || die "could not read the old primary's shutdown checkpoint"
  log "old primary shutdown checkpoint $lsn; waiting for local replay"
  self wait-replay "$lsn" 180
}

promote_self() {
  self promote
  self set-role primary
  self ensure-slot
}

demote_peer() {
  peer set-role standby
  peer isolated off
  peer make-standby "$SELF_DB_HOST"
  peer db-start
  peer drop-slot
  peer wait-streaming 180 ||
    die "old primary did not resume streaming; run rejoin.sh on $PEER_SITE_NAME (Samgita stays stopped)"
}

step "stop Samgita and the database on $PEER_SITE_NAME, then wait until $SITE_NAME replayed everything" fence_and_catch_up
step "promote $SITE_NAME" promote_self
step "turn $PEER_SITE_NAME into a standby of $SITE_NAME" demote_peer
step "point $SITE_NAME proxy at itself" self upstream self
step "point $PEER_SITE_NAME proxy at $SITE_NAME" peer upstream peer
step "start Samgita on $SITE_NAME" self web-start
((EXECUTE)) || echo "Dry run only. Re-run with --execute."
