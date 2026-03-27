#!/usr/bin/env bash
# OML Hooks Engine - Hooks 引擎主逻辑
# 整合事件总线、注册表、分发器，提供统一的 Hooks 管理接口

set -eo pipefail
# 注意：不使用 -u 选项，因为关联数组在 bash 中与 set -u 有兼容性问题

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_HOOKS_ENGINE_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_HOOKS_ENGINE_LOADED=true

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

# 源事件总线
if [[ -f "${SCRIPT_DIR}/event-bus.sh" ]]; then
    source "${SCRIPT_DIR}/event-bus.sh"
    export OML_EVENT_BUS_LOADED=true
fi

# 源 Hooks 注册表
if [[ -f "${SCRIPT_DIR}/hooks-registry.sh" ]]; then
    source "${SCRIPT_DIR}/hooks-registry.sh"
fi

# 源 Hooks 分发器
if [[ -f "${SCRIPT_DIR}/hooks-dispatcher.sh" ]]; then
    source "${SCRIPT_DIR}/hooks-dispatcher.sh"
fi

# ============================================================================
# 常量定义
# ============================================================================
readonly OML_HOOKS_ENGINE_VERSION="0.1.0"
readonly OML_HOOKS_CONFIG_DIR="${OML_HOOKS_CONFIG_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/hooks}"
readonly OML_HOOKS_CONFIG_FILE="${OML_HOOKS_CONFIG_FILE:-${OML_HOOKS_CONFIG_DIR}/config.json}"

# Hook 类型定义
readonly OML_HOOK_TYPE_PRE="pre"
readonly OML_HOOK_TYPE_POST="post"
readonly OML_HOOK_TYPE_AROUND="around"

# ============================================================================
# 内部状态
# ============================================================================
declare -A __OML_HOOKS_ENGINE_CONFIG=()
declare -a __OML_HOOKS_EXECUTION_STACK=()
declare __OML_HOOKS_ENGINE_INITIALIZED=false

# ============================================================================
# 工具函数
# ============================================================================

# 日志输出
oml_hooks_engine_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[${timestamp}] [HOOKS-ENGINE] [${level}] ${message}" >&2

    local log_file="${OML_HOOKS_CONFIG_DIR}/engine.log"
    mkdir -p "$(dirname "$log_file")"
    echo "[${timestamp}] [HOOKS-ENGINE] [${level}] ${message}" >> "$log_file" 2>/dev/null || true
}

# 读取配置
oml_hooks_engine_load_config() {
    if [[ -f "$OML_HOOKS_CONFIG_FILE" ]]; then
        python3 -c "
import json
with open('${OML_HOOKS_CONFIG_FILE}', 'r') as f:
    config = json.load(f)
for key, value in config.items():
    print(f'{key}={value}')
" 2>/dev/null | while IFS='=' read -r key value; do
            __OML_HOOKS_ENGINE_CONFIG[$key]="$value"
        done
    fi
}

# 保存配置
oml_hooks_engine_save_config() {
    mkdir -p "$(dirname "$OML_HOOKS_CONFIG_FILE")"

    python3 - "${OML_HOOKS_CONFIG_FILE}" "$(declare -p __OML_HOOKS_ENGINE_CONFIG 2>/dev/null || echo '')" <<'PY'
import json
import sys
import re

config_file = sys.argv[1]
config_dump = sys.argv[2] if len(sys.argv) > 2 else ''

config = {}

# 解析 bash declare -p 输出
if config_dump:
    # 提取关联数组内容
    match = re.search(r'\((.*)\)', config_dump, re.DOTALL)
    if match:
        content = match.group(1)
        for line in content.split('\n'):
            line = line.strip()
            if line.startswith('['):
                key_match = re.search(r'\["([^"]+)"\]="([^"]*)"', line)
                if key_match:
                    config[key_match.group(1)] = key_match.group(2)

# 保存配置
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
PY
}

# ============================================================================
# 引擎核心函数
# ============================================================================

# 初始化 Hooks 引擎
oml_hooks_engine_init() {
    if [[ "$__OML_HOOKS_ENGINE_INITIALIZED" == true ]]; then
        oml_hooks_engine_log "WARN" "Engine already initialized"
        return 0
    fi

    oml_hooks_engine_log "INFO" "Initializing Hooks Engine v${OML_HOOKS_ENGINE_VERSION}"

    # 初始化各组件
    oml_event_bus_init
    oml_hooks_registry_init
    oml_hooks_dispatcher_init

    # 创建配置目录
    mkdir -p "${OML_HOOKS_CONFIG_DIR}"

    # 加载配置
    oml_hooks_engine_load_config

    # 创建默认配置文件（如果不存在）
    if [[ ! -f "$OML_HOOKS_CONFIG_FILE" ]]; then
        cat > "$OML_HOOKS_CONFIG_FILE" <<'EOF'
{
  "version": "0.1.0",
  "enabled": true,
  "default_timeout": 30,
  "max_retries": 3,
  "retry_delay": 1,
  "stop_on_error": false,
  "parallel_execution": false,
  "log_level": "info",
  "events": {}
}
EOF
    fi

    __OML_HOOKS_ENGINE_INITIALIZED=true

    oml_hooks_engine_log "INFO" "Hooks Engine initialized successfully"
    echo "Hooks Engine v${OML_HOOKS_ENGINE_VERSION} initialized"
}

# 注册 Hook（简化接口）
# 用法：oml_hook_add <type> <target> <handler> [options]
# type: pre, post, around
# target: 目标事件/操作名称
oml_hook_add() {
    local hook_type="$1"
    local target="$2"
    local handler="$3"
    local priority="${4:-0}"
    local options="${5:-{}}"

    local hook_name="${hook_type}-${target}"
    local event_name

    # 根据类型生成事件名
    case "$hook_type" in
        pre)
            event_name="${target}:pre"
            ;;
        post)
            event_name="${target}:post"
            ;;
        around)
            event_name="${target}:around"
            ;;
        *)
            oml_hooks_engine_log "ERROR" "Invalid hook type: $hook_type"
            return 1
            ;;
    esac

    oml_hook_register "$hook_name" "$event_name" "$handler" "$priority" "$options"
}

# 移除 Hook
oml_hook_remove() {
    local hook_type="$1"
    local target="$2"

    local hook_name="${hook_type}-${target}"
    oml_hook_unregister "$hook_name"
}

# 触发 Hook 事件
# 用法：oml_hook_trigger <target> [payload...] [options]
oml_hook_trigger() {
    local target="$1"
    shift

    local timeout="${OML_DISPATCHER_DEFAULT_TIMEOUT}"
    local stop_on_error=false
    local parallel_mode=false
    local blocking=true
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
            --async|--non-blocking)
                blocking=false
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

    oml_hooks_engine_log "INFO" "Triggering hooks for target: $target (blocking=$blocking)"

    # 构建分发选项
    local dispatch_opts=()
    dispatch_opts+=("--timeout" "$timeout")
    [[ "$stop_on_error" == true ]] && dispatch_opts+=("--stop-on-error")
    [[ "$parallel_mode" == true ]] && dispatch_opts+=("--parallel")

    if [[ "$blocking" == true ]]; then
        # 阻塞模式：依次执行 pre -> target -> post
        local exit_code=0

        # 执行 pre-hooks
        oml_hooks_dispatch "${target}:pre" "${payload[@]}" "${dispatch_opts[@]}" || exit_code=$?
        if [[ $exit_code -ne 0 && "$stop_on_error" == true ]]; then
            oml_hooks_engine_log "ERROR" "Pre-hooks failed, aborting"
            return $exit_code
        fi

        # 执行主事件
        oml_event_emit "${target}" "${payload[@]}" --timeout "$timeout" || true

        # 执行 post-hooks
        oml_hooks_dispatch "${target}:post" "${payload[@]}" "${dispatch_opts[@]}" || exit_code=$?

        return $exit_code
    else
        # 非阻塞模式：异步执行
        (
            oml_hooks_dispatch "${target}:pre" "${payload[@]}" "${dispatch_opts[@]}" || true
            oml_event_emit "${target}" "${payload[@]}" --async || true
            oml_hooks_dispatch "${target}:post" "${payload[@]}" "${dispatch_opts[@]}" || true
        ) &
        echo $!
    fi
}

# 执行带 Around Hook 的操作
# 用法：oml_hook_around_exec <target> <command> [args]
oml_hook_around_exec() {
    local target="$1"
    local command="$2"
    shift 2 || true
    local args=("$@")

    local exit_code=0

    # 执行 around pre
    oml_hooks_dispatch "${target}:around:pre" "${args[@]}" || true

    # 执行命令
    if declare -f "$command" >/dev/null 2>&1; then
        "$command" "${args[@]}" || exit_code=$?
    elif [[ -x "$command" ]]; then
        "$command" "${args[@]}" || exit_code=$?
    else
        oml_hooks_engine_log "ERROR" "Command not found: $command"
        exit_code=127
    fi

    # 执行 around post（传递退出码）
    oml_hooks_dispatch "${target}:around:post" "${args[@]}" "$exit_code" || true

    return $exit_code
}

# 批量注册 Hooks
# 用法：oml_hooks_batch_register <config_file>
oml_hooks_batch_register() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        oml_hooks_engine_log "ERROR" "Config file not found: $config_file"
        return 1
    fi

    python3 - "$config_file" <<'PY'
import json
import sys
import subprocess

config_file = sys.argv[1]

with open(config_file, 'r') as f:
    config = json.load(f)

hooks = config.get('hooks', [])
for hook in hooks:
    name = hook['name']
    event = hook['event']
    handler = hook['handler']
    priority = hook.get('priority', 0)
    options = json.dumps(hook.get('options', {}))

    # 调用注册命令
    result = subprocess.run(
        ['oml_hook_register', name, event, handler, str(priority), options],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"Failed to register {name}: {result.stderr}", file=sys.stderr)
    else:
        print(f"Registered: {name}")

print(f"Batch registered {len(hooks)} hooks")
PY
}

# 获取引擎状态
oml_hooks_engine_status() {
    local registry_stats
    local dispatcher_status

    registry_stats="$(oml_hooks_registry_stats 2>/dev/null || echo '{}')"
    dispatcher_status="$(oml_hooks_dispatcher_status 2>/dev/null || echo '{}')"

    python3 - "$registry_stats" "$dispatcher_status" <<'PY'
import json
import sys

registry = json.loads(sys.argv[1])
dispatcher = json.loads(sys.argv[2])

status = {
    'version': '0.1.0',
    'initialized': True,
    'hooks': {
        'total': registry.get('total_hooks', 0),
        'enabled': registry.get('enabled_hooks', 0),
        'disabled': registry.get('disabled_hooks', 0)
    },
    'events': {
        'total': registry.get('total_events', 0),
        'triggered': registry.get('total_triggered', 0),
        'success_rate': registry.get('success_rate', 'N/A')
    },
    'dispatcher': {
        'current_event': dispatcher.get('current_event', 'none'),
        'pending_events': dispatcher.get('pending_events', 0),
        'active_dispatches': dispatcher.get('active_dispatches', 0)
    }
}

print(json.dumps(status, indent=2))
PY
}

# 健康检查
oml_hooks_engine_health() {
    local errors=0
    local warnings=0

    echo "Running Hooks Engine health check..."
    echo ""

    # 检查注册表
    echo -n "Checking registry... "
    if [[ -f "${OML_HOOKS_REGISTRY_FILE:-}" ]]; then
        if oml_hooks_registry_validate >/dev/null 2>&1; then
            echo "✓ OK"
        else
            echo "⚠ WARNINGS"
            ((warnings++))
        fi
    else
        echo "✗ NOT FOUND"
        ((errors++))
    fi

    # 检查分发器日志目录
    echo -n "Checking dispatcher logs... "
    if [[ -d "${OML_DISPATCHER_LOGS_DIR:-}" ]]; then
        echo "✓ OK"
    else
        echo "✗ NOT FOUND"
        ((errors++))
    fi

    # 检查事件队列
    echo -n "Checking event queue... "
    if [[ -d "${OML_EVENT_QUEUE_DIR:-}" ]]; then
        local queue_count
        queue_count="$(find "${OML_EVENT_QUEUE_DIR}" -name "*.json" 2>/dev/null | wc -l)"
        if [[ $queue_count -eq 0 ]]; then
            echo "✓ OK (empty)"
        else
            echo "⚠ ${queue_count} pending"
            ((warnings++))
        fi
    else
        echo "✗ NOT FOUND"
        ((errors++))
    fi

    # 检查处理器可执行性
    echo -n "Checking handlers... "
    local handler_errors=0
    if [[ -f "${OML_HOOKS_REGISTRY_FILE:-}" ]]; then
        while IFS= read -r handler; do
            if [[ -n "$handler" && ! -x "$handler" && ! -d "$handler" ]]; then
                ((handler_errors++))
            fi
        done < <(python3 -c "
import json
with open('${OML_HOOKS_REGISTRY_FILE}', 'r') as f:
    data = json.load(f)
for hook in data['hooks']:
    print(hook['handler'])
" 2>/dev/null)

        if [[ $handler_errors -eq 0 ]]; then
            echo "✓ OK"
        else
            echo "⚠ ${handler_errors} invalid"
            ((warnings++))
        fi
    else
        echo "✓ N/A"
    fi

    echo ""
    if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
        echo "Health check: PASSED"
        return 0
    elif [[ $errors -eq 0 ]]; then
        echo "Health check: PASSED with ${warnings} warning(s)"
        return 0
    else
        echo "Health check: FAILED with ${errors} error(s)"
        return 1
    fi
}

# 清理引擎资源
oml_hooks_engine_cleanup() {
    local clear_queue="${1:-false}"
    local clear_logs="${2:-false}"
    local clear_all="${3:-false}"

    if [[ "$clear_all" == true ]]; then
        clear_queue=true
        clear_logs=true
    fi

    local cleared=0

    if [[ "$clear_queue" == true ]]; then
        local queue_cleared
        queue_cleared="$(oml_event_queue_clear 2>/dev/null || echo 0)"
        cleared=$((cleared + queue_cleared))
        oml_hooks_engine_log "INFO" "Cleared ${queue_cleared} queued events"
    fi

    if [[ "$clear_logs" == true ]]; then
        local log_count=0
        for log_file in "${OML_HOOKS_CONFIG_DIR}"/*.log "${OML_DISPATCHER_LOGS_DIR:-}"/*.log; do
            [[ -f "$log_file" ]] && rm -f "$log_file" && ((log_count++))
        done
        cleared=$((cleared + log_count))
        oml_hooks_engine_log "INFO" "Cleared ${log_count} log files"
    fi

    echo "Cleaned up ${cleared} item(s)"
}

# 导出引擎配置和注册表
oml_hooks_engine_export() {
    local export_file="$1"
    local include_stats="${2:-false}"

    mkdir -p "$(dirname "$export_file")"

    python3 - "${OML_HOOKS_REGISTRY_FILE:-}" "${OML_HOOKS_CONFIG_FILE:-}" "$export_file" "$include_stats" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
config_path = sys.argv[2]
export_path = sys.argv[3]
include_stats = sys.argv[4].lower() == 'true' if len(sys.argv) > 4 else False

export_data = {
    'exported_at': datetime.utcnow().isoformat() + 'Z',
    'version': '0.1.0',
    'config': {},
    'hooks': [],
    'events': {}
}

# 读取配置
try:
    with open(config_path, 'r') as f:
        export_data['config'] = json.load(f)
except:
    pass

# 读取注册表
try:
    with open(registry_path, 'r') as f:
        registry = json.load(f)
        export_data['hooks'] = registry.get('hooks', [])
        export_data['events'] = registry.get('events', {})

        if not include_stats:
            # 移除统计信息以减小文件大小
            for hook in export_data['hooks']:
                hook.pop('stats', None)
except:
    pass

with open(export_path, 'w') as f:
    json.dump(export_data, f, indent=2)

print(f"Exported to {export_path}")
PY
}

# 导入引擎配置
oml_hooks_engine_import() {
    local import_file="$1"
    local merge="${2:-true}"

    if [[ ! -f "$import_file" ]]; then
        oml_hooks_engine_log "ERROR" "Import file not found: $import_file"
        return 1
    fi

    # 导入配置
    python3 -c "
import json
import shutil
shutil.copy('${import_file}', '${OML_HOOKS_CONFIG_FILE}.imported')
with open('${import_file}', 'r') as f:
    data = json.load(f)
if 'config' in data:
    with open('${OML_HOOKS_CONFIG_FILE}', 'w') as f:
        json.dump(data['config'], f, indent=2)
" 2>/dev/null

    # 导入 Hooks
    python3 - "${OML_HOOKS_REGISTRY_FILE:-}" "$import_file" "$merge" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
import_file = sys.argv[2]
merge = sys.argv[3].lower() == 'true' if len(sys.argv) > 3 else True

with open(registry_path, 'r') as f:
    registry = json.load(f)

with open(import_file, 'r') as f:
    import_data = json.load(f)

if merge:
    existing_names = {h['name'] for h in registry['hooks']}
    for hook in import_data.get('hooks', []):
        if hook['name'] in existing_names:
            for i, existing in enumerate(registry['hooks']):
                if existing['name'] == hook['name']:
                    hook['updated_at'] = datetime.utcnow().isoformat() + 'Z'
                    registry['hooks'][i] = hook
                    break
        else:
            registry['hooks'].append(hook)

    for event, hooks in import_data.get('events', {}).items():
        if event not in registry['events']:
            registry['events'][event] = []
        for hook_name in hooks:
            if hook_name not in registry['events'][event]:
                registry['events'][event].append(hook_name)
else:
    registry['hooks'] = import_data.get('hooks', [])
    registry['events'] = import_data.get('events', {})

registry['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(registry_path, 'w') as f:
    json.dump(registry, f, indent=2)

print(f"Imported {len(import_data.get('hooks', []))} hooks")
PY
}

# ============================================================================
# CLI 入口
# ============================================================================
main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_hooks_engine_init
            ;;
        add)
            oml_hook_add "$@"
            ;;
        remove)
            oml_hook_remove "$@"
            ;;
        trigger)
            oml_hook_trigger "$@"
            ;;
        around-exec)
            oml_hook_around_exec "$@"
            ;;
        batch-register)
            oml_hooks_batch_register "$@"
            ;;
        status)
            oml_hooks_engine_status
            ;;
        health)
            oml_hooks_engine_health
            ;;
        cleanup)
            oml_hooks_engine_cleanup "$@"
            ;;
        export)
            oml_hooks_engine_export "$@"
            ;;
        import)
            oml_hooks_engine_import "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Hooks Engine - Hooks 引擎主逻辑 (v${OML_HOOKS_ENGINE_VERSION})

用法：oml hooks <action> [args]

动作:
  init                        初始化 Hooks 引擎
  add <type> <target> <handler> [priority] [options]
                              注册 Hook (type: pre|post|around)
  remove <type> <target>      移除 Hook
  trigger <target> [args]     触发目标的所有 Hooks
    --timeout <seconds>       超时时间
    --stop-on-error           遇到错误立即停止
    --parallel                并行执行
    --async                   非阻塞模式
  around-exec <target> <cmd> [args]
                              执行带 Around Hook 的命令
  batch-register <config>     批量注册 Hooks
  status                      显示引擎状态
  health                      健康检查
  cleanup [queue] [logs] [all]
                              清理资源
  export <file> [include_stats]
                              导出配置
  import <file> [merge]       导入配置

示例:
  oml hooks init
  oml hooks add pre build:start /path/to/pre-build.sh 10
  oml hooks add post build:complete /path/to/post-build.sh 5
  oml hooks trigger build:start --timeout 60 --stop-on-error
  oml hooks around-exec git:commit git commit -m "message"
  oml hooks status
  oml hooks health
  oml hooks export ~/hooks-backup.json
  oml hooks cleanup --all

事件命名约定:
  - Pre-hooks:  <target>:pre   (例如：build:start:pre)
  - Post-hooks: <target>:post  (例如：build:complete:post)
  - Around-hooks: <target>:around:pre/post

阻塞/非阻塞模式:
  - 阻塞模式（默认）：等待所有 Hooks 执行完成
  - 非阻塞模式（--async）：后台执行，返回 PID
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml hooks help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
