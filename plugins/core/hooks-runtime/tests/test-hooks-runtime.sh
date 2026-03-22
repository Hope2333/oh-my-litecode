#!/usr/bin/env bash
# OML Hooks Runtime Plugin - 测试套件
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CORE_DIR="${PLUGIN_DIR}/../../core"

# 测试统计
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 测试临时目录
TEST_TEMP_DIR=""

# ============================================================================
# 测试工具
# ============================================================================

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export OML_HOOKS_CONFIG_DIR="${TEST_TEMP_DIR}/hooks"
    export OML_HOOKS_REGISTRY_FILE="${TEST_TEMP_DIR}/hooks/registry.json"
    export OML_EVENT_QUEUE_DIR="${TEST_TEMP_DIR}/events/queue"
    export OML_EVENT_LOGS_DIR="${TEST_TEMP_DIR}/events/logs"
    export OML_DISPATCHER_LOGS_DIR="${TEST_TEMP_DIR}/hooks/dispatcher"

    # 源核心模块
    for module in platform event-bus hooks-registry hooks-dispatcher hooks-engine; do
        [[ -f "${CORE_DIR}/${module}.sh" ]] && source "${CORE_DIR}/${module}.sh"
    done
}

teardown() {
    [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]] && rm -rf "$TEST_TEMP_DIR"
}

assert_true() {
    local condition="$1"
    local message="${2:-}"

    if eval "$condition"; then
        return 0
    else
        [[ -n "$message" ]] && echo "  $message"
        return 1
    fi
}

assert_file_exists() {
    [[ -f "$1" ]] || { echo "  File not found: $1"; return 1; }
}

run_test() {
    local name="$1"
    local func="$2"

    ((TESTS_RUN++))
    echo -n "  Testing: $name... "

    if $func; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASSED${NC}"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAILED${NC}"
    fi
}

# ============================================================================
# 插件测试
# ============================================================================

test_plugin_main_exists() {
    assert_file_exists "${SCRIPT_DIR}/main.sh"
}

test_plugin_json_valid() {
    local plugin_json="${SCRIPT_DIR}/plugin.json"
    assert_file_exists "$plugin_json"

    python3 -c "import json; json.load(open('${plugin_json}'))" 2>/dev/null
}

test_plugin_lib_exports() {
    assert_file_exists "${SCRIPT_DIR}/lib/event-bus-exports.sh" && \
    assert_file_exists "${SCRIPT_DIR}/lib/registry-exports.sh" && \
    assert_file_exists "${SCRIPT_DIR}/lib/dispatcher-exports.sh" && \
    assert_file_exists "${SCRIPT_DIR}/lib/engine-exports.sh"
}

test_plugin_scripts() {
    assert_file_exists "${SCRIPT_DIR}/scripts/post-install.sh" && \
    assert_file_exists "${SCRIPT_DIR}/scripts/pre-uninstall.sh"
}

test_plugin_examples() {
    assert_file_exists "${SCRIPT_DIR}/examples/pre-build.sh" && \
    assert_file_exists "${SCRIPT_DIR}/examples/post-build.sh" && \
    assert_file_exists "${SCRIPT_DIR}/examples/plugin-install.sh"
}

test_plugin_init_command() {
    local output
    output="$(bash "${SCRIPT_DIR}/main.sh" init 2>&1 || echo "")"
    [[ "$output" == *"initialized"* ]] || return 1
}

test_plugin_list_command() {
    setup
    bash "${SCRIPT_DIR}/main.sh" init >/dev/null 2>&1
    local output
    output="$(bash "${SCRIPT_DIR}/main.sh" list 2>&1 || echo "")"
    teardown
    [[ -n "$output" ]] || return 1
}

test_plugin_status_command() {
    setup
    bash "${SCRIPT_DIR}/main.sh" init >/dev/null 2>&1
    local output
    output="$(bash "${SCRIPT_DIR}/main.sh" status 2>&1 || echo "")"
    teardown
    [[ "$output" == *"Status"* ]] || return 1
}

test_plugin_help_command() {
    local output
    output="$(bash "${SCRIPT_DIR}/main.sh" help 2>&1 || echo "")"
    [[ "$output" == *"用法"* ]] || [[ "$output" == *"Usage"* ]] || return 1
}

test_plugin_example_command() {
    local output
    output="$(bash "${SCRIPT_DIR}/main.sh" example basic 2>&1 || echo "")"
    [[ "$output" == *"初始化"* ]] || [[ "$output" == *"init"* ]] || return 1
}

test_lib_engine_exports() {
    setup
    source "${SCRIPT_DIR}/lib/engine-exports.sh"

    # 检查函数是否存在
    declare -f plugin_hook_pre >/dev/null 2>&1 && \
    declare -f plugin_hook_post >/dev/null 2>&1 && \
    declare -f plugin_trigger >/dev/null 2>&1

    teardown
}

test_lib_registry_exports() {
    setup
    source "${SCRIPT_DIR}/lib/registry-exports.sh"

    declare -f plugin_register_hook >/dev/null 2>&1 && \
    declare -f plugin_unregister_hook >/dev/null 2>&1

    teardown
}

test_examples_syntax() {
    bash -n "${SCRIPT_DIR}/examples/pre-build.sh" && \
    bash -n "${SCRIPT_DIR}/examples/post-build.sh" && \
    bash -n "${SCRIPT_DIR}/examples/plugin-install.sh"
}

# ============================================================================
# 主运行器
# ============================================================================

main() {
    echo "============================================"
    echo "  OML Hooks Runtime Plugin - Tests"
    echo "============================================"
    echo ""

    echo "Running plugin tests..."
    echo ""

    run_test "Plugin main.sh exists" test_plugin_main_exists
    run_test "Plugin.json valid" test_plugin_json_valid
    run_test "Lib exports exist" test_plugin_lib_exports
    run_test "Scripts exist" test_plugin_scripts
    run_test "Examples exist" test_plugin_examples
    run_test "Init command" test_plugin_init_command
    run_test "List command" test_plugin_list_command
    run_test "Status command" test_plugin_status_command
    run_test "Help command" test_plugin_help_command
    run_test "Example command" test_plugin_example_command
    run_test "Engine exports" test_lib_engine_exports
    run_test "Registry exports" test_lib_registry_exports
    run_test "Examples syntax" test_examples_syntax

    echo ""
    echo "============================================"
    echo "  Test Results"
    echo "============================================"
    echo ""
    echo "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    [[ $TESTS_FAILED -eq 0 ]] && echo -e "${GREEN}All tests passed!${NC}" || echo -e "${RED}Some tests failed.${NC}"

    return $TESTS_FAILED
}

main "$@"
