#!/bin/bash
# First deployment: make THIS site the primary on an empty database volume.
# Runs isolated until init-standby.sh attaches the peer. Usage: init-primary.sh [--execute]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_execute "$@"
[[ "$(self role)" == "unset" ]] || die "this site already has a role; use status.sh"
mark_primary() {
  self set-role primary
  self isolated on
}
step "mark $SITE_NAME primary (isolated until the standby attaches)" mark_primary
step "point $SITE_NAME proxy at itself" self upstream self
step "start database (first start initializes roles and the replication slot)" self db-start
step "start Samgita (runs migrations)" self web-start
((EXECUTE)) || echo "Dry run only. Re-run with --execute."
