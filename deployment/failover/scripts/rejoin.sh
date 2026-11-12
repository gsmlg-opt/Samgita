#!/bin/bash
# Turn THIS former primary into a standby of the current peer primary, after a
# failover (pg_rewind) or a switchover whose old primary failed to stream.
# Usage: rejoin.sh [--execute]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_execute "$@"

[[ "$(peer role)" == "primary" ]] || die "peer $PEER_SITE_NAME is not marked primary"
[[ "$(peer sql 'select pg_is_in_recovery()')" == "f" ]] || die "peer database is not a running primary"

stop_local() {
  self web-stop
  self set-role standby
  self isolated off
  self db-stop
}

rewind_local() {
  self rewind "$PEER_DB_HOST" || die "pg_rewind failed. Stop here: move this site's database volume aside
(do not delete it), then run init-standby.sh flow: site.sh basebackup/make-standby/db-start."
  self make-standby "$PEER_DB_HOST"
}

start_standby() {
  peer ensure-slot
  self db-start
  self drop-slot
  self wait-streaming 180
}

step "stop Samgita and the database on $SITE_NAME and mark it standby" stop_local
step "rewind $SITE_NAME onto $PEER_SITE_NAME's timeline and configure replication" rewind_local
step "start $SITE_NAME as a streaming standby" start_standby
step "point $SITE_NAME proxy at $PEER_SITE_NAME" self upstream peer
step "clear $PEER_SITE_NAME's isolated marker" peer isolated off
((EXECUTE)) || echo "Dry run only. Re-run with --execute."
