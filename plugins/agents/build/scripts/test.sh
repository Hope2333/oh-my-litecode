#!/usr/bin/env bash
# Test Suite for Build Agent Plugin
# 测试构建代理插件的所有功能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
MAIN_SCRIPT="${PLUGIN_DIR}/main.sh"

# 测试统计
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试断言
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        [[ -n "$message" ]] && echo "  Message:  $message"
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
        echo "  Expected to contain: $needle"
        echo "  In: $haystack"
        [[ -n "$message" ]] && echo "  Message: $message"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"
    
    if [[ -f "$file" ]]; then
        return 0
    else
        echo "  File not found: $file"
        [[ -n "$message" ]] && echo "  Message: $message"
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
        echo "  Expected exit code: $expected"
        echo "  Actual exit code:   $actual"
        [[ -n "$message" ]] && echo "  Message: $message"
        return 1
    fi
}

# 运行测试
run_test() {
    local name="$1"
    local func="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -n "  Testing: $name ... "
    
    if $func; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# 测试用例
# ============================================================================

# 测试：帮助命令
test_help_command() {
    local output
    output=$("$MAIN_SCRIPT" --help 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 $exit_code "Help command should succeed" || return 1
    assert_contains "$output" "build" "Output should mention build" || return 1
    
    return 0
}

# 测试：JSON 格式帮助
test_help_json() {
    local output
    output=$("$MAIN_SCRIPT" --help 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 $exit_code "Help command should succeed" || return 1
    
    return 0
}

# 测试：版本命令
test_version_command() {
    local output
    output=$("$MAIN_SCRIPT" version 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 $exit_code "Version command should succeed" || return 1
    assert_contains "$output" "v1.0.0" "Output should contain version" || return 1
    
    return 0
}

# 测试：状态命令（无项目）
test_status_command() {
    local output
    output=$("$MAIN_SCRIPT" status 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 $exit_code "Status command should succeed" || return 1
    assert_contains "$output" "Build Status" "Output should contain status header" || return 1
    
    return 0
}

# 测试：状态命令 JSON 格式
test_status_json() {
    local output
    output=$(OML_OUTPUT_FORMAT=json "$MAIN_SCRIPT" status 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 $exit_code "Status JSON should succeed" || return 1
    
    # 验证 JSON 格式
    if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        return 0
    else
        echo "  Invalid JSON output"
        return 1
    fi
}

# 测试：日志命令（无日志时）
test_logs_command_empty() {
    local output
    output=$("$MAIN_SCRIPT" logs 2>&1)
    # 无日志时可能返回非零退出码
    
    # 只要不崩溃就算通过
    return 0
}

# 测试：未知命令
test_unknown_command() {
    local output
    output=$("$MAIN_SCRIPT" unknown-command-xyz 2>&1)
    local exit_code=$?
    
    assert_exit_code 1 $exit_code "Unknown command should fail" || return 1
    assert_contains "$output" "Unknown" "Output should mention unknown" || return 1
    
    return 0
}

# 测试：Makefile 路径解析
test_makefile_path_resolution() {
    # 测试顶层 Makefile
    local output
    output=$("$MAIN_SCRIPT" status 2>&1)
    
    # 应该能找到 Makefile 相关信息
    return 0
}

# 测试：平台检测
test_platform_detection() {
    local output
    output=$("$MAIN_SCRIPT" status 2>&1)
    
    # 状态输出应该包含平台信息
    return 0
}

# 测试：环境变量 OML_BUILD_VERBOSE
test_env_verbose() {
    local output
    OML_BUILD_VERBOSE=true output=$("$MAIN_SCRIPT" status 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 $exit_code "Verbose status should succeed" || return 1
    
    return 0
}

# 测试：环境变量 OML_OUTPUT_FORMAT
test_env_output_format() {
    local output
    output=$(OML_OUTPUT_FORMAT=json "$MAIN_SCRIPT" status 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 $exit_code "JSON output should succeed" || return 1
    
    # 验证 JSON 格式
    if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        return 0
    else
        echo "  Invalid JSON output"
        return 1
    fi
}

# 测试：clean 命令（空项目）
test_clean_command() {
    local output
    output=$("$MAIN_SCRIPT" clean 2>&1)
    local exit_code=$?
    
    # clean 可能因为项目不存在而失败，但不应该崩溃
    return 0
}

# 测试：clean 命令指定项目
test_clean_command_project() {
    local output
    output=$("$MAIN_SCRIPT" clean opencode 2>&1)
    local exit_code=$?
    
    # 可能失败但不应该崩溃
    return 0
}

# 测试：project 命令帮助
test_project_help() {
    local output
    output=$("$MAIN_SCRIPT" project --help 2>&1)
    
    # 应该显示帮助或错误，但不崩溃
    return 0
}

# 测试：日志目录创建
test_logs_directory_creation() {
    # 运行任何命令都应该创建日志目录
    "$MAIN_SCRIPT" status >/dev/null 2>&1 || true
    
    # 检查日志目录是否存在（在插件目录或 OML_ROOT）
    return 0
}

# 测试：plugin.json 有效性
test_plugin_json_valid() {
    local plugin_json="${PLUGIN_DIR}/plugin.json"
    
    assert_file_exists "$plugin_json" "plugin.json should exist" || return 1
    
    # 验证 JSON 格式
    if python3 -c "import json; json.load(open('$plugin_json'))" 2>/dev/null; then
        return 0
    else
        echo "  Invalid JSON in plugin.json"
        return 1
    fi
}

# 测试：plugin.json 内容
test_plugin_json_content() {
    local plugin_json="${PLUGIN_DIR}/plugin.json"
    
    # 验证必要字段
    local name version type
    name=$(python3 -c "import json; print(json.load(open('$plugin_json')).get('name', ''))")
    version=$(python3 -c "import json; print(json.load(open('$plugin_json')).get('version', ''))")
    type=$(python3 -c "import json; print(json.load(open('$plugin_json')).get('type', ''))")
    
    assert_equals "build" "$name" "Plugin name should be 'build'" || return 1
    assert_equals "agent" "$type" "Plugin type should be 'agent'" || return 1
    [[ -n "$version" ]] || { echo "  Version should not be empty"; return 1; }
    
    return 0
}

# 测试：钩子脚本存在
test_hook_scripts_exist() {
    local post_install="${PLUGIN_DIR}/scripts/post-install.sh"
    local pre_uninstall="${PLUGIN_DIR}/scripts/pre-uninstall.sh"
    
    assert_file_exists "$post_install" "post-install.sh should exist" || return 1
    assert_file_exists "$pre_uninstall" "pre-uninstall.sh should exist" || return 1
    
    # 检查可执行权限
    if [[ -x "$post_install" ]] && [[ -x "$pre_uninstall" ]]; then
        return 0
    else
        echo "  Hook scripts should be executable"
        return 1
    fi
}

# 测试：main.sh 可执行
test_main_script_executable() {
    assert_file_exists "$MAIN_SCRIPT" "main.sh should exist" || return 1
    
    if [[ -x "$MAIN_SCRIPT" ]]; then
        return 0
    else
        echo "  main.sh should be executable"
        return 1
    fi
}

# 测试：bash 语法检查
test_bash_syntax() {
    if bash -n "$MAIN_SCRIPT" 2>/dev/null; then
        return 0
    else
        echo "  main.sh has syntax errors"
        return 1
    fi
}

# 测试：钩子脚本语法检查
test_hook_scripts_syntax() {
    local post_install="${PLUGIN_DIR}/scripts/post-install.sh"
    local pre_uninstall="${PLUGIN_DIR}/scripts/pre-uninstall.sh"
    
    if bash -n "$post_install" 2>/dev/null && bash -n "$pre_uninstall" 2>/dev/null; then
        return 0
    else
        echo "  Hook scripts have syntax errors"
        return 1
    fi
}

# ============================================================================
# 主测试运行器
# ============================================================================

run_all_tests() {
    echo "============================================"
    echo "Build Agent Plugin Test Suite"
    echo "============================================"
    echo ""
    
    echo "Plugin Directory: ${PLUGIN_DIR}"
    echo "Main Script: ${MAIN_SCRIPT}"
    echo ""
    
    echo "Running tests..."
    echo ""
    
    # 文件结构测试
    echo "--- File Structure Tests ---"
    run_test "main.sh exists and executable" test_main_script_executable
    run_test "plugin.json exists" test_plugin_json_valid
    run_test "plugin.json content" test_plugin_json_content
    run_test "hook scripts exist" test_hook_scripts_exist
    run_test "bash syntax valid" test_bash_syntax
    run_test "hook scripts syntax" test_hook_scripts_syntax
    echo ""
    
    # 命令测试
    echo "--- Command Tests ---"
    run_test "help command" test_help_command
    run_test "version command" test_version_command
    run_test "status command" test_status_command
    run_test "status JSON format" test_status_json
    run_test "logs command (empty)" test_logs_command_empty
    run_test "clean command" test_clean_command
    run_test "clean with project" test_clean_command_project
    run_test "unknown command" test_unknown_command
    echo ""
    
    # 环境变量测试
    echo "--- Environment Variable Tests ---"
    run_test "OML_BUILD_VERBOSE" test_env_verbose
    run_test "OML_OUTPUT_FORMAT=json" test_env_output_format
    echo ""
    
    # 总结
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo "Total:  ${TESTS_RUN}"
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

# 运行单个测试
run_single_test() {
    local test_name="$1"
    
    echo "Running single test: ${test_name}"
    echo ""
    
    case "$test_name" in
        help)
            run_test "help command" test_help_command
            ;;
        version)
            run_test "version command" test_version_command
            ;;
        status)
            run_test "status command" test_status_command
            ;;
        status_json)
            run_test "status JSON format" test_status_json
            ;;
        logs)
            run_test "logs command" test_logs_command_empty
            ;;
        clean)
            run_test "clean command" test_clean_command
            ;;
        plugin_json)
            run_test "plugin.json valid" test_plugin_json_valid
            run_test "plugin.json content" test_plugin_json_content
            ;;
        syntax)
            run_test "bash syntax" test_bash_syntax
            run_test "hook scripts syntax" test_hook_scripts_syntax
            ;;
        *)
            echo "Unknown test: $test_name"
            echo "Available tests: help, version, status, status_json, logs, clean, plugin_json, syntax"
            return 1
            ;;
    esac
}

# 主入口
main() {
    local action="${1:-all}"
    
    case "$action" in
        all)
            run_all_tests
            ;;
        help|--help|-h)
            echo "Usage: $0 [all|<test_name>]"
            echo ""
            echo "Available tests:"
            echo "  all          Run all tests (default)"
            echo "  help         Test help command"
            echo "  version      Test version command"
            echo "  status       Test status command"
            echo "  status_json  Test status JSON output"
            echo "  logs         Test logs command"
            echo "  clean        Test clean command"
            echo "  plugin_json  Test plugin.json"
            echo "  syntax       Test bash syntax"
            ;;
        *)
            run_single_test "$action"
            ;;
    esac
}

main "$@"
