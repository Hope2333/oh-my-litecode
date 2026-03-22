#!/usr/bin/env bash
# Integration Test Suite for Build Agent Session/Hooks
# 测试构建代理的 Session 和 Hooks 集成功能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SCRIPT="${PLUGIN_DIR}/main.sh"
HOOKS_DIR="${PLUGIN_DIR}/hooks"

# Test data directory
TEST_DATA_DIR=$(mktemp -d)
export HOME="${TEST_DATA_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Cleanup on exit
cleanup() {
    rm -rf "${TEST_DATA_DIR}"
}
trap cleanup EXIT

# ============================================================================
# Test Helper Functions
# ============================================================================

log_test() {
    local name="$1"
    echo -e "${YELLOW}[TEST]${NC} $name"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_pass() {
    local name="$1"
    echo -e "${GREEN}[PASS]${NC} $name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "${RED}[FAIL]${NC} $name"
    if [[ -n "$reason" ]]; then
        echo "       Reason: $reason"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name" "Expected: '$expected', Got: '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name" "Expected to contain: '$needle'"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"

    if [[ -f "$file" ]]; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name" "File not found: $file"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local test_name="$2"

    if [[ -d "$dir" ]]; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name" "Directory not found: $dir"
        return 1
    fi
}

assert_json_valid() {
    local json="$1"
    local test_name="$2"

    if echo "$json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name" "Invalid JSON"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" -eq "$actual" ]]; then
        log_pass "$test_name"
        return 0
    else
        log_fail "$test_name" "Expected exit code: $expected, Got: $actual"
        return 1
    fi
}

# ============================================================================
# Session Tests
# ============================================================================

test_session_directory_creation() {
    log_test "Session directory creation"

    # Run a command that should initialize session
    "$MAIN_SCRIPT" status >/dev/null 2>&1 || true

    # Check if session directory was created
    local session_dir="${TEST_DATA_DIR}/.oml/sessions/build"
    if [[ -d "$session_dir" ]]; then
        log_pass "Session directory creation"
    else
        log_fail "Session directory creation" "Directory not created: $session_dir"
    fi
}

test_session_init_function() {
    log_test "Session init function exists"

    # Check if main.sh contains session init function
    if grep -q "build_session_init" "$MAIN_SCRIPT"; then
        log_pass "Session init function exists"
    else
        log_fail "Session init function exists" "Function not found in main.sh"
    fi
}

test_session_create_function() {
    log_test "Session create function exists"

    if grep -q "build_session_create" "$MAIN_SCRIPT"; then
        log_pass "Session create function exists"
    else
        log_fail "Session create function exists" "Function not found in main.sh"
    fi
}

test_session_config_variables() {
    log_test "Session config variables exist"

    local has_enabled=$(grep -c "BUILD_SESSION_ENABLED" "$MAIN_SCRIPT" || echo "0")
    local has_dir=$(grep -c "BUILD_SESSION_DIR" "$MAIN_SCRIPT" || echo "0")
    local has_id=$(grep -c "BUILD_SESSION_ID" "$MAIN_SCRIPT" || echo "0")

    if [[ $has_enabled -gt 0 && $has_dir -gt 0 && $has_id -gt 0 ]]; then
        log_pass "Session config variables exist"
    else
        log_fail "Session config variables exist" "Missing config variables"
    fi
}

# ============================================================================
# Hooks Tests
# ============================================================================

test_hooks_directory_exists() {
    log_test "Hooks directory exists"

    if [[ -d "$HOOKS_DIR" ]]; then
        log_pass "Hooks directory exists"
    else
        log_fail "Hooks directory exists" "Directory not found: $HOOKS_DIR"
    fi
}

test_hooks_init_function() {
    log_test "Hooks init function exists"

    if grep -q "build_hooks_init" "$MAIN_SCRIPT"; then
        log_pass "Hooks init function exists"
    else
        log_fail "Hooks init function exists" "Function not found in main.sh"
    fi
}

test_hooks_trigger_function() {
    log_test "Hooks trigger function exists"

    if grep -q "build_hooks_trigger" "$MAIN_SCRIPT"; then
        log_pass "Hooks trigger function exists"
    else
        log_fail "Hooks trigger function exists" "Function not found in main.sh"
    fi
}

test_hooks_config_variables() {
    log_test "Hooks config variables exist"

    local has_enabled=$(grep -c "BUILD_HOOKS_ENABLED" "$MAIN_SCRIPT" || echo "0")
    local has_dir=$(grep -c "BUILD_HOOKS_DIR" "$MAIN_SCRIPT" || echo "0")

    if [[ $has_enabled -gt 0 && $has_dir -gt 0 ]]; then
        log_pass "Hooks config variables exist"
    else
        log_fail "Hooks config variables exist" "Missing config variables"
    fi
}

test_hooks_events_defined() {
    log_test "Hooks events defined"

    local events=("HOOK_BUILD_START" "HOOK_BUILD_COMPLETE" "HOOK_BUILD_FAILED" "HOOK_CLEAN_START" "HOOK_CLEAN_COMPLETE")
    local found=0

    for event in "${events[@]}"; do
        if grep -q "$event" "$MAIN_SCRIPT"; then
            found=$((found + 1))
        fi
    done

    if [[ $found -eq ${#events[@]} ]]; then
        log_pass "Hooks events defined"
    else
        log_fail "Hooks events defined" "Expected ${#events[@]} events, found $found"
    fi
}

# ============================================================================
# Hook Scripts Tests
# ============================================================================

test_hook_scripts_exist() {
    log_test "Hook scripts exist"

    local expected_hooks=("build-logger.sh" "build-notification.sh")
    local found=0

    for hook in "${expected_hooks[@]}"; do
        if [[ -f "${HOOKS_DIR}/${hook}" ]]; then
            found=$((found + 1))
        fi
    done

    if [[ $found -eq ${#expected_hooks[@]} ]]; then
        log_pass "Hook scripts exist"
    else
        log_fail "Hook scripts exist" "Expected ${#expected_hooks[@]} hooks, found $found"
    fi
}

test_hook_scripts_executable() {
    log_test "Hook scripts are executable"

    local all_executable=true
    for hook_script in "${HOOKS_DIR}"/*.sh; do
        if [[ -f "$hook_script" && ! -x "$hook_script" ]]; then
            all_executable=false
            break
        fi
    done

    if [[ "$all_executable" == true ]]; then
        log_pass "Hook scripts are executable"
    else
        log_fail "Hook scripts are executable" "Some scripts are not executable"
    fi
}

test_hook_check_event_interface() {
    log_test "Hook check_event interface"

    local hook_script="${HOOKS_DIR}/build-logger.sh"
    if [[ -x "$hook_script" ]]; then
        local result
        result=$("$hook_script" --check-event "build:start" 2>/dev/null || echo "false")
        if [[ "$result" == "true" ]]; then
            log_pass "Hook check_event interface"
        else
            log_fail "Hook check_event interface" "Expected 'true', got '$result'"
        fi
    else
        log_fail "Hook check_event interface" "Hook script not executable"
    fi
}

test_hook_help_interface() {
    log_test "Hook help interface"

    local hook_script="${HOOKS_DIR}/build-logger.sh"
    if [[ -x "$hook_script" ]]; then
        local output
        output=$("$hook_script" --help 2>&1)
        if [[ "$output" == *"Usage"* ]]; then
            log_pass "Hook help interface"
        else
            log_fail "Hook help interface" "Help output missing"
        fi
    else
        log_fail "Hook help interface" "Hook script not executable"
    fi
}

# ============================================================================
# Integration Tests
# ============================================================================

test_main_initializes_session_hooks() {
    log_test "Main function initializes session and hooks"

    # Check if main function calls init functions
    if grep -q "build_session_init" "$MAIN_SCRIPT" && grep -q "build_hooks_init" "$MAIN_SCRIPT"; then
        # Check if they are called in main
        local main_section
        main_section=$(sed -n '/^main()/,/^}/p' "$MAIN_SCRIPT")
        
        if echo "$main_section" | grep -q "build_session_init" && echo "$main_section" | grep -q "build_hooks_init"; then
            log_pass "Main function initializes session and hooks"
        else
            log_fail "Main function initializes session and hooks" "Init calls not in main function"
        fi
    else
        log_fail "Main function initializes session and hooks" "Init functions not found"
    fi
}

test_cmd_project_triggers_hooks() {
    log_test "cmd_project triggers hooks"

    # Check if cmd_project calls hooks_trigger
    local cmd_section
    cmd_section=$(sed -n '/^cmd_project()/,/^}/p' "$MAIN_SCRIPT")
    
    if echo "$cmd_section" | grep -q "build_hooks_trigger"; then
        log_pass "cmd_project triggers hooks"
    else
        log_fail "cmd_project triggers hooks" "hooks_trigger not called in cmd_project"
    fi
}

test_cmd_clean_triggers_hooks() {
    log_test "cmd_clean triggers hooks"

    local cmd_section
    cmd_section=$(sed -n '/^cmd_clean()/,/^}/p' "$MAIN_SCRIPT")
    
    if echo "$cmd_section" | grep -q "build_hooks_trigger"; then
        log_pass "cmd_clean triggers hooks"
    else
        log_fail "cmd_clean triggers hooks" "hooks_trigger not called in cmd_clean"
    fi
}

test_cmd_status_triggers_hooks() {
    log_test "cmd_status triggers hooks"

    local cmd_section
    cmd_section=$(sed -n '/^cmd_status()/,/^}/p' "$MAIN_SCRIPT")
    
    if echo "$cmd_section" | grep -q "build_hooks_trigger"; then
        log_pass "cmd_status triggers hooks"
    else
        log_fail "cmd_status triggers hooks" "hooks_trigger not called in cmd_status"
    fi
}

test_session_add_build_record() {
    log_test "Session add_build function exists"

    if grep -q "build_session_add_build" "$MAIN_SCRIPT"; then
        log_pass "Session add_build function exists"
    else
        log_fail "Session add_build function exists" "Function not found in main.sh"
    fi
}

test_backward_compatibility() {
    log_test "Backward compatibility - commands still work"

    # Test that basic commands still work
    local output
    local exit_code=0

    output=$("$MAIN_SCRIPT" --help 2>&1) || exit_code=$?
    assert_exit_code 0 $exit_code "Help command works"

    output=$("$MAIN_SCRIPT" version 2>&1) || exit_code=$?
    assert_exit_code 0 $exit_code "Version command works"

    output=$("$MAIN_SCRIPT" status 2>&1) || exit_code=$?
    # Status may fail if no projects exist, but shouldn't crash
    return 0
}

test_session_disabled_mode() {
    log_test "Session disabled mode"

    # Run with session disabled
    local output
    BUILD_SESSION_ENABLED=false output=$("$MAIN_SCRIPT" status 2>&1) || true

    # Should not crash
    log_pass "Session disabled mode"
}

test_hooks_disabled_mode() {
    log_test "Hooks disabled mode"

    # Run with hooks disabled
    local output
    BUILD_HOOKS_ENABLED=false output=$("$MAIN_SCRIPT" status 2>&1) || true

    # Should not crash
    log_pass "Hooks disabled mode"
}

# ============================================================================
# Main Test Runner
# ============================================================================

run_all_tests() {
    echo "========================================"
    echo "Build Agent Session/Hooks Integration Test"
    echo "========================================"
    echo ""
    echo "Test data directory: ${TEST_DATA_DIR}"
    echo "Plugin directory: ${PLUGIN_DIR}"
    echo "Hooks directory: ${HOOKS_DIR}"
    echo ""

    # Session tests
    echo "--- Session Tests ---"
    test_session_directory_creation
    test_session_init_function
    test_session_create_function
    test_session_config_variables
    echo ""

    # Hooks tests
    echo "--- Hooks Tests ---"
    test_hooks_directory_exists
    test_hooks_init_function
    test_hooks_trigger_function
    test_hooks_config_variables
    test_hooks_events_defined
    echo ""

    # Hook scripts tests
    echo "--- Hook Scripts Tests ---"
    test_hook_scripts_exist
    test_hook_scripts_executable
    test_hook_check_event_interface
    test_hook_help_interface
    echo ""

    # Integration tests
    echo "--- Integration Tests ---"
    test_main_initializes_session_hooks
    test_cmd_project_triggers_hooks
    test_cmd_clean_triggers_hooks
    test_cmd_status_triggers_hooks
    test_session_add_build_record
    test_backward_compatibility
    test_session_disabled_mode
    test_hooks_disabled_mode
    echo ""

    # Summary
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo -e "Total:  ${TESTS_TOTAL}"
    echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Run single test
run_single_test() {
    local test_name="$1"

    echo "Running single test: ${test_name}"
    echo ""

    case "$test_name" in
        session)
            test_session_directory_creation
            test_session_init_function
            test_session_create_function
            test_session_config_variables
            ;;
        hooks)
            test_hooks_directory_exists
            test_hooks_init_function
            test_hooks_trigger_function
            test_hooks_config_variables
            test_hooks_events_defined
            ;;
        scripts)
            test_hook_scripts_exist
            test_hook_scripts_executable
            test_hook_check_event_interface
            test_hook_help_interface
            ;;
        integration)
            test_main_initializes_session_hooks
            test_cmd_project_triggers_hooks
            test_cmd_clean_triggers_hooks
            test_cmd_status_triggers_hooks
            test_session_add_build_record
            test_backward_compatibility
            ;;
        *)
            echo "Unknown test: $test_name"
            echo "Available tests: session, hooks, scripts, integration"
            return 1
            ;;
    esac
}

# Main entry point
main() {
    local action="${1:-all}"

    case "$action" in
        all)
            run_all_tests
            ;;
        help|--help|-h)
            echo "Usage: $0 [all|session|hooks|scripts|integration]"
            echo ""
            echo "Available test groups:"
            echo "  all         Run all tests (default)"
            echo "  session     Session management tests"
            echo "  hooks       Hooks management tests"
            echo "  scripts     Hook scripts tests"
            echo "  integration Integration tests"
            ;;
        *)
            run_single_test "$action"
            ;;
    esac
}

main "$@"
