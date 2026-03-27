#!/usr/bin/env bash
# OML Event Bus - 事件总线核心模块
# 提供事件的发布/订阅机制，支持同步/异步、超时控制

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_EVENT_BUS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_EVENT_BUS_LOADED=true

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

# ============================================================================
# 常量定义
# ============================================================================
readonly OML_EVENT_BUS_VERSION="0.1.0"
readonly OML_EVENT_DEFAULT_TIMEOUT=30
readonly OML_EVENT_MAX_LISTENERS=100
readonly OML_EVENT_QUEUE_DIR="${OML_EVENT_QUEUE_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/events/queue}"
readonly OML_EVENT_LOGS_DIR="${OML_EVENT_LOGS_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/events/logs}"

# ============================================================================
# 内部状态（使用关联数组）
# ============================================================================
declare -A __OML_EVENT_LISTENERS=()
declare -A __OML_EVENT_ONCE_LISTENERS=()
declare -A __OML_EVENT_HANDLERS=()
declare -a __OML_EVENT_QUEUE=()
declare -A __OML_EVENT_META=()

# ============================================================================
# 工具函数
# ============================================================================

# 生成唯一事件 ID
oml_event_generate_id() {
    echo "evt-$(date +%s%N)-$$-${RANDOM}"
}

# 获取当前时间戳（毫秒）
oml_event_timestamp() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import time; print(int(time.time() * 1000))"
    else
        date +%s
    fi
}

# 日志输出
oml_event_log() {
    local level="$1"
    local message="$2"
    local event_id="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_entry="[${timestamp}] [${level}]"
    [[ -n "$event_id" ]] && log_entry+=" [${event_id}]"
    log_entry+=" ${message}"

    # 输出到 stderr（避免污染 stdout）
    echo "$log_entry" >&2

    # 同时写入日志文件
    local log_file="${OML_EVENT_LOGS_DIR}/event-bus.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file" 2>/dev/null || true
}

# 验证事件名称
oml_event_validate_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_.:-]*$ ]]; then
        return 1
    fi
    return 0
}

# ============================================================================
# 事件总线核心函数
# ============================================================================

# 初始化事件总线
oml_event_bus_init() {
    mkdir -p "${OML_EVENT_QUEUE_DIR}"
    mkdir -p "${OML_EVENT_LOGS_DIR}"
    oml_event_log "INFO" "Event bus initialized"
}

# 注册事件监听器
# 用法：oml_event_on <event_name> <handler_function>
oml_event_on() {
    local event_name="$1"
    local handler="$2"

    if ! oml_event_validate_name "$event_name"; then
        oml_event_log "ERROR" "Invalid event name: $event_name"
        return 1
    fi

    if [[ -z "$handler" ]]; then
        oml_event_log "ERROR" "Handler function not specified"
        return 1
    fi

    # 检查是否已存在
    local key="${event_name}:${handler}"
    local existing=""
    # 使用 declare -p 检查键是否存在（避免 bash 解析问题）
    if declare -p "__OML_EVENT_LISTENERS" 2>/dev/null | grep -qF "[$key]"; then
        existing="isset"
    fi
    if [[ -n "$existing" ]]; then
        oml_event_log "WARN" "Listener already registered: ${event_name} -> ${handler}"
        return 0
    fi

    # 检查监听器数量限制
    local count=0
    # 使用 declare -p 检查数组是否为空
    if declare -p "__OML_EVENT_LISTENERS" 2>/dev/null | grep -qF '()='; then
        : # 数组为空
    else
        for k in "${!__OML_EVENT_LISTENERS[@]}"; do
            [[ "$k" == "${event_name}:"* ]] && ((count++)) || true
        done
    fi
    if [[ $count -ge $OML_EVENT_MAX_LISTENERS ]]; then
        oml_event_log "ERROR" "Max listeners (${OML_EVENT_MAX_LISTENERS}) reached for event: $event_name"
        return 1
    fi

    # 使用 eval 来设置关联数组值
    eval "__OML_EVENT_LISTENERS[\"${key}\"]='1'"
    oml_event_log "DEBUG" "Registered listener: ${event_name} -> ${handler}"
}

# 注册一次性事件监听器（触发后自动移除）
# 用法：oml_event_once <event_name> <handler_function>
oml_event_once() {
    local event_name="$1"
    local handler="$2"

    if ! oml_event_validate_name "$event_name"; then
        oml_event_log "ERROR" "Invalid event name: $event_name"
        return 1
    fi

    local key="${event_name}:${handler}"
    __OML_EVENT_ONCE_LISTENERS[$key]=1
    oml_event_log "DEBUG" "Registered once listener: ${event_name} -> ${handler}"
}

# 移除事件监听器
# 用法：oml_event_off <event_name> <handler_function>
oml_event_off() {
    local event_name="$1"
    local handler="${2:-}"

    if [[ -z "$handler" ]]; then
        # 移除该事件的所有监听器
        local keys_to_remove=()
        if [[ ${#__OML_EVENT_LISTENERS[@]} -gt 0 ]]; then
            for key in "${!__OML_EVENT_LISTENERS[@]}"; do
                [[ "$key" == "${event_name}:"* ]] && keys_to_remove+=("$key") || true
            done
        fi
        for key in "${keys_to_remove[@]}"; do
            unset "__OML_EVENT_LISTENERS[$key]"
        done
        oml_event_log "DEBUG" "Removed all listeners for: $event_name"
    else
        local key="${event_name}:${handler}"
        unset "__OML_EVENT_LISTENERS[$key]"
        oml_event_log "DEBUG" "Removed listener: ${event_name} -> ${handler}"
    fi
}

# 发布事件（同步）
# 用法：oml_event_emit <event_name> [payload...] [--timeout <seconds>] [--async]
oml_event_emit() {
    local event_name="$1"
    shift

    local timeout="$OML_EVENT_DEFAULT_TIMEOUT"
    local async_mode=false
    local payload=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --async)
                async_mode=true
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

    if ! oml_event_validate_name "$event_name"; then
        oml_event_log "ERROR" "Invalid event name: $event_name"
        return 1
    fi

    local event_id
    event_id="$(oml_event_generate_id)"
    local start_time
    start_time="$(oml_event_timestamp)"

    oml_event_log "INFO" "Emitting event: $event_name (id=$event_id, async=$async_mode, timeout=${timeout}s)"

    # 收集所有匹配的监听器
    local handlers=()
    if [[ ${#__OML_EVENT_LISTENERS[@]} -gt 0 ]]; then
        for key in "${!__OML_EVENT_LISTENERS[@]}"; do
            [[ "$key" == "${event_name}:"* ]] && handlers+=("${key#*:}") || true
        done
    fi
    if [[ ${#__OML_EVENT_ONCE_LISTENERS[@]} -gt 0 ]]; then
        for key in "${!__OML_EVENT_ONCE_LISTENERS[@]}"; do
            [[ "$key" == "${event_name}:"* ]] && handlers+=("${key#*:}") || true
        done
    fi

    if [[ ${#handlers[@]} -eq 0 ]]; then
        oml_event_log "DEBUG" "No listeners for event: $event_name"
        return 0
    fi

    # 执行处理器
    local exit_code=0
    for handler in "${handlers[@]}"; do
        if [[ "$async_mode" == true ]]; then
            # 异步模式：后台执行
            (
                local result=0
                if declare -f "$handler" >/dev/null 2>&1; then
                    "$handler" "${payload[@]}" || result=$?
                elif [[ -x "$handler" ]]; then
                    "$handler" "${payload[@]}" || result=$?
                else
                    oml_event_log "ERROR" "Handler not found: $handler"
                    result=1
                fi
                exit $result
            ) &
            local pid=$!
            oml_event_log "DEBUG" "Async handler started: ${handler} (PID: $pid)"
        else
            # 同步模式：带超时控制
            local handler_result=0
            if declare -f "$handler" >/dev/null 2>&1; then
                timeout "$timeout" bash -c "$(declare -f "$handler"); $handler \"\$@\"" _ "${payload[@]}" || handler_result=$?
            elif [[ -x "$handler" ]]; then
                timeout "$timeout" "$handler" "${payload[@]}" || handler_result=$?
            else
                oml_event_log "ERROR" "Handler not found: $handler"
                handler_result=1
            fi

            if [[ $handler_result -eq 124 ]]; then
                oml_event_log "ERROR" "Handler timeout: ${handler} (> ${timeout}s)"
                exit_code=1
            elif [[ $handler_result -ne 0 ]]; then
                oml_event_log "ERROR" "Handler failed: ${handler} (exit code: $handler_result)"
                exit_code=$handler_result
            fi

            # 清理 once 监听器
            local once_key="${event_name}:${handler}"
            if [[ -n "${__OML_EVENT_ONCE_LISTENERS[$once_key]:-}" ]]; then
                unset "__OML_EVENT_ONCE_LISTENERS[$once_key]"
            fi
        fi
    done

    local end_time
    end_time="$(oml_event_timestamp)"
    local duration=$(( (end_time - start_time) / 1000 ))
    oml_event_log "INFO" "Event completed: $event_name (duration=${duration}ms)"

    return $exit_code
}

# 发布事件并等待所有异步处理器完成
# 用法：oml_event_emit_wait <event_name> [payload...] [--timeout <seconds>]
oml_event_emit_wait() {
    local event_name="$1"
    shift

    local timeout="$OML_EVENT_DEFAULT_TIMEOUT"
    local payload=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)
                timeout="$2"
                shift 2
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

    # 启动异步事件
    oml_event_emit "$event_name" "${payload[@]}" --async --timeout "$timeout"

    # 等待所有后台进程
    local exit_code=0
    local pids=()
    while read -r pid; do
        pids+=("$pid")
    done < <(jobs -p 2>/dev/null || true)

    for pid in "${pids[@]}"; do
        if ! wait "$pid" 2>/dev/null; then
            exit_code=1
        fi
    done

    return $exit_code
}

# 将事件加入队列（用于延迟处理）
# 用法：oml_event_enqueue <event_name> <payload_json>
oml_event_enqueue() {
    local event_name="$1"
    local payload="${2:-{}}"

    if ! oml_event_validate_name "$event_name"; then
        oml_event_log "ERROR" "Invalid event name: $event_name"
        return 1
    fi

    local event_id
    event_id="$(oml_event_generate_id)"
    local timestamp
    timestamp="$(date -Iseconds)"

    local queue_file="${OML_EVENT_QUEUE_DIR}/${event_id}.json"
    cat > "$queue_file" <<EOF
{
  "event_id": "${event_id}",
  "event_name": "${event_name}",
  "payload": ${payload},
  "created_at": "${timestamp}",
  "status": "pending"
}
EOF

    __OML_EVENT_QUEUE+=("$event_id")
    oml_event_log "INFO" "Event enqueued: ${event_name} (id=$event_id)"
    echo "$event_id"
}

# 从队列中取出并处理事件
# 用法：oml_event_dequeue [--all]
oml_event_dequeue() {
    local process_all=false
    [[ "${1:-}" == "--all" ]] && process_all=true

    local processed=0
    local queue_files=()

    # 获取队列文件
    while IFS= read -r -d '' file; do
        queue_files+=("$file")
    done < <(find "${OML_EVENT_QUEUE_DIR}" -name "*.json" -print0 2>/dev/null | sort -z)

    for queue_file in "${queue_files[@]}"; do
        local event_id
        event_id="$(basename "$queue_file" .json)"
        local event_name
        event_name="$(python3 -c "import json; print(json.load(open('${queue_file}'))['event_name'])" 2>/dev/null || echo "")"

        if [[ -z "$event_name" ]]; then
            oml_event_log "WARN" "Invalid queue file: $queue_file"
            continue
        fi

        local payload
        payload="$(python3 -c "import json; print(json.dumps(json.load(open('${queue_file}'))['payload']))" 2>/dev/null || echo '{}')"

        # 触发事件
        if oml_event_emit "$event_name" "$payload"; then
            # 更新状态为 completed
            python3 -c "
import json
with open('${queue_file}', 'r') as f:
    data = json.load(f)
data['status'] = 'completed'
data['completed_at'] = '$(date -Iseconds)'
with open('${queue_file}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || rm -f "$queue_file"
            ((processed++))
        else
            # 更新状态为 failed
            python3 -c "
import json
with open('${queue_file}', 'r') as f:
    data = json.load(f)
data['status'] = 'failed'
data['failed_at'] = '$(date -Iseconds)'
with open('${queue_file}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
        fi

        [[ "$process_all" == false ]] && break
    done

    oml_event_log "INFO" "Processed ${processed} queued event(s)"
    echo "$processed"
}

# 获取事件统计信息
oml_event_stats() {
    local listener_count=0
    local once_count=0

    if [[ ${#__OML_EVENT_LISTENERS[@]} -gt 0 ]]; then
        for key in "${!__OML_EVENT_LISTENERS[@]}"; do
            ((listener_count++)) || true
        done
    fi
    if [[ ${#__OML_EVENT_ONCE_LISTENERS[@]} -gt 0 ]]; then
        for key in "${!__OML_EVENT_ONCE_LISTENERS[@]}"; do
            ((once_count++)) || true
        done
    fi

    local queue_count
    queue_count="$(find "${OML_EVENT_QUEUE_DIR}" -name "*.json" 2>/dev/null | wc -l)"

    cat <<EOF
{
  "version": "${OML_EVENT_BUS_VERSION}",
  "listeners": ${listener_count},
  "once_listeners": ${once_count},
  "queued_events": ${queue_count},
  "queue_dir": "${OML_EVENT_QUEUE_DIR}",
  "logs_dir": "${OML_EVENT_LOGS_DIR}"
}
EOF
}

# 清空事件队列
oml_event_queue_clear() {
    local status_filter="${1:-}"
    local count=0

    for queue_file in "${OML_EVENT_QUEUE_DIR}"/*.json; do
        [[ -f "$queue_file" ]] || continue

        if [[ -n "$status_filter" ]]; then
            local file_status
            file_status="$(python3 -c "import json; print(json.load(open('${queue_file}')).get('status', ''))" 2>/dev/null || echo "")"
            [[ "$file_status" != "$status_filter" ]] && continue
        fi

        rm -f "$queue_file"
        ((count++))
    done

    oml_event_log "INFO" "Cleared ${count} queued event(s)"
    echo "$count"
}

# 列出所有已注册的事件监听器
oml_event_list_listeners() {
    local event_filter="${1:-}"

    echo "EVENT_NAME -> HANDLER"
    echo "========================================"

    if [[ ${#__OML_EVENT_LISTENERS[@]} -gt 0 ]]; then
        for key in "${!__OML_EVENT_LISTENERS[@]}"; do
            local event_name="${key%%:*}"
            local handler="${key#*:}"

            if [[ -z "$event_filter" || "$event_name" == "$event_filter" ]]; then
                echo "${event_name} -> ${handler}"
            fi
        done
    fi

    if [[ ${#__OML_EVENT_ONCE_LISTENERS[@]} -gt 0 ]]; then
        for key in "${!__OML_EVENT_ONCE_LISTENERS[@]}"; do
            local event_name="${key%%:*}"
            local handler="${key#*:}"

            if [[ -z "$event_filter" || "$event_name" == "$event_filter" ]]; then
                echo "${event_name} -> ${handler} [once]"
            fi
        done
    fi
}

# ============================================================================
# CLI 入口
# ============================================================================
main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_event_bus_init
            echo "Event bus initialized"
            ;;
        on)
            oml_event_on "$@"
            ;;
        once)
            oml_event_once "$@"
            ;;
        off)
            oml_event_off "$@"
            ;;
        emit)
            oml_event_emit "$@"
            ;;
        emit-wait)
            oml_event_emit_wait "$@"
            ;;
        enqueue)
            oml_event_enqueue "$@"
            ;;
        dequeue)
            oml_event_dequeue "$@"
            ;;
        stats)
            oml_event_stats
            ;;
        queue-clear)
            oml_event_queue_clear "$@"
            ;;
        list)
            oml_event_list_listeners "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Event Bus - 事件总线核心

用法：oml event-bus <action> [args]

动作:
  init                        初始化事件总线
  on <event> <handler>        注册事件监听器
  once <event> <handler>      注册一次性事件监听器
  off <event> [handler]       移除事件监听器
  emit <event> [args]         发布事件
    --timeout <seconds>       设置超时时间（默认：${OML_EVENT_DEFAULT_TIMEOUT}s）
    --async                   异步模式
  emit-wait <event> [args]    发布事件并等待完成
  enqueue <event> <payload>   将事件加入队列
  dequeue [--all]             处理队列中的事件
  stats                       显示统计信息
  queue-clear [status]        清空事件队列
  list [event]                列出已注册的监听器

示例:
  oml event-bus init
  oml event-bus on "plugin:install" my_handler
  oml event-bus emit "plugin:install" "my-plugin" --timeout 60
  oml event-bus emit "build:complete" --async
  oml event-bus stats
  oml event-bus dequeue --all

事件命名约定:
  - 使用冒号分隔命名空间：namespace:action
  - 示例：plugin:install, build:start, hook:pre-commit
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml event-bus help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
