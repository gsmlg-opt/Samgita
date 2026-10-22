#!/bin/bash
# Foundation HTTP proof only; Agent WebSocket exchange remains a later gate.
set -euo pipefail
TARGET_URL="${1:-http://localhost:3110}"
TIMEOUT="${2:-30}"
curl --fail --silent --show-error --max-time "$TIMEOUT" \
  "$TARGET_URL/api/health" |
  jq -e '.status == "healthy" and .checks.samgita_repo == "ok"' >/dev/null
curl --fail --silent --show-error --max-time "$TIMEOUT" \
  "$TARGET_URL/api/info" |
  jq -e '.app == "samgita" and ([.umbrella_apps[].name] | sort) == ["samgita", "samgita_web"]' >/dev/null
curl --fail --silent --show-error --max-time "$TIMEOUT" \
  "$TARGET_URL/" >/dev/null
echo "Foundation HTTP smoke checks passed; Agent WebSocket proof is pending."
