#!/usr/bin/env bash
# OML Hooks Registry - Hooks 注册表管理
# 管理 Hooks 的注册、查询、启用/禁用状态

set -eo pipefail
# 注意：不使用 -u 选项，因为关联数组在 bash 中与 set -u 有兼容性问题

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_HOOKS_REGISTRY_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_HOOKS_REGISTRY_LOADED=true

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

# ============================================================================
# 常量定义
# ============================================================================
readonly OML_HOOKS_REGISTRY_VERSION="0.1.0"
readonly OML_HOOKS_REGISTRY_FILE="${OML_HOOKS_REGISTRY_FILE:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/hooks/registry.json}"
readonly OML_HOOKS_DIR="${OML_HOOKS_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/hooks}"
readonly OML_HOOKS_ENABLED_DIR="${OML_HOOKS_ENABLED_DIR:-${OML_HOOKS_DIR}/enabled}"
readonly OML_HOOKS_AVAILABLE_DIR="${OML_HOOKS_AVAILABLE_DIR:-${OML_HOOKS_DIR}/available}"

# ============================================================================
# 内部状态
# ============================================================================
declare -A __OML_HOOKS_CACHE=()
declare -A __OML_HOOKS_ENABLED=()

# ============================================================================
# 工具函数
# ============================================================================

# 生成唯一 Hook ID
oml_hook_generate_id() {
    echo "hook-$(date +%s)-$$-${RANDOM}"
}

# 验证 Hook 名称
oml_hook_validate_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_.:-]*$ ]]; then
        return 1
    fi
    return 0
}

# 验证事件名称
oml_hook_validate_event() {
    local event="$1"
    if [[ -z "$event" ]]; then
        return 1
    fi
    if [[ ! "$event" =~ ^[a-zA-Z][a-zA-Z0-9_.:-]*$ ]]; then
        return 1
    fi
    return 0
}

# 日志输出
oml_hook_registry_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[${timestamp}] [${level}] ${message}" >&2

    local log_file="${OML_HOOKS_DIR}/registry.log"
    mkdir -p "$(dirname "$log_file")"
    echo "[${timestamp}] [${level}] ${message}" >> "$log_file" 2>/dev/null || true
}

# ============================================================================
# 注册表核心函数
# ============================================================================

# 初始化注册表
oml_hooks_registry_init() {
    mkdir -p "$(dirname "${OML_HOOKS_REGISTRY_FILE}")"
    mkdir -p "${OML_HOOKS_ENABLED_DIR}"
    mkdir -p "${OML_HOOKS_AVAILABLE_DIR}"

    if [[ ! -f "${OML_HOOKS_REGISTRY_FILE}" ]]; then
        cat > "${OML_HOOKS_REGISTRY_FILE}" <<'EOF'
{
  "version": "0.1.0",
  "created_at": "",
  "updated_at": "",
  "hooks": [],
  "events": {}
}
EOF
        python3 -c "
import json
from datetime import datetime
with open('${OML_HOOKS_REGISTRY_FILE}', 'r') as f:
    data = json.load(f)
data['created_at'] = datetime.utcnow().isoformat() + 'Z'
data['updated_at'] = datetime.utcnow().isoformat() + 'Z'
with open('${OML_HOOKS_REGISTRY_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true
    fi

    oml_hook_registry_log "INFO" "Hooks registry initialized at: ${OML_HOOKS_REGISTRY_FILE}"
}

# 注册 Hook
# 用法：oml_hook_register <hook_name> <event_name> <handler_path> [priority] [options_json]
oml_hook_register() {
    local hook_name="$1"
    local event_name="$2"
    local handler_path="$3"
    local priority="${4:-0}"
    local options="${5:-{}}"

    if ! oml_hook_validate_name "$hook_name"; then
        oml_hook_registry_log "ERROR" "Invalid hook name: $hook_name"
        return 1
    fi

    if ! oml_hook_validate_event "$event_name"; then
        oml_hook_registry_log "ERROR" "Invalid event name: $event_name"
        return 1
    fi

    if [[ ! -f "$handler_path" && ! -d "$handler_path" ]]; then
        oml_hook_registry_log "ERROR" "Handler not found: $handler_path"
        return 1
    fi

    # 转换为绝对路径
    if [[ ! "$handler_path" = /* ]]; then
        handler_path="$(cd "$(dirname "$handler_path")" && pwd)/$(basename "$handler_path")"
    fi

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$hook_name" "$event_name" "$handler_path" "$priority" "$options" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
hook_name = sys.argv[2]
event_name = sys.argv[3]
handler_path = sys.argv[4]
priority = int(sys.argv[5]) if sys.argv[5] else 0
options = json.loads(sys.argv[6]) if sys.argv[6] else {}

with open(registry_path, 'r') as f:
    data = json.load(f)

# 检查是否已存在
existing_idx = None
for i, hook in enumerate(data['hooks']):
    if hook['name'] == hook_name:
        existing_idx = i
        break

hook_entry = {
    'name': hook_name,
    'event': event_name,
    'handler': handler_path,
    'priority': priority,
    'enabled': True,
    'options': options,
    'created_at': datetime.utcnow().isoformat() + 'Z',
    'updated_at': datetime.utcnow().isoformat() + 'Z',
    'stats': {
        'triggered': 0,
        'succeeded': 0,
        'failed': 0,
        'last_triggered': None
    }
}

if existing_idx is not None:
    hook_entry['created_at'] = data['hooks'][existing_idx]['created_at']
    data['hooks'][existing_idx] = hook_entry
else:
    data['hooks'].append(hook_entry)

# 更新事件索引
if event_name not in data['events']:
    data['events'][event_name] = []
if hook_name not in data['events'][event_name]:
    data['events'][event_name].append(hook_name)

data['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Registered hook: {hook_name} -> {event_name}")
PY

    # 清除缓存
    __OML_HOOKS_CACHE=()

    oml_hook_registry_log "INFO" "Hook registered: ${hook_name} -> ${event_name}"
}

# 注销 Hook
oml_hook_unregister() {
    local hook_name="$1"

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$hook_name" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
hook_name = sys.argv[2]

with open(registry_path, 'r') as f:
    data = json.load(f)

# 查找并移除
found = False
for i, hook in enumerate(data['hooks']):
    if hook['name'] == hook_name:
        # 从事件索引中移除
        event_name = hook['event']
        if event_name in data['events']:
            if hook_name in data['events'][event_name]:
                data['events'][event_name].remove(hook_name)
            if not data['events'][event_name]:
                del data['events'][event_name]

        data['hooks'].pop(i)
        found = True
        break

if not found:
    print(f"Hook not found: {hook_name}", file=sys.stderr)
    sys.exit(1)

data['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Unregistered hook: {hook_name}")
PY

    # 清除缓存
    __OML_HOOKS_CACHE=()

    oml_hook_registry_log "INFO" "Hook unregistered: $hook_name"
}

# 启用 Hook
oml_hook_enable() {
    local hook_name="$1"

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$hook_name" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
hook_name = sys.argv[2]

with open(registry_path, 'r') as f:
    data = json.load(f)

found = False
for hook in data['hooks']:
    if hook['name'] == hook_name:
        hook['enabled'] = True
        hook['updated_at'] = datetime.utcnow().isoformat() + 'Z'
        found = True
        break

if not found:
    print(f"Hook not found: {hook_name}", file=sys.stderr)
    sys.exit(1)

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Enabled hook: {hook_name}")
PY

    # 创建启用标记
    local marker_file="${OML_HOOKS_ENABLED_DIR}/${hook_name}.enabled"
    touch "$marker_file"
    __OML_HOOKS_ENABLED[$hook_name]=1

    oml_hook_registry_log "INFO" "Hook enabled: $hook_name"
}

# 禁用 Hook
oml_hook_disable() {
    local hook_name="$1"

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$hook_name" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
hook_name = sys.argv[2]

with open(registry_path, 'r') as f:
    data = json.load(f)

found = False
for hook in data['hooks']:
    if hook['name'] == hook_name:
        hook['enabled'] = False
        hook['updated_at'] = datetime.utcnow().isoformat() + 'Z'
        found = True
        break

if not found:
    print(f"Hook not found: {hook_name}", file=sys.stderr)
    sys.exit(1)

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Disabled hook: {hook_name}")
PY

    # 移除启用标记
    local marker_file="${OML_HOOKS_ENABLED_DIR}/${hook_name}.enabled"
    rm -f "$marker_file"
    unset "__OML_HOOKS_ENABLED[$hook_name]" 2>/dev/null || true

    oml_hook_registry_log "INFO" "Hook disabled: $hook_name"
}

# 获取 Hook 信息
oml_hook_info() {
    local hook_name="$1"
    local format="${2:-json}"

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$hook_name" "$format" <<'PY'
import json
import sys

registry_path = sys.argv[1]
hook_name = sys.argv[2]
format_type = sys.argv[3] if len(sys.argv) > 3 else 'json'

with open(registry_path, 'r') as f:
    data = json.load(f)

for hook in data['hooks']:
    if hook['name'] == hook_name:
        if format_type == 'json':
            print(json.dumps(hook, indent=2))
        elif format_type == 'plain':
            print(f"Name: {hook['name']}")
            print(f"Event: {hook['event']}")
            print(f"Handler: {hook['handler']}")
            print(f"Priority: {hook['priority']}")
            print(f"Enabled: {hook['enabled']}")
            print(f"Created: {hook['created_at']}")
            print(f"Stats: triggered={hook['stats']['triggered']}, succeeded={hook['stats']['succeeded']}, failed={hook['stats']['failed']}")
        sys.exit(0)

print(f"Hook not found: {hook_name}", file=sys.stderr)
sys.exit(1)
PY
}

# 列出所有 Hooks
oml_hooks_list() {
    local event_filter="${1:-}"
    local status_filter="${2:-all}"
    local format="${3:-plain}"

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$event_filter" "$status_filter" "$format" <<'PY'
import json
import sys

registry_path = sys.argv[1]
event_filter = sys.argv[2] if len(sys.argv) > 2 else ''
status_filter = sys.argv[3] if len(sys.argv) > 3 else 'all'
format_type = sys.argv[4] if len(sys.argv) > 4 else 'plain'

with open(registry_path, 'r') as f:
    data = json.load(f)

hooks = data['hooks']

# 应用过滤器
if event_filter:
    hooks = [h for h in hooks if h['event'] == event_filter]
if status_filter == 'enabled':
    hooks = [h for h in hooks if h['enabled']]
elif status_filter == 'disabled':
    hooks = [h for h in hooks if not h['enabled']]

if format_type == 'json':
    print(json.dumps(hooks, indent=2))
elif format_type == 'plain':
    if not hooks:
        print("No hooks found")
    else:
        print(f"{'NAME':<25} {'EVENT':<25} {'PRIORITY':<10} {'STATUS':<10}")
        print("=" * 70)
        for hook in sorted(hooks, key=lambda x: (-x['priority'], x['name'])):
            status = "enabled" if hook['enabled'] else "disabled"
            print(f"{hook['name']:<25} {hook['event']:<25} {hook['priority']:<10} {status:<10}")
elif format_type == 'names':
    for hook in hooks:
        print(hook['name'])
PY
}

# 获取指定事件的所有 Hooks（按优先级排序）
oml_hooks_get_for_event() {
    local event_name="$1"
    local enabled_only="${2:-true}"

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$event_name" "$enabled_only" <<'PY'
import json
import sys

registry_path = sys.argv[1]
event_name = sys.argv[2] if len(sys.argv) > 2 else ''
enabled_only = sys.argv[3].lower() == 'true' if len(sys.argv) > 3 else True

with open(registry_path, 'r') as f:
    data = json.load(f)

hooks = [h for h in data['hooks'] if h['event'] == event_name]
if enabled_only:
    hooks = [h for h in hooks if h['enabled']]

# 按优先级降序排序
hooks.sort(key=lambda x: -x['priority'])

# 输出 handler 列表
for hook in hooks:
    print(f"{hook['handler']}|{hook['name']}|{hook['priority']}|{json.dumps(hook.get('options', {}))}")
PY
}

# 更新 Hook 统计信息
oml_hooks_update_stats() {
    local hook_name="$1"
    local status="${2:-success}"  # success, failed

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$hook_name" "$status" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
hook_name = sys.argv[2]
status = sys.argv[3] if len(sys.argv) > 3 else 'success'

with open(registry_path, 'r') as f:
    data = json.load(f)

for hook in data['hooks']:
    if hook['name'] == hook_name:
        hook['stats']['triggered'] += 1
        if status == 'success':
            hook['stats']['succeeded'] += 1
        else:
            hook['stats']['failed'] += 1
        hook['stats']['last_triggered'] = datetime.utcnow().isoformat() + 'Z'
        hook['updated_at'] = datetime.utcnow().isoformat() + 'Z'
        break

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)
PY
}

# 批量导入 Hooks
oml_hooks_import() {
    local import_file="$1"
    local merge="${2:-true}"

    if [[ ! -f "$import_file" ]]; then
        oml_hook_registry_log "ERROR" "Import file not found: $import_file"
        return 1
    fi

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$import_file" "$merge" <<'PY'
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
    # 合并模式：添加新 hooks，更新已存在的
    existing_names = {h['name'] for h in registry['hooks']}
    for hook in import_data.get('hooks', []):
        if hook['name'] in existing_names:
            # 更新已存在的
            for i, existing in enumerate(registry['hooks']):
                if existing['name'] == hook['name']:
                    hook['updated_at'] = datetime.utcnow().isoformat() + 'Z'
                    registry['hooks'][i] = hook
                    break
        else:
            # 添加新的
            registry['hooks'].append(hook)

    # 合并事件索引
    for event, hooks in import_data.get('events', {}).items():
        if event not in registry['events']:
            registry['events'][event] = []
        for hook_name in hooks:
            if hook_name not in registry['events'][event]:
                registry['events'][event].append(hook_name)
else:
    # 覆盖模式
    registry['hooks'] = import_data.get('hooks', [])
    registry['events'] = import_data.get('events', {})

registry['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(registry_path, 'w') as f:
    json.dump(registry, f, indent=2)

print(f"Imported {len(import_data.get('hooks', []))} hooks from {import_file}")
PY

    oml_hook_registry_log "INFO" "Imported hooks from: $import_file"
}

# 导出 Hooks
oml_hooks_export() {
    local export_file="$1"
    local event_filter="${2:-}"

    python3 - "${OML_HOOKS_REGISTRY_FILE}" "$export_file" "$event_filter" <<'PY'
import json
import sys

registry_path = sys.argv[1]
export_file = sys.argv[2]
event_filter = sys.argv[3] if len(sys.argv) > 3 else ''

with open(registry_path, 'r') as f:
    data = json.load(f)

export_data = {
    'version': data.get('version', '0.1.0'),
    'exported_at': data.get('updated_at'),
    'hooks': data['hooks'],
    'events': data['events']
}

if event_filter:
    export_data['hooks'] = [h for h in data['hooks'] if h['event'] == event_filter]
    export_data['events'] = {event_filter: data['events'].get(event_filter, [])} if event_filter in data['events'] else {}

with open(export_file, 'w') as f:
    json.dump(export_data, f, indent=2)

print(f"Exported {len(export_data['hooks'])} hooks to {export_file}")
PY

    oml_hook_registry_log "INFO" "Exported hooks to: $export_file"
}

# 获取注册表统计信息
oml_hooks_registry_stats() {
    python3 - "${OML_HOOKS_REGISTRY_FILE}" <<'PY'
import json
import sys

registry_path = sys.argv[1]

with open(registry_path, 'r') as f:
    data = json.load(f)

total_hooks = len(data['hooks'])
enabled_hooks = sum(1 for h in data['hooks'] if h['enabled'])
disabled_hooks = total_hooks - enabled_hooks
total_events = len(data['events'])
total_triggered = sum(h['stats']['triggered'] for h in data['hooks'])
total_succeeded = sum(h['stats']['succeeded'] for h in data['hooks'])
total_failed = sum(h['stats']['failed'] for h in data['hooks'])

print(json.dumps({
    'version': data.get('version', 'unknown'),
    'total_hooks': total_hooks,
    'enabled_hooks': enabled_hooks,
    'disabled_hooks': disabled_hooks,
    'total_events': total_events,
    'total_triggered': total_triggered,
    'total_succeeded': total_succeeded,
    'total_failed': total_failed,
    'success_rate': f"{(total_succeeded / total_triggered * 100):.1f}%" if total_triggered > 0 else "N/A",
    'registry_file': registry_path
}, indent=2))
PY
}

# 验证注册表完整性
oml_hooks_registry_validate() {
    local errors=0
    local warnings=0

    python3 - "${OML_HOOKS_REGISTRY_FILE}" <<'PY'
import json
import sys
import os

registry_path = sys.argv[1]
errors = []
warnings = []

with open(registry_path, 'r') as f:
    data = json.load(f)

# 检查 hooks
for hook in data['hooks']:
    # 检查 handler 是否存在
    if not os.path.exists(hook['handler']):
        errors.append(f"Handler not found: {hook['handler']} (hook: {hook['name']})")

    # 检查事件名称格式
    if not hook['event'].replace(':', '').replace('.', '').replace('_', '').isalnum():
        warnings.append(f"Invalid event name format: {hook['event']} (hook: {hook['name']})")

    # 检查优先级范围
    if not (-1000 <= hook['priority'] <= 1000):
        warnings.append(f"Priority out of recommended range: {hook['priority']} (hook: {hook['name']})")

# 检查事件索引一致性
for event, hooks in data['events'].items():
    for hook_name in hooks:
        if not any(h['name'] == hook_name for h in data['hooks']):
            warnings.append(f"Event index references non-existent hook: {hook_name} (event: {event})")

# 输出结果
if errors:
    print("ERRORS:")
    for err in errors:
        print(f"  ✗ {err}")
if warnings:
    print("WARNINGS:")
    for warn in warnings:
        print(f"  ! {warn}")
if not errors and not warnings:
    print("Registry validation passed")
    sys.exit(0)
elif not errors:
    print(f"Validation completed with {len(warnings)} warning(s)")
    sys.exit(0)
else:
    print(f"Validation failed with {len(errors)} error(s)")
    sys.exit(1)
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
            oml_hooks_registry_init
            echo "Hooks registry initialized"
            ;;
        register)
            oml_hook_register "$@"
            ;;
        unregister)
            oml_hook_unregister "$@"
            ;;
        enable)
            oml_hook_enable "$@"
            ;;
        disable)
            oml_hook_disable "$@"
            ;;
        info)
            oml_hook_info "$@"
            ;;
        list)
            oml_hooks_list "$@"
            ;;
        get)
            oml_hooks_get_for_event "$@"
            ;;
        import)
            oml_hooks_import "$@"
            ;;
        export)
            oml_hooks_export "$@"
            ;;
        stats)
            oml_hooks_registry_stats
            ;;
        validate)
            oml_hooks_registry_validate
            ;;
        help|--help|-h)
            cat <<EOF
OML Hooks Registry - Hooks 注册表管理

用法：oml hooks-registry <action> [args]

动作:
  init                              初始化注册表
  register <name> <event> <handler> [priority] [options]
                                    注册 Hook
  unregister <name>                 注销 Hook
  enable <name>                     启用 Hook
  disable <name>                    禁用 Hook
  info <name> [format]              获取 Hook 信息 (json|plain)
  list [event] [status] [format]    列出 Hooks
  get <event> [enabled_only]        获取事件的所有 Hooks
  import <file> [merge]             导入 Hooks
  export <file> [event]             导出 Hooks
  stats                             显示统计信息
  validate                          验证注册表完整性

示例:
  oml hooks-registry init
  oml hooks-registry register "pre-build" "build:start" "/path/to/hook.sh" 10
  oml hooks-registry list build enabled
  oml hooks-registry enable "pre-build"
  oml hooks-registry export ~/hooks-backup.json
  oml hooks-registry stats

优先级说明:
  - 数值越大优先级越高
  - 推荐范围：-1000 到 1000
  - 高优先级 Hook 先执行
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml hooks-registry help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
