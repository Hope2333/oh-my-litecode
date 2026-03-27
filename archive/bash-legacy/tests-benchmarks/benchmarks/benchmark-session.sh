#!/usr/bin/env bash
# OML Session Performance Benchmark
# Session 性能基准测试 - 测试 Session 创建/读取/写入/删除性能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="${PROJECT_ROOT}/core"

# ============================================================================
# 配置
# ============================================================================

readonly BENCHMARK_SESSIONS_DIR="${BENCHMARK_SESSIONS_DIR:-$(mktemp -d)}"
readonly SAMPLE_COUNT="${SAMPLE_COUNT:-100}"
readonly WARMUP_COUNT="${WARMUP_COUNT:-10}"
readonly OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"  # text, json, markdown

# 测试结果存储
declare -A BENCHMARK_RESULTS=()

# ============================================================================
# 工具函数
# ============================================================================

# 获取纳秒级时间戳
get_timestamp_ns() {
    python3 -c "import time; print(int(time.time_ns()))"
}

# 计算耗时（毫秒）
calc_duration_ms() {
    local start="$1"
    local end="$2"
    python3 -c "print((${end} - ${start}) / 1_000_000)"
}

# 计算平均值
calc_average() {
    local sum="$1"
    local count="$2"
    python3 -c "print(${sum} / ${count} if ${count} > 0 else 0)"
}

# 计算百分位数
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

# 日志输出
log_info() {
    echo "[INFO] $*" >&2
}

log_result() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "$@"
    fi
}

# JSON 输出
output_json() {
    local key="$1"
    local data="$2"
    BENCHMARK_RESULTS["$key"]="$data"
}

# ============================================================================
# 测试环境设置
# ============================================================================

setup_test_env() {
    log_info "Setting up test environment at: ${BENCHMARK_SESSIONS_DIR}"

    export HOME="${BENCHMARK_SESSIONS_DIR}"
    export OML_SESSIONS_DIR="${BENCHMARK_SESSIONS_DIR}/sessions"

    mkdir -p "${OML_SESSIONS_DIR}/data"
    mkdir -p "${OML_SESSIONS_DIR}/meta"
    mkdir -p "${OML_SESSIONS_DIR}/cache"

    # 初始化索引
    cat > "${OML_SESSIONS_DIR}/index.json" <<'EOF'
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

    # 加载核心模块
    source "${CORE_DIR}/platform.sh" 2>/dev/null || true
    source "${CORE_DIR}/session-storage.sh"
    source "${CORE_DIR}/session-manager.sh"

    oml_session_storage_init 2>/dev/null || true
}

teardown_test_env() {
    log_info "Cleaning up test environment"
    if [[ -d "$BENCHMARK_SESSIONS_DIR" ]]; then
        rm -rf "$BENCHMARK_SESSIONS_DIR"
    fi
}

# ============================================================================
# 基准测试：Session 创建
# ============================================================================

benchmark_session_create() {
    log_info "Running Session Create Benchmark (${SAMPLE_COUNT} iterations)..."

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        local session_id="warmup-${i}"
        oml_session_create "$session_id" '{"warmup": true}' >/dev/null 2>&1 || true
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local session_id="bench-create-${i}-$$"

        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_session_create "$session_id" '{"benchmark": "create", "iteration": '"$i"'}' >/dev/null 2>&1

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")

        # 清理
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
    done

    # 计算统计
    local avg
    avg=$(calc_average "$sum" "$SAMPLE_COUNT")

    local min
    min=$(python3 -c "print(min([$(IFS=,; echo "${durations[*]}")]))")

    local max
    max=$(python3 -c "print(max([$(IFS=,; echo "${durations[*]}")]))")

    local p50
    p50=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 50)

    local p95
    p95=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 95)

    local p99
    p99=$(calc_percentile "[$(IFS=,; echo "${durations[*]}")]" 99)

    # 输出结果
    log_result ""
    log_result "=== Session Create Benchmark ==="
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Warmup:     ${WARMUP_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    # JSON 输出
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        python3 -c "
import json
result = {
    'test': 'session_create',
    'samples': ${SAMPLE_COUNT},
    'warmup': ${WARMUP_COUNT},
    'stats': {
        'avg_ms': ${avg},
        'min_ms': ${min},
        'max_ms': ${max},
        'p50_ms': ${p50},
        'p95_ms': ${p95},
        'p99_ms': ${p99}
    }
}
print(json.dumps(result, indent=2))
"
    fi

    # 保存结果
    BENCHMARK_RESULTS["session_create"]=$(cat <<EOF
{
  "samples": ${SAMPLE_COUNT},
  "warmup": ${WARMUP_COUNT},
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
# 基准测试：Session 读取
# ============================================================================

benchmark_session_read() {
    log_info "Running Session Read Benchmark (${SAMPLE_COUNT} iterations)..."

    # 预创建会话
    local session_ids=()
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local session_id="bench-read-${i}-$$"
        oml_session_create "$session_id" '{"benchmark": "read", "data": "test content for session '"$i"'"}' >/dev/null 2>&1
        session_ids+=("$session_id")
    done

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_session_read "${session_ids[0]}" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_session_read "${session_ids[$i]}" >/dev/null 2>&1

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 清理
    for session_id in "${session_ids[@]}"; do
        oml_session_delete "$session_id" >/dev/null 2>&1 || true
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
    log_result "=== Session Read Benchmark ==="
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["session_read"]=$(cat <<EOF
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
# 基准测试：Session 写入/更新
# ============================================================================

benchmark_session_write() {
    log_info "Running Session Write Benchmark (${SAMPLE_COUNT} iterations)..."

    # 预创建会话
    local session_id="bench-write-$$"
    oml_session_create "$session_id" '{"benchmark": "write", "counter": 0}' >/dev/null 2>&1

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_session_update "$session_id" "{\"counter\": ${i}}" "true" >/dev/null 2>&1 || true
    done

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_session_update "$session_id" "{\"counter\": ${i}, \"timestamp\": $(date +%s)}" "true" >/dev/null 2>&1

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 清理
    oml_session_delete "$session_id" >/dev/null 2>&1 || true

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
    log_result "=== Session Write Benchmark ==="
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["session_write"]=$(cat <<EOF
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
# 基准测试：Session 删除
# ============================================================================

benchmark_session_delete() {
    log_info "Running Session Delete Benchmark (${SAMPLE_COUNT} iterations)..."

    # 预创建会话
    local session_ids=()
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local session_id="bench-del-${i}-$$"
        oml_session_create "$session_id" '{"benchmark": "delete"}' >/dev/null 2>&1
        session_ids+=("$session_id")
    done

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    if [[ ${#session_ids[@]} -gt 0 ]]; then
        oml_session_delete "${session_ids[0]}" >/dev/null 2>&1 || true
        oml_session_create "${session_ids[0]}" '{"benchmark": "delete"}' >/dev/null 2>&1 || true
    fi

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_session_delete "${session_ids[$i]}" >/dev/null 2>&1 || true

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
    log_result "=== Session Delete Benchmark ==="
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["session_delete"]=$(cat <<EOF
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
# 基准测试：Session 消息操作
# ============================================================================

benchmark_session_messages() {
    log_info "Running Session Messages Benchmark (${SAMPLE_COUNT} iterations)..."

    local session_id="bench-messages-$$"
    oml_session_create "$session_id" '{"benchmark": "messages"}' >/dev/null 2>&1

    local durations=()
    local sum=0

    # Warmup
    log_info "  Warmup: ${WARMUP_COUNT} iterations..."
    for ((i=0; i<WARMUP_COUNT; i++)); do
        oml_session_mgr_add_message "$session_id" "user" "Warmup message ${i}" >/dev/null 2>&1 || true
    done
    oml_session_mgr_clear_messages "$session_id" >/dev/null 2>&1 || true

    # 正式测试
    log_info "  Running benchmark..."
    for ((i=0; i<SAMPLE_COUNT; i++)); do
        local start_ns
        start_ns=$(get_timestamp_ns)

        oml_session_mgr_add_message "$session_id" "user" "Benchmark message ${i}" >/dev/null 2>&1

        local end_ns
        end_ns=$(get_timestamp_ns)

        local duration_ms
        duration_ms=$(calc_duration_ms "$start_ns" "$end_ns")
        durations+=("$duration_ms")
        sum=$(python3 -c "print(${sum} + ${duration_ms})")
    done

    # 清理
    oml_session_delete "$session_id" >/dev/null 2>&1 || true

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
    log_result "=== Session Messages Benchmark ==="
    log_result "  Samples:    ${SAMPLE_COUNT}"
    log_result "  Avg:        ${avg} ms"
    log_result "  Min:        ${min} ms"
    log_result "  Max:        ${max} ms"
    log_result "  P50:        ${p50} ms"
    log_result "  P95:        ${p95} ms"
    log_result "  P99:        ${p99} ms"

    BENCHMARK_RESULTS["session_messages"]=$(cat <<EOF
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
# 生成报告
# ============================================================================

generate_report() {
    local report_file="${1:-}"

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
}

generate_json_report() {
    local output_file="$1"

    python3 -c "
import json
import sys
from datetime import datetime

results = {}
$(for key in "${!BENCHMARK_RESULTS[@]}"; do
    echo "results['${key}'] = json.loads('${BENCHMARK_RESULTS[$key]}')"
done)

report = {
    'benchmark': 'OML Session Performance Benchmark',
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'config': {
        'sample_count': ${SAMPLE_COUNT},
        'warmup_count': ${WARMUP_COUNT},
        'sessions_dir': '${BENCHMARK_SESSIONS_DIR}'
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
# OML Session Performance Benchmark Report

**Generated:** ${timestamp}

## Configuration

| Parameter | Value |
|-----------|-------|
| Sample Count | ${SAMPLE_COUNT} |
| Warmup Count | ${WARMUP_COUNT} |
| Test Directory | ${BENCHMARK_SESSIONS_DIR} |

## Results Summary

### Session Create

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["session_create"]:-N/A} |

### Session Read

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["session_read"]:-N/A} |

### Session Write

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["session_write"]:-N/A} |

### Session Delete

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["session_delete"]:-N/A} |

### Session Messages

| Metric | Value (ms) |
|--------|------------|
| Average | ${BENCHMARK_RESULTS["session_messages"]:-N/A} |

## Detailed Statistics

\`\`\`json
$(for key in "${!BENCHMARK_RESULTS[@]}"; do
    echo "\"${key}\": ${BENCHMARK_RESULTS[$key]},"
done | sed '$ s/,$//')
\`\`\`

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
    echo "OML Session Performance Benchmark"
    echo "============================================"
    echo ""
    echo "Configuration:"
    echo "  Sample Count:  ${SAMPLE_COUNT}"
    echo "  Warmup Count:  ${WARMUP_COUNT}"
    echo "  Output Format: ${OUTPUT_FORMAT}"
    echo "  Test Dir:      ${BENCHMARK_SESSIONS_DIR}"
    echo ""

    # 设置环境
    setup_test_env

    case "$action" in
        all)
            benchmark_session_create
            benchmark_session_read
            benchmark_session_write
            benchmark_session_delete
            benchmark_session_messages
            ;;
        create)
            benchmark_session_create
            ;;
        read)
            benchmark_session_read
            ;;
        write)
            benchmark_session_write
            ;;
        delete)
            benchmark_session_delete
            ;;
        messages)
            benchmark_session_messages
            ;;
        *)
            echo "Unknown action: $action"
            echo "Usage: $0 [all|create|read|write|delete|messages] [report_file]"
            teardown_test_env
            exit 1
            ;;
    esac

    # 生成报告
    if [[ -n "$report_file" ]]; then
        generate_report "$report_file"
    fi

    # 清理
    teardown_test_env

    echo ""
    echo "============================================"
    echo "Benchmark Complete"
    echo "============================================"
}

main "$@"
