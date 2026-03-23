#!/usr/bin/env bash
# Test suite for Qwen OAuth Switcher

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${PLUGIN_DIR}/main.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test directory
TEST_OAUTH_DIR=$(mktemp -d)
export QWEN_OAUTH_DIR="$TEST_OAUTH_DIR"

# Cleanup
cleanup() {
    rm -rf "$TEST_OAUTH_DIR"
}
trap cleanup EXIT

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

# Test output contains
run_test_contains() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_content="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    echo -n "Testing: ${test_name} ... "
    
    set +e
    output=$(eval "$test_cmd" 2>&1)
    actual_exit=$?
    set -e
    
    if [[ "$output" == *"$expected_content"* ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Expected to contain: $expected_content"
        echo "  Actual output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "========================================"
echo "Qwen OAuth Switcher Test Suite"
echo "========================================"
echo ""
echo "Test directory: $TEST_OAUTH_DIR"
echo ""

# Help command tests
echo "--- Help Command Tests ---"
run_test_contains "Help command" "$MAIN_SH help" "Usage:"
run_test_contains "Help flag" "$MAIN_SH --help" "Commands:"
run_test_contains "Unknown command" "$MAIN_SH unknown" 1

# List command (empty)
echo ""
echo "--- List Command Tests ---"
run_test_contains "List empty" "$MAIN_SH list" "Configured Accounts"

# Add command
echo ""
echo "--- Add Command Tests ---"
run_test "Add account missing name" "echo | $MAIN_SH add" 1

# Current command (empty)
echo ""
echo "--- Current Command Tests ---"
run_test_contains "Current empty" "$MAIN_SH current" "No active account"

# Stats command (empty)
echo ""
echo "--- Stats Command Tests ---"
run_test_contains "Stats empty" "$MAIN_SH stats" "Total Requests: 0"

# Health command (empty)
echo ""
echo "--- Health Command Tests ---"
run_test "Health empty" "$MAIN_SH health" 1

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
