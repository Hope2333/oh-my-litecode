#!/usr/bin/env bash
# OML System Performance Benchmark
# 整体系统基准测试 - 测试系统整体吞吐量和综合性能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="${PROJECT_ROOT}/core"

# ============================================================================
# 配置
# ============================================================================

readonly BENCHMARK_SYSTEM_DIR="${BENCHMARK_SYSTEM_DIR:-$(mktemp -d)}"
readonly SAMPLE_COUNT="${SAMPLE_COUNT:-30}"
readonly WARMUP_COUNT="${WARMUP_COUNT:-5}"
readonly POOL_SIZE="${POOL_SIZE:-3}"
readonly HOOK_COUNT="${HOOK_COUNT:-3}"
readonly OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"

# 测试结果存储
declare -A BENCHMARK_RESULTS=()

# ============================================================================
# 工具函数
# ============================================================================

get_timestamp_ns() {
    python3 -c "import time; print(int(time.time_ns()))"
}

calc_duration_ms() {
    local start="$1"
    local end="$2"
    python3 -c "print((${end} - ${start}) / 1_000_000)"
}

calc_average() {
    local sum="$1"
    local count="$2"
    python3 -c "print(${sum} / ${count} if ${count} > 0 else 0)"
}

calc_percentile() {
    local values="$1"
    local percentile="$2"
    python3 -c "
import json
values = json.loads('${values}')
values.sort()
idx = int(len(values) * ${percentile} / 100)
print(values[idx] if idx < len(values) else values[-1] if values else 0)
"
}

log_info() {
    echo "[INFO] $*" >&2
}

log_result() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "$@"
    fi
}

# ============================================================================
# 测试环境设置
# ============================================================================

setup_test_env() {
    log_info "Setting up test environment at: ${BENCHMARK_SYSTEM_DIR}"

    export HOME="${BENCHMARK_SYSTEM_DIR}"

    # Session 目录
    export OML_SESSIONS_DIR="${BENCHMARK_SYSTEM_DIR}/sessions"
    mkdir -p "${OML_SESSIONS_DIR}/data"
    mkdir -p "${OML_SESSIONS_DIR}/meta"
    mkdir -p "${OML_SESSIONS_DIR}/cache"

    # Hooks 目录
    export OML_HOOKS_CONFIG_DIR="${BENCHMARK_SYSTEM_DIR}/hooks"
    export OML_HOOKS_REGISTRY_FILE="${BENCHMARK_SYSTEM_DIR}/hooks/registry.json"
    export OML_DISPATCHER_LOGS_DIR="${BENCHMARK_SYSTEM_DIR}/hooks/dispatcher"
    export OML_EVENT_QUEUE_DIR="${BENCHMARK_SYSTEM_DIR}/hooks/queue"
    mkdir -p "${OML_HOOKS_CONFIG_DIR}"
    mkdir -p "${OML_DISPATCHER_LOGS_DIR}"
    mkdir -p "${OML_EVENT_QUEUE_DIR}"

    # Pool 目录
    export OML_POOL_DIR="${BENCHMARK_SYSTEM_DIR}/pool"
    export OML_POOL_WORKERS_DIR="${BENCHMARK_SYSTEM_DIR}/pool/workers"
    export OML_POOL_STATE_FILE="${BENCHMARK_SYSTEM_DIR}/pool/state.json"
    export OML_POOL_LOGS_DIR="${BENCHMARK_SYSTEM_DIR}/pool/logs"
    mkdir -p "${OML_POOL_WORKERS_DIR}"
    mkdir -p "${OML_POOL_LOGS_DIR}"

    # 初始化 Session 索引
    cat > "${OML_SESSIONS_DIR}/index.json" <<'EOF'
{
  "sessions": {},
  "metadata": {"created_at": "", "updated_at": "", "total_count": 0, "version": "1.0.0"}
}
EOF

    # 初始化 Hooks 注册表
    cat > "${OML_HOOKS_REGISTRY_FILE}" <<'EOF'
{
  "hooks": [],
  "events": {},
  "metadata": {"created_at": "", "updated_at": "", "version": "1.0.0"}
}
EOF

    # 创建测试 Hook 处理器
    mkdir -p "${BENCHMARK_SYSTEM_DIR}/handlers"
    cat > "${BENCHMARK_SYSTEM_DIR}/handlers/dummy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${BENCHMARK_SYSTEM_DIR}/handlers/dummy.sh"

    # 创建测试 Worker 脚本
    mkdir -p "${BENCHMARK_SYSTEM_DIR}/workers"
    cat > "${BENCHMARK_SYSTEM_DIR}/workers/dummy-worker.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${BENCHMARK_SYSTEM_DIR}/workers/dummy-worker.sh"

    # 加载核心模块
    source "${CORE_DIR}/platform.sh" 2>/dev/null || true
    source "${CORE_DIR}/session-storage.sh" 2>/dev/null || true
    source "${CORE_DIR}/session-manager.sh" 2>/dev/null || true
    source "${CORE_DIR}/event-bus.sh" 2>/dev/null || true
    source "${CORE_DIR}/hooks-registry.sh" 2>/dev/null || true
    source "${CORE_DIR}/hooks-dispatcher.sh" 2>/dev/null || true
    source "${CORE_DIR}/hooks-engine.sh" 2>/dev/null || true
    source "${CORE_DIR}/pool-manager.sh" 2>/dev/null || true

    # 初始化组件
    oml_session_storage_init 2>/dev/null || true
    oml_hooks_registry_init 2>/dev/null || true
    oml_event_bus_init 2>/dev/null || true
    oml_pool_init 1 "${POOL_SIZE}" 2>/dev/null || true
}

teardown_test_env() {
    log_info "Cleaning up test environment"
    if [[ -d "$BENCHMARK_SYSTEM_DIR" ]]; then
        rm -rf "$BENCHMARK_SYSTEM_DIR"
    fi
}

# ============================================================================
# 基准测试：端到端工作流
# ============================================================================

benchmark_end_to_end_workflow() {
    log_info "Running End-to-End Workflow Benchmark (${SAMPLE_COUNT} iterations)..."

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local session_id="warmup-e2e-${i}"
        oml_session_create "$session_id" '{"warmup": true}' >/dev/null 2>&1 || true
        oml_session_mgr_add_message "$session_id" "user" "Warmup" >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local session_id="e2e-${i}-$$"

        local start_ns
        start_ns=$(get_timestamp_ns)

        # 完整工作流：创建 -> 启动 -> 添加消息 -> 完成 -> 删除
        oml_session_create "$session_id" '{"benchmark": "e2e", "iteration": '"$i"'}' >/dev/null 2>&1 || true
        oml_session_mgr_start "$session_id" >/dev/null 2>&1 || true
        oml_session_mgr_add_message "$session_id" "user" "Test message ${i}" >/dev/null 2>&1 || true
        oml_session_mgr_add_message "$session_id" "assistant" "Response ${i}" >/dev/null 2>&1 || true
        oml_session_mgr_complete "$session_id" '{"status": "success"}' >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 计算统计
    local actual_samples=${#durations[@]}
    local avg
    avg=$(calc_average "$sum" "$actual_samples")

    local min
    min=$(python3 -c "print(min([$(IFS=,; echo "${durations[*]}")]))")

    local max
    max=$(python3 -c "print(max([$(IFS=,; echo "${durations[*]}")]))")

    local p50 p95 p99
    p50=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 50)
    p95=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 95)
    p99=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 99)

    # 输出结果
    log_result ""
    log_result "=== End-to-End Workflow Benchmark ==="
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["end_to_end_workflow"]=$(cat <<EOF
{
  "samples": ${actual_samples},
  "avg_ms": ${avg},
  "min_ms": ${min},
  "max_ms": ${max},
  "p50_ms": ${p50},
  "p95_ms": ${p95},
  "p99_ms": ${p99}
}
EOF
)
}

# ============================================================================
# 基准测试：集成工作流（Session + Hooks）
# ============================================================================

benchmark_integrated_session_hooks() {
    log_info "Running Integrated Session+Hooks Benchmark (${SAMPLE_COUNT} iterations)..."

    local event_name="benchmark:integrated"

    # 注册 Hook
    oml_hook_register "integrated-hook" "$event_name" "${BENCHMARK_SYSTEM_DIR}/handlers/dummy.sh" "0" '{}' >/dev/null 2>&1 || true

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local session_id="warmup-int-${i}"
        oml_session_create "$session_id" '{"warmup": true}' >/dev/null 2>&1 || true
        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local session_id="int-${i}-$$"

        local start_ns
        start_ns=$(get_timestamp_ns)

        # 工作流：创建 Session -> 触发 Hook -> 添加消息 -> 删除
        oml_session_create "$session_id" '{"benchmark": "integrated"}' >/dev/null 2>&1 || true
        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true
        oml_session_mgr_add_message "$session_id" "user" "Integrated test ${i}" >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 清理 Hook
    oml_hook_unregister "integrated-hook" >/dev/null 2>&1 || true

    # 计算统计
    local actual_samples=${#durations[@]}
    local avg
    avg=$(calc_average "$sum" "$actual_samples")

    local min
    min=$(python3 -c "print(min([$(IFS=,; echo "${durations[*]}")]))")

    local max
    max=$(python3 -c "print(max([$(IFS=,; echo "${durations[*]}")]))")

    local p50 p95 p99
    p50=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 50)
    p95=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 95)
    p99=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 99)

    # 输出结果
    log_result ""
    log_result "=== Integrated Session+Hooks Benchmark ==="
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["integrated_session_hooks"]=$(cat <<EOF
{
  "samples": ${actual_samples},
  "avg_ms": ${avg},
  "min_ms": ${min},
  "max_ms": ${max},
  "p50_ms": ${p50},
  "p95_ms": ${p95},
  "p99_ms": ${p99}
}
EOF
)
}

# ============================================================================
# 基准测试：集成工作流（Session + Pool）
# ============================================================================

benchmark_integrated_session_pool() {
    log_info "Running Integrated Session+Pool Benchmark (${SAMPLE_COUNT} iterations)..."

    # 预创建 Worker
    local worker_ids=()
    for ((i=0; i<POOL_SIZE; i++)); do
        local worker_id
        worker_id=$(oml_pool_create_worker 2>/dev/null || echo "")
        if [[ -n "$worker_id" ]]; then
            worker_ids+=("$worker_id")
        fi
    done

    if [[ ${#worker_ids[@]} -eq 0 ]]; then
        log_result "  ERROR: No workers available"
        return 1
    fi

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local session_id="warmup-sp-${i}"
        local task_id="warmup-task-${i}"
        oml_session_create "$session_id" '{"warmup": true}' >/dev/null 2>&1 || true
        oml_pool_assign_task "$task_id" '{}' "${worker_ids[0]}" >/dev/null 2>&1 || true
        oml_pool_complete_task "$task_id" '{}' "true" >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local session_id="sp-${i}-$$"
        local task_id="task-${i}-$$"
        local worker_idx=$((i % ${#worker_ids[@]}))

        local start_ns
        start_ns=$(get_timestamp_ns)

        # 工作流：创建 Session -> 分配任务 -> 完成任务 -> 删除 Session
        oml_session_create "$session_id" '{"benchmark": "session_pool"}' >/dev/null 2>&1 || true
        oml_pool_assign_task "$task_id" '{"session": "'"${session_id}"'"}' "${worker_ids[$worker_idx]}" >/dev/null 2>&1 || true
        oml_pool_complete_task "$task_id" '{"result": "done"}' "true" >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 清理 Worker
    for worker_id in "${worker_ids[@]}"; do
        oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
    done

    # 计算统计
    local actual_samples=${#durations[@]}
    local avg
    avg=$(calc_average "$sum" "$actual_samples")

    local min
    min=$(python3 -c "print(min([$(IFS=,; echo "${durations[*]}")]))")

    local max
    max=$(python3 -c "print(max([$(IFS=,; echo "${durations[*]}")]))")

    local p50 p95 p99
    p50=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 50)
    p95=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 95)
    p99=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 99)

    # 输出结果
    log_result ""
    log_result "=== Integrated Session+Pool Benchmark ==="
    log_result "  Workers:    ${#worker_ids[@]}"
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["integrated_session_pool"]=$(cat <<EOF
{
  "workers": ${#worker_ids[@]},
  "samples": ${actual_samples},
  "avg_ms": ${avg},
  "min_ms": ${min},
  "max_ms": ${max},
  "p50_ms": ${p50},
  "p95_ms": ${p95},
  "p99_ms": ${p99}
}
EOF
)
}

# ============================================================================
# 基准测试：完整系统吞吐量
# ============================================================================

benchmark_full_system_throughput() {
    log_info "Running Full System Throughput Benchmark..."

    # 初始化所有组件
    local worker_ids=()
    for ((i=0; i<POOL_SIZE; i++)); do
        local worker_id
        worker_id=$(oml_pool_create_worker 2>/dev/null || echo "")
        if [[ -n "$worker_id" ]]; then
            worker_ids+=("$worker_id")
        fi
    done

    # 注册多个 Hook
    local event_name="benchmark:full"
    for ((i=0; i<HOOK_COUNT; i++)); do
        oml_hook_register "full-hook-${i}" "$event_name" "${BENCHMARK_SYSTEM_DIR}/handlers/dummy.sh" "$i" '{}' >/dev/null 2>&1 || true
    done

    local total_tasks=$((SAMPLE_COUNT * POOL_SIZE))
    local total_duration=0

    log_info "  Testing ${total_tasks} operations across all components..."

    # Warmup
    log_info "  Warmup..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local session_id="warmup-full-${i}"
        oml_session_create "$session_id" '{}' >/dev/null 2>&1 || true
        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    local start_ns
    start_ns=$(get_timestamp_ns)

    for ((i=0; i<total_tasks; i++)); do
        local session_id="full-${i}-$$"
        local task_id="full-task-${i}-$$"
        local worker_idx=$((i % ${#worker_ids[@]}))

        # 完整操作链
        oml_session_create "$session_id" '{"throughput": true}' >/dev/null 2>&1 || true
        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true
        oml_pool_assign_task "$task_id" '{}' "${worker_ids[$worker_idx]}" >/dev/null 2>&1 || true
        oml_pool_complete_task "$task_id" '{}' "true" >/dev/null 2>&1 || true
        oml_session_mgr_add_message "$session_id" "user" "Message ${i}" >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    local end_ns
    end_ns=$(get_timestamp_ns)

    total_duration=$(calc_duration_ms "$start_ns" "$end_ns")

    # 清理
    for worker_id in "${worker_ids[@]}"; do
        oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
    done
    for ((i=0; i<HOOK_COUNT; i++)); do
        oml_hook_unregister "full-hook-${i}" >/dev/null 2>&1 || true
    done

    # 计算统计
    local avg
    avg=$(python3 -c "print(${total_duration} / ${total_tasks} if ${total_tasks} > 0 else 0)")

    local throughput
    throughput=$(python3 -c "print(${total_tasks} / (${total_duration} / 1000) if ${total_duration} > 0 else 0)")

    local ops_per_sec
    ops_per_sec=$(python3 -c "print(${total_tasks} * 1000 / ${total_duration} if ${total_duration} > 0 else 0)")

    # 输出结果
    log_result ""
    log_result "=== Full System Throughput Benchmark ==="
    log_result "  Workers:        ${#worker_ids[@]}"
    log_result "  Hooks:          ${HOOK_COUNT}"
    log_result "  Total Ops:      ${total_tasks}"
    log_result "  Total Time:     ${total_duration} ms"
    log_result "  Avg per Op:     ${avg} ms"
    log_result "  Throughput:     ${throughput} ops/sec"
    log_result "  Ops/sec:        ${ops_per_sec}"

    BENCHMARK_RESULTS["full_system_throughput"]=$(cat <<EOF
{
  "workers": ${#worker_ids[@]},
  "hooks": ${HOOK_COUNT},
  "total_operations": ${total_tasks},
  "total_time_ms": ${total_duration},
  "avg_time_per_op_ms": ${avg},
  "throughput_ops_per_sec": ${throughput},
  "ops_per_sec": ${ops_per_sec}
}
EOF
)
}

# ============================================================================
# 基准测试：系统资源使用
# ============================================================================

benchmark_system_resources() {
    log_info "Running System Resource Usage Benchmark..."

    # 创建大量 Session
    local session_count=50
    local session_ids=()

    log_info "  Creating ${session_count} sessions..."
    for ((i=0; i<session_count; i++)); do
        local session_id="resource-${i}-$$"
        oml_session_create "$session_id" '{"resource_test": true, "data": "test data for session '"$i"'"}' >/dev/null 2>&1 || true
        session_ids+=("$session_id")
    done

    # 测量存储大小
    local total_size=0
    local data_dir="${OML_SESSIONS_DIR}/data"
    if [[ -d "$data_dir" ]]; then
        total_size=$(du -sb "$data_dir" 2>/dev/null | cut -f1 || echo "0")
    fi

    # 测量索引大小
    local index_size=0
    if [[ -f "${OML_SESSIONS_DIR}/index.json" ]]; then
        index_size=$(wc -c < "${OML_SESSIONS_DIR}/index.json" || echo "0")
    fi

    # 清理
    for session_id in "${session_ids[@]}"; do
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    # 输出结果
    log_result ""
    log_result "=== System Resource Usage Benchmark ==="
    log_result "  Sessions Created:  ${session_count}"
    log_result "  Data Dir Size:     ${total_size} bytes"
    log_result "  Index Size:        ${index_size} bytes"
    log_result "  Avg Session Size:  $((total_size / session_count)) bytes"

    BENCHMARK_RESULTS["system_resources"]=$(cat <<EOF
{
  "sessions_created": ${session_count},
  "data_dir_size_bytes": ${total_size},
  "index_size_bytes": ${index_size},
  "avg_session_size_bytes": $((total_size / session_count))
}
EOF
)
}

# ============================================================================
# 基准测试：并发压力测试
# ============================================================================

benchmark_stress_test() {
    log_info "Running Stress Test Benchmark..."

    local concurrent_sessions="${POOL_SIZE}"
    local operations_per_session=10

    # 预创建 Worker
    local worker_ids=()
    for ((i=0; i<POOL_SIZE; i++)); do
        local worker_id
        worker_id=$(oml_pool_create_worker 2>/dev/null || echo "")
        if [[ -n "$worker_id" ]]; then
            worker_ids+=("$worker_id")
        fi
    done

    local durations=()
    local sum=0

    log_info "  Testing ${concurrent_sessions} concurrent sessions with ${operations_per_session} ops each..."

    # 正式测试
    local start_ns
    start_ns=$(get_timestamp_ns)

    for ((s=0; s<concurrent_sessions; s++)); do
        local session_id="stress-${s}-$$"
        oml_session_create "$session_id" '{"stress_test": true}' >/dev/null 2>&1 || true

        for ((i=0; i<operations_per_session; i++)); do
            local task_id="stress-task-${s}-${i}-$$"
            local worker_idx=$((i % ${#worker_ids[@]}))

            oml_session_mgr_add_message "$session_id" "user" "Stress message ${i}" >/dev/null 2>&1 || true
            oml_pool_assign_task "$task_id" '{}' "${worker_ids[$worker_idx]}" >/dev/null 2>&1 || true
            oml_pool_complete_task "$task_id" '{}' "true" >/dev/null 2>&1 || true
        done

        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    local end_ns
    end_ns=$(get_timestamp_ns)

    local total_duration
    total_duration=$(calc_duration_ms "$start_ns" "$end_ns")

    local total_ops=$((concurrent_sessions * operations_per_session * 3))  # 3 ops per iteration

    # 清理
    for worker_id in "${worker_ids[@]}"; do
        oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
    done

    # 计算统计
    local throughput
    throughput=$(python3 -c "print(${total_ops} / (${total_duration} / 1000) if ${total_duration} > 0 else 0)")

    # 输出结果
    log_result ""
    log_result "=== Stress Test Benchmark ==="
    log_result "  Concurrent Sessions: ${concurrent_sessions}"
    log_result "  Ops per Session:     ${operations_per_session}"
    log_result "  Total Operations:    ${total_ops}"
    log_result "  Total Time:          ${total_duration} ms"
    log_result "  Throughput:          ${throughput} ops/sec"

    BENCHMARK_RESULTS["stress_test"]=$(cat <<EOF
{
  "concurrent_sessions": ${concurrent_sessions},
  "ops_per_session": ${operations_per_session},
  "total_operations": ${total_ops},
  "total_time_ms": ${total_duration},
  "throughput_ops_per_sec": ${throughput}
}
EOF
)
}

# ============================================================================
# 生成综合报告
# ============================================================================

generate_json_report() {
    local output_file="$1"

    python3 -c "
import json
from datetime import datetime

results = {}
$(for key in "${!BENCHMARK_RESULTS[@]}"; do
    echo "results['${key}'] = json.loads('${BENCHMARK_RESULTS[$key]}')"
done)

report = {
    'benchmark': 'OML System Performance Benchmark',
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'config': {
        'sample_count': ${SAMPLE_COUNT},
        'warmup_count': ${WARMUP_COUNT},
        'pool_size': ${POOL_SIZE},
        'hook_count': ${HOOK_COUNT}
    },
    'results': results
}

with open('${output_file}', 'w') as f:
    json.dump(report, f, indent=2)

print(f'JSON report saved to: ${output_file}')
"
}

generate_markdown_report() {
    local output_file="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$output_file" <<EOF
# OML System Performance Benchmark Report

**Generated:** ${timestamp}

## Configuration

| Parameter | Value |
|-----------|-------|
| Sample Count | ${SAMPLE_COUNT} |
| Warmup Count | ${WARMUP_COUNT} |
| Pool Size | ${POOL_SIZE} |
| Hook Count | ${HOOK_COUNT} |

## Results Summary

### End-to-End Workflow

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["end_to_end_workflow"]:-N/A} |

### Integrated Session+Hooks

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["integrated_session_hooks"]:-N/A} |

### Integrated Session+Pool

| Metric | Value |
|--------|-------|
| Avg Latency | ${BENCHMARK_RESULTS["integrated_session_pool"]:-N/A} |

### Full System Throughput

| Metric | Value |
|--------|-------|
| Throughput | ${BENCHMARK_RESULTS["full_system_throughput"]:-N/A} |

### Stress Test

| Metric | Value |
|--------|-------|
| Throughput | ${BENCHMARK_RESULTS["stress_test"]:-N/A} |

### System Resources

| Metric | Value |
|--------|-------|
| Data Size | ${BENCHMARK_RESULTS["system_resources"]:-N/A} |

---
*Report generated by OML Benchmark Suite*
EOF

    log_info "Markdown report saved to: ${output_file}"
}

# ============================================================================
# 主入口
# ============================================================================

main() {
    local action="${1:-all}"
    local report_file="${2:-}"

    echo "============================================"
    echo "OML System Performance Benchmark"
    echo "============================================"
    echo ""
    echo "Configuration:"
    echo "  Sample Count:  ${SAMPLE_COUNT}"
    echo "  Warmup Count:  ${WARMUP_COUNT}"
    echo "  Pool Size:     ${POOL_SIZE}"
    echo "  Hook Count:    ${HOOK_COUNT}"
    echo "  Output Format: ${OUTPUT_FORMAT}"
    echo "  Test Dir:      ${BENCHMARK_SYSTEM_DIR}"
    echo ""

    # 设置环境
    setup_test_env

    case "$action" in
        all)
            benchmark_end_to_end_workflow
            benchmark_integrated_session_hooks
            benchmark_integrated_session_pool
            benchmark_full_system_throughput
            benchmark_system_resources
            benchmark_stress_test
            ;;
        e2e)
            benchmark_end_to_end_workflow
            ;;
        session-hooks)
            benchmark_integrated_session_hooks
            ;;
        session-pool)
            benchmark_integrated_session_pool
            ;;
        throughput)
            benchmark_full_system_throughput
            ;;
        resources)
            benchmark_system_resources
            ;;
        stress)
            benchmark_stress_test
            ;;
        *)
            echo "Unknown action: $action"
            echo "Usage: $0 [all|e2e|session-hooks|session-pool|throughput|resources|stress] [report_file]"
            teardown_test_env
            exit 1
            ;;
    esac

    # 生成报告
    if [[ -n "$report_file" ]]; then
        case "$report_file" in
            *.json)
                generate_json_report "$report_file"
                ;;
            *.md)
                generate_markdown_report "$report_file"
                ;;
            *)
                generate_markdown_report "${report_file}.md"
                ;;
        esac
    fi

    # 清理
    teardown_test_env

    echo ""
    echo "============================================"
    echo "Benchmark Complete"
    echo "============================================"
}

main "$@"
