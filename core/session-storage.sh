#!/usr/bin/env bash
# OML Session Storage
# 会话存储管理 - 提供会话数据的持久化、读取和删除功能

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

# ============================================================================
# 配置与常量
# ============================================================================

# 会话存储目录 - 如果已设置则使用，否则动态计算
# 注意：这些变量会在 oml_session_storage_init 中重新计算
: "${OML_SESSIONS_DIR:=${HOME}/.oml/sessions}"
: "${OML_SESSION_STORAGE_BACKEND:=file}"
: "${OML_OUTPUT_FORMAT:=text}"
: "${OML_SESSION_TTL:=0}"
: "${OML_SESSION_MAX_COUNT:=1000}"

# ============================================================================
# 初始化函数
# ============================================================================

# 初始化存储目录
oml_session_storage_init() {
    # 直接使用 OML_SESSIONS_DIR 环境变量，如果未设置则使用默认值
    local sessions_dir="${OML_SESSIONS_DIR:-${HOME}/.oml/sessions}"

    mkdir -p "${sessions_dir}"
    mkdir -p "${sessions_dir}/data"
    mkdir -p "${sessions_dir}/meta"
    mkdir -p "${sessions_dir}/cache"

    # 更新全局变量
    export OML_SESSIONS_DIR="$sessions_dir"
    export OML_SESSIONS_INDEX="${sessions_dir}/index.json"
    export OML_SESSIONS_DATA_DIR="${sessions_dir}/data"
    export OML_SESSIONS_META_DIR="${sessions_dir}/meta"
    export OML_SESSIONS_CACHE_DIR="${sessions_dir}/cache"

    # 初始化索引文件
    if [[ ! -f "${OML_SESSIONS_INDEX}" ]]; then
        cat > "${OML_SESSIONS_INDEX}" <<EOF
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
        # 设置创建时间
        python3 - "${OML_SESSIONS_INDEX}" <<PY
import json
from datetime import datetime

with open('${OML_SESSIONS_INDEX}', 'r') as f:
    data = json.load(f)

data['metadata']['created_at'] = datetime.utcnow().isoformat() + 'Z'
data['metadata']['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open('${OML_SESSIONS_INDEX}', 'w') as f:
    json.dump(data, f, indent=2)
PY
    fi
}

# ============================================================================
# 工具函数
# ============================================================================

# 获取当前时间戳（ISO 8601）
oml_session_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# 获取当前时间戳（Unix 秒）
oml_session_timestamp_unix() {
    date +%s
}

# 生成唯一会话 ID
oml_session_generate_id() {
    local prefix="${1:-sess}"
    echo "${prefix}-$(date +%s)-$$-${RANDOM}"
}

# 输出 JSON
oml_session_output_json() {
    local data="$1"
    echo "$data"
}

# 输出文本
oml_session_output_text() {
    local msg="$1"
    if [[ "${OML_OUTPUT_FORMAT}" != "json" ]]; then
        echo "$msg"
    fi
}

# 输出错误
oml_session_error() {
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

# 验证会话 ID 格式
oml_session_validate_id() {
    local session_id="$1"

    if [[ -z "$session_id" ]]; then
        return 1
    fi

    # 基本格式检查：允许字母、数字、连字符、下划线
    if [[ "$session_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取会话文件路径
oml_session_get_data_path() {
    local session_id="$1"
    echo "${OML_SESSIONS_DATA_DIR}/${session_id}.json"
}

# 获取会话元文件路径
oml_session_get_meta_path() {
    local session_id="$1"
    echo "${OML_SESSIONS_META_DIR}/${session_id}.meta"
}

# ============================================================================
# 索引管理
# ============================================================================

# 读取索引
oml_session_read_index() {
    if [[ -f "${OML_SESSIONS_INDEX}" ]]; then
        cat "${OML_SESSIONS_INDEX}"
    else
        echo '{"sessions": {}, "metadata": {"total_count": 0}}'
    fi
}

# 写入索引
oml_session_write_index() {
    local index_data="$1"
    echo "$index_data" > "${OML_SESSIONS_INDEX}"
}

# 更新索引中的会话信息
oml_session_update_index() {
    local session_id="$1"
    local action="$2"  # add, update, remove
    local session_data="${3:-}"

    python3 - "${OML_SESSIONS_INDEX}" "${session_id}" "${action}" "${session_data}" <<'PY'
import json
import sys
from datetime import datetime

index_path = sys.argv[1]
session_id = sys.argv[2]
action = sys.argv[3]
session_data = sys.argv[4] if len(sys.argv) > 4 else None

with open(index_path, 'r') as f:
    index = json.load(f)

if action == 'add':
    data = json.loads(session_data) if session_data else {}
    index['sessions'][session_id] = {
        'created_at': datetime.utcnow().isoformat() + 'Z',
        'updated_at': datetime.utcnow().isoformat() + 'Z',
        'size': data.get('size', 0),
        'status': data.get('status', 'active')
    }
    index['metadata']['total_count'] = len(index['sessions'])
elif action == 'update':
    if session_id in index['sessions']:
        index['sessions'][session_id]['updated_at'] = datetime.utcnow().isoformat() + 'Z'
        if session_data:
            data = json.loads(session_data)
            if 'size' in data:
                index['sessions'][session_id]['size'] = data['size']
            if 'status' in data:
                index['sessions'][session_id]['status'] = data['status']
elif action == 'remove':
    if session_id in index['sessions']:
        del index['sessions'][session_id]
        index['metadata']['total_count'] = len(index['sessions'])

index['metadata']['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(index_path, 'w') as f:
    json.dump(index, f, indent=2)
PY
}

# ============================================================================
# 会话 CRUD 操作
# ============================================================================

# 创建会话
oml_session_create() {
    local session_id="${1:-}"
    local initial_data="${2:-}"

    # 生成或验证会话 ID
    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_generate_id)"
    elif ! oml_session_validate_id "$session_id"; then
        oml_session_error "Invalid session ID format: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"
    local meta_path
    meta_path="$(oml_session_get_meta_path "$session_id")"

    # 检查会话是否已存在
    if [[ -f "$data_path" ]]; then
        oml_session_error "Session already exists: ${session_id}" 1
        return 1
    fi

    # 检查最大会话数
    local current_count
    current_count=$(python3 -c "import json; print(len(json.load(open('${OML_SESSIONS_INDEX}')).get('sessions', {})))" 2>/dev/null || echo "0")
    if [[ "$current_count" -ge "$OML_SESSION_MAX_COUNT" ]]; then
        oml_session_error "Maximum session count reached: ${OML_SESSION_MAX_COUNT}" 1
        return 1
    fi

    # 创建数据文件
    local timestamp
    timestamp="$(oml_session_timestamp)"

    if [[ -n "$initial_data" ]]; then
        echo "$initial_data" > "$data_path"
    else
        cat > "$data_path" <<EOF
{
  "session_id": "${session_id}",
  "created_at": "${timestamp}",
  "updated_at": "${timestamp}",
  "data": {}
}
EOF
    fi

    # 创建元数据文件
    cat > "$meta_path" <<EOF
session_id=${session_id}
created_at=${timestamp}
updated_at=${timestamp}
status=active
size=$(wc -c < "$data_path")
EOF

    # 更新索引
    oml_session_update_index "$session_id" "add" "$(cat "$data_path")"

    # 输出结果
    if [[ "${OML_OUTPUT_FORMAT}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'created_at': '${timestamp}',
    'status': 'active',
    'data_path': '${data_path}',
    'meta_path': '${meta_path}'
}, indent=2))
"
    else
        echo "Created session: ${session_id}"
        echo "Data path: ${data_path}"
        echo "Meta path: ${meta_path}"
    fi

    echo "$session_id"
}

# 读取会话
oml_session_read() {
    local session_id="$1"
    local field="${2:-}"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_error "Session not found: ${session_id}" 1
        return 1
    fi

    # 检查过期
    if oml_session_is_expired "$session_id"; then
        oml_session_error "Session expired: ${session_id}" 1
        return 1
    fi

    if [[ -n "$field" ]]; then
        # 读取特定字段
        python3 -c "
import json
import sys

with open('${data_path}', 'r') as f:
    data = json.load(f)

field = sys.argv[1]
keys = field.split('.')
result = data

for key in keys:
    if isinstance(result, dict) and key in result:
        result = result[key]
    else:
        print('', file=sys.stderr)
        sys.exit(1)

if isinstance(result, (dict, list)):
    print(json.dumps(result, indent=2))
else:
    print(result)
" "$field"
    else
        # 读取完整会话
        cat "$data_path"
    fi
}

# 更新会话
oml_session_update() {
    local session_id="$1"
    local update_data="$2"
    local merge="${3:-true}"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_error "Session not found: ${session_id}" 1
        return 1
    fi

    local timestamp
    timestamp="$(oml_session_timestamp)"

    # 更新数据
    python3 - "${data_path}" "${update_data}" "${merge}" "${timestamp}" <<'PY'
import json
import sys

data_path = sys.argv[1]
update_data = sys.argv[2]
merge = sys.argv[3].lower() == 'true'
timestamp = sys.argv[4]

with open(data_path, 'r') as f:
    data = json.load(f)

new_data = json.loads(update_data)

if merge:
    # 合并更新
    def deep_merge(base, update):
        for key, value in update.items():
            if key in base and isinstance(base[key], dict) and isinstance(value, dict):
                deep_merge(base[key], value)
            else:
                base[key] = value
        return base

    if 'data' in data and 'data' in new_data:
        deep_merge(data['data'], new_data['data'])
        del new_data['data']

    data.update(new_data)
else:
    # 完全替换
    data = new_data

data['updated_at'] = timestamp

with open(data_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"Updated session at {timestamp}")
PY

    # 更新元数据
    local meta_path
    meta_path="$(oml_session_get_meta_path "$session_id")"
    if [[ -f "$meta_path" ]]; then
        sed -i "s/^updated_at=.*/updated_at=${timestamp}/" "$meta_path"
        sed -i "s/^size=.*/size=$(wc -c < "$data_path")/" "$meta_path"
    fi

    # 更新索引
    oml_session_update_index "$session_id" "update" "{\"size\": $(wc -c < "$data_path")}"

    oml_session_output_text "Session updated: ${session_id}"
}

# 删除会话
oml_session_delete() {
    local session_id="$1"
    local force="${2:-false}"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"
    local meta_path
    meta_path="$(oml_session_get_meta_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        if [[ "$force" == "true" ]]; then
            oml_session_output_text "Session not found (forced delete): ${session_id}"
            return 0
        else
            oml_session_error "Session not found: ${session_id}" 1
            return 1
        fi
    fi

    # 删除文件
    rm -f "$data_path" "$meta_path"

    # 从索引中移除
    oml_session_update_index "$session_id" "remove"

    oml_session_output_text "Deleted session: ${session_id}"
}

# 列出所有会话
oml_session_list() {
    local status_filter="${1:-all}"
    local limit="${2:-0}"
    local offset="${3:-0}"

    python3 - "${OML_SESSIONS_INDEX}" "${status_filter}" "${limit}" "${offset}" <<'PY'
import json
import sys

index_path = sys.argv[1]
status_filter = sys.argv[2]
limit = int(sys.argv[3]) if sys.argv[3] != '0' else None
offset = int(sys.argv[4]) if sys.argv[4] != '0' else 0

with open(index_path, 'r') as f:
    index = json.load(f)

sessions = index.get('sessions', {})

# 过滤
if status_filter != 'all':
    sessions = {k: v for k, v in sessions.items() if v.get('status') == status_filter}

# 排序（按更新时间倒序）
sorted_sessions = sorted(sessions.items(), key=lambda x: x[1].get('updated_at', ''), reverse=True)

# 分页
if offset:
    sorted_sessions = sorted_sessions[offset:]
if limit:
    sorted_sessions = sorted_sessions[:limit]

# 输出
output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    result = {
        'total': len(sessions),
        'returned': len(sorted_sessions),
        'offset': offset,
        'sessions': {k: v for k, v in sorted_sessions}
    }
    print(json.dumps(result, indent=2))
else:
    print(f"{'SESSION_ID':<40} {'STATUS':<10} {'SIZE':<10} {'UPDATED_AT'}")
    print("=" * 80)
    for session_id, info in sorted_sessions:
        print(f"{session_id:<40} {info.get('status', 'unknown'):<10} {info.get('size', 0):<10} {info.get('updated_at', 'unknown')[:19]}")
    print(f"\nTotal: {len(sessions)}, Returned: {len(sorted_sessions)}")
PY
}

# ============================================================================
# 会话数据操作
# ============================================================================

# 设置会话数据
oml_session_set() {
    local session_id="$1"
    local key="$2"
    local value="$3"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_error "Session not found: ${session_id}" 1
        return 1
    fi

    python3 - "${data_path}" "${key}" "${value}" <<'PY'
import json
import sys

data_path = sys.argv[1]
key = sys.argv[2]
value = sys.argv[3]

with open(data_path, 'r') as f:
    data = json.load(f)

# 尝试解析值为 JSON
try:
    parsed_value = json.loads(value)
except json.JSONDecodeError:
    parsed_value = value

# 支持嵌套键（如 "user.name"）
keys = key.split('.')
current = data

for k in keys[:-1]:
    if k not in current:
        current[k] = {}
    current = current[k]

current[keys[-1]] = parsed_value

with open(data_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"Set {key} = {value}")
PY

    # 更新索引
    oml_session_update_index "$session_id" "update" "{\"size\": $(wc -c < "$data_path")}"
}

# 获取会话数据
oml_session_get() {
    local session_id="$1"
    local key="$2"
    local default="${3:-}"

    if ! oml_session_validate_id "$session_id"; then
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        oml_session_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        oml_session_error "Session not found: ${session_id}" 1
        return 1
    fi

    python3 - "${data_path}" "${key}" "${default}" <<'PY'
import json
import sys

data_path = sys.argv[1]
key = sys.argv[2]
default = sys.argv[3] if len(sys.argv) > 3 else None

with open(data_path, 'r') as f:
    data = json.load(f)

# 支持嵌套键
keys = key.split('.')
result = data

for k in keys:
    if isinstance(result, dict) and k in result:
        result = result[k]
    else:
        if default is not None:
            print(default)
        else:
            sys.exit(1)
        sys.exit(0)

if isinstance(result, (dict, list)):
    print(json.dumps(result, indent=2))
else:
    print(result)
PY
}

# 删除会话数据键
oml_session_unset() {
    local session_id="$1"
    local key="$2"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_error "Session not found: ${session_id}" 1
        return 1
    fi

    python3 - "${data_path}" "${key}" <<'PY'
import json
import sys

data_path = sys.argv[1]
key = sys.argv[2]

with open(data_path, 'r') as f:
    data = json.load(f)

keys = key.split('.')
current = data

for k in keys[:-1]:
    if k not in current:
        print(f"Key not found: {key}", file=sys.stderr)
        sys.exit(1)
    current = current[k]

if keys[-1] in current:
    del current[keys[-1]]
    with open(data_path, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"Unset: {key}")
else:
    print(f"Key not found: {key}", file=sys.stderr)
    sys.exit(1)
PY
}

# ============================================================================
# 过期管理
# ============================================================================

# 检查会话是否过期
oml_session_is_expired() {
    local session_id="$1"

    if [[ "$OML_SESSION_TTL" -eq 0 ]]; then
        return 1  # 永不过期
    fi

    local meta_path
    meta_path="$(oml_session_get_meta_path "$session_id")"

    if [[ ! -f "$meta_path" ]]; then
        return 1
    fi

    local updated_at
    updated_at=$(grep "^updated_at=" "$meta_path" | cut -d'=' -f2)

    if [[ -z "$updated_at" ]]; then
        return 1
    fi

    # 检查是否过期
    python3 - "${updated_at}" "${OML_SESSION_TTL}" <<'PY'
import sys
from datetime import datetime

updated_at_str = sys.argv[1]
ttl = int(sys.argv[2])

if ttl <= 0:
    sys.exit(1)  # 永不过期

updated_at = datetime.fromisoformat(updated_at_str.replace('Z', '+00:00'))
now = datetime.utcnow()

if (now - updated_at).total_seconds() > ttl:
    sys.exit(0)  # 已过期
else:
    sys.exit(1)  # 未过期
PY
}

# 清理过期会话
oml_session_cleanup_expired() {
    local dry_run="${1:-false}"

    oml_session_output_text "Cleaning up expired sessions..."

    local count=0
    local index_data
    index_data="$(oml_session_read_index)"

    python3 - "${OML_SESSIONS_INDEX}" "${OML_SESSION_TTL}" "${OML_SESSIONS_DATA_DIR}" "${OML_SESSIONS_META_DIR}" "${dry_run}" <<'PY'
import json
import sys
import os
from datetime import datetime

index_path = sys.argv[1]
ttl = int(sys.argv[2])
data_dir = sys.argv[3]
meta_dir = sys.argv[4]
dry_run = sys.argv[5].lower() == 'true'

if ttl <= 0:
    print("TTL is 0, no sessions will expire")
    sys.exit(0)

with open(index_path, 'r') as f:
    index = json.load(f)

now = datetime.utcnow()
expired = []

for session_id, info in index.get('sessions', {}).items():
    updated_at_str = info.get('updated_at', '')
    if updated_at_str:
        try:
            updated_at = datetime.fromisoformat(updated_at_str.replace('Z', '+00:00'))
            if (now - updated_at).total_seconds() > ttl:
                expired.append(session_id)
        except:
            pass

print(f"Found {len(expired)} expired sessions")

for session_id in expired:
    if dry_run:
        print(f"  Would delete: {session_id}")
    else:
        data_path = os.path.join(data_dir, f"{session_id}.json")
        meta_path = os.path.join(meta_dir, f"{session_id}.meta")

        if os.path.exists(data_path):
            os.remove(data_path)
        if os.path.exists(meta_path):
            os.remove(meta_path)

        del index['sessions'][session_id]
        print(f"  Deleted: {session_id}")

if not dry_run:
    index['metadata']['updated_at'] = datetime.utcnow().isoformat() + 'Z'
    index['metadata']['total_count'] = len(index['sessions'])

    with open(index_path, 'w') as f:
        json.dump(index, f, indent=2)

print(f"Cleanup complete. Removed {len(expired)} sessions.")
PY
}

# ============================================================================
# 统计信息
# ============================================================================

# 获取存储统计
oml_session_storage_stats() {
    python3 - "${OML_SESSIONS_INDEX}" "${OML_SESSIONS_DATA_DIR}" <<'PY'
import json
import sys
import os

index_path = sys.argv[1]
data_dir = sys.argv[2]

with open(index_path, 'r') as f:
    index = json.load(f)

sessions = index.get('sessions', {})
total_size = 0
total_count = len(sessions)

# 计算总大小
for session_id in sessions:
    data_path = os.path.join(data_dir, f"{session_id}.json")
    if os.path.exists(data_path):
        total_size += os.path.getsize(data_path)

# 按状态统计
status_counts = {}
for info in sessions.values():
    status = info.get('status', 'unknown')
    status_counts[status] = status_counts.get(status, 0) + 1

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'total_sessions': total_count,
        'total_size_bytes': total_size,
        'total_size_human': f"{total_size / 1024:.2f} KB" if total_size < 1024*1024 else f"{total_size / 1024 / 1024:.2f} MB",
        'by_status': status_counts,
        'storage_dir': data_dir,
        'index_path': index_path
    }, indent=2))
else:
    print("=== Session Storage Statistics ===")
    print(f"Total Sessions: {total_count}")
    print(f"Total Size: {total_size / 1024:.2f} KB" if total_size < 1024*1024 else f"Total Size: {total_size / 1024 / 1024:.2f} MB")
    print(f"Storage Dir: {data_dir}")
    print("")
    print("By Status:")
    for status, count in sorted(status_counts.items()):
        print(f"  {status}: {count}")
PY
}

# ============================================================================
# 主入口（CLI）
# ============================================================================

main() {
    # 初始化
    oml_session_storage_init

    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_session_storage_init
            oml_session_output_text "Session storage initialized at: ${OML_SESSIONS_DIR}"
            ;;

        create)
            oml_session_create "$@"
            ;;

        read|get)
            oml_session_read "$@"
            ;;

        update|set-data)
            local session_id="$1"
            local data="$2"
            shift 2 || true
            local merge="${1:-true}"
            oml_session_update "$session_id" "$data" "$merge"
            ;;

        delete|remove)
            local session_id="$1"
            local force="${2:-false}"
            oml_session_delete "$session_id" "$force"
            ;;

        list|ls)
            local status="${1:-all}"
            local limit="${2:-0}"
            local offset="${3:-0}"
            oml_session_list "$status" "$limit" "$offset"
            ;;

        set)
            oml_session_set "$@"
            ;;

        get-key)
            oml_session_get "$@"
            ;;

        unset)
            oml_session_unset "$@"
            ;;

        exists)
            local session_id="$1"
            local data_path
            data_path="$(oml_session_get_data_path "$session_id")"
            if [[ -f "$data_path" ]]; then
                echo "true"
                exit 0
            else
                echo "false"
                exit 1
            fi
            ;;

        cleanup)
            local dry_run="${1:-false}"
            oml_session_cleanup_expired "$dry_run"
            ;;

        stats)
            oml_session_storage_stats
            ;;

        info)
            local session_id="$1"
            if [[ -z "$session_id" ]]; then
                oml_session_error "Session ID required" 1
            fi
            oml_session_read "$session_id"
            ;;

        help|--help|-h)
            cat <<EOF
OML Session Storage

用法：oml session-storage <action> [args]

动作:
  init                      初始化会话存储
  create [id] [data]        创建新会话
  read <id> [field]         读取会话数据
  update <id> <data> [merge] 更新会话数据
  delete <id> [--force]     删除会话
  list [status] [limit] [offset] 列出所有会话
  set <id> <key> <value>    设置会话数据键值
  get <id> <key> [default]  获取会话数据键值
  unset <id> <key>          删除会话数据键
  exists <id>               检查会话是否存在
  cleanup [--dry-run]       清理过期会话
  stats                     显示存储统计
  info <id>                 显示会话详情

示例:
  oml session-storage create
  oml session-storage create my-session '{"user": "test"}'
  oml session-storage read my-session
  oml session-storage read my-session data.user
  oml session-storage update my-session '{"data": {"key": "value"}}'
  oml session-storage set my-session user.name "John"
  oml session-storage get my-session user.name
  oml session-storage list active
  oml session-storage delete my-session
  oml session-storage stats
  oml session-storage cleanup --dry-run

环境变量:
  OML_SESSIONS_DIR          会话存储目录
  OML_OUTPUT_FORMAT         输出格式 (text|json)
  OML_SESSION_TTL           会话过期时间 (秒，0=永不过期)
  OML_SESSION_MAX_COUNT     最大会话数
EOF
            ;;

        *)
            oml_session_error "Unknown action: ${action}" 1
            echo "Use 'oml session-storage help' for usage"
            return 1
            ;;
    esac
}

# 仅在直接执行时运行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
