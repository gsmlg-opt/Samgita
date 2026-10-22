#!/bin/bash
# Foundation HTTP and database health only.
set -euo pipefail
TARGET_HOST="${1:-localhost}"
TARGET_PORT="${2:-3110}"
TIMEOUT="${3:-10}"
curl --fail --silent --show-error --max-time "$TIMEOUT" \
  "http://$TARGET_HOST:$TARGET_PORT/api/health" |
  jq -e '.status == "healthy" and .checks.samgita_repo == "ok"' >/dev/null
echo "HTTP and database health passed."
