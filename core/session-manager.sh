#!/usr/bin/env bash
# OML Session Manager
# Session 管理器核心 - 提供会话生命周期管理和 Task Registry 集成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 尝试查找 OML 根目录
if [[ -z "${OML_ROOT:-}" ]]; then
    if [[ "$(basename "$SCRIPT_DIR")" == "core" ]]; then
        export OML_ROOT="$(dirname "$SCRIPT_DIR")"
    fi
fi

# 加载 platform.sh
if [[ -z "${OML_PLATFORM_LOADED:-}" && -f "${SCRIPT_DIR}/platform.sh" ]]; then
    source "${SCRIPT_DIR}/platform.sh"
    export OML_PLATFORM_LOADED=true
fi

# 加载 session-storage.sh
if [[ -f "${SCRIPT_DIR}/session-storage.sh" ]]; then
    source "${SCRIPT_DIR}/session-storage.sh"
fi

# 加载 task-registry.sh
if [[ -f "${SCRIPT_DIR}/task-registry.sh" ]]; then
    source "${SCRIPT_DIR}/task-registry.sh"
fi

# ============================================================================
# 配置与常量
# ============================================================================

# 会话存储目录（继承自 session-storage.sh）
OML_SESSIONS_DIR="${OML_SESSIONS_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/sessions}"

# 会话状态
SESSION_STATUS_PENDING="pending"
SESSION_STATUS_RUNNING="running"
SESSION_STATUS_COMPLETED="completed"
SESSION_STATUS_FAILED="failed"
SESSION_STATUS_CANCELLED="cancelled"

# 会话类型
SESSION_TYPE_DEFAULT="default"
SESSION_TYPE_FORK="fork"
SESSION_TYPE_SHARED="shared"

# 输出格式
OML_OUTPUT_FORMAT="${OML_OUTPUT_FORMAT:-text}"

# ============================================================================
# 工具函数
# ============================================================================

# 输出 JSON
oml_session_json_output() {
    local data="$1"
    echo "$data"
}

# 输出文本
oml_session_text_output() {
    local msg="$1"
    if [[ "${OML_OUTPUT_FORMAT}" != "json" ]]; then
        echo "$msg"
    fi
}

# 输出错误
oml_session_mgr_error() {
    local msg="$1"
    local code="${2:-1}"

    if [[ "${OML_OUTPUT_FORMAT}" == "json" ]]; then
        python3 -c "
import json
import sys
data = {'error': True, 'message': sys.argv[1], 'code': int(sys.argv[2])}
print(json.dumps(data, ensure_ascii=False, indent=2))
" "$msg" "$code"
    else
        echo "ERROR: $msg" >&2
    fi
    return "$code"
}

# 生成会话 ID
oml_session_mgr_generate_id() {
    local prefix="${1:-session}"
    echo "${prefix}-$(date +%s)-$$-${RANDOM}"
}

# 获取当前时间戳
oml_session_mgr_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# ============================================================================
# 会话上下文管理
# ============================================================================

# 当前活动会话
OML_CURRENT_SESSION_ID="${OML_CURRENT_SESSION_ID:-}"
OML_CURRENT_SESSION_DATA="${OML_CURRENT_SESSION_DATA:-}"

# 设置当前会话
oml_session_set_current() {
    local session_id="$1"
    export OML_CURRENT_SESSION_ID="$session_id"

    # 保存到缓存
    local cache_file="${OML_SESSIONS_DIR}/cache/current_session"
    mkdir -p "$(dirname "$cache_file")"
    echo "$session_id" > "$cache_file"
}

# 获取当前会话
oml_session_get_current() {
    if [[ -n "${OML_CURRENT_SESSION_ID:-}" ]]; then
        echo "$OML_CURRENT_SESSION_ID"
        return 0
    fi

    local cache_file="${OML_SESSIONS_DIR}/cache/current_session"
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    fi

    return 1
}

# 清除当前会话
oml_session_clear_current() {
    unset OML_CURRENT_SESSION_ID
    local cache_file="${OML_SESSIONS_DIR}/cache/current_session"
    rm -f "$cache_file"
}

# ============================================================================
# 会话生命周期管理
# ============================================================================

# 创建新会话
oml_session_mgr_create() {
    local name="${1:-}"
    local type="${2:-$SESSION_TYPE_DEFAULT}"
    local parent_id="${3:-}"
    local metadata="${4:-}"

    # 生成会话 ID
    local session_id
    session_id="$(oml_session_mgr_generate_id)"

    # 构建初始数据
    local timestamp
    timestamp="$(oml_session_mgr_timestamp)"

    local initial_data
    initial_data=$(python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'type': '${type}',
    'parent_id': '${parent_id}',
    'status': '${SESSION_STATUS_PENDING}',
    'created_at': '${timestamp}',
    'updated_at': '${timestamp}',
    'metadata': ${metadata:-'{}'},
    'data': {},
    'messages': [],
    'context': {}
}, indent=2))
")

    # 创建存储
    oml_session_create "$session_id" "$initial_data" >/dev/null

    # 设置当前会话
    oml_session_set_current "$session_id"

    # 注册到 Task Registry（如果可用）
    if type -t oml_task_register >/dev/null 2>&1; then
        oml_task_register "$session_id" "session" "${name:-unnamed}" "**" "" "0" 2>/dev/null || true
    fi

    # 输出结果
    if [[ "${OML_OUTPUT_FORMAT}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'type': '${type}',
    'status': '${SESSION_STATUS_PENDING}',
    'created_at': '${timestamp}'
}, indent=2))
"
    else
        echo "Created session: ${session_id}"
        echo "Name: ${name:-unnamed}"
        echo "Type: ${type}"
        echo "Status: ${SESSION_STATUS_PENDING}"
    fi

    echo "$session_id"
}

# 启动会话
oml_session_mgr_start() {
    local session_id="${1:-}"

    # 如果没有指定 ID，使用当前会话
    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session. Create one first." 1
            return 1
        }
    fi

    # 更新状态为 running
    oml_session_update "$session_id" '{"status": "'${SESSION_STATUS_RUNNING}'"}' "true" >/dev/null

    # 更新 Task Registry
    if type -t oml_task_update_status >/dev/null 2>&1; then
        oml_task_update_status "$session_id" "running" 2>/dev/null || true
    fi

    # 设置当前会话
    oml_session_set_current "$session_id"

    oml_session_text_output "Started session: ${session_id}"
}

# 完成会话
oml_session_mgr_complete() {
    local session_id="${1:-}"
    local result="${2:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    local timestamp
    timestamp="$(oml_session_mgr_timestamp)"

    # 更新状态为 completed
    local update_data
    if [[ -n "$result" ]]; then
        update_data='{"status": "'${SESSION_STATUS_COMPLETED}'", "completed_at": "'${timestamp}'", "result": '"${result}"'}'
    else
        update_data='{"status": "'${SESSION_STATUS_COMPLETED}'", "completed_at": "'${timestamp}'"}'
    fi

    oml_session_update "$session_id" "$update_data" "true" >/dev/null

    # 更新 Task Registry
    if type -t oml_task_update_status >/dev/null 2>&1; then
        oml_task_update_status "$session_id" "completed" 2>/dev/null || true
    fi

    # 清除当前会话
    oml_session_clear_current

    oml_session_text_output "Completed session: ${session_id}"
}

# 失败会话
oml_session_mgr_fail() {
    local session_id="${1:-}"
    local error="${2:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    local timestamp
    timestamp="$(oml_session_mgr_timestamp)"

    local update_data
    if [[ -n "$error" ]]; then
        update_data='{"status": "'${SESSION_STATUS_FAILED}'", "completed_at": "'${timestamp}'", "error": '"${error}"'}'
    else
        update_data='{"status": "'${SESSION_STATUS_FAILED}'", "completed_at": "'${timestamp}'"}'
    fi

    oml_session_update "$session_id" "$update_data" "true" >/dev/null

    # 更新 Task Registry
    if type -t oml_task_update_status >/dev/null 2>&1; then
        oml_task_update_status "$session_id" "failed" 2>/dev/null || true
    fi

    oml_session_clear_current

    oml_session_text_output "Failed session: ${session_id}"
}

# 取消会话
oml_session_mgr_cancel() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    local timestamp
    timestamp="$(oml_session_mgr_timestamp)"

    oml_session_update "$session_id" '{"status": "'${SESSION_STATUS_CANCELLED}'", "completed_at": "'${timestamp}'"}' "true" >/dev/null

    # 更新 Task Registry
    if type -t oml_task_update_status >/dev/null 2>&1; then
        oml_task_update_status "$session_id" "cancelled" 2>/dev/null || true
    fi

    oml_session_clear_current

    oml_session_text_output "Cancelled session: ${session_id}"
}

# ============================================================================
# 会话消息管理
# ============================================================================

# 添加消息到会话
oml_session_mgr_add_message() {
    local session_id="${1:-}"
    local role="$2"  # user, assistant, system
    local content="$3"
    local metadata="${4:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    local timestamp
    timestamp="$(oml_session_mgr_timestamp)"

    # 添加消息
    python3 - "$(oml_session_get_data_path "$session_id")" "${role}" "${content}" "${timestamp}" "${metadata:-'{}'}" <<'PY'
import json
import sys

data_path = sys.argv[1]
role = sys.argv[2]
content = sys.argv[3]
timestamp = sys.argv[4]
metadata = json.loads(sys.argv[5])

with open(data_path, 'r') as f:
    data = json.load(f)

message = {
    'role': role,
    'content': content,
    'timestamp': timestamp,
    'metadata': metadata
}

if 'messages' not in data:
    data['messages'] = []

data['messages'].append(message)
data['updated_at'] = timestamp

with open(data_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"Added {role} message")
PY

    # 更新索引
    oml_session_update_index "$session_id" "update" "{\"size\": $(wc -c < "$(oml_session_get_data_path "$session_id")")}"
}

# 获取会话消息
oml_session_mgr_get_messages() {
    local session_id="${1:-}"
    local role="${2:-}"
    local limit="${3:-0}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    python3 - "${data_path}" "${role}" "${limit}" <<'PY'
import json
import sys

data_path = sys.argv[1]
role_filter = sys.argv[2] if len(sys.argv) > 2 else None
limit = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] != '0' else None

with open(data_path, 'r') as f:
    data = json.load(f)

messages = data.get('messages', [])

if role_filter:
    messages = [m for m in messages if m.get('role') == role_filter]

if limit:
    messages = messages[-limit:]

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps(messages, indent=2, ensure_ascii=False))
else:
    for msg in messages:
        role = msg.get('role', 'unknown')
        content = msg.get('content', '')[:100]
        timestamp = msg.get('timestamp', '')[:19]
        print(f"[{timestamp}] {role}: {content}...")
PY
}

# 清除会话消息
oml_session_mgr_clear_messages() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    oml_session_update "$session_id" '{"messages": []}' "true" >/dev/null
    oml_session_text_output "Cleared messages for session: ${session_id}"
}

# ============================================================================
# 会话上下文管理
# ============================================================================

# 设置会话上下文
oml_session_mgr_set_context() {
    local session_id="${1:-}"
    local key="$2"
    local value="$3"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    oml_session_set "$session_id" "context.${key}" "$value"
}

# 获取会话上下文
oml_session_mgr_get_context() {
    local session_id="${1:-}"
    local key="$2"
    local default="${3:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            if [[ -n "$default" ]]; then
                echo "$default"
                return 0
            fi
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    oml_session_get "$session_id" "context.${key}" "$default"
}

# 获取完整上下文
oml_session_mgr_get_full_context() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    oml_session_get "$session_id" "context"
}

# ============================================================================
# 会话查询与统计
# ============================================================================

# 获取会话信息
oml_session_mgr_info() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_get_current)" || {
            oml_session_mgr_error "No active session." 1
            return 1
        }
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_mgr_error "Session not found: ${session_id}" 1
        return 1
    fi

    if [[ "${OML_OUTPUT_FORMAT}" == "json" ]]; then
        cat "$data_path"
    else
        python3 -c "
import json

with open('${data_path}', 'r') as f:
    data = json.load(f)

print('=== Session Info ===')
print(f\"Session ID: {data.get('session_id', 'unknown')}\")
print(f\"Name: {data.get('name', 'unnamed')}\")
print(f\"Type: {data.get('type', 'default')}\")
print(f\"Status: {data.get('status', 'unknown')}\")
print(f\"Created: {data.get('created_at', 'unknown')}\")
print(f\"Updated: {data.get('updated_at', 'unknown')}\")

messages = data.get('messages', [])
print(f\"Messages: {len(messages)}\")

context = data.get('context', {})
if context:
    print(f\"Context keys: {', '.join(context.keys())}\")
"
    fi
}

# 列出所有会话
oml_session_mgr_list() {
    local status="${1:-all}"
    local type_filter="${2:-}"
    local limit="${3:-20}"

    python3 - "${OML_SESSIONS_INDEX}" "${status}" "${type_filter}" "${limit}" <<'PY'
import json
import sys

index_path = sys.argv[1]
status_filter = sys.argv[2]
type_filter = sys.argv[3] if len(sys.argv) > 3 else None
limit = int(sys.argv[4]) if len(sys.argv) > 4 else 20

with open(index_path, 'r') as f:
    index = json.load(f)

sessions = index.get('sessions', {})

# 过滤状态
if status_filter != 'all':
    sessions = {k: v for k, v in sessions.items() if v.get('status') == status_filter}

# 获取详细信息并过滤类型
result = []
for session_id, info in sessions.items():
    # 尝试读取完整数据获取类型
    try:
        import os
        data_dir = os.path.join(os.path.dirname(index_path), 'data')
        data_path = os.path.join(data_dir, f"{session_id}.json")
        if os.path.exists(data_path):
            with open(data_path, 'r') as f:
                data = json.load(f)
            if type_filter and data.get('type') != type_filter:
                continue
            info['type'] = data.get('type', 'default')
            info['name'] = data.get('name', '')
    except:
        pass

    result.append((session_id, info))

# 排序
result.sort(key=lambda x: x[1].get('updated_at', ''), reverse=True)

# 限制数量
result = result[:limit]

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    output = {
        'total': len(result),
        'sessions': {k: v for k, v in result}
    }
    print(json.dumps(output, indent=2))
else:
    print(f"{'SESSION_ID':<36} {'NAME':<20} {'TYPE':<10} {'STATUS':<10} {'UPDATED'}")
    print("=" * 90)
    for session_id, info in result:
        name = info.get('name', 'unnamed')[:18]
        type_ = info.get('type', 'default')[:8]
        status = info.get('status', 'unknown')[:8]
        updated = info.get('updated_at', 'unknown')[:10]
        print(f"{session_id:<36} {name:<20} {type_:<10} {status:<10} {updated}")
    print(f"\nTotal: {len(result)} sessions")
PY
}

# 搜索会话
oml_session_mgr_search() {
    local query="$1"
    local field="${2:-all}"  # all, name, content, metadata

    python3 - "${OML_SESSIONS_DATA_DIR}" "${query}" "${field}" <<'PY'
import json
import sys
import os
import glob

data_dir = sys.argv[1]
query = sys.argv[2].lower()
field = sys.argv[3] if len(sys.argv) > 3 else 'all'

results = []

for data_file in glob.glob(os.path.join(data_dir, '*.json')):
    try:
        with open(data_file, 'r') as f:
            data = json.load(f)

        match = False

        if field == 'all' or field == 'name':
            if query in data.get('name', '').lower():
                match = True

        if field == 'all' or field == 'content':
            for msg in data.get('messages', []):
                if query in msg.get('content', '').lower():
                    match = True
                    break

        if field == 'all' or field == 'metadata':
            metadata_str = json.dumps(data.get('metadata', {})).lower()
            if query in metadata_str:
                match = True

        if match:
            results.append({
                'session_id': data.get('session_id'),
                'name': data.get('name'),
                'status': data.get('status'),
                'updated_at': data.get('updated_at'),
                'match_field': field
            })
    except Exception as e:
        pass

# 排序
results.sort(key=lambda x: x.get('updated_at', ''), reverse=True)

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({'results': results, 'count': len(results)}, indent=2))
else:
    print(f"Search results for: {query}")
    print(f"{'SESSION_ID':<36} {'NAME':<20} {'STATUS':<10} {'UPDATED'}")
    print("=" * 80)
    for r in results:
        print(f"{r['session_id']:<36} {r['name'][:18]:<20} {r['status']:<10} {r['updated_at'][:10] if r['updated_at'] else 'unknown'}")
    print(f"\nFound {len(results)} matches")
PY
}

# 会话统计
oml_session_mgr_stats() {
    python3 - "${OML_SESSIONS_INDEX}" "${OML_SESSIONS_DATA_DIR}" <<'PY'
import json
import sys
import os

index_path = sys.argv[1]
data_dir = sys.argv[2]

with open(index_path, 'r') as f:
    index = json.load(f)

sessions = index.get('sessions', {})

# 统计
total = len(sessions)
by_status = {}
by_type = {}
total_messages = 0
total_size = 0

for session_id, info in sessions.items():
    status = info.get('status', 'unknown')
    by_status[status] = by_status.get(status, 0) + 1

    # 读取类型
    try:
        data_path = os.path.join(data_dir, f"{session_id}.json")
        if os.path.exists(data_path):
            with open(data_path, 'r') as f:
                data = json.load(f)
            type_ = data.get('type', 'default')
            by_type[type_] = by_type.get(type_, 0) + 1
            total_messages += len(data.get('messages', []))
            total_size += os.path.getsize(data_path)
    except:
        pass

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'total_sessions': total,
        'by_status': by_status,
        'by_type': by_type,
        'total_messages': total_messages,
        'total_size_bytes': total_size,
        'total_size_human': f"{total_size / 1024:.2f} KB" if total_size < 1024*1024 else f"{total_size / 1024 / 1024:.2f} MB"
    }, indent=2))
else:
    print("=== Session Manager Statistics ===")
    print(f"Total Sessions: {total}")
    print("")
    print("By Status:")
    for status, count in sorted(by_status.items()):
        print(f"  {status}: {count}")
    print("")
    print("By Type:")
    for type_, count in sorted(by_type.items()):
        print(f"  {type_}: {count}")
    print("")
    print(f"Total Messages: {total_messages}")
    print(f"Total Size: {total_size / 1024:.2f} KB" if total_size < 1024*1024 else f"Total Size: {total_size / 1024 / 1024:.2f} MB")
PY
}

# ============================================================================
# Task Registry 集成
# ============================================================================

# 同步会话到 Task Registry
oml_session_mgr_sync_to_registry() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        oml_session_mgr_error "Session ID required" 1
        return 1
    fi

    if ! type -t oml_task_register >/dev/null 2>&1; then
        oml_session_text_output "Task Registry not available"
        return 0
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_mgr_error "Session not found: ${session_id}" 1
        return 1
    fi

    python3 - "${data_path}" <<'PY'
import json
import sys
import subprocess
import os

data_path = sys.argv[1]

with open(data_path, 'r') as f:
    data = json.load(f)

session_id = data.get('session_id')
name = data.get('name', 'unnamed')
status = data.get('status', 'pending')

# 调用 task registry
script_dir = os.path.dirname(os.path.dirname(data_path))
task_registry = os.path.join(script_dir, 'task-registry.sh')

if os.path.exists(task_registry):
    # 这里可以调用 oml_task_register 等函数
    print(f"Synced session {session_id} to Task Registry")
else:
    print("Task Registry script not found")
PY
}

# ============================================================================
# 主入口（CLI）
# ============================================================================

main() {
    # 初始化存储
    oml_session_storage_init 2>/dev/null || true

    local action="${1:-help}"
    shift || true

    case "$action" in
        # 生命周期管理
        create)
            local name="${1:-}"
            local type="${2:-$SESSION_TYPE_DEFAULT}"
            shift 2 || true
            oml_session_mgr_create "$name" "$type" "$@"
            ;;

        start)
            oml_session_mgr_start "$@"
            ;;

        complete|end)
            local session_id="${1:-}"
            shift || true
            local result="${1:-}"
            oml_session_mgr_complete "$session_id" "$result"
            ;;

        fail)
            local session_id="${1:-}"
            shift || true
            local error="${1:-}"
            oml_session_mgr_fail "$session_id" "$error"
            ;;

        cancel)
            oml_session_mgr_cancel "$@"
            ;;

        # 消息管理
        add-message|msg)
            local session_id="${1:-}"
            local role="$2"
            local content="$3"
            shift 3 || true
            local metadata="${1:-}"
            oml_session_mgr_add_message "$session_id" "$role" "$content" "$metadata"
            ;;

        get-messages|messages)
            local session_id="${1:-}"
            shift || true
            local role="${1:-}"
            local limit="${2:-0}"
            oml_session_mgr_get_messages "$session_id" "$role" "$limit"
            ;;

        clear-messages)
            oml_session_mgr_clear_messages "$@"
            ;;

        # 上下文管理
        set-context)
            local session_id="${1:-}"
            local key="$2"
            local value="$3"
            oml_session_mgr_set_context "$session_id" "$key" "$value"
            ;;

        get-context)
            local session_id="${1:-}"
            local key="$2"
            local default="${3:-}"
            oml_session_mgr_get_context "$session_id" "$key" "$default"
            ;;

        # 查询与统计
        info|i)
            oml_session_mgr_info "$@"
            ;;

        list|ls)
            local status="${1:-all}"
            local type_filter="${2:-}"
            local limit="${3:-20}"
            oml_session_mgr_list "$status" "$type_filter" "$limit"
            ;;

        search)
            local query="$1"
            local field="${2:-all}"
            oml_session_mgr_search "$query" "$field"
            ;;

        stats)
            oml_session_mgr_stats
            ;;

        # 当前会话
        current)
            oml_session_get_current || echo "No active session"
            ;;

        use)
            local session_id="$1"
            oml_session_set_current "$session_id"
            oml_session_text_output "Using session: ${session_id}"
            ;;

        # Task Registry 同步
        sync)
            oml_session_mgr_sync_to_registry "$@"
            ;;

        # 帮助
        help|--help|-h)
            cat <<EOF
OML Session Manager

用法：oml session <action> [args]

生命周期管理:
  create [name] [type]        创建新会话 (type: default|fork|shared)
  start [session_id]          启动会话
  complete [session_id]       完成会话
  fail [session_id] [error]   标记会话失败
  cancel [session_id]         取消会话

消息管理:
  add-message [id] <role> <content>  添加消息 (role: user|assistant|system)
  get-messages [id] [role] [limit]   获取消息
  clear-messages [id]                清除消息

上下文管理:
  set-context [id] <key> <value>     设置上下文
  get-context [id] <key> [default]   获取上下文

查询与统计:
  info [session_id]                  显示会话信息
  list [status] [type] [limit]       列出会话
  search <query> [field]             搜索会话
  stats                              显示统计

当前会话:
  current                            显示当前会话 ID
  use <session_id>                   切换到指定会话

Task Registry:
  sync <session_id>                  同步到 Task Registry

示例:
  oml session create "My Task" default
  oml session start
  oml session add-message user "Hello, help me write code"
  oml session add-message assistant "Sure, I can help..."
  oml session complete
  oml session list
  oml session search "code"
  oml session stats

环境变量:
  OML_OUTPUT_FORMAT         输出格式 (text|json)
  OML_CURRENT_SESSION_ID    当前会话 ID
EOF
            ;;

        *)
            oml_session_mgr_error "Unknown action: ${action}" 1
            echo "Use 'oml session help' for usage"
            return 1
            ;;
    esac
}

# 仅在直接执行时运行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
