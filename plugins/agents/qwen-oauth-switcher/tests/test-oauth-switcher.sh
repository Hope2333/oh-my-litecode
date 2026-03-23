#!/usr/bin/env bash
# Test suite for Qwen OAuth Switcher

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${PLUGIN_DIR}/main.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test directory
TEST_OAUTH_DIR=$(mktemp -d)
export QWEN_OAUTH_DIR="$TEST_OAUTH_DIR"
export QWEN_CONFIG_DIR="$TEST_OAUTH_DIR/qwen-config"

# Cleanup
cleanup() {
    rm -rf "$TEST_OAUTH_DIR"
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
echo "Qwen OAuth Switcher Test Suite"
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
run_test_contains "List empty" "$MAIN_SH list" "No accounts stored"

# Add tests
echo ""
echo "--- Add Tests ---"
run_test "Add missing name" "$MAIN_SH add" 1

# Create test account
mkdir -p "$TEST_OAUTH_DIR/accounts/test"
echo '{"test": true, "created_at": "2026-03-23"}' > "$TEST_OAUTH_DIR/accounts/test/settings.json"

# Current tests
echo ""
echo "--- Current Tests ---"
run_test_contains "Current before use" "$MAIN_SH current" "No active account"

# Use tests
echo ""
echo "--- Use Tests ---"
run_test_contains "Use account" "$MAIN_SH use test" "✓ Switched"
run_test_contains "Current after use" "$MAIN_SH current" "test"

# Rotate tests
echo ""
echo "--- Rotate Tests ---"
mkdir -p "$TEST_OAUTH_DIR/accounts/test2"
echo '{"test": true}' > "$TEST_OAUTH_DIR/accounts/test2/settings.json"
run_test_contains "Rotate" "$MAIN_SH rotate" "Switched to account"

# Backup tests
echo ""
echo "--- Backup Tests ---"
mkdir -p "$TEST_OAUTH_DIR/qwen-config"
echo '{"backup": true}' > "$TEST_OAUTH_DIR/qwen-config/settings.json"
run_test_contains "Backup" "$MAIN_SH backup" "Backup created"

# Remove tests
echo ""
echo "--- Remove Tests ---"
run_test "Remove invalid" "$MAIN_SH remove invalid" 1

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
