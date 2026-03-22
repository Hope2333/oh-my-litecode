#!/usr/bin/env bash
# OML Worker Pool Performance Benchmark
# Worker 池性能基准测试 - 测试 Worker 池调度延迟和吞吐量

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="${PROJECT_ROOT}/core"

# ============================================================================
# 配置
# ============================================================================

readonly BENCHMARK_POOL_DIR="${BENCHMARK_POOL_DIR:-$(mktemp -d)}"
readonly SAMPLE_COUNT="${SAMPLE_COUNT:-50}"
readonly WARMUP_COUNT="${WARMUP_COUNT:-5}"
readonly POOL_SIZE="${POOL_SIZE:-5}"
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
    log_info "Setting up test environment at: ${BENCHMARK_POOL_DIR}"

    export HOME="${BENCHMARK_POOL_DIR}"
    export OML_POOL_DIR="${BENCHMARK_POOL_DIR}/pool"
    export OML_POOL_WORKERS_DIR="${BENCHMARK_POOL_DIR}/pool/workers"
    export OML_POOL_STATE_FILE="${BENCHMARK_POOL_DIR}/pool/state.json"
    export OML_POOL_LOGS_DIR="${BENCHMARK_POOL_DIR}/pool/logs"

    mkdir -p "${OML_POOL_WORKERS_DIR}"
    mkdir -p "${OML_POOL_LOGS_DIR}"

    # 创建测试 Worker 脚本
    mkdir -p "${BENCHMARK_POOL_DIR}/workers"

    # 创建空 Worker 脚本
    cat > "${BENCHMARK_POOL_DIR}/workers/empty-worker.sh" <<'EOF'
#!/usr/bin/env bash
# Empty worker - does nothing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worker-id) shift; shift ;;
        *) shift ;;
    esac
done
exit 0
EOF
    chmod +x "${BENCHMARK_POOL_DIR}/workers/empty-worker.sh"

    # 创建轻量 Worker 脚本
    cat > "${BENCHMARK_POOL_DIR}/workers/light-worker.sh" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worker-id) shift; shift ;;
        *) shift ;;
    esac
done
echo "processed"
exit 0
EOF
    chmod +x "${BENCHMARK_POOL_DIR}/workers/light-worker.sh"

    # 创建模拟任务 Worker
    cat > "${BENCHMARK_POOL_DIR}/workers/task-worker.sh" <<'EOF'
#!/usr/bin/env bash
# Simulates task processing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worker-id) shift; shift ;;
        --task) shift; shift ;;
        *) shift ;;
    esac
done
# Simulate some work
for i in {1..10}; do
    echo "working" >/dev/null
done
exit 0
EOF
    chmod +x "${BENCHMARK_POOL_DIR}/workers/task-worker.sh"

    # 加载核心模块
    source "${CORE_DIR}/platform.sh" 2>/dev/null || true
    source "${CORE_DIR}/pool-manager.sh"

    # 初始化池
    oml_pool_init 1 "${POOL_SIZE}" >/dev/null 2>&1 || true
}

teardown_test_env() {
    log_info "Cleaning up test environment"
    if [[ -d "$BENCHMARK_POOL_DIR" ]]; then
        rm -rf "$BENCHMARK_POOL_DIR"
    fi
}

# 重置池状态
reset_pool() {
    local min_workers="${1:-1}"
    local max_workers="${2:-$POOL_SIZE}"

    rm -f "${OML_POOL_WORKERS_DIR}"/*.json 2>/dev/null || true

    oml_pool_init "$min_workers" "$max_workers" >/dev/null 2>&1 || true
}

# ============================================================================
# 基准测试：Worker 创建延迟
# ============================================================================

benchmark_worker_creation() {
    log_info "Running Worker Creation Benchmark (${SAMPLE_COUNT} iterations)..."

    reset_pool 1 "${POOL_SIZE}"

    local durations=()
    local sum=0
    local created_workers=()

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local worker_id
        worker_id=$(oml_pool_create_worker 2>/dev/null || echo "")
        if [[ -n "$worker_id" ]]; then
            oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
        fi
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        local worker_id
        worker_id=$(oml_pool_create_worker 2>/dev/null || echo "")

        local end_ns
        end_ns=$(get_timestamp_ns)

        if [[ -n "$worker_id" ]]; then
            local duration_ms
            duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
            durations+=("$duration_ms")
            sum=$(python3 -c "print(${sum} + ${duration_ms})")
            created_workers+=("$worker_id")
        fi
    done

    # 清理
    for worker_id in "${created_workers[@]}"; do
        oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
    done

    local actual_samples=${#durations[@]}

    if [[ $actual_samples -eq 0 ]]; then
        log_result "  ERROR: No workers created"
        return 1
    fi

    # 计算统计
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
    log_result "=== Worker Creation Benchmark ==="
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["worker_creation"]=$(cat <<EOF
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
# 基准测试：任务分配延迟
# ============================================================================

benchmark_task_assignment() {
    log_info "Running Task Assignment Benchmark (${SAMPLE_COUNT} iterations)..."

    reset_pool 1 "${POOL_SIZE}"

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
    local assigned_tasks=()

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local task_id="warmup-task-${i}"
        oml_pool_assign_task "$task_id" '{"warmup": true}' "${worker_ids[0]}" >/dev/null 2>&1 || true
        oml_pool_complete_task "$task_id" '{"result": "done"}' "true" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local task_id="bench-task-${i}-$$"
        local worker_idx=$((i % ${#worker_ids[@]}))
        local worker_id="${worker_ids[$worker_idx]}"

        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_pool_assign_task "$task_id" '{"benchmark": true, "iteration": '"$i"'}' "$worker_id" >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
        assigned_tasks+=("$task_id")
    done

    # 清理：完成任务
    for task_id in "${assigned_tasks[@]}"; do
        oml_pool_complete_task "$task_id" '{"result": "done"}' "true" >/dev/null 2>&1 || true
    done

    # 清理 Worker
    for worker_id in "${worker_ids[@]}"; do
        oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
    done

    local actual_samples=${#durations[@]}

    if [[ $actual_samples -eq 0 ]]; then
        log_result "  ERROR: No tasks assigned"
        return 1
    fi

    # 计算统计
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

    # 计算吞吐量（tasks/秒）
    local throughput
    throughput=$(python3 -c "print(1000 / ${avg} if ${avg} > 0 else 0)")

    # 输出结果
    log_result ""
    log_result "=== Task Assignment Benchmark ==="
    log_result "  Workers:    ${#worker_ids[@]}"
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"
    log_result "  Throughput: ${throughput} tasks/sec"

    BENCHMARK_RESULTS["task_assignment"]=$(cat <<EOF
{
  "workers": ${#worker_ids[@]},
  "samples": ${actual_samples},
  "avg_ms": ${avg},
  "min_ms": ${min},
  "max_ms": ${max},
  "p50_ms": ${p50},
  "p95_ms": ${p95},
  "p99_ms": ${p99},
  "throughput_tasks_per_sec": ${throughput}
}
EOF
)
}

# ============================================================================
# 基准测试：Worker 调度延迟
# ============================================================================

benchmark_worker_scheduling() {
    log_info "Running Worker Scheduling Benchmark (${SAMPLE_COUNT} iterations)..."

    reset_pool "${POOL_SIZE}" "${POOL_SIZE}"

    # 预创建并启动 Worker
    local worker_ids=()
    for ((i=0; i<POOL_SIZE; i++)); do
        local worker_id
        worker_id=$(oml_pool_create_worker 2>/dev/null || echo "")
        if [[ -n "$worker_id" ]]; then
            worker_ids+=("$worker_id")
            oml_pool_start_worker "$worker_id" "${BENCHMARK_POOL_DIR}/workers/empty-worker.sh" >/dev/null 2>&1 || true
        fi
    done

    if [[ ${#worker_ids[@]} -eq 0 ]]; then
        log_result "  ERROR: No workers available"
        return 1
    fi

    local durations=()
    local sum=0
    local scheduled_tasks=()

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local task_id="warmup-sched-${i}"
        oml_pool_assign_task "$task_id" '{}' "" >/dev/null 2>&1 || true
        oml_pool_complete_task "$task_id" '{}' "true" >/dev/null 2>&1 || true
    done

    # 正式测试：测试从任务分配到找到空闲 Worker 的延迟
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local task_id="bench-sched-${i}-$$"

        local start_ns
        start_ns=$(get_timestamp_ns)

        # 分配任务（自动选择空闲 Worker）
        oml_pool_assign_task "$task_id" '{"iteration": '"$i"'}' "" >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
        scheduled_tasks+=("$task_id")

        # 完成任务以释放 Worker
        oml_pool_complete_task "$task_id" '{"result": "done"}' "true" >/dev/null 2>&1 || true
    done

    # 清理 Worker
    for worker_id in "${worker_ids[@]}"; do
        oml_pool_stop_worker "$worker_id" "true" >/dev/null 2>&1 || true
        oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
    done

    local actual_samples=${#durations[@]}

    if [[ $actual_samples -eq 0 ]]; then
        log_result "  ERROR: No tasks scheduled"
        return 1
    fi

    # 计算统计
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
    log_result "=== Worker Scheduling Benchmark ==="
    log_result "  Pool Size:  ${POOL_SIZE}"
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["worker_scheduling"]=$(cat <<EOF
{
  "pool_size": ${POOL_SIZE},
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
# 基准测试：自动扩缩容性能
# ============================================================================

benchmark_autoscaling() {
    log_info "Running Autoscaling Benchmark..."

    reset_pool 1 "${POOL_SIZE}"

    local durations=()
    local sum=0
    local scale_operations=0

    # Warmup
    log_info "  Warmup: Creating initial workers..."
    oml_pool_scale_up 2 >/dev/null 2>&1 || true
    oml_pool_scale_down 1 >/dev/null 2>&1 || true

    # 正式测试：测试扩缩容操作
    log_info "  Running benchmark (scale up/down cycles)..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        # Scale up
        oml_pool_scale_up 1 >/dev/null 2>&1 || true
        ((scale_operations++))

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")

        # Scale down
        oml_pool_scale_down 1 >/dev/null 2>&1 || true
        ((scale_operations++))
    done

    # 清理
    reset_pool 1 "${POOL_SIZE}"

    local actual_samples=${#durations[@]}

    if [[ $actual_samples -eq 0 ]]; then
        log_result "  ERROR: No scale operations completed"
        return 1
    fi

    # 计算统计
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
    log_result "=== Autoscaling Benchmark ==="
    log_result "  Operations: ${scale_operations}"
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["autoscaling"]=$(cat <<EOF
{
  "operations": ${scale_operations},
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
# 基准测试：并发任务处理
# ============================================================================

benchmark_concurrent_tasks() {
    log_info "Running Concurrent Tasks Benchmark..."

    reset_pool "${POOL_SIZE}" "${POOL_SIZE}"

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

    local total_duration=0
    local task_count=$((SAMPLE_COUNT * POOL_SIZE))

    log_info "  Testing ${task_count} tasks across ${#worker_ids[@]} workers..."

    # Warmup
    log_info "  Warmup..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local task_id="warmup-conc-${i}"
        local worker_idx=$((i % ${#worker_ids[@]}))
        oml_pool_assign_task "$task_id" '{}' "${worker_ids[$worker_idx]}" >/dev/null 2>&1 || true
        oml_pool_complete_task "$task_id" '{}' "true" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    local start_ns
    start_ns=$(get_timestamp_ns)

    for ((i=0; i<task_count; i++)); do
        local task_id="bench-conc-${i}-$$"
        local worker_idx=$((i % ${#worker_ids[@]}))
        oml_pool_assign_task "$task_id" '{"concurrent": true}' "${worker_ids[$worker_idx]}" >/dev/null 2>&1 || true
        oml_pool_complete_task "$task_id" '{"result": "done"}' "true" >/dev/null 2>&1 || true
    done

    local end_ns
    end_ns=$(get_timestamp_ns)

    total_duration=$(calc_duration_ms "$start_ns" "$end_ns")

    # 计算统计
    local avg
    avg=$(python3 -c "print(${total_duration} / ${task_count} if ${task_count} > 0 else 0)")

    local throughput
    throughput=$(python3 -c "print(${task_count} / (${total_duration} / 1000) if ${total_duration} > 0 else 0)")

    # 清理
    for worker_id in "${worker_ids[@]}"; do
        oml_pool_delete_worker "$worker_id" >/dev/null 2>&1 || true
    done

    # 输出结果
    log_result ""
    log_result "=== Concurrent Tasks Benchmark ==="
    log_result "  Workers:        ${#worker_ids[@]}"
    log_result "  Total Tasks:    ${task_count}"
    log_result "  Total Time:     ${total_duration} ms"
    log_result "  Avg per Task:   ${avg} ms"
    log_result "  Throughput:     ${throughput} tasks/sec"

    BENCHMARK_RESULTS["concurrent_tasks"]=$(cat <<EOF
{
  "workers": ${#worker_ids[@]},
  "total_tasks": ${task_count},
  "total_time_ms": ${total_duration},
  "avg_time_per_task_ms": ${avg},
  "throughput_tasks_per_sec": ${throughput}
}
EOF
)
}

# ============================================================================
# 基准测试：池状态查询性能
# ============================================================================

benchmark_pool_queries() {
    log_info "Running Pool Queries Benchmark (${SAMPLE_COUNT} iterations)..."

    reset_pool "${POOL_SIZE}" "${POOL_SIZE}"

    # 预创建 Worker
    for ((i=0; i<POOL_SIZE; i++)); do
        oml_pool_create_worker >/dev/null 2>&1 || true
    done

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_pool_stats >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_pool_get_state >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 清理
    reset_pool 1 "${POOL_SIZE}"

    local actual_samples=${#durations[@]}

    if [[ $actual_samples -eq 0 ]]; then
        log_result "  ERROR: No queries completed"
        return 1
    fi

    # 计算统计
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
    log_result "=== Pool Queries Benchmark ==="
    log_result "  Samples:    ${actual_samples}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["pool_queries"]=$(cat <<EOF
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
# 生成报告
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
    'benchmark': 'OML Worker Pool Performance Benchmark',
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'config': {
        'sample_count': ${SAMPLE_COUNT},
        'warmup_count': ${WARMUP_COUNT},
        'pool_size': ${POOL_SIZE}
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
# OML Worker Pool Performance Benchmark Report

**Generated:** ${timestamp}

## Configuration

| Parameter | Value |
|-----------|-------|
| Sample Count | ${SAMPLE_COUNT} |
| Warmup Count | ${WARMUP_COUNT} |
| Pool Size | ${POOL_SIZE} |

## Results Summary

### Worker Creation

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["worker_creation"]:-N/A} |

### Task Assignment

| Metric | Value |
|--------|-------|
| Avg Latency | ${BENCHMARK_RESULTS["task_assignment"]:-N/A} |

### Worker Scheduling

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["worker_scheduling"]:-N/A} |

### Autoscaling

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["autoscaling"]:-N/A} |

### Concurrent Tasks

| Metric | Value |
|--------|-------|
| Throughput | ${BENCHMARK_RESULTS["concurrent_tasks"]:-N/A} |

### Pool Queries

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["pool_queries"]:-N/A} |

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
    echo "OML Worker Pool Performance Benchmark"
    echo "============================================"
    echo ""
    echo "Configuration:"
    echo "  Sample Count:  ${SAMPLE_COUNT}"
    echo "  Warmup Count:  ${WARMUP_COUNT}"
    echo "  Pool Size:     ${POOL_SIZE}"
    echo "  Output Format: ${OUTPUT_FORMAT}"
    echo "  Test Dir:      ${BENCHMARK_POOL_DIR}"
    echo ""

    # 设置环境
    setup_test_env

    case "$action" in
        all)
            benchmark_worker_creation
            benchmark_task_assignment
            benchmark_worker_scheduling
            benchmark_autoscaling
            benchmark_concurrent_tasks
            benchmark_pool_queries
            ;;
        creation)
            benchmark_worker_creation
            ;;
        assignment)
            benchmark_task_assignment
            ;;
        scheduling)
            benchmark_worker_scheduling
            ;;
        autoscaling)
            benchmark_autoscaling
            ;;
        concurrent)
            benchmark_concurrent_tasks
            ;;
        queries)
            benchmark_pool_queries
            ;;
        *)
            echo "Unknown action: $action"
            echo "Usage: $0 [all|creation|assignment|scheduling|autoscaling|concurrent|queries] [report_file]"
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
