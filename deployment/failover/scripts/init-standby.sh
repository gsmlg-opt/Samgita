#!/bin/bash
# First deployment: attach THIS site as the standby of the running peer primary.
# Requires an empty database volume. Usage: init-standby.sh [--execute]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_execute "$@"
[[ "$(self role)" == "unset" ]] || die "this site already has a role; use rejoin.sh"
[[ "$(peer sql 'select pg_is_in_recovery()')" == "f" ]] || die "peer $PEER_SITE_NAME is not a running primary"
step "mark $SITE_NAME standby" self set-role standby
step "copy the primary with pg_basebackup" self basebackup "$PEER_DB_HOST"
step "configure standby replication" self make-standby "$PEER_DB_HOST"
step "start standby database" self db-start
step "wait for streaming replication" self wait-streaming
step "point $SITE_NAME proxy at the primary" self upstream peer
step "clear the primary's isolated marker" peer isolated off
((EXECUTE)) || echo "Dry run only. Re-run with --execute."
