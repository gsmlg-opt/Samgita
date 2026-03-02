#!/bin/bash
# Health check script for Samgita

set -e

HOST="${1:-localhost}"
PORT="${2:-3110}"
TIMEOUT="${3:-10}"

echo "Checking Samgita health at http://$HOST:$PORT"

# Health check
RESPONSE=$(curl -f -s -m "$TIMEOUT" "http://$HOST:$PORT/api/health" || echo "FAILED")

if [ "$RESPONSE" == "FAILED" ]; then
    echo "❌ Health check failed!"
    exit 1
fi

echo "✓ Health check passed"

# Info check
echo ""
echo "Application info:"
curl -s "http://$HOST:$PORT/api/info" | jq '.' 2>/dev/null || echo "$RESPONSE"

exit 0
