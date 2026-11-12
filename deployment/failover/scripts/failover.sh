#!/bin/bash
# UNPLANNED failover: the primary is lost. Promote THIS standby.
# Asynchronous replication: commits the standby had not replayed are lost.
# Usage: failover.sh --execute --peer-is-down
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_execute "$@"
[[ " $* " == *" --peer-is-down "* ]] || die "confirm the primary is really lost with --peer-is-down (planned moves use switchover.sh)"

[[ "$(self role)" == "standby" ]] || die "this site is not marked standby"
[[ "$(self sql 'select pg_is_in_recovery()')" == "t" ]] || die "local database is not a standby"

if peer_state="$(peer sql 'select pg_is_in_recovery()' 2>/dev/null)" && [[ "$peer_state" == "f" ]]; then
  die "peer primary database is reachable and writable; use switchover.sh"
fi

log "local standby: $(self sql "select 'last replayed transaction at ' || coalesce(pg_last_xact_replay_timestamp()::text, 'never')")"
log "anything the old primary committed after that point is lost"

fence_peer() {
  # Best effort: if the peer host still answers, keep its Samgita stopped.
  if peer web-stop && peer set-role standby; then
    log "fenced $PEER_SITE_NAME"
  else
    log "$PEER_SITE_NAME unreachable; its guard will refuse to start while $SITE_NAME is primary"
  fi
}

promote_self() {
  self promote
  self set-role primary
  self isolated on
  self ensure-slot
}

step "fence $PEER_SITE_NAME (best effort)" fence_peer
step "promote $SITE_NAME" promote_self
step "point $SITE_NAME proxy at itself" self upstream self
repoint_peer_proxy() {
  peer upstream peer || log "$PEER_SITE_NAME proxy not updated; it serves errors until rejoin.sh runs there"
}

step "point $PEER_SITE_NAME proxy at $SITE_NAME (best effort)" repoint_peer_proxy
step "start Samgita on $SITE_NAME" self web-start
if ((EXECUTE)); then
  cat >&2 <<'NOTE'
==> Failover complete. Before resuming work:
    - Attempts claimed, renewed or reported after the last replayed transaction are
      gone; Agents may still be running them. Treat those effects as duplicate-risk
      and reconcile through the normal Attempt recovery/review paths.
    - Run rejoin.sh on the old primary once it is reachable.
NOTE
else
  echo "Dry run only. Re-run with --execute --peer-is-down."
fi
