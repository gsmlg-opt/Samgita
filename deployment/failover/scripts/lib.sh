# Shared helpers for the failover scripts. Source, do not execute.
# shellcheck shell=bash
set -euo pipefail

FAILOVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${SAMGITA_FAILOVER_STATE:-$FAILOVER_DIR/state}"
[[ -f "$STATE/site.env" ]] || { echo "missing $STATE/site.env (see site.env.example)" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source "$STATE/site.env"
set +a
export STATE_DIR="$STATE"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }

compose() {
  (cd "$FAILOVER_DIR" && docker compose --env-file "$STATE/site.env" "$@")
}

# Run a site.sh subcommand on the peer site.
peer() {
  if [[ -n "${PEER_SSH:-}" ]]; then
    # shellcheck disable=SC2029  # arguments are expanded locally on purpose
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$PEER_SSH" "$(printf '%q ' "$PEER_DIR/scripts/site.sh" "$@")"
  else
    # Rehearsal only: the peer site lives on this host.
    SAMGITA_FAILOVER_STATE="${PEER_STATE:?PEER_STATE is required when PEER_SSH is empty}" \
      "$PEER_DIR/scripts/site.sh" "$@"
  fi
}

self() { "$FAILOVER_DIR/scripts/site.sh" "$@"; }

# Orchestrators: print the plan unless --execute was given.
EXECUTE=0
parse_execute() {
  for arg in "$@"; do [[ "$arg" == "--execute" ]] && EXECUTE=1; done
  return 0
}
step() {
  local desc="$1"
  shift
  if ((EXECUTE)); then
    log "$desc"
    "$@"
  else
    echo "[plan] $desc"
  fi
}
