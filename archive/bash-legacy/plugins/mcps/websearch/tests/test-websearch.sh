#!/usr/bin/env bash
# WebSearch MCP Plugin - Test Suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test helper
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_exit="${3:-0}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    echo -n "Testing: ${test_name} ... "
    
    set +e
    output=$(eval "$test_cmd" 2>&1)
    actual_exit=$?
    set -e
    
    if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Expected exit code: $expected_exit"
        echo "  Actual exit code: $actual_exit"
        if [[ -n "$output" ]]; then
            echo "  Output: $output"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "========================================"
echo "WebSearch MCP Test Suite"
echo "========================================"
echo ""

# Plugin structure tests
echo "--- Plugin Structure Tests ---"
run_test "Plugin.json exists" "test -f ${PLUGIN_DIR}/plugin.json"
run_test "Main.sh exists" "test -f ${PLUGIN_DIR}/main.sh"
run_test "Main.sh is executable" "test -x ${PLUGIN_DIR}/main.sh"
run_test "Post-install exists" "test -f ${PLUGIN_DIR}/scripts/post-install.sh"
run_test "Pre-uninstall exists" "test -f ${PLUGIN_DIR}/scripts/pre-uninstall.sh"

# Help command tests
echo ""
echo "--- Help Command Tests ---"
run_test "Help command" "${PLUGIN_DIR}/main.sh help"
run_test "Help flag" "${PLUGIN_DIR}/main.sh --help"
run_test "Unknown command" "${PLUGIN_DIR}/main.sh unknown" 1

# Config tests
echo ""
echo "--- Configuration Tests ---"
run_test "Config show" "${PLUGIN_DIR}/main.sh config show"
run_test "Config set" "${PLUGIN_DIR}/main.sh config set EXA_TIMEOUT 60"
run_test "Config clear-cache" "${PLUGIN_DIR}/main.sh config clear-cache"

# Search tests (without API key)
echo ""
echo "--- Search Tests (No API Key) ---"
run_test "Search without key" "${PLUGIN_DIR}/main.sh search \"test\"" 1
run_test "Code context without key" "${PLUGIN_DIR}/main.sh code-context \"test\"" 1

# Sources test
echo ""
echo "--- Sources Test ---"
run_test "Sources list" "${PLUGIN_DIR}/main.sh sources"

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total:  $TESTS_TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    exit 1
fi
