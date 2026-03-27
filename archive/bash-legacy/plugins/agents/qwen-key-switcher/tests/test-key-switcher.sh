#!/usr/bin/env bash
# Test suite for Qwen Key Switcher

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${PLUGIN_DIR}/main.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test directory
TEST_KEY_DIR=$(mktemp -d)
export QWEN_KEY_DIR="$TEST_KEY_DIR"

# Cleanup
cleanup() {
    rm -rf "$TEST_KEY_DIR"
}
trap cleanup EXIT

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
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Expected: $expected_exit, Got: $actual_exit"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

run_test_contains() {
    local test_name="$1"
    local test_cmd="$2"
    local expected="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -n "Testing: ${test_name} ... "
    
    set +e
    output=$(eval "$test_cmd" 2>&1)
    set -e
    
    if [[ "$output" == *"$expected"* ]]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Expected to contain: $expected"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "========================================"
echo "Qwen Key Switcher Test Suite"
echo "========================================"
echo ""

# Help tests
echo "--- Help Tests ---"
run_test_contains "Help command" "$MAIN_SH help" "Usage:"
run_test "Help flag" "$MAIN_SH --help" 0
run_test "Unknown command" "$MAIN_SH unknown" 1

# List tests (empty)
echo ""
echo "--- List Tests ---"
run_test_contains "List empty" "$MAIN_SH list" "No keys stored"

# Add tests
echo ""
echo "--- Add Tests ---"
run_test "Add missing key" "$MAIN_SH add" 1
run_test_contains "Add valid key" "$MAIN_SH add sk-test123456789 test_key" "✓ Key added"

# Current tests
echo ""
echo "--- Current Tests ---"
run_test_contains "Current before use" "$MAIN_SH current" "No active key"
run_test_contains "Use key" "$MAIN_SH use 0" "✓ Switched"
run_test_contains "Current after use" "$MAIN_SH current" "test_key"

# Export tests
echo ""
echo "--- Export Tests ---"
run_test_contains "Export" "$MAIN_SH export" "QWEN_API_KEY"

# Rotate tests
echo ""
echo "--- Rotate Tests ---"
run_test_contains "Rotate" "$MAIN_SH rotate" "Switched to key"

# Stats tests
echo ""
echo "--- Stats Tests ---"
run_test_contains "Stats" "$MAIN_SH stats" "Total Requests"

# Health tests
echo ""
echo "--- Health Tests ---"
run_test_contains "Health" "$MAIN_SH health" "Health Check"

# Remove tests
echo ""
echo "--- Remove Tests ---"
run_test_contains "Remove invalid" "$MAIN_SH remove 99" "Invalid index"
run_test_contains "Remove valid" "$MAIN_SH remove 0" "✓ Key removed"

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
