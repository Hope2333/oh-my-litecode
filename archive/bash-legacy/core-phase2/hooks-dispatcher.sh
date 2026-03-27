#!/usr/bin/env bash
# OML Hooks Dispatcher - 事件分发器
# 负责将事件分发给已注册的 Hooks 处理器

set -eo pipefail
# 注意：不使用 -u 选项，因为关联数组在 bash 中与 set -u 有兼容性问题

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_HOOKS_DISPATCHER_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_HOOKS_DISPATCHER_LOADED=true

# 尝试查找 OML 根目录
if [[ -z "${OML_ROOT:-}" ]]; then
    if [[ "$(basename "$SCRIPT_DIR")" == "core" ]]; then
        export OML_ROOT="$(dirname "$SCRIPT_DIR")"
    fi
fi

# 源平台模块（如果可用）
if [[ -z "${OML_PLATFORM_LOADED:-}" && -f "${SCRIPT_DIR}/platform.sh" ]]; then
    source "${SCRIPT_DIR}/platform.sh"
    export OML_PLATFORM_LOADED=true
fi

# 源事件总线（如果可用）
if [[ -f "${SCRIPT_DIR}/event-bus.sh" ]]; then
    source "${SCRIPT_DIR}/event-bus.sh"
fi

# 源 Hooks 注册表（如果可用）
if [[ -f "${SCRIPT_DIR}/hooks-registry.sh" ]]; then
    source "${SCRIPT_DIR}/hooks-registry.sh"
fi

# ============================================================================
# 常量定义
# ============================================================================
readonly OML_HOOKS_DISPATCHER_VERSION="0.1.0"
readonly OML_DISPATCHER_DEFAULT_TIMEOUT="${OML_DISPATCHER_DEFAULT_TIMEOUT:-30}"
readonly OML_DISPATCHER_MAX_RETRIES="${OML_DISPATCHER_MAX_RETRIES:-3}"
readonly OML_DISPATCHER_RETRY_DELAY="${OML_DISPATCHER_RETRY_DELAY:-1}"
readonly OML_DISPATCHER_LOGS_DIR="${OML_DISPATCHER_LOGS_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/hooks/dispatcher}"

# ============================================================================
# 内部状态
# ============================================================================
declare -A __OML_DISPATCH_CACHE=()
declare -a __OML_DISPATCH_HISTORY=()
declare __OML_DISPATCH_CURRENT_EVENT=""
declare __OML_DISPATCH_CURRENT_INDEX=0

# ============================================================================
# 工具函数
# ============================================================================

# 生成唯一分发 ID
oml_dispatch_generate_id() {
    echo "disp-$(date +%s%N)-$$-${RANDOM}"
}

# 获取当前时间戳（毫秒）
oml_dispatch_timestamp() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import time; print(int(time.time() * 1000))"
    else
        date +%s
    fi
}

# 日志输出
oml_dispatch_log() {
    local level="$1"
    local message="$2"
    local dispatch_id="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_entry="[${timestamp}] [${level}]"
    [[ -n "$dispatch_id" ]] && log_entry+=" [${dispatch_id}]"
    log_entry+=" ${message}"

    echo "$log_entry" >&2

    local log_file="${OML_DISPATCHER_LOGS_DIR}/dispatcher.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file" 2>/dev/null || true
}

# 验证处理器路径
oml_dispatch_validate_handler() {
    local handler="$1"

    if [[ -f "$handler" && -x "$handler" ]]; then
        return 0
    elif [[ -d "$handler" ]]; then
        # 目录：检查是否有 main.sh
        if [[ -x "${handler}/main.sh" ]]; then
            return 0
        fi
    elif declare -f "$handler" >/dev/null 2>&1; then
        # Bash 函数
        return 0
    fi

    return 1
}

# 执行单个处理器
oml_dispatch_execute_handler() {
    local handler="$1"
    local hook_name="$2"
    local timeout="${3:-$OML_DISPATCHER_DEFAULT_TIMEOUT}"
    shift 3 || true
    local payload=("$@")

    local exit_code=0
    local start_time
    start_time="$(oml_dispatch_timestamp)"

    if declare -f "$handler" >/dev/null 2>&1; then
        # Bash 函数
        timeout "$timeout" bash -c "$(declare -f "$handler"); $handler \"\$@\"" _ "${payload[@]}" 2>/dev/null || exit_code=$?
    elif [[ -f "$handler" && -x "$handler" ]]; then
        # 可执行文件
        timeout "$timeout" "$handler" "${payload[@]}" 2>/dev/null || exit_code=$?
    elif [[ -d "$handler" && -x "${handler}/main.sh" ]]; then
        # 目录（插件）
        timeout "$timeout" "${handler}/main.sh" "${payload[@]}" 2>/dev/null || exit_code=$?
    else
        oml_dispatch_log "ERROR" "Invalid handler: $handler"
        return 1
    fi

    local end_time
    end_time="$(oml_dispatch_timestamp)"
    local duration=$(( (end_time - start_time) / 1000 ))

    if [[ $exit_code -eq 124 ]]; then
        oml_dispatch_log "ERROR" "Handler timeout: ${handler} (> ${timeout}s)"
        return 124
    elif [[ $exit_code -ne 0 ]]; then
        oml_dispatch_log "ERROR" "Handler failed: ${handler} (exit: $exit_code, duration: ${duration}ms)"
        return $exit_code
    else
        oml_dispatch_log "DEBUG" "Handler succeeded: ${handler} (duration: ${duration}ms)"
        return 0
    fi
}

# 带重试的执行
oml_dispatch_execute_with_retry() {
    local handler="$1"
    local hook_name="$2"
    local timeout="${3:-$OML_DISPATCHER_DEFAULT_TIMEOUT}"
    local max_retries="${4:-$OML_DISPATCHER_MAX_RETRIES}"
    local retry_delay="${5:-$OML_DISPATCHER_RETRY_DELAY}"
    shift 5 || true
    local payload=("$@")

    local attempt=0
    local last_exit_code=0

    while [[ $attempt -lt $max_retries ]]; do
        ((attempt++))

        if [[ $attempt -gt 1 ]]; then
            oml_dispatch_log "INFO" "Retry attempt ${attempt}/${max_retries} for: ${handler}"
            sleep "$retry_delay"
        fi

        oml_dispatch_execute_handler "$handler" "$hook_name" "$timeout" "${payload[@]}"
        last_exit_code=$?

        if [[ $last_exit_code -eq 0 ]]; then
            return 0
        fi

        # 超时不重试
        if [[ $last_exit_code -eq 124 ]]; then
            return 124
        fi
    done

    oml_dispatch_log "ERROR" "All retry attempts failed for: ${handler}"
    return $last_exit_code
}

# ============================================================================
# 分发器核心函数
# ============================================================================

# 初始化分发器
oml_hooks_dispatcher_init() {
    mkdir -p "${OML_DISPATCHER_LOGS_DIR}"
    oml_dispatch_log "INFO" "Hooks dispatcher initialized"
}

# 分发事件到所有注册的 Hooks
# 用法：oml_hooks_dispatch <event_name> [payload...] [options]
# 选项:
#   --timeout <seconds>    超时时间
#   --stop-on-error        遇到错误立即停止
#   --parallel             并行执行
#   --dry-run              仅显示将要执行的 Hooks
oml_hooks_dispatch() {
    local event_name="$1"
    shift

    local timeout="$OML_DISPATCHER_DEFAULT_TIMEOUT"
    local stop_on_error=false
    local parallel_mode=false
    local dry_run=false
    local payload=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --stop-on-error)
                stop_on_error=true
                shift
                ;;
            --parallel)
                parallel_mode=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --)
                shift
                payload+=("$@")
                break
                ;;
            *)
                payload+=("$1")
                shift
                ;;
        esac
    done

    local dispatch_id
    dispatch_id="$(oml_dispatch_generate_id)"
    __OML_DISPATCH_CURRENT_EVENT="$event_name"
    __OML_DISPATCH_CURRENT_INDEX=0

    oml_dispatch_log "INFO" "Dispatching event: ${event_name} (id=$dispatch_id, timeout=${timeout}s)"

    # 获取已注册的 Hooks
    local hooks_raw
    hooks_raw="$(oml_hooks_get_for_event "$event_name" true 2>/dev/null || echo "")"

    if [[ -z "$hooks_raw" ]]; then
        oml_dispatch_log "DEBUG" "No hooks registered for event: $event_name"
        return 0
    fi

    # 解析 Hooks 信息
    local -a handlers=()
    local -a hook_names=()
    local -a priorities=()
    local -a options_list=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local handler hook_name priority options
        handler="$(echo "$line" | cut -d'|' -f1)"
        hook_name="$(echo "$line" | cut -d'|' -f2)"
        priority="$(echo "$line" | cut -d'|' -f3)"
        options="$(echo "$line" | cut -d'|' -f4-)"
        handlers+=("$handler")
        hook_names+=("$hook_name")
        priorities+=("$priority")
        options_list+=("$options")
    done <<< "$hooks_raw"

    local total_hooks=${#handlers[@]}

    if [[ $total_hooks -eq 0 ]]; then
        oml_dispatch_log "DEBUG" "No enabled hooks for event: $event_name"
        return 0
    fi

    # 干运行模式
    if [[ "$dry_run" == true ]]; then
        echo "Dry run for event: $event_name"
        echo "Will execute ${total_hooks} hook(s):"
        for i in "${!handlers[@]}"; do
            echo "  [$((i+1))/${total_hooks}] ${hook_names[$i]} -> ${handlers[$i]} (priority: ${priorities[$i]})"
        done
        return 0
    fi

    oml_dispatch_log "INFO" "Found ${total_hooks} hook(s) for event: $event_name"

    # 执行 Hooks
    local exit_code=0
    local success_count=0
    local fail_count=0
    local pids=()

    if [[ "$parallel_mode" == true ]]; then
        # 并行模式
        for i in "${!handlers[@]}"; do
            local handler="${handlers[$i]}"
            local hook_name="${hook_names[$i]}"

            (
                local result=0
                oml_dispatch_execute_with_retry "$handler" "$hook_name" "$timeout" "$OML_DISPATCHER_MAX_RETRIES" "$OML_DISPATCHER_RETRY_DELAY" "${payload[@]}" || result=$?
                exit $result
            ) &
            pids+=($!)
        done

        # 等待所有进程
        for pid in "${pids[@]}"; do
            if ! wait "$pid" 2>/dev/null; then
                ((fail_count++))
                exit_code=1
                [[ "$stop_on_error" == true ]] && break
            else
                ((success_count++))
            fi
        done
    else
        # 串行模式（按优先级顺序）
        for i in "${!handlers[@]}"; do
            local handler="${handlers[$i]}"
            local hook_name="${hook_names[$i]}"

            __OML_DISPATCH_CURRENT_INDEX=$((i + 1))

            oml_dispatch_log "INFO" "Executing hook ${hook_name} (${__OML_DISPATCH_CURRENT_INDEX}/${total_hooks})"

            local result=0
            oml_dispatch_execute_with_retry "$handler" "$hook_name" "$timeout" "$OML_DISPATCHER_MAX_RETRIES" "$OML_DISPATCHER_RETRY_DELAY" "${payload[@]}" || result=$?

            if [[ $result -eq 0 ]]; then
                ((success_count++))
                # 更新统计
                oml_hooks_update_stats "$hook_name" "success" 2>/dev/null || true
            else
                ((fail_count++))
                oml_hooks_update_stats "$hook_name" "failed" 2>/dev/null || true
                exit_code=$result

                if [[ $result -eq 124 ]]; then
                    oml_dispatch_log "ERROR" "Hook timeout, stopping dispatch"
                    break
                elif [[ "$stop_on_error" == true ]]; then
                    oml_dispatch_log "WARN" "Hook failed with --stop-on-error, stopping dispatch"
                    break
                fi
            fi

            # 记录到历史
            __OML_DISPATCH_HISTORY+=("${event_name}:${hook_name}:${result}:$(date -Iseconds)")
        done
    fi

    oml_dispatch_log "INFO" "Dispatch completed: ${success_count} succeeded, ${fail_count} failed"

    # 触发完成事件
    if [[ -n "${OML_EVENT_BUS_LOADED:-}" ]]; then
        if [[ $exit_code -eq 0 ]]; then
            oml_event_emit "hooks:complete:${event_name}" "$dispatch_id" "$success_count" 2>/dev/null || true
        else
            oml_event_emit "hooks:failed:${event_name}" "$dispatch_id" "$fail_count" 2>/dev/null || true
        fi
    fi

    return $exit_code
}

# 分发单个 Hook
oml_hooks_dispatch_single() {
    local hook_name="$1"
    shift
    local payload=("$@")

    local handler
    handler="$(python3 - "${OML_HOOKS_REGISTRY_FILE:-}" "$hook_name" <<'PY'
import json
import sys

registry_path = sys.argv[1]
hook_name = sys.argv[2]

try:
    with open(registry_path, 'r') as f:
        data = json.load(f)
    for hook in data['hooks']:
        if hook['name'] == hook_name:
            print(hook['handler'])
            sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
PY
)" || {
        oml_dispatch_log "ERROR" "Hook not found: $hook_name"
        return 1
    }

    oml_dispatch_log "INFO" "Dispatching single hook: ${hook_name}"
    oml_dispatch_execute_handler "$handler" "$hook_name" "$OML_DISPATCHER_DEFAULT_TIMEOUT" "${payload[@]}"
}

# 获取分发历史
oml_hooks_dispatch_history() {
    local limit="${1:-10}"
    local event_filter="${2:-}"

    local count=0
    for entry in "${__OML_DISPATCH_HISTORY[@]}"; do
        [[ $count -ge $limit ]] && break

        local event_name hook_name status timestamp
        event_name="$(echo "$entry" | cut -d':' -f1)"
        hook_name="$(echo "$entry" | cut -d':' -f2)"
        status="$(echo "$entry" | cut -d':' -f3)"
        timestamp="$(echo "$entry" | cut -d':' -f4-)"

        if [[ -z "$event_filter" || "$event_name" == "$event_filter" ]]; then
            local status_icon="✓"
            [[ "$status" != "0" ]] && status_icon="✗"
            echo "[${timestamp}] ${status_icon} ${event_name} -> ${hook_name}"
            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "No dispatch history found"
    fi
}

# 清除分发历史
oml_hooks_dispatch_history_clear() {
    __OML_DISPATCH_HISTORY=()
    oml_dispatch_log "INFO" "Dispatch history cleared"
}

# 获取分发器状态
oml_hooks_dispatcher_status() {
    local pending_events=0
    local active_dispatches=0

    # 检查队列中的事件
    if [[ -d "${OML_EVENT_QUEUE_DIR:-}" ]]; then
        pending_events="$(find "${OML_EVENT_QUEUE_DIR}" -name "*.json" 2>/dev/null | wc -l)"
    fi

    # 检查后台进程
    active_dispatches="$(jobs -r 2>/dev/null | wc -l)"

    cat <<EOF
{
  "version": "${OML_HOOKS_DISPATCHER_VERSION}",
  "current_event": "${__OML_DISPATCH_CURRENT_EVENT:-none}",
  "current_index": ${__OML_DISPATCH_CURRENT_INDEX},
  "pending_events": ${pending_events},
  "active_dispatches": ${active_dispatches},
  "history_size": ${#__OML_DISPATCH_HISTORY[@]},
  "default_timeout": ${OML_DISPATCHER_DEFAULT_TIMEOUT},
  "max_retries": ${OML_DISPATCHER_MAX_RETRIES},
  "logs_dir": "${OML_DISPATCHER_LOGS_DIR}"
}
EOF
}

# 测试分发器
oml_hooks_dispatcher_test() {
    local event_name="${1:-test:hook}"
    local test_payload="${2:-test}"

    echo "Testing dispatcher with event: $event_name"
    echo "Payload: $test_payload"
    echo ""

    # 创建临时测试 Hook
    local temp_hook="/tmp/oml_test_hook_$$.sh"
    cat > "$temp_hook" <<'EOF'
#!/usr/bin/env bash
echo "Test hook executed with args: $@"
exit 0
EOF
    chmod +x "$temp_hook"

    # 注册测试 Hook
    oml_hook_register "test-hook-$$" "$event_name" "$temp_hook" 0 2>/dev/null || true

    # 执行分发
    local result=0
    oml_hooks_dispatch "$event_name" "$test_payload" || result=$?

    # 清理
    oml_hook_unregister "test-hook-$$" 2>/dev/null || true
    rm -f "$temp_hook"

    echo ""
    if [[ $result -eq 0 ]]; then
        echo "Dispatcher test: PASSED"
    else
        echo "Dispatcher test: FAILED (exit code: $result)"
    fi

    return $result
}

# ============================================================================
# CLI 入口
# ============================================================================
main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_hooks_dispatcher_init
            echo "Hooks dispatcher initialized"
            ;;
        dispatch)
            oml_hooks_dispatch "$@"
            ;;
        dispatch-single)
            oml_hooks_dispatch_single "$@"
            ;;
        history)
            oml_hooks_dispatch_history "$@"
            ;;
        history-clear)
            oml_hooks_dispatch_history_clear
            ;;
        status)
            oml_hooks_dispatcher_status
            ;;
        test)
            oml_hooks_dispatcher_test "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Hooks Dispatcher - 事件分发器

用法：oml hooks-dispatcher <action> [args]

动作:
  init                        初始化分发器
  dispatch <event> [args]     分发事件到所有 Hooks
    --timeout <seconds>       超时时间（默认：${OML_DISPATCHER_DEFAULT_TIMEOUT}s）
    --stop-on-error           遇到错误立即停止
    --parallel                并行执行所有 Hooks
    --dry-run                 仅显示将要执行的 Hooks
  dispatch-single <hook> [args] 分发到单个 Hook
  history [limit] [event]     查看分发历史
  history-clear               清除分发历史
  status                      显示分发器状态
  test [event] [payload]      运行测试

示例:
  oml hooks-dispatcher init
  oml hooks-dispatcher dispatch "build:start" --timeout 60
  oml hooks-dispatcher dispatch "plugin:install" "my-plugin" --stop-on-error
  oml hooks-dispatcher dispatch "test:event" --dry-run
  oml hooks-dispatcher dispatch "async:event" --parallel
  oml hooks-dispatcher history 20
  oml hooks-dispatcher status

执行模式:
  - 串行模式（默认）：按优先级顺序依次执行
  - 并行模式（--parallel）：同时执行所有 Hooks
  - 停止模式（--stop-on-error）：遇到错误立即停止
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml hooks-dispatcher help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
