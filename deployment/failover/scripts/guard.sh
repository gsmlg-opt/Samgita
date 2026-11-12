#!/bin/bash
# Web container entrypoint wrapper: start Samgita only on the single primary.
# Refuses (exit 1) unless all of these hold:
#   1. this site is marked primary (state/node/role)
#   2. the local database is writable (not in recovery)
#   3. the peer database is a standby, or is unreachable and the operator
#      recorded an isolated failover (state/node/allow-isolated)
# Never prints connection strings.
set -euo pipefail

refuse() {
  echo "failover guard: refusing to start Samgita: $*" >&2
  exit 1
}

role="$(cat /failover/node/role 2>/dev/null || echo unset)"
[[ "$role" == "primary" ]] || refuse "site role is '$role', not 'primary'"

local_recovery="$(psql "$DATABASE_URL" -tAXc 'select pg_is_in_recovery()' 2>/dev/null)" ||
  refuse "local database is unreachable"
[[ "$local_recovery" == "f" ]] || refuse "local database is a standby"

if peer_recovery="$(psql "$SAMGITA_PEER_MONITOR_URL" -tAXc 'select pg_is_in_recovery()' 2>/dev/null)"; then
  [[ "$peer_recovery" == "t" ]] || refuse "peer database is also writable (two primaries); run status.sh"
else
  [[ -f /failover/node/allow-isolated ]] ||
    refuse "peer database is unreachable and no isolated failover was recorded"
  echo "failover guard: peer unreachable; starting under a recorded isolated failover" >&2
fi

echo "failover guard: primary checks passed" >&2
exec "$@"
