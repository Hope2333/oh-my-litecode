#!/usr/bin/env bash
# OML Worker Pool Test Suite
# Worker 池管理核心模块单元测试

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
TEST_POOL_DIR=""
TEST_HOME=""

# ============================================================================
# 测试工具函数
# ============================================================================

# 设置测试环境
setup_test_env() {
    TEST_HOME="$(mktemp -d)"
    TEST_POOL_DIR="${TEST_HOME}/.oml/pool"

    export HOME="$TEST_HOME"
    export OML_POOL_DIR="$TEST_POOL_DIR"
    export OML_CONCURRENCY_DIR="${TEST_HOME}/.oml/concurrency"
    export OML_QUEUE_DIR="${TEST_HOME}/.oml/queue"
    export OML_MONITOR_DIR="${TEST_HOME}/.oml/monitor"
    export OML_RECOVERY_DIR="${TEST_HOME}/.oml/recovery"

    # 创建所有必要目录
    mkdir -p "${TEST_POOL_DIR}/workers"
    mkdir -p "${TEST_POOL_DIR}/logs"
    mkdir -p "${OML_CONCURRENCY_DIR}/logs"
    mkdir -p "${OML_QUEUE_DIR}/logs"
    mkdir -p "${OML_MONITOR_DIR}/history"
    mkdir -p "${OML_MONITOR_DIR}/logs"
    mkdir -p "${OML_RECOVERY_DIR}/logs"
    mkdir -p "${OML_RECOVERY_DIR}/checkpoints"
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

assert_not_empty() {
    local value="$1"
    local message="${2:-}"

    if [[ -n "$value" ]]; then
        return 0
    else
        echo "  Expected non-empty value"
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
# Pool Manager 测试
# ============================================================================

# 测试：池初始化
test_pool_init() {
    source "${CORE_DIR}/pool-manager.sh"

    oml_pool_init 2 5

    assert_file_exists "${OML_POOL_DIR}/state.json" "State file should exist" || return 1

    local state
    state=$(cat "${OML_POOL_DIR}/state.json")
    assert_json_valid "$state" "State should be valid JSON" || return 1
    assert_contains "$state" '"min_workers": 2' "Should contain min_workers config" || return 1
    assert_contains "$state" '"max_workers": 5' "Should contain max_workers config" || return 1

    return 0
}

# 测试：创建 Worker
test_pool_create_worker() {
    source "${CORE_DIR}/pool-manager.sh"

    oml_pool_init 1 10

    local worker_id
    worker_id=$(oml_pool_create_worker)

    assert_not_empty "$worker_id" "Worker ID should not be empty" || return 1
    assert_contains "$worker_id" "worker-" "Worker ID should have prefix" || return 1

    local worker_file="${OML_POOL_DIR}/workers/${worker_id}.json"
    assert_file_exists "$worker_file" "Worker file should exist" || return 1

    return 0
}

# 测试：Worker 生命周期
test_pool_worker_lifecycle() {
    source "${CORE_DIR}/pool-manager.sh"

    oml_pool_init 1 10

    local worker_id
    worker_id=$(oml_pool_create_worker)

    # 启动 Worker
    oml_pool_start_worker "$worker_id"

    local status
    status=$(python3 -c "import json; print(json.load(open('${OML_POOL_DIR}/workers/${worker_id}.json'))['status'])")
    assert_equals "busy" "$status" "Status should be busy after start" || return 1

    # 停止 Worker
    oml_pool_stop_worker "$worker_id"

    status=$(python3 -c "import json; print(json.load(open('${OML_POOL_DIR}/workers/${worker_id}.json'))['status'])")
    assert_equals "stopped" "$status" "Status should be stopped after stop" || return 1

    return 0
}

# 测试：扩缩容
test_pool_scaling() {
    source "${CORE_DIR}/pool-manager.sh"

    oml_pool_init 1 10

    # 扩容
    local created
    created=$(oml_pool_scale_up 3)
    assert_equals "3" "$created" "Should create 3 workers" || return 1

    local total
    total=$(oml_pool_get_total_count)
    assert_equals "3" "$total" "Total should be 3" || return 1

    # 缩容
    local removed
    removed=$(oml_pool_scale_down 1)
    assert_equals "1" "$removed" "Should remove 1 worker" || return 1

    total=$(oml_pool_get_total_count)
    assert_equals "2" "$total" "Total should be 2 after scale down" || return 1

    return 0
}

# 测试：任务分配
test_pool_task_assignment() {
    source "${CORE_DIR}/pool-manager.sh"

    oml_pool_init 1 10

    # 创建 Worker
    local worker_id
    worker_id=$(oml_pool_create_worker)

    # 分配任务
    local task_id="test-task-$(date +%s)"
    local assigned_worker
    assigned_worker=$(oml_pool_assign_task "$task_id" '{"cmd": "echo hello"}')

    assert_equals "$worker_id" "$assigned_worker" "Task should be assigned to the worker" || return 1

    # 完成任务
    oml_pool_complete_task "$task_id" '{"output": "hello"}' "true"

    return 0
}

# 测试：池统计
test_pool_stats() {
    source "${CORE_DIR}/pool-manager.sh"

    oml_pool_init 1 10

    oml_pool_create_worker >/dev/null
    oml_pool_create_worker >/dev/null

    local stats
    stats=$(oml_pool_stats)

    assert_contains "$stats" "Total: 2" "Stats should show 2 workers" || return 1
    assert_contains "$stats" "Idle: 2" "Stats should show 2 idle workers" || return 1

    return 0
}

# ============================================================================
# Concurrency Control 测试
# ============================================================================

# 测试：令牌桶初始化
test_bucket_init() {
    source "${CORE_DIR}/pool-concurrency.sh"

    oml_bucket_init "test-bucket" 10 5 1

    assert_file_exists "${OML_CONCURRENCY_DIR}/state.json" "State file should exist" || return 1

    local state
    state=$(cat "${OML_CONCURRENCY_DIR}/state.json")
    assert_json_valid "$state" "State should be valid JSON" || return 1
    assert_contains "$state" '"test-bucket"' "Should contain test-bucket" || return 1

    return 0
}

# 测试：令牌消费
test_bucket_consume() {
    source "${CORE_DIR}/pool-concurrency.sh"

    oml_bucket_init "consume-bucket" 10 5 1

    # 消费令牌
    local result
    result=$(oml_bucket_consume "consume-bucket" 3)

    assert_contains "$result" "success" "Should successfully consume tokens" || return 1

    # 检查剩余令牌（允许一定误差，因为令牌会随时间补充）
    local status
    status=$(oml_bucket_status_json "consume-bucket")
    local tokens
    tokens=$(echo "$status" | python3 -c "import json,sys; print(json.load(sys.stdin)['tokens'])")

    # 令牌应该在 7-9 之间（考虑时间补充）
    if python3 -c "
tokens = float('$tokens')
assert 6.5 <= tokens <= 10, f'Tokens {tokens} out of expected range'
" 2>/dev/null; then
        return 0
    else
        echo "  Tokens out of range: $tokens"
        return 1
    fi
}

# 测试：令牌不足
test_bucket_insufficient_tokens() {
    source "${CORE_DIR}/pool-concurrency.sh"

    oml_bucket_init "insufficient-bucket" 5 1 1

    # 尝试消费超过可用数量的令牌
    local result
    result=$(oml_bucket_consume "insufficient-bucket" 10 "false" || echo "insufficient")

    assert_contains "$result" "insufficient" "Should report insufficient tokens" || return 1

    return 0
}

# 测试：并发限制器
test_concurrency_limiter() {
    source "${CORE_DIR}/pool-concurrency.sh"

    oml_concurrency_init 3 10

    # 获取槽位
    local result
    result=$(oml_concurrency_acquire 5 "test-task-1")
    assert_contains "$result" "acquired" "Should acquire slot" || return 1

    # 检查状态
    local status
    status=$(oml_concurrency_status_json)
    local current
    current=$(echo "$status" | python3 -c "import json,sys; print(json.load(sys.stdin)['current_count'])")
    assert_equals "1" "$current" "Current count should be 1" || return 1

    # 释放槽位
    oml_concurrency_release

    status=$(oml_concurrency_status_json)
    current=$(echo "$status" | python3 -c "import json,sys; print(json.load(sys.stdin)['current_count'])")
    assert_equals "0" "$current" "Current count should be 0 after release" || return 1

    return 0
}

# ============================================================================
# Queue (MLFQ) 测试
# ============================================================================

# 测试：MLFQ 初始化
test_mlfq_init() {
    source "${CORE_DIR}/pool-queue.sh"

    oml_mlfq_init 3 100 5 100

    assert_file_exists "${OML_QUEUE_DIR}/state.json" "State file should exist" || return 1

    local state
    state=$(cat "${OML_QUEUE_DIR}/state.json")
    assert_json_valid "$state" "State should be valid JSON" || return 1
    assert_contains "$state" '"num_queues": 3' "Should have 3 queues" || return 1

    return 0
}

# 测试：任务入队
test_queue_enqueue() {
    source "${CORE_DIR}/pool-queue.sh"

    oml_mlfq_init 3 100 5 100

    local task_id
    task_id=$(oml_queue_enqueue '{"cmd": "test"}' 0)

    assert_not_empty "$task_id" "Task ID should not be empty" || return 1
    assert_contains "$task_id" "qtask-" "Task ID should have prefix" || return 1

    return 0
}

# 测试：任务出队（MLFQ 调度）
test_queue_dequeue() {
    source "${CORE_DIR}/pool-queue.sh"

    oml_mlfq_init 3 100 5 100

    # 添加不同优先级的任务
    local task_low
    task_low=$(oml_queue_enqueue '{"priority": "low"}' 2)
    local task_high
    task_high=$(oml_queue_enqueue '{"priority": "high"}' 0)
    local task_medium
    task_medium=$(oml_queue_enqueue '{"priority": "medium"}' 1)

    # 出队应该返回最高优先级的任务
    local dequeued
    dequeued=$(oml_queue_dequeue)

    assert_json_valid "$dequeued" "Dequeued task should be valid JSON" || return 1
    assert_contains "$dequeued" "$task_high" "Should dequeue high priority task first" || return 1

    return 0
}

# 测试：任务完成
test_queue_complete() {
    source "${CORE_DIR}/pool-queue.sh"

    oml_mlfq_init 3 100 5 100

    local task_id
    task_id=$(oml_queue_enqueue '{"cmd": "test"}' 1)

    oml_queue_complete "$task_id" '{"result": "success"}' "true"

    local task_status
    task_status=$(python3 -c "import json; print(json.load(open('${OML_QUEUE_DIR}/state.json'))['tasks']['${task_id}']['status'])")
    assert_equals "completed" "$task_status" "Task status should be completed" || return 1

    return 0
}

# 测试：优先级提升
test_queue_priority_boost() {
    source "${CORE_DIR}/pool-queue.sh"

    oml_mlfq_init 3 100 1 100  # 1 秒提升间隔以便测试

    # 添加低优先级任务
    local task_id
    task_id=$(oml_queue_enqueue '{"cmd": "test"}' 2)

    # 强制优先级提升
    oml_queue_priority_boost "true"

    local task_priority
    task_priority=$(python3 -c "import json; print(json.load(open('${OML_QUEUE_DIR}/state.json'))['tasks']['${task_id}']['priority'])")
    assert_equals "0" "$task_priority" "Task should be promoted to highest priority" || return 1

    return 0
}

# 测试：队列统计
test_queue_stats() {
    source "${CORE_DIR}/pool-queue.sh"

    oml_mlfq_init 3 100 5 100

    oml_queue_enqueue '{"cmd": "test1"}' 0
    oml_queue_enqueue '{"cmd": "test2"}' 1

    local stats
    stats=$(oml_queue_stats)

    assert_contains "$stats" "Total Enqueued: 2" "Stats should show 2 enqueued tasks" || return 1

    return 0
}

# ============================================================================
# Monitor 测试
# ============================================================================

# 测试：监控初始化
test_monitor_init() {
    source "${CORE_DIR}/pool-monitor.sh"

    oml_monitor_init 70 90 70 90

    assert_file_exists "${OML_MONITOR_DIR}/state.json" "State file should exist" || return 1
    assert_file_exists "${OML_MONITOR_DIR}/alerts.json" "Alerts file should exist" || return 1

    return 0
}

# 测试：资源采样
test_monitor_sample() {
    source "${CORE_DIR}/pool-monitor.sh"

    oml_monitor_init

    local sample
    sample=$(oml_monitor_sample)

    assert_json_valid "$sample" "Sample should be valid JSON" || return 1
    assert_contains "$sample" '"cpu"' "Sample should contain cpu" || return 1
    assert_contains "$sample" '"memory"' "Sample should contain memory" || return 1

    return 0
}

# 测试：CPU 监控
test_monitor_cpu() {
    source "${CORE_DIR}/pool-monitor.sh"

    local cpu
    cpu=$(oml_monitor_cpu)

    # CPU 使用率应该是 0-100 之间的数字
    if python3 -c "
cpu = float('$cpu')
assert 0 <= cpu <= 100, f'CPU {cpu} out of range'
" 2>/dev/null; then
        return 0
    else
        echo "  CPU value out of range: $cpu"
        return 1
    fi
}

# 测试：内存监控
test_monitor_memory() {
    source "${CORE_DIR}/pool-monitor.sh"

    local mem_info
    mem_info=$(oml_monitor_memory)

    assert_json_valid "$mem_info" "Memory info should be valid JSON" || return 1
    assert_contains "$mem_info" '"usage_percent"' "Should contain usage_percent" || return 1

    return 0
}

# 测试：阈值检查
test_monitor_threshold_check() {
    source "${CORE_DIR}/pool-monitor.sh"

    oml_monitor_init 70 90 70 90

    # 采样并检查阈值
    oml_monitor_sample >/dev/null
    local result
    result=$(oml_monitor_check_thresholds)

    # 结果应该是 OK 或包含告警
    if [[ "$result" == "OK" ]] || [[ "$result" == ALERT:* ]]; then
        return 0
    else
        echo "  Unexpected result: $result"
        return 1
    fi
}

# 测试：告警管理
test_monitor_alerts() {
    source "${CORE_DIR}/pool-monitor.sh"

    oml_monitor_init 70 90 70 90

    # 获取告警（应该是空的）
    local alerts
    alerts=$(oml_monitor_get_alerts)

    assert_json_valid "$alerts" "Alerts should be valid JSON" || return 1

    local count
    count=$(echo "$alerts" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
    assert_equals "0" "$count" "Should have no active alerts initially" || return 1

    return 0
}

# ============================================================================
# Recovery 测试
# ============================================================================

# 测试：恢复系统初始化
test_recovery_init() {
    source "${CORE_DIR}/pool-recovery.sh"

    oml_recovery_init 10 3 5

    assert_file_exists "${OML_RECOVERY_DIR}/state.json" "State file should exist" || return 1
    assert_file_exists "${OML_RECOVERY_DIR}/checkpoints" "Checkpoints dir should exist" || return 1

    return 0
}

# 测试：故障报告
test_recovery_report_failure() {
    source "${CORE_DIR}/pool-recovery.sh"

    oml_recovery_init

    local failure_id
    failure_id=$(oml_recovery_report_failure "worker-test-1" "timeout" '{"duration": 30}')

    assert_not_empty "$failure_id" "Failure ID should not be empty" || return 1
    assert_contains "$failure_id" "failure-" "Failure ID should have prefix" || return 1

    return 0
}

# 测试：恢复流程
test_recovery_process() {
    source "${CORE_DIR}/pool-recovery.sh"

    oml_recovery_init

    # 报告故障
    local failure_id
    failure_id=$(oml_recovery_report_failure "worker-test-2" "crash")

    # 启动恢复
    local recovery_id
    recovery_id=$(oml_recovery_start "$failure_id" "retry")

    assert_not_empty "$recovery_id" "Recovery ID should not be empty" || return 1
    assert_contains "$recovery_id" "recovery-" "Recovery ID should have prefix" || return 1

    # 执行恢复
    local result
    result=$(oml_recovery_execute "$recovery_id")
    assert_contains "$result" "in_progress" "Recovery should be in progress" || return 1

    # 完成恢复
    oml_recovery_complete "$recovery_id" "true" '{"status": "recovered"}'

    return 0
}

# 测试：检查点管理
test_recovery_checkpoint() {
    source "${CORE_DIR}/pool-recovery.sh"

    oml_recovery_init

    # 创建检查点
    local checkpoint_id
    checkpoint_id=$(oml_recovery_checkpoint_create "task-test-1" '{"progress": 50, "data": "test"}')

    assert_not_empty "$checkpoint_id" "Checkpoint ID should not be empty" || return 1

    # 恢复检查点
    local checkpoint_data
    checkpoint_data=$(oml_recovery_checkpoint_restore "$checkpoint_id")

    assert_json_valid "$checkpoint_data" "Checkpoint data should be valid JSON" || return 1
    assert_contains "$checkpoint_data" '"progress": 50' "Should contain progress data" || return 1

    # 列出检查点
    local list_output
    list_output=$(oml_recovery_checkpoint_list)
    assert_contains "$list_output" "$checkpoint_id" "Checkpoint list should contain the checkpoint" || return 1

    return 0
}

# 测试：熔断器
test_recovery_circuit_breaker() {
    source "${CORE_DIR}/pool-recovery.sh"

    oml_recovery_init

    # 初始状态应该是 closed
    local status
    status=$(oml_recovery_circuit_breaker_status "test-worker-cb")
    assert_contains "$status" "closed" "Circuit breaker should be closed initially" || return 1

    return 0
}

# 测试：恢复统计
test_recovery_stats() {
    source "${CORE_DIR}/pool-recovery.sh"

    oml_recovery_init

    local stats
    stats=$(oml_recovery_stats)

    assert_contains "$stats" "Recovery System Statistics" "Should contain stats header" || return 1
    assert_contains "$stats" "Total Failures: 0" "Should show 0 failures initially" || return 1

    return 0
}

# ============================================================================
# 集成测试
# ============================================================================

# 测试：完整 Worker 池工作流
test_integration_pool_workflow() {
    source "${CORE_DIR}/pool-manager.sh"
    source "${CORE_DIR}/pool-concurrency.sh"
    source "${CORE_DIR}/pool-queue.sh"

    # 初始化所有组件
    oml_pool_init 2 5
    oml_bucket_init "workflow-bucket" 20 10 1
    oml_mlfq_init 3 100 5 100

    # 创建 Worker
    local worker1
    worker1=$(oml_pool_create_worker)
    local worker2
    worker2=$(oml_pool_create_worker)

    # 消费令牌
    oml_bucket_consume "workflow-bucket" 5 >/dev/null

    # 添加任务到队列
    local task1
    task1=$(oml_queue_enqueue '{"cmd": "task1"}' 0)
    local task2
    task2=$(oml_queue_enqueue '{"cmd": "task2"}' 1)

    # 从队列取出任务并分配给 Worker
    local dequeued
    dequeued=$(oml_queue_dequeue)
    local task_id
    task_id=$(echo "$dequeued" | python3 -c "import json,sys; print(json.load(sys.stdin)['task_id'])")

    oml_pool_assign_task "$task_id" "{}" "$worker1"

    # 完成任务
    oml_pool_complete_task "$task_id" '{"result": "done"}' "true"
    oml_queue_complete "$task_id"

    # 验证统计
    local pool_stats
    pool_stats=$(oml_pool_stats)
    assert_contains "$pool_stats" "Completed: 1" "Should show 1 completed task" || return 1

    return 0
}

# 测试：故障恢复工作流
test_integration_recovery_workflow() {
    source "${CORE_DIR}/pool-manager.sh"
    source "${CORE_DIR}/pool-recovery.sh"
    source "${CORE_DIR}/pool-monitor.sh"

    # 初始化
    oml_pool_init 1 5
    oml_recovery_init
    oml_monitor_init

    # 创建 Worker
    local worker_id
    worker_id=$(oml_pool_create_worker)

    # 注册到监控
    oml_monitor_register_worker "$worker_id" "$$"

    # 报告故障
    local failure_id
    failure_id=$(oml_recovery_report_failure "$worker_id" "health_check")

    # 启动恢复
    local recovery_id
    recovery_id=$(oml_recovery_start "$failure_id" "restart")

    # 执行并完成任务
    oml_recovery_execute "$recovery_id"
    oml_recovery_complete "$recovery_id" "true"

    # 验证统计
    local stats
    stats=$(oml_recovery_stats)
    assert_contains "$stats" "Successful Recoveries: 1" "Should show 1 successful recovery" || return 1

    return 0
}

# 测试：并发控制与任务调度
test_integration_concurrency_scheduling() {
    source "${CORE_DIR}/pool-concurrency.sh"
    source "${CORE_DIR}/pool-queue.sh"

    # 初始化
    oml_concurrency_init 2 10
    oml_mlfq_init 3 100 5 100

    # 添加多个任务
    for i in {1..5}; do
        oml_queue_enqueue "{\"task\": $i}" 1 >/dev/null
    done

    # 模拟并发执行
    local executed=0
    for i in {1..3}; do
        local acquire_result
        acquire_result=$(oml_concurrency_acquire 5 "task-$i")

        if [[ "$acquire_result" == acquired:* ]]; then
            # 出队并"执行"任务
            oml_queue_dequeue >/dev/null
            oml_concurrency_release
            ((executed++))
        fi
    done

    assert_equals "3" "$executed" "Should execute 3 tasks within concurrency limit" || return 1

    return 0
}

# ============================================================================
# 主测试运行器
# ============================================================================

run_all_tests() {
    echo "============================================"
    echo "OML Worker Pool Test Suite"
    echo "============================================"
    echo ""
    echo "Project Root: ${PROJECT_ROOT}"
    echo "Core Dir: ${CORE_DIR}"
    echo ""

    # 设置测试环境
    setup_test_env

    echo "Test Pool Dir: ${TEST_POOL_DIR}"
    echo ""
    echo "Running tests..."
    echo ""

    # Pool Manager 测试
    echo -e "${BLUE}--- Pool Manager Tests ---${NC}"
    run_test "Pool init" test_pool_init
    run_test "Pool create worker" test_pool_create_worker
    run_test "Pool worker lifecycle" test_pool_worker_lifecycle
    run_test "Pool scaling" test_pool_scaling
    run_test "Pool task assignment" test_pool_task_assignment
    run_test "Pool stats" test_pool_stats
    echo ""

    # Concurrency Control 测试
    echo -e "${BLUE}--- Concurrency Control Tests ---${NC}"
    run_test "Bucket init" test_bucket_init
    run_test "Bucket consume" test_bucket_consume
    run_test "Bucket insufficient tokens" test_bucket_insufficient_tokens
    run_test "Concurrency limiter" test_concurrency_limiter
    echo ""

    # Queue (MLFQ) 测试
    echo -e "${BLUE}--- Queue (MLFQ) Tests ---${NC}"
    run_test "MLFQ init" test_mlfq_init
    run_test "Queue enqueue" test_queue_enqueue
    run_test "Queue dequeue" test_queue_dequeue
    run_test "Queue complete" test_queue_complete
    run_test "Queue priority boost" test_queue_priority_boost
    run_test "Queue stats" test_queue_stats
    echo ""

    # Monitor 测试
    echo -e "${BLUE}--- Monitor Tests ---${NC}"
    run_test "Monitor init" test_monitor_init
    run_test "Monitor sample" test_monitor_sample
    run_test "Monitor CPU" test_monitor_cpu
    run_test "Monitor memory" test_monitor_memory
    run_test "Monitor threshold check" test_monitor_threshold_check
    run_test "Monitor alerts" test_monitor_alerts
    echo ""

    # Recovery 测试
    echo -e "${BLUE}--- Recovery Tests ---${NC}"
    run_test "Recovery init" test_recovery_init
    run_test "Recovery report failure" test_recovery_report_failure
    run_test "Recovery process" test_recovery_process
    run_test "Recovery checkpoint" test_recovery_checkpoint
    run_test "Recovery circuit breaker" test_recovery_circuit_breaker
    run_test "Recovery stats" test_recovery_stats
    echo ""

    # 集成测试
    echo -e "${BLUE}--- Integration Tests ---${NC}"
    run_test "Integration pool workflow" test_integration_pool_workflow
    run_test "Integration recovery workflow" test_integration_recovery_workflow
    run_test "Integration concurrency scheduling" test_integration_concurrency_scheduling
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
        pool_init)
            run_test "Pool init" test_pool_init
            ;;
        pool_create_worker)
            run_test "Pool create worker" test_pool_create_worker
            ;;
        bucket_consume)
            run_test "Bucket consume" test_bucket_consume
            ;;
        mlfq_enqueue)
            run_test "Queue enqueue" test_queue_enqueue
            ;;
        monitor_sample)
            run_test "Monitor sample" test_monitor_sample
            ;;
        recovery_process)
            run_test "Recovery process" test_recovery_process
            ;;
        integration)
            run_test "Integration pool workflow" test_integration_pool_workflow
            ;;
        *)
            echo "Unknown test: $test_name"
            echo "Available tests: pool_init, pool_create_worker, bucket_consume, mlfq_enqueue, monitor_sample, recovery_process, integration"
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
            echo "  all                 Run all tests (default)"
            echo "  pool_init           Test pool initialization"
            echo "  pool_create_worker  Test worker creation"
            echo "  bucket_consume      Test token bucket consume"
            echo "  mlfq_enqueue        Test MLFQ enqueue"
            echo "  monitor_sample      Test monitor sampling"
            echo "  recovery_process    Test recovery process"
            echo "  integration         Test integration workflow"
            ;;
        *)
            run_single_test "$action"
            ;;
    esac
}

main "$@"
