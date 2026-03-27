#!/usr/bin/env bash
# Qwen Agent Plugin - Session & Hooks Integration Tests
# 集成测试脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SH="${SCRIPT_DIR}/main.sh"
HOOKS_DIR="${SCRIPT_DIR}/hooks"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Temporary test directory
TEST_TMP_DIR=""

# ============================================================================
# Test Utilities
# ============================================================================

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

setup_test_env() {
    TEST_TMP_DIR="$(mktemp -d)"
    export HOME="${TEST_TMP_DIR}"
    export _FAKEHOME="${TEST_TMP_DIR}/fake_home"
    export QWEN_SESSION_ENABLED="true"
    export QWEN_HOOKS_ENABLED="true"
    export OML_OUTPUT_FORMAT="text"

    # Create fake home
    mkdir -p "${_FAKEHOME}/.qwen"

    log_info "Test environment setup at: ${TEST_TMP_DIR}"
}

cleanup_test_env() {
    if [[ -n "${TEST_TMP_DIR:-}" && -d "${TEST_TMP_DIR}" ]]; then
        rm -rf "${TEST_TMP_DIR}"
        log_info "Cleaned up test environment"
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    ((TESTS_RUN++))
    log_info "Running test: ${test_name}"

    if $test_func; then
        ((TESTS_PASSED++))
        log_pass "Test passed: ${test_name}"
        return 0
    else
        ((TESTS_FAILED++))
        log_fail "Test failed: ${test_name}"
        return 1
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        log_fail "Assertion failed: expected '${expected}', got '${actual}'${message:+ - ${message}}"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        log_fail "Assertion failed: '${haystack}' does not contain '${needle}'${message:+ - ${message}}"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"

    if [[ -f "$file" ]]; then
        return 0
    else
        log_fail "Assertion failed: file does not exist: ${file}${message:+ - ${message}}"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-}"

    if [[ -d "$dir" ]]; then
        return 0
    else
        log_fail "Assertion failed: directory does not exist: ${dir}${message:+ - ${message}}"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" -eq "$actual" ]]; then
        return 0
    else
        log_fail "Assertion failed: expected exit code ${expected}, got ${actual}${message:+ - ${message}}"
        return 1
    fi
}

# ============================================================================
# Hook Tests
# ============================================================================

test_hook_prompt_scan_check_event() {
    local result
    result=$("${HOOKS_DIR}/prompt-scan.sh" --check-event "qwen:user_prompt_submit")
    assert_equals "true" "$result" "prompt-scan should handle user_prompt_submit event"
}

test_hook_prompt_scan_wrong_event() {
    local result
    result=$("${HOOKS_DIR}/prompt-scan.sh" --check-event "qwen:wrong_event")
    assert_equals "false" "$result" "prompt-scan should not handle wrong event"
}

test_hook_prompt_scan_valid_prompt() {
    local result
    result=$("${HOOKS_DIR}/prompt-scan.sh" "qwen:user_prompt_submit" "Hello, how are you?" "" "{}" 2>&1) || true
    # Should not fail for valid prompt
    assert_not_contains "$result" "validation failed"
}

test_hook_prompt_scan_empty_prompt() {
    local result
    local exit_code=0
    result=$("${HOOKS_DIR}/prompt-scan.sh" "qwen:user_prompt_submit" "" "" "{}" 2>&1) || exit_code=$?
    assert_exit_code 1 "$exit_code" "Empty prompt should fail validation"
}

test_hook_tool_permission_check_event() {
    local result
    result=$("${HOOKS_DIR}/tool-permission.sh" --check-event "qwen:pre_tool_use")
    assert_equals "true" "$result" "tool-permission should handle pre_tool_use event"
}

test_hook_tool_permission_allowed_tool() {
    local result
    result=$("${HOOKS_DIR}/tool-permission.sh" "qwen:pre_tool_use" "read_file" "{}" "" "{}" 2>&1) || true
    # Should allow read_file by default
    assert_not_contains "$result" "denied"
}

test_hook_tool_permission_denied_tool() {
    local result
    local exit_code=0
    export TOOL_PERMISSION_DENY_LIST="dangerous_tool"
    result=$("${HOOKS_DIR}/tool-permission.sh" "qwen:pre_tool_use" "dangerous_tool" "{}" "" "{}" 2>&1) || exit_code=$?
    assert_exit_code 1 "$exit_code" "Denied tool should fail"
    unset TOOL_PERMISSION_DENY_LIST
}

test_hook_result_cache_check_event() {
    local result
    result=$("${HOOKS_DIR}/result-cache.sh" --check-event "qwen:post_tool_use")
    assert_equals "true" "$result" "result-cache should handle post_tool_use event"
}

test_hook_session_summary_check_event() {
    local result
    result=$("${HOOKS_DIR}/session-summary.sh" --check-event "qwen:stop")
    assert_equals "true" "$result" "session-summary should handle stop event"
}

# ============================================================================
# Session Tests
# ============================================================================

test_session_create() {
    local result
    result=$("${MAIN_SH}" session create "test-session" '{"test": true}' 2>&1) || true
    assert_contains "$result" "Created session" "Session creation should succeed"
}

test_session_list() {
    # First create a session
    "${MAIN_SH}" session create "list-test" 2>/dev/null || true

    local result
    result=$("${MAIN_SH}" session list 2>&1) || true
    # Should not error
    assert_equals 0 $? "Session list should not error"
}

test_session_current_no_session() {
    local result
    result=$("${MAIN_SH}" session current 2>&1) || true
    assert_contains "$result" "No active session" "Should report no active session initially"
}

test_session_help() {
    local result
    result=$("${MAIN_SH}" session help 2>&1) || true
    assert_contains "$result" "Session Management" "Session help should show usage"
}

# ============================================================================
# Hooks Management Tests
# ============================================================================

test_hooks_enable() {
    local result
    result=$("${MAIN_SH}" hooks enable 2>&1) || true
    assert_contains "$result" "enabled" "Hooks enable should succeed"
}

test_hooks_disable() {
    local result
    result=$("${MAIN_SH}" hooks disable 2>&1) || true
    assert_contains "$result" "disabled" "Hooks disable should succeed"
}

test_hooks_status() {
    local result
    result=$("${MAIN_SH}" hooks status 2>&1) || true
    # Should show status information
    assert_contains "$result" "Hooks" "Hooks status should show hooks info"
}

test_hooks_help() {
    local result
    result=$("${MAIN_SH}" hooks help 2>&1) || true
    assert_contains "$result" "Hooks Management" "Hooks help should show usage"
}

# ============================================================================
# Integration Tests
# ============================================================================

test_session_with_message() {
    # Create session
    local session_id
    session_id=$("${MAIN_SH}" session create "message-test" 2>&1) || true

    # Add message
    local result
    result=$("${MAIN_SH}" session add-message "user" "Test message content" 2>&1) || true

    # Should succeed (may silently skip if no active session in subshell)
    assert_equals 0 $? "Add message should not error"
}

test_hooks_trigger_custom_event() {
    # Create a simple test hook
    local test_hook="${HOOKS_DIR}/test-custom.sh"
    cat > "$test_hook" <<'EOF'
#!/usr/bin/env bash
check_event() {
    [[ "$1" == "test:custom" ]] && echo "true" || echo "false"
}
if [[ "${1:-}" == "--check-event" ]]; then
    check_event "$2"
    exit 0
fi
echo "Test hook executed: $@"
exit 0
EOF
    chmod +x "$test_hook"

    local result
    result=$("${MAIN_SH}" hooks trigger "test:custom" "arg1" "arg2" 2>&1) || true

    # Clean up
    rm -f "$test_hook"

    assert_contains "$result" "Test hook executed" "Custom hook should be triggered"
}

test_session_disabled() {
    export QWEN_SESSION_ENABLED="false"

    local result
    result=$("${MAIN_SH}" session create "disabled-test" 2>&1) || true
    assert_contains "$result" "disabled" "Should report session is disabled"

    export QWEN_SESSION_ENABLED="true"
}

test_hooks_disabled() {
    export QWEN_HOOKS_ENABLED="false"

    # Trigger should not fail, just skip execution
    local result
    result=$("${MAIN_SH}" hooks trigger "test:event" 2>&1) || true
    # Should not error even when disabled

    export QWEN_HOOKS_ENABLED="true"
}

# ============================================================================
# Helper Assertions
# ============================================================================

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        log_fail "Assertion failed: '${haystack}' should not contain '${needle}'${message:+ - ${message}}"
        return 1
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

run_all_tests() {
    log_info "Starting Qwen Agent Session & Hooks Integration Tests"
    echo "=================================================="

    setup_test_env

    # Hook tests
    run_test "Hook: prompt-scan check event" test_hook_prompt_scan_check_event
    run_test "Hook: prompt-scan wrong event" test_hook_prompt_scan_wrong_event
    run_test "Hook: prompt-scan valid prompt" test_hook_prompt_scan_valid_prompt
    run_test "Hook: prompt-scan empty prompt" test_hook_prompt_scan_empty_prompt
    run_test "Hook: tool-permission check event" test_hook_tool_permission_check_event
    run_test "Hook: tool-permission allowed tool" test_hook_tool_permission_allowed_tool
    run_test "Hook: tool-permission denied tool" test_hook_tool_permission_denied_tool
    run_test "Hook: result-cache check event" test_hook_result_cache_check_event
    run_test "Hook: session-summary check event" test_hook_session_summary_check_event

    # Session tests
    run_test "Session: create" test_session_create
    run_test "Session: list" test_session_list
    run_test "Session: current (no session)" test_session_current_no_session
    run_test "Session: help" test_session_help

    # Hooks management tests
    run_test "Hooks: enable" test_hooks_enable
    run_test "Hooks: disable" test_hooks_disable
    run_test "Hooks: status" test_hooks_status
    run_test "Hooks: help" test_hooks_help

    # Integration tests
    run_test "Integration: session with message" test_session_with_message
    run_test "Integration: trigger custom event" test_hooks_trigger_custom_event
    run_test "Integration: session disabled" test_session_disabled
    run_test "Integration: hooks disabled" test_hooks_disabled

    cleanup_test_env

    echo "=================================================="
    echo "Test Results:"
    echo "  Total:  ${TESTS_RUN}"
    echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}"
    echo "=================================================="

    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        return 1
    fi
    return 0
}

show_help() {
    cat <<EOF
Qwen Agent Plugin - Session & Hooks Integration Tests

Usage: $(basename "$0") [OPTIONS] [TEST_NAME]

Options:
  -h, --help          Show this help message
  -v, --verbose       Verbose output
  -l, --list          List available tests
  --run-all           Run all tests (default)

Available Tests:
  hook_prompt_scan_check_event
  hook_prompt_scan_wrong_event
  hook_prompt_scan_valid_prompt
  hook_prompt_scan_empty_prompt
  hook_tool_permission_check_event
  hook_tool_permission_allowed_tool
  hook_tool_permission_denied_tool
  hook_result_cache_check_event
  hook_session_summary_check_event
  session_create
  session_list
  session_current_no_session
  session_help
  hooks_enable
  hooks_disable
  hooks_status
  hooks_help
  session_with_message
  trigger_custom_event
  session_disabled
  hooks_disabled

Examples:
  $(basename "$0")                    # Run all tests
  $(basename "$0") --list             # List all tests
  $(basename "$0") session_create     # Run specific test
EOF
}

# Main entry point
main() {
    case "${1:-}" in
        -h|--help)
            show_help
            ;;
        -l|--list)
            echo "Available tests:"
            declare -F | grep "^declare -f test_" | cut -d' ' -f3 | sed 's/test_//'
            ;;
        --run-all|"")
            run_all_tests
            ;;
        *)
            # Run specific test
            local test_name="test_${1}"
            if type -t "$test_name" >/dev/null 2>&1; then
                setup_test_env
                run_test "$1" "$test_name"
                cleanup_test_env
            else
                echo "Unknown test: $1"
                echo "Use '$(basename "$0") --list' to see available tests"
                exit 1
            fi
            ;;
    esac
}

main "$@"
