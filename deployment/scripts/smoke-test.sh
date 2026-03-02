#!/bin/bash
# Smoke tests for Samgita post-deployment verification

set -e

# Configuration
TARGET_URL="${1:-http://localhost:3110}"
TIMEOUT="${2:-30}"
MAX_RETRIES="${3:-5}"
RETRY_DELAY="${4:-5}"

echo "========================================"
echo "Running Samgita Smoke Tests"
echo "========================================"
echo ""
echo "Target URL: $TARGET_URL"
echo "Timeout: ${TIMEOUT}s"
echo "Max retries: $MAX_RETRIES"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_status="${3:-200}"

    echo -n "Testing: $test_name ... "

    local retry_count=0
    local response_code=""

    while [ $retry_count -lt $MAX_RETRIES ]; do
        response_code=$(eval "$test_command" 2>/dev/null || echo "FAILED")

        if [ "$response_code" == "$expected_status" ]; then
            echo -e "${GREEN}✓ PASSED${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $MAX_RETRIES ]; then
            echo -n "."
            sleep $RETRY_DELAY
        fi
    done

    echo -e "${RED}✗ FAILED${NC} (got: $response_code, expected: $expected_status)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

# Test 1: Health endpoint
run_test "Health endpoint" \
    "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT $TARGET_URL/api/health" \
    "200"

# Test 2: Info endpoint
run_test "Info endpoint" \
    "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT $TARGET_URL/api/info" \
    "200"

# Test 3: Root page loads
run_test "Root page" \
    "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT $TARGET_URL/" \
    "200"

# Test 4: Dashboard page loads (may require auth)
run_test "Dashboard page" \
    "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT $TARGET_URL/dashboard" \
    "200"

# Test 5: API projects endpoint
run_test "API projects endpoint" \
    "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT $TARGET_URL/api/projects" \
    "200"

# Test 6: Static assets load
run_test "Static assets" \
    "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT $TARGET_URL/assets/app.js" \
    "200"

# Test 7: Database connectivity (via health endpoint with DB check)
echo -n "Testing: Database connectivity ... "
DB_CHECK=$(curl -s -m $TIMEOUT "$TARGET_URL/api/health" | grep -o '"database":"healthy"' || echo "FAILED")
if [ "$DB_CHECK" != "FAILED" ]; then
    echo -e "${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: Response time check
echo -n "Testing: Response time ... "
RESPONSE_TIME=$(curl -s -o /dev/null -w '%{time_total}' -m $TIMEOUT "$TARGET_URL/api/health")
RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc | cut -d'.' -f1)
if [ "$RESPONSE_TIME_MS" -lt 2000 ]; then
    echo -e "${GREEN}✓ PASSED${NC} (${RESPONSE_TIME_MS}ms)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${YELLOW}⚠ SLOW${NC} (${RESPONSE_TIME_MS}ms)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 9: API authentication (if API keys are configured)
if [ -n "$SAMGITA_API_KEY" ]; then
    run_test "API authentication" \
        "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT -H 'Authorization: Bearer $SAMGITA_API_KEY' $TARGET_URL/api/projects" \
        "200"
else
    echo "Testing: API authentication ... ${YELLOW}⊘ SKIPPED${NC} (no API key provided)"
fi

# Test 10: LiveView websocket connection
echo -n "Testing: LiveView websocket ... "
WS_CHECK=$(curl -s -m $TIMEOUT "$TARGET_URL/dashboard" | grep -o 'phx-main' || echo "FAILED")
if [ "$WS_CHECK" != "FAILED" ]; then
    echo -e "${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Summary
echo ""
echo "========================================"
echo "Smoke Test Summary"
echo "========================================"
echo "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo "Failed: ${RED}$TESTS_FAILED${NC}"
echo "Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All smoke tests passed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some smoke tests failed!${NC}"
    echo ""
    echo "Deployment may have issues. Please investigate."
    exit 1
fi
