#!/usr/bin/env bash
# OML Session Protocol Test Suite
# 会话协议核心模块单元测试

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="${PROJECT_ROOT}/core"

# 测试统计
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 临时测试目录
TEST_SESSIONS_DIR=""
TEST_HOME=""

# ============================================================================
# 测试工具函数
# ============================================================================

# 设置测试环境
setup_test_env() {
    TEST_HOME="$(mktemp -d)"
    TEST_SESSIONS_DIR="${TEST_HOME}/.oml/sessions"

    export HOME="$TEST_HOME"
    export OML_SESSIONS_DIR="$TEST_SESSIONS_DIR"
    export OML_OUTPUT_FORMAT="text"

    # 创建所有必要目录
    mkdir -p "${TEST_SESSIONS_DIR}/data"
    mkdir -p "${TEST_SESSIONS_DIR}/meta"
    mkdir -p "${TEST_SESSIONS_DIR}/cache"

    # 初始化索引
    cat > "${TEST_SESSIONS_DIR}/index.json" <<'EOF'
{
  "sessions": {},
  "metadata": {
    "created_at": "",
    "updated_at": "",
    "total_count": 0,
    "version": "1.0.0"
  }
}
EOF
}

# 清理测试环境
teardown_test_env() {
    if [[ -n "$TEST_HOME" && -d "$TEST_HOME" ]]; then
        rm -rf "$TEST_HOME"
    fi
}

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

    if [[ -e "$file" ]]; then
        return 0
    else
        echo "  Path not found: $file"
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

assert_json_valid() {
    local json="$1"
    local message="${2:-}"

    if echo "$json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        return 0
    else
        echo "  Invalid JSON"
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

# 跳过测试
skip_test() {
    local name="$1"
    local reason="${2:-}"

    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "  ${YELLOW}SKIP${NC}: $name (${reason})"
}

# ============================================================================
# Session Storage 测试
# ============================================================================

# 测试：存储初始化
test_storage_init() {
    source "${CORE_DIR}/session-storage.sh"

    oml_session_storage_init

    # 使用 OML_SESSIONS_DIR 而不是 TEST_SESSIONS_DIR
    assert_file_exists "${OML_SESSIONS_DIR}/index.json" "Index file should exist" || return 1
    assert_file_exists "${OML_SESSIONS_DIR}/data" "Data directory should exist" || return 1
    assert_file_exists "${OML_SESSIONS_DIR}/meta" "Meta directory should exist" || return 1

    return 0
}

# 测试：创建会话
test_storage_create() {
    source "${CORE_DIR}/session-storage.sh"

    oml_session_storage_init

    # 不传递参数，让函数自动生成 ID
    local session_id
    session_id=$(oml_session_create "" '{"test": "data"}' 2>&1 | tail -1)

    assert_contains "$session_id" "sess-" "Session ID should have prefix" || return 1

    local data_path="${OML_SESSIONS_DIR}/data/${session_id}.json"
    assert_file_exists "$data_path" "Session data file should exist" || return 1

    return 0
}

# 测试：读取会话
test_storage_read() {
    source "${CORE_DIR}/session-storage.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "test-read" 2>&1 | tail -1)

    local data
    data=$(oml_session_read "$session_id")

    assert_contains "$data" "$session_id" "Read data should contain session ID" || return 1

    return 0
}

# 测试：更新会话
test_storage_update() {
    source "${CORE_DIR}/session-storage.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "test-update" 2>&1 | tail -1)

    oml_session_update "$session_id" '{"data": {"key": "value"}}' "true"

    local value
    value=$(oml_session_get "$session_id" "data.key")

    assert_equals "value" "$value" "Updated value should match" || return 1

    return 0
}

# 测试：删除会话
test_storage_delete() {
    source "${CORE_DIR}/session-storage.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "test-delete" 2>&1 | tail -1)

    oml_session_delete "$session_id"

    local data_path="${OML_SESSIONS_DIR}/data/${session_id}.json"
    if [[ -f "$data_path" ]]; then
        echo "  Session file should be deleted"
        return 1
    fi

    return 0
}

# 测试：设置/获取键值
test_storage_set_get() {
    source "${CORE_DIR}/session-storage.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "test-kv" 2>&1 | tail -1)

    oml_session_set "$session_id" "user.name" "TestUser"
    oml_session_set "$session_id" "user.email" "test@example.com"

    local name
    name=$(oml_session_get "$session_id" "user.name")
    local email
    email=$(oml_session_get "$session_id" "user.email")

    assert_equals "TestUser" "$name" "Name should match" || return 1
    assert_equals "test@example.com" "$email" "Email should match" || return 1

    return 0
}

# 测试：列出会话
test_storage_list() {
    source "${CORE_DIR}/session-storage.sh"

    oml_session_storage_init

    oml_session_create "list-test-1" 2>&1 >/dev/null
    oml_session_create "list-test-2" 2>&1 >/dev/null
    oml_session_create "list-test-3" 2>&1 >/dev/null

    local list_output
    list_output=$(oml_session_list "all" "10" "0")

    assert_contains "$list_output" "list-test-1" "List should contain session 1" || return 1
    assert_contains "$list_output" "list-test-2" "List should contain session 2" || return 1
    assert_contains "$list_output" "list-test-3" "List should contain session 3" || return 1

    return 0
}

# 测试：JSON 输出格式
test_storage_json_output() {
    source "${CORE_DIR}/session-storage.sh"

    export OML_OUTPUT_FORMAT="json"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "" "" 2>&1 | tail -1)

    # 测试 get 命令的 JSON 输出
    local json_output
    json_output=$(oml_session_get "$session_id" "session_id" 2>/dev/null)

    # 验证输出包含 session_id
    assert_contains "$json_output" "$session_id" "JSON output should contain session_id" || return 1

    export OML_OUTPUT_FORMAT="text"
    return 0
}

# ============================================================================
# Session Manager 测试
# ============================================================================

# 测试：创建会话（Manager）
test_manager_create() {
    source "${CORE_DIR}/session-manager.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_mgr_create "manager-test" "default")

    assert_contains "$session_id" "session-" "Manager session ID should have prefix" || return 1

    return 0
}

# 测试：启动/完成会话
test_manager_lifecycle() {
    source "${CORE_DIR}/session-manager.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_mgr_create "lifecycle-test")

    oml_session_mgr_start "$session_id"

    local status
    status=$(oml_session_get "$session_id" "status")
    assert_equals "running" "$status" "Status should be running" || return 1

    oml_session_mgr_complete "$session_id" '{"result": "success"}'

    status=$(oml_session_get "$session_id" "status")
    assert_equals "completed" "$status" "Status should be completed" || return 1

    return 0
}

# 测试：添加消息
test_manager_add_message() {
    source "${CORE_DIR}/session-manager.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_mgr_create "message-test")

    oml_session_mgr_add_message "$session_id" "user" "Hello, world!"
    oml_session_mgr_add_message "$session_id" "assistant" "Hi there!"

    local messages
    messages=$(oml_session_mgr_get_messages "$session_id")

    assert_contains "$messages" "Hello, world!" "Messages should contain user message" || return 1
    assert_contains "$messages" "Hi there!" "Messages should contain assistant message" || return 1

    return 0
}

# 测试：上下文管理
test_manager_context() {
    source "${CORE_DIR}/session-manager.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_mgr_create "context-test")

    oml_session_mgr_set_context "$session_id" "language" "zh-CN"
    oml_session_mgr_set_context "$session_id" "theme" "dark"

    local lang
    lang=$(oml_session_mgr_get_context "$session_id" "language")
    local theme
    theme=$(oml_session_mgr_get_context "$session_id" "theme")

    assert_equals "zh-CN" "$lang" "Language should match" || return 1
    assert_equals "dark" "$theme" "Theme should match" || return 1

    return 0
}

# ============================================================================
# Session Fork 测试
# ============================================================================

# 测试：Fork 会话
test_fork_create() {
    source "${CORE_DIR}/session-fork.sh"

    oml_session_storage_init

    # 创建父会话
    local parent_id
    parent_id=$(oml_session_create "parent-test" '{"messages": [{"role": "user", "content": "Hello"}]}')

    # Fork
    local fork_id
    fork_id=$(oml_session_fork "$parent_id" "fork-test" "full")

    assert_contains "$fork_id" "fork-" "Fork ID should have prefix" || return 1

    # 验证 Fork 数据
    local fork_data_path="${OML_SESSIONS_DIR}/data/${fork_id}.json"
    assert_file_exists "$fork_data_path" "Fork data file should exist" || return 1

    return 0
}

# 测试：浅 Fork
test_fork_shallow() {
    source "${CORE_DIR}/session-fork.sh"

    oml_session_storage_init

    local parent_id
    parent_id=$(oml_session_create "parent-shallow" '{"messages": [{"role": "user", "content": "Hello"}]}')

    local fork_id
    fork_id=$(oml_session_fork "$parent_id" "shallow-fork" "shallow")

    # 浅 Fork 不应该复制消息
    local msg_count
    msg_count=$(python3 -c "
import json
with open('${OML_SESSIONS_DIR}/data/${fork_id}.json', 'r') as f:
    data = json.load(f)
print(len(data.get('messages', [])))
")

    assert_equals "0" "$msg_count" "Shallow fork should have no messages" || return 1

    return 0
}

# 测试：列出 Fork
test_fork_list() {
    source "${CORE_DIR}/session-fork.sh"

    oml_session_storage_init

    local parent_id
    parent_id=$(oml_session_create "parent-list")

    oml_session_fork "$parent_id" "fork-1" "full"
    oml_session_fork "$parent_id" "fork-2" "full"

    local list_output
    list_output=$(oml_session_fork_list "$parent_id")

    assert_contains "$list_output" "fork-1" "Fork list should contain fork-1" || return 1
    assert_contains "$list_output" "fork-2" "Fork list should contain fork-2" || return 1

    return 0
}

# ============================================================================
# Session Share 测试
# ============================================================================

# 测试：共享会话
test_share_create() {
    source "${CORE_DIR}/session-share.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "share-test")

    local share_token
    share_token=$(oml_session_share "$session_id" "link" "3600")

    assert_contains "$share_token" "share-" "Share token should have prefix" || return 1

    return 0
}

# 测试：验证共享令牌
test_share_verify() {
    source "${CORE_DIR}/session-share.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "verify-test")

    local share_token
    share_token=$(oml_session_share "$session_id" "link" "3600")

    local verify_result
    verify_result=$(oml_session_share_verify "$share_token")

    assert_contains "$verify_result" "valid" "Share token should be valid" || return 1

    return 0
}

# 测试：导出会话
test_share_export() {
    source "${CORE_DIR}/session-share.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "export-test" '{"data": {"key": "value"}}')

    local export_output
    export_output=$(oml_session_export "$session_id" "json")

    assert_json_valid "$export_output" "Export output should be valid JSON" || return 1
    assert_contains "$export_output" "$session_id" "Export should contain session ID" || return 1

    return 0
}

# 测试：导入会话
test_share_import() {
    source "${CORE_DIR}/session-share.sh"

    oml_session_storage_init

    # 创建测试导出文件
    local export_file="${TEST_HOME}/export.json"
    cat > "$export_file" <<EOF
{
  "messages": [
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi"}
  ],
  "data": {"imported": true}
}
EOF

    local imported_id
    imported_id=$(oml_session_import "$export_file" "" "Imported Session")

    assert_contains "$imported_id" "imported-" "Imported session ID should have prefix" || return 1

    return 0
}

# ============================================================================
# Session Diff 测试
# ============================================================================

# 测试：比较会话
test_diff_compare() {
    source "${CORE_DIR}/session-diff.sh"

    oml_session_storage_init

    local session_a
    session_a=$(oml_session_create "diff-a" '{"messages": [{"role": "user", "content": "Hello A"}]}')

    local session_b
    session_b=$(oml_session_create "diff-b" '{"messages": [{"role": "user", "content": "Hello B"}]}')

    local diff_output
    diff_output=$(oml_session_diff "$session_a" "$session_b" "messages")

    # Diff 输出应该包含差异信息
    assert_contains "$diff_output" "diff" "Diff output should mention diff" || return 1

    return 0
}

# 测试：JSON 格式 Diff
test_diff_json() {
    source "${CORE_DIR}/session-diff.sh"

    export DIFF_OUTPUT_FORMAT="json"

    oml_session_storage_init

    local session_a
    session_a=$(oml_session_create "diff-json-a")
    local session_b
    session_b=$(oml_session_create "diff-json-b")

    local diff_output
    diff_output=$(oml_session_diff "$session_a" "$session_b" "full")

    assert_json_valid "$diff_output" "Diff output should be valid JSON" || return 1

    export DIFF_OUTPUT_FORMAT="text"
    return 0
}

# 测试：会话统计
test_diff_stats() {
    source "${CORE_DIR}/session-diff.sh"

    oml_session_storage_init

    local session_id
    session_id=$(oml_session_create "stats-test" '{"messages": [{"role": "user", "content": "Test"}]}')

    local stats_output
    stats_output=$(oml_session_diff_stats "$session_id")

    assert_contains "$stats_output" "Message" "Stats should mention messages" || return 1

    return 0
}

# ============================================================================
# Session Search 测试
# ============================================================================

# 测试：构建索引
test_search_index() {
    source "${CORE_DIR}/session-search.sh"

    oml_session_storage_init

    oml_session_create "search-test-1" '{"messages": [{"role": "user", "content": "Python code example"}]}'
    oml_session_create "search-test-2" '{"messages": [{"role": "user", "content": "JavaScript example"}]}'

    oml_session_search_index "true"

    local index_file="${OML_SESSIONS_DIR}/search_index.json"
    assert_file_exists "$index_file" "Search index should exist" || return 1

    return 0
}

# 测试：搜索会话
test_search_query() {
    source "${CORE_DIR}/session-search.sh"

    oml_session_storage_init

    oml_session_create "search-query-1" '{"messages": [{"role": "user", "content": "Python programming"}]}'
    oml_session_create "search-query-2" '{"messages": [{"role": "user", "content": "Java programming"}]}'

    oml_session_search_index "true"

    local search_output
    search_output=$(oml_session_search "Python" "messages" "contains" "10")

    assert_contains "$search_output" "Python" "Search should find Python" || return 1

    return 0
}

# 测试：搜索建议
test_search_suggest() {
    source "${CORE_DIR}/session-search.sh"

    oml_session_storage_init

    oml_session_create "suggest-test" '{"name": "Python Project"}'

    oml_session_search_index "true"

    local suggest_output
    suggest_output=$(oml_session_search_suggest "py" "5")

    # 应该返回建议
    assert_contains "$suggest_output" "py" "Suggest should contain prefix" || return 1

    return 0
}

# ============================================================================
# 集成测试
# ============================================================================

# 测试：完整会话生命周期
test_integration_lifecycle() {
    source "${CORE_DIR}/session-manager.sh"

    oml_session_storage_init

    # 创建
    local session_id
    session_id=$(oml_session_mgr_create "integration-test" "default")

    # 启动
    oml_session_mgr_start "$session_id"

    # 添加消息
    oml_session_mgr_add_message "$session_id" "user" "Write a Python function"
    oml_session_mgr_add_message "$session_id" "assistant" "Here's the function..."

    # 设置上下文
    oml_session_mgr_set_context "$session_id" "language" "python"

    # 完成
    oml_session_mgr_complete "$session_id" '{"status": "success"}'

    # 验证
    local status
    status=$(oml_session_get "$session_id" "status")
    assert_equals "completed" "$status" "Final status should be completed" || return 1

    local msg_count
    msg_count=$(python3 -c "
import json
with open('${OML_SESSIONS_DIR}/data/${session_id}.json', 'r') as f:
    data = json.load(f)
print(len(data.get('messages', [])))
")
    assert_equals "2" "$msg_count" "Should have 2 messages" || return 1

    return 0
}

# 测试：Fork 后修改
test_integration_fork_modify() {
    source "${CORE_DIR}/session-fork.sh"

    oml_session_storage_init

    # 创建父会话
    local parent_id
    parent_id=$(oml_session_create "fork-parent" '{"messages": [{"role": "user", "content": "Original"}]}')

    # Fork
    local fork_id
    fork_id=$(oml_session_fork "$parent_id" "fork-child" "full")

    # 修改 Fork
    oml_session_set "$fork_id" "data.modified" "true"
    oml_session_set "$fork_id" "messages" '[{"role": "user", "content": "Modified"}]'

    # 验证父会话未受影响
    local parent_content
    parent_content=$(oml_session_get "$parent_id" "messages.0.content")
    assert_equals "Original" "$parent_content" "Parent should not be affected" || return 1

    return 0
}

# ============================================================================
# 主测试运行器
# ============================================================================

run_all_tests() {
    echo "============================================"
    echo "OML Session Protocol Test Suite"
    echo "============================================"
    echo ""
    echo "Project Root: ${PROJECT_ROOT}"
    echo "Core Dir: ${CORE_DIR}"
    echo ""

    # 设置测试环境
    setup_test_env

    echo "Test Session Dir: ${TEST_SESSIONS_DIR}"
    echo ""
    echo "Running tests..."
    echo ""

    # Session Storage 测试
    echo -e "${BLUE}--- Session Storage Tests ---${NC}"
    run_test "Storage init" test_storage_init
    run_test "Storage create" test_storage_create
    run_test "Storage read" test_storage_read
    run_test "Storage update" test_storage_update
    run_test "Storage delete" test_storage_delete
    run_test "Storage set/get" test_storage_set_get
    run_test "Storage list" test_storage_list
    run_test "Storage JSON output" test_storage_json_output
    echo ""

    # Session Manager 测试
    echo -e "${BLUE}--- Session Manager Tests ---${NC}"
    run_test "Manager create" test_manager_create
    run_test "Manager lifecycle" test_manager_lifecycle
    run_test "Manager add message" test_manager_add_message
    run_test "Manager context" test_manager_context
    echo ""

    # Session Fork 测试
    echo -e "${BLUE}--- Session Fork Tests ---${NC}"
    run_test "Fork create" test_fork_create
    run_test "Fork shallow" test_fork_shallow
    run_test "Fork list" test_fork_list
    echo ""

    # Session Share 测试
    echo -e "${BLUE}--- Session Share Tests ---${NC}"
    run_test "Share create" test_share_create
    run_test "Share verify" test_share_verify
    run_test "Share export" test_share_export
    run_test "Share import" test_share_import
    echo ""

    # Session Diff 测试
    echo -e "${BLUE}--- Session Diff Tests ---${NC}"
    run_test "Diff compare" test_diff_compare
    run_test "Diff JSON" test_diff_json
    run_test "Diff stats" test_diff_stats
    echo ""

    # Session Search 测试
    echo -e "${BLUE}--- Session Search Tests ---${NC}"
    run_test "Search index" test_search_index
    run_test "Search query" test_search_query
    run_test "Search suggest" test_search_suggest
    echo ""

    # 集成测试
    echo -e "${BLUE}--- Integration Tests ---${NC}"
    run_test "Integration lifecycle" test_integration_lifecycle
    run_test "Integration fork modify" test_integration_fork_modify
    echo ""

    # 清理
    teardown_test_env

    # 总结
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo "Total:    ${TESTS_RUN}"
    echo -e "Passed:   ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Failed:   ${RED}${TESTS_FAILED}${NC}"
    echo -e "Skipped:  ${YELLOW}${TESTS_SKIPPED}${NC}"
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

    setup_test_env

    echo "Running single test: ${test_name}"
    echo ""

    case "$test_name" in
        storage_init)
            run_test "Storage init" test_storage_init
            ;;
        storage_create)
            run_test "Storage create" test_storage_create
            ;;
        manager_create)
            run_test "Manager create" test_manager_create
            ;;
        fork_create)
            run_test "Fork create" test_fork_create
            ;;
        share_create)
            run_test "Share create" test_share_create
            ;;
        diff_compare)
            run_test "Diff compare" test_diff_compare
            ;;
        search_query)
            run_test "Search query" test_search_query
            ;;
        integration)
            run_test "Integration lifecycle" test_integration_lifecycle
            ;;
        *)
            echo "Unknown test: $test_name"
            echo "Available tests: storage_init, storage_create, manager_create, fork_create, share_create, diff_compare, search_query, integration"
            teardown_test_env
            return 1
            ;;
    esac

    teardown_test_env
}

# 主入口
main() {
    local action="${1:-all}"

    case "$action" in
        all)
            run_all_tests
            ;;
        help|--help|-h)
            echo "Usage: $0 [all|<test_name>|help]"
            echo ""
            echo "Available tests:"
            echo "  all              Run all tests (default)"
            echo "  storage_init     Test storage initialization"
            echo "  storage_create   Test session creation"
            echo "  manager_create   Test manager create"
            echo "  fork_create      Test fork creation"
            echo "  share_create     Test share creation"
            echo "  diff_compare     Test diff comparison"
            echo "  search_query     Test search query"
            echo "  integration      Test integration lifecycle"
            ;;
        *)
            run_single_test "$action"
            ;;
    esac
}

main "$@"
