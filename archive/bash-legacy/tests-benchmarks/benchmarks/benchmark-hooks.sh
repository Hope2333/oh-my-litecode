#!/usr/bin/env bash
# OML Hooks Performance Benchmark
# Hooks 性能基准测试 - 测试 Hooks 触发延迟和执行性能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="${PROJECT_ROOT}/core"

# ============================================================================
# 配置
# ============================================================================

readonly BENCHMARK_HOOKS_DIR="${BENCHMARK_HOOKS_DIR:-$(mktemp -d)}"
readonly SAMPLE_COUNT="${SAMPLE_COUNT:-100}"
readonly WARMUP_COUNT="${WARMUP_COUNT:-10}"
readonly HOOK_COUNT="${HOOK_COUNT:-5}"  # 每次测试的 Hook 数量
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
    log_info "Setting up test environment at: ${BENCHMARK_HOOKS_DIR}"

    export HOME="${BENCHMARK_HOOKS_DIR}"
    export OML_HOOKS_CONFIG_DIR="${BENCHMARK_HOOKS_DIR}/hooks"
    export OML_HOOKS_REGISTRY_FILE="${BENCHMARK_HOOKS_DIR}/hooks/registry.json"
    export OML_DISPATCHER_LOGS_DIR="${BENCHMARK_HOOKS_DIR}/hooks/dispatcher"
    export OML_EVENT_QUEUE_DIR="${BENCHMARK_HOOKS_DIR}/hooks/queue"

    mkdir -p "${OML_HOOKS_CONFIG_DIR}"
    mkdir -p "${OML_DISPATCHER_LOGS_DIR}"
    mkdir -p "${OML_EVENT_QUEUE_DIR}"

    # 创建测试 Hook 处理器脚本
    mkdir -p "${BENCHMARK_HOOKS_DIR}/handlers"

    # 创建空处理器（最快）
    cat > "${BENCHMARK_HOOKS_DIR}/handlers/empty.sh" <<'EOF'
#!/usr/bin/env bash
# Empty handler - does nothing
exit 0
EOF
    chmod +x "${BENCHMARK_HOOKS_DIR}/handlers/empty.sh"

    # 创建轻量处理器
    cat > "${BENCHMARK_HOOKS_DIR}/handlers/light.sh" <<'EOF'
#!/usr/bin/env bash
# Light handler - minimal work
echo "processed"
exit 0
EOF
    chmod +x "${BENCHMARK_HOOKS_DIR}/handlers/light.sh"

    # 创建中等处理器
    cat > "${BENCHMARK_HOOKS_DIR}/handlers/medium.sh" <<'EOF'
#!/usr/bin/env bash
# Medium handler - some work
for i in {1..10}; do
    echo "iteration $i" >/dev/null
done
exit 0
EOF
    chmod +x "${BENCHMARK_HOOKS_DIR}/handlers/medium.sh"

    # 创建重量处理器
    cat > "${BENCHMARK_HOOKS_DIR}/handlers/heavy.sh" <<'EOF'
#!/usr/bin/env bash
# Heavy handler - more work
for i in {1..100}; do
    echo "iteration $i" >/dev/null
done
sleep 0.01
exit 0
EOF
    chmod +x "${BENCHMARK_HOOKS_DIR}/handlers/heavy.sh"

    # 初始化 Hooks 注册表
    cat > "${OML_HOOKS_REGISTRY_FILE}" <<'EOF'
{
  "hooks": [],
  "events": {},
  "metadata": {
    "created_at": "",
    "updated_at": "",
    "version": "1.0.0"
  }
}
EOF

    # 加载核心模块
    source "${CORE_DIR}/platform.sh" 2>/dev/null || true
    source "${CORE_DIR}/event-bus.sh" 2>/dev/null || true
    source "${CORE_DIR}/hooks-registry.sh" 2>/dev/null || true
    source "${CORE_DIR}/hooks-dispatcher.sh" 2>/dev/null || true
    source "${CORE_DIR}/hooks-engine.sh" 2>/dev/null || true

    oml_hooks_registry_init 2>/dev/null || true
    oml_event_bus_init 2>/dev/null || true
}

teardown_test_env() {
    log_info "Cleaning up test environment"
    if [[ -d "$BENCHMARK_HOOKS_DIR" ]]; then
        rm -rf "$BENCHMARK_HOOKS_DIR"
    fi
}

# 注册测试 Hook
register_test_hooks() {
    local count="$1"
    local handler="$2"
    local event_prefix="$3"

    for ((i=0; i<count; i++)); do
        local hook_name="${event_prefix}-hook-${i}"
        local event_name="${event_prefix}:test"
        oml_hook_register "$hook_name" "$event_name" "$handler" "$i" '{}' >/dev/null 2>&1 || true
    done
}

# 清除所有 Hook
clear_all_hooks() {
    cat > "${OML_HOOKS_REGISTRY_FILE}" <<'EOF'
{
  "hooks": [],
  "events": {},
  "metadata": {
    "created_at": "",
    "updated_at": "",
    "version": "1.0.0"
  }
}
EOF
}

# ============================================================================
# 基准测试：单 Hook 触发延迟
# ============================================================================

benchmark_single_hook_latency() {
    log_info "Running Single Hook Latency Benchmark (${SAMPLE_COUNT} iterations)..."

    local handler="${BENCHMARK_HOOKS_DIR}/handlers/empty.sh"
    local event_name="benchmark:single"

    # 注册单个 Hook
    clear_all_hooks
    oml_hook_register "single-hook" "$event_name" "$handler" "0" '{}' >/dev/null 2>&1

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 计算统计
    local avg
    avg=$(calc_average "$sum" "$SAMPLE_COUNT")

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
    log_result "=== Single Hook Latency Benchmark ==="
    log_result "  Handler:    empty.sh"
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["single_hook_latency"]=$(cat <<EOF
{
  "handler": "empty.sh",
  "samples": ${SAMPLE_COUNT},
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
# 基准测试：多 Hook 触发性能
# ============================================================================

benchmark_multi_hook_throughput() {
    log_info "Running Multi-Hook Throughput Benchmark (${HOOK_COUNT} hooks, ${SAMPLE_COUNT} iterations)..."

    local handler="${BENCHMARK_HOOKS_DIR}/handlers/light.sh"
    local event_name="benchmark:multi"

    # 注册多个 Hook
    clear_all_hooks
    register_test_hooks "$HOOK_COUNT" "$handler" "$event_name"

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 计算统计
    local avg
    avg=$(calc_average "$sum" "$SAMPLE_COUNT")

    local min
    min=$(python3 -c "print(min([$(IFS=,; echo "${durations[*]}")]))")

    local max
    max=$(python3 -c "print(max([$(IFS=,; echo "${durations[*]}")]))")

    local p50 p95 p99
    p50=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 50)
    p95=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 95)
    p99=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 99)

    # 计算吞吐量（hooks/秒）
    local throughput
    throughput=$(python3 -c "print(${HOOK_COUNT} / (${avg} / 1000) if ${avg} > 0 else 0)")

    # 输出结果
    log_result ""
    log_result "=== Multi-Hook Throughput Benchmark ==="
    log_result "  Hooks:      ${HOOK_COUNT}"
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"
    log_result "  Throughput: ${throughput} hooks/sec"

    BENCHMARK_RESULTS["multi_hook_throughput"]=$(cat <<EOF
{
  "hook_count": ${HOOK_COUNT},
  "handler": "light.sh",
  "samples": ${SAMPLE_COUNT},
  "avg_ms": ${avg},
  "min_ms": ${min},
  "max_ms": ${max},
  "p50_ms": ${p50},
  "p95_ms": ${p95},
  "p99_ms": ${p99},
  "throughput_hooks_per_sec": ${throughput}
}
EOF
)
}

# ============================================================================
# 基准测试：Hook 处理器性能对比
# ============================================================================

benchmark_handler_performance() {
    log_info "Running Handler Performance Benchmark..."

    local event_name="benchmark:handler"
    local handlers=("empty.sh" "light.sh" "medium.sh" "heavy.sh")

    for handler in "${handlers[@]}"; do
        local handler_path="${BENCHMARK_HOOKS_DIR}/handlers/${handler}"
        log_info "  Testing handler: ${handler}..."

        # 注册 Hook
        clear_all_hooks
        oml_hook_register "handler-test" "$event_name" "$handler_path" "0" '{}' >/dev/null 2>&1

        local durations=()
        local sum=0
        local test_count=$((SAMPLE_COUNT / 4))  # 每个处理器测试较少次数

        # Warmup
        for ((i=0; i<WARMUP_COUNT; i++)); do
            oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true
        done

        # 正式测试
        for ((i=0; i<test_count; i++)); do
            local start_ns
            start_ns=$(get_timestamp_ns)

            oml_hooks_dispatch "$event_name" >/dev/null 2>&1 || true

            local end_ns
            end_ns=$(get_timestamp_ns)

            local duration_ms
            duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
            durations+=("$duration_ms")
            sum=$(python3 -c "print(${sum} + ${duration_ms})")
        done

        local avg
        avg=$(calc_average "$sum" "$test_count")

        log_result "  Handler ${handler}: Avg ${avg} ms (${test_count} samples)"

        BENCHMARK_RESULTS["handler_${handler}"]=$(cat <<EOF
{
  "handler": "${handler}",
  "samples": ${test_count},
  "avg_ms": ${avg}
}
EOF
)
    done
}

# ============================================================================
# 基准测试：Hook 注册/注销性能
# ============================================================================

benchmark_hook_registration() {
    log_info "Running Hook Registration Benchmark (${SAMPLE_COUNT} iterations)..."

    local handler="${BENCHMARK_HOOKS_DIR}/handlers/empty.sh"
    local event_name="benchmark:registration"

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_hook_register "warmup-${i}" "$event_name" "$handler" "0" '{}' >/dev/null 2>&1 || true
        oml_hook_unregister "warmup-${i}" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local hook_name="bench-reg-${i}-$$"

        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_hook_register "$hook_name" "$event_name" "$handler" "0" '{}' >/dev/null 2>&1

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")

        # 清理
        oml_hook_unregister "$hook_name" >/dev/null 2>&1 || true
    done

    # 计算统计
    local avg
    avg=$(calc_average "$sum" "$SAMPLE_COUNT")

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
    log_result "=== Hook Registration Benchmark ==="
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["hook_registration"]=$(cat <<EOF
{
  "samples": ${SAMPLE_COUNT},
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
# 基准测试：Pre/Post Hook 链性能
# ============================================================================

benchmark_pre_post_chain() {
    log_info "Running Pre/Post Hook Chain Benchmark..."

    local handler="${BENCHMARK_HOOKS_DIR}/handlers/light.sh"
    local target="benchmark:target"

    # 注册 Pre 和 Post Hooks
    clear_all_hooks
    for ((i=0; i<HOOK_COUNT; i++)); do
        oml_hook_register "pre-hook-${i}" "${target}:pre" "$handler" "$i" '{}' >/dev/null 2>&1 || true
        oml_hook_register "post-hook-${i}" "${target}:post" "$handler" "$i" '{}' >/dev/null 2>&1 || true
    done

    local durations=()
    local sum=0
    local test_count=$((SAMPLE_COUNT / 2))

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_hook_trigger "$target" --timeout 30 >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark (Pre+Post chains)..."
    for ((i=0; i<test_count; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_hook_trigger "$target" --timeout 30 >/dev/null 2>&1 || true

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 计算统计
    local avg
    avg=$(calc_average "$sum" "$test_count")

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
    log_result "=== Pre/Post Hook Chain Benchmark ==="
    log_result "  Pre Hooks:  ${HOOK_COUNT}"
    log_result "  Post Hooks: ${HOOK_COUNT}"
    log_result "  Samples:    ${test_count}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["pre_post_chain"]=$(cat <<EOF
{
  "pre_hooks": ${HOOK_COUNT},
  "post_hooks": ${HOOK_COUNT},
  "samples": ${test_count},
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
    'benchmark': 'OML Hooks Performance Benchmark',
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'config': {
        'sample_count': ${SAMPLE_COUNT},
        'warmup_count': ${WARMUP_COUNT},
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
# OML Hooks Performance Benchmark Report

**Generated:** ${timestamp}

## Configuration

| Parameter | Value |
|-----------|-------|
| Sample Count | ${SAMPLE_COUNT} |
| Warmup Count | ${WARMUP_COUNT} |
| Hook Count | ${HOOK_COUNT} |

## Results Summary

### Single Hook Latency

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["single_hook_latency"]:-N/A} |

### Multi-Hook Throughput

| Metric | Value |
|--------|-------|
| Hooks | ${HOOK_COUNT} |
| Avg Latency | ${BENCHMARK_RESULTS["multi_hook_throughput"]:-N/A} |

### Hook Registration

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["hook_registration"]:-N/A} |

### Pre/Post Chain

| Metric | Value |
|--------|-------|
| Pre Hooks | ${HOOK_COUNT} |
| Post Hooks | ${HOOK_COUNT} |
| Avg Latency | ${BENCHMARK_RESULTS["pre_post_chain"]:-N/A} |

## Handler Performance Comparison

| Handler | Avg Latency (ms) |
|---------|-----------------|
| empty.sh | ${BENCHMARK_RESULTS["handler_empty.sh"]:-N/A} |
| light.sh | ${BENCHMARK_RESULTS["handler_light.sh"]:-N/A} |
| medium.sh | ${BENCHMARK_RESULTS["handler_medium.sh"]:-N/A} |
| heavy.sh | ${BENCHMARK_RESULTS["handler_heavy.sh"]:-N/A} |

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
    echo "OML Hooks Performance Benchmark"
    echo "============================================"
    echo ""
    echo "Configuration:"
    echo "  Sample Count:  ${SAMPLE_COUNT}"
    echo "  Warmup Count:  ${WARMUP_COUNT}"
    echo "  Hook Count:    ${HOOK_COUNT}"
    echo "  Output Format: ${OUTPUT_FORMAT}"
    echo "  Test Dir:      ${BENCHMARK_HOOKS_DIR}"
    echo ""

    # 设置环境
    setup_test_env

    case "$action" in
        all)
            benchmark_single_hook_latency
            benchmark_multi_hook_throughput
            benchmark_handler_performance
            benchmark_hook_registration
            benchmark_pre_post_chain
            ;;
        single)
            benchmark_single_hook_latency
            ;;
        multi)
            benchmark_multi_hook_throughput
            ;;
        handler)
            benchmark_handler_performance
            ;;
        registration)
            benchmark_hook_registration
            ;;
        chain)
            benchmark_pre_post_chain
            ;;
        *)
            echo "Unknown action: $action"
            echo "Usage: $0 [all|single|multi|handler|registration|chain] [report_file]"
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
