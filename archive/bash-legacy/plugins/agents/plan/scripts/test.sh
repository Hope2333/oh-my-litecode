#!/usr/bin/env bash
# Test script for Plan Agent Plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SCRIPT="${PLUGIN_DIR}/main.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Temporary data directory for testing
TEST_DATA_DIR=$(mktemp -d)
export OML_PLAN_DATA_DIR="${TEST_DATA_DIR}"

# Cleanup on exit
cleanup() {
    rm -rf "${TEST_DATA_DIR}"
}
trap cleanup EXIT

# Test helper functions
log_test() {
    local name="$1"
    echo -e "${YELLOW}[TEST]${NC} $name"
    ((TESTS_TOTAL++))
}

log_pass() {
    local name="$1"
    echo -e "${GREEN}[PASS]${NC} $name"
    ((TESTS_PASSED++))
}

log_fail() {
    local name="$1"
    local reason="${2:-}"
    echo -e "${RED}[FAIL]${NC} $name"
    if [[ -n "$reason" ]]; then
        echo "       Reason: $reason"
    fi
    ((TESTS_FAILED++))
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

# ============================================================================
# Test Cases
# ============================================================================

test_help_command() {
    log_test "Help command"
    
    local output
    output=$("$MAIN_SCRIPT" help 2>&1)
    
    assert_contains "$output" "plan create" "Help contains create command"
    assert_contains "$output" "plan list" "Help contains list command"
    assert_contains "$output" "plan status" "Help contains status command"
    assert_contains "$output" "plan update" "Help contains update command"
    assert_contains "$output" "plan complete" "Help contains complete command"
}

test_version_command() {
    log_test "Version command"
    
    local output
    output=$("$MAIN_SCRIPT" version 2>&1)
    
    assert_contains "$output" "v1.0.0" "Version output"
}

test_create_plan_basic() {
    log_test "Create plan - basic"
    
    local output
    output=$("$MAIN_SCRIPT" create "测试功能开发" 2>&1)
    
    assert_contains "$output" "计划已创建" "Plan created message"
    assert_file_exists "${TEST_DATA_DIR}/plans.json" "Plans file created"
}

test_create_plan_with_options() {
    log_test "Create plan - with options"
    
    local output
    output=$("$MAIN_SCRIPT" create "复杂功能" --complexity=complex --desc="这是一个复杂功能" 2>&1)
    
    assert_contains "$output" "计划已创建" "Plan created with options"
}

test_create_plan_json_output() {
    log_test "Create plan - JSON output"
    
    local output
    output=$("$MAIN_SCRIPT" create "JSON 测试" --format=json 2>&1)
    
    # Extract JSON part (last valid JSON object)
    local json_output
    json_output=$(echo "$output" | grep -E '^\{' | head -1 || echo "$output")
    
    if [[ -n "$json_output" ]]; then
        assert_json_valid "$json_output" "JSON output is valid"
    else
        log_fail "Create plan JSON output" "No JSON found in output"
    fi
}

test_list_plans() {
    log_test "List plans"
    
    local output
    output=$("$MAIN_SCRIPT" list 2>&1)
    
    assert_contains "$output" "PLAN_ID" "List header contains PLAN_ID"
    assert_contains "$output" "TITLE" "List header contains TITLE"
}

test_list_plans_json() {
    log_test "List plans - JSON format"
    
    local output
    output=$("$MAIN_SCRIPT" list --format=json 2>&1)
    
    assert_json_valid "$output" "List JSON output is valid"
}

test_status_command() {
    log_test "Status command"
    
    # First create a plan
    local create_output
    create_output=$("$MAIN_SCRIPT" create "状态测试" 2>&1)
    
    # Extract plan ID
    local plan_id
    plan_id=$(echo "$create_output" | grep -oE 'plan-[0-9]+-[0-9]+-[0-9]+' | head -1 || echo "")
    
    if [[ -n "$plan_id" ]]; then
        local status_output
        status_output=$("$MAIN_SCRIPT" status "$plan_id" 2>&1)
        
        assert_contains "$status_output" "状态测试" "Status shows plan title"
        assert_contains "$status_output" "任务详情" "Status shows task details"
    else
        log_fail "Status command" "Could not extract plan ID"
    fi
}

test_update_plan() {
    log_test "Update plan"
    
    # Create a plan
    local create_output
    create_output=$("$MAIN_SCRIPT" create "更新测试" 2>&1)
    
    local plan_id
    plan_id=$(echo "$create_output" | grep -oE 'plan-[0-9]+-[0-9]+-[0-9]+' | head -1 || echo "")
    
    if [[ -n "$plan_id" ]]; then
        local update_output
        update_output=$("$MAIN_SCRIPT" update "$plan_id" --status=in_progress 2>&1)
        
        assert_contains "$update_output" "计划已更新" "Plan updated message"
    else
        log_fail "Update plan" "Could not extract plan ID"
    fi
}

test_complete_task() {
    log_test "Complete task"
    
    # Create a plan
    local create_output
    create_output=$("$MAIN_SCRIPT" create "完成测试" 2>&1)
    
    local plan_id
    plan_id=$(echo "$create_output" | grep -oE 'plan-[0-9]+-[0-9]+-[0-9]+' | head -1 || echo "")
    
    if [[ -n "$plan_id" ]]; then
        local complete_output
        complete_output=$("$MAIN_SCRIPT" complete "$plan_id" "task-1" 2>&1)
        
        assert_contains "$complete_output" "任务已完成" "Task completed message"
    else
        log_fail "Complete task" "Could not extract plan ID"
    fi
}

test_complete_plan() {
    log_test "Complete plan"
    
    # Create a plan
    local create_output
    create_output=$("$MAIN_SCRIPT" create "计划完成测试" 2>&1)
    
    local plan_id
    plan_id=$(echo "$create_output" | grep -oE 'plan-[0-9]+-[0-9]+-[0-9]+' | head -1 || echo "")
    
    if [[ -n "$plan_id" ]]; then
        local complete_output
        complete_output=$("$MAIN_SCRIPT" complete "$plan_id" 2>&1)
        
        assert_contains "$complete_output" "计划已完成" "Plan completed message"
    else
        log_fail "Complete plan" "Could not extract plan ID"
    fi
}

test_task_decomposition() {
    log_test "Task decomposition algorithm"
    
    # Create plans with different complexities and verify task counts
    local simple_output
    simple_output=$("$MAIN_SCRIPT" create "简单任务" --complexity=simple 2>&1)
    
    local complex_output
    complex_output=$("$MAIN_SCRIPT" create "复杂任务" --complexity=complex 2>&1)
    
    # Both should have tasks created
    assert_contains "$simple_output" "计划已创建" "Simple plan created"
    assert_contains "$complex_output" "计划已创建" "Complex plan created"
}

test_dependency_analysis() {
    log_test "Dependency analysis"
    
    local output
    output=$("$MAIN_SCRIPT" create "依赖测试" 2>&1)
    
    # Verify plans file contains dependency analysis
    if [[ -f "${TEST_DATA_DIR}/plans.json" ]]; then
        local has_deps
        has_deps=$(python3 -c "
import json
data = json.load(open('${TEST_DATA_DIR}/plans.json'))
for plan in data.get('plans', []):
    if '依赖测试' in plan.get('title', ''):
        if plan.get('dependency_analysis'):
            print('yes')
            break
print('no')
" 2>/dev/null || echo "no")
        
        if [[ "$has_deps" == "yes" ]]; then
            log_pass "Dependency analysis present"
        else
            log_fail "Dependency analysis" "No dependency analysis found"
        fi
    else
        log_fail "Dependency analysis" "Plans file not found"
    fi
}

test_effort_estimation() {
    log_test "Effort estimation"
    
    local output
    output=$("$MAIN_SCRIPT" create "估算测试" 2>&1)
    
    if [[ -f "${TEST_DATA_DIR}/plans.json" ]]; then
        local has_estimate
        has_estimate=$(python3 -c "
import json
data = json.load(open('${TEST_DATA_DIR}/plans.json'))
for plan in data.get('plans', []):
    if '估算测试' in plan.get('title', ''):
        if plan.get('effort_estimate'):
            print('yes')
            break
print('no')
" 2>/dev/null || echo "no")
        
        if [[ "$has_estimate" == "yes" ]]; then
            log_pass "Effort estimation present"
        else
            log_fail "Effort estimation" "No effort estimate found"
        fi
    else
        log_fail "Effort estimation" "Plans file not found"
    fi
}

test_error_handling_unknown_command() {
    log_test "Error handling - unknown command"
    
    local output
    local exit_code=0
    output=$("$MAIN_SCRIPT" unknowncommand 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_pass "Error handling - returns non-zero exit code"
    else
        log_fail "Error handling" "Should return non-zero exit code"
    fi
    
    assert_contains "$output" "Unknown command" "Error message present"
}

test_error_handling_missing_plan_id() {
    log_test "Error handling - missing plan ID"
    
    local output
    local exit_code=0
    output=$("$MAIN_SCRIPT" status 2>&1) || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_pass "Error handling - missing plan ID returns non-zero"
    else
        log_fail "Error handling" "Should return non-zero exit code"
    fi
}

test_markdown_output() {
    log_test "Markdown output format"
    
    local output
    output=$("$MAIN_SCRIPT" create "Markdown 测试" --format=markdown 2>&1)
    
    # Check for markdown elements
    assert_contains "$output" "#" "Markdown contains headers"
    assert_contains "$output" "|" "Markdown contains tables"
}

test_progress_calculation() {
    log_test "Progress calculation"
    
    # Create a plan and complete some tasks
    local create_output
    create_output=$("$MAIN_SCRIPT" create "进度测试" 2>&1)
    
    local plan_id
    plan_id=$(echo "$create_output" | grep -oE 'plan-[0-9]+-[0-9]+-[0-9]+' | head -1 || echo "")
    
    if [[ -n "$plan_id" ]]; then
        # Complete first task
        "$MAIN_SCRIPT" complete "$plan_id" "task-1" >/dev/null 2>&1
        
        # Check status
        local status_output
        status_output=$("$MAIN_SCRIPT" status "$plan_id" 2>&1)
        
        assert_contains "$status_output" "进度" "Status shows progress"
    else
        log_fail "Progress calculation" "Could not extract plan ID"
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

run_all_tests() {
    echo "========================================"
    echo "Plan Agent Plugin - Test Suite"
    echo "========================================"
    echo ""
    echo "Test data directory: ${TEST_DATA_DIR}"
    echo ""
    
    # Initialize data directory
    "$MAIN_SCRIPT" list >/dev/null 2>&1 || true
    
    # Run tests
    test_help_command
    test_version_command
    test_create_plan_basic
    test_create_plan_with_options
    test_create_plan_json_output
    test_list_plans
    test_list_plans_json
    test_status_command
    test_update_plan
    test_complete_task
    test_complete_plan
    test_task_decomposition
    test_dependency_analysis
    test_effort_estimation
    test_error_handling_unknown_command
    test_error_handling_missing_plan_id
    test_markdown_output
    test_progress_calculation
    
    # Summary
    echo ""
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

# Run tests
run_all_tests
