#!/usr/bin/env bash
# OML Test Suite
# Tests for OML plugin system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OML_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OML="${OML_ROOT}/oml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OML Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect platform for test expectations
CURRENT_PLATFORM=$(source "$OML_ROOT/core/platform.sh" && oml_platform_detect)
echo -e "${BLUE}Current Platform: ${CURRENT_PLATFORM}${NC}"
echo ""

# Platform tests
echo -e "${YELLOW}[Platform Tests]${NC}"

run_test "Platform detect" "$OML platform detect" 0

# Platform-specific expectations
if [[ "$CURRENT_PLATFORM" == "termux" ]]; then
    run_test_contains "Platform detect output (termux)" "$OML platform detect" "termux"
elif [[ "$CURRENT_PLATFORM" == "arch" ]] || [[ "$CURRENT_PLATFORM" == "manjaro" ]] || [[ "$CURRENT_PLATFORM" == "endeavouros" ]]; then
    run_test_contains "Platform detect output (arch)" "$OML platform detect" "arch"
elif [[ "$CURRENT_PLATFORM" == "debian" ]] || [[ "$CURRENT_PLATFORM" == "ubuntu" ]]; then
    run_test_contains "Platform detect output (debian)" "$OML platform detect" "debian"
elif [[ "$CURRENT_PLATFORM" == "fedora" ]]; then
    run_test_contains "Platform detect output (fedora)" "$OML platform detect" "fedora"
else
    run_test_contains "Platform detect output (gnu-linux)" "$OML platform detect" "gnu-linux"
fi

run_test "Platform info" "$OML platform info" 0
run_test "Platform doctor" "$OML platform doctor" 0

# Plugin tests
echo ""
echo -e "${YELLOW}[Plugin Tests]${NC}"

run_test "Plugins list" "$OML plugins list" 0
run_test_contains "Plugins list contains qwen" "$OML plugins list" "qwen"
run_test "Plugins list agents" "$OML plugins list agents" 0
run_test "Plugins help" "$OML plugins help" 0

# Qwen plugin tests
echo ""
echo -e "${YELLOW}[Qwen Plugin Tests]${NC}"

run_test "Qwen help" "$OML qwen --help" 0
run_test_contains "Qwen help contains ctx7" "$OML qwen --help" "ctx7"
run_test "Qwen ctx7 list" "$OML qwen ctx7 list" 0
run_test "Qwen ctx7 current" "$OML qwen ctx7 current" 0
run_test "Qwen models list" "$OML qwen models list" 0

# Worker plugin tests
echo ""
echo -e "${YELLOW}[Worker Plugin Tests]${NC}"

run_test "Worker help" "$OML worker help" 0
run_test_contains "Worker help contains spawn" "$OML worker help" "spawn"
run_test "Worker status" "$OML worker status" 0
run_test "Worker status running" "$OML worker status running" 0

# MCPs command tests
echo ""
echo -e "${YELLOW}[MCPs Command Tests]${NC}"

run_test "MCPs list" "$OML mcps list" 0
run_test "MCPs help" "$OML mcps help" 0

# Core function tests
echo ""
echo -e "${YELLOW}[Core Function Tests]${NC}"

# Platform-specific test for platform.sh
if [[ "$CURRENT_PLATFORM" == "termux" ]]; then
    run_test_contains "Source platform.sh (termux)" "source $OML_ROOT/core/platform.sh && oml_platform_detect" "termux"
elif [[ "$CURRENT_PLATFORM" == "arch" ]] || [[ "$CURRENT_PLATFORM" == "manjaro" ]] || [[ "$CURRENT_PLATFORM" == "endeavouros" ]]; then
    run_test_contains "Source platform.sh (arch)" "source $OML_ROOT/core/platform.sh && oml_platform_detect" "arch"
elif [[ "$CURRENT_PLATFORM" == "debian" ]] || [[ "$CURRENT_PLATFORM" == "ubuntu" ]]; then
    run_test_contains "Source platform.sh (debian)" "source $OML_ROOT/core/platform.sh && oml_platform_detect" "debian"
elif [[ "$CURRENT_PLATFORM" == "fedora" ]]; then
    run_test_contains "Source platform.sh (fedora)" "source $OML_ROOT/core/platform.sh && oml_platform_detect" "fedora"
else
    run_test_contains "Source platform.sh (gnu-linux)" "source $OML_ROOT/core/platform.sh && oml_platform_detect" "gnu-linux"
fi

run_test_contains "Source plugin-loader.sh" "source $OML_ROOT/core/plugin-loader.sh && oml_plugins_list" "qwen"
run_test_contains "Source task-registry.sh" "source $OML_ROOT/core/task-registry.sh && oml_task_generate_id" "task-"

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
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
