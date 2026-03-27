#!/usr/bin/env bash
# DEPRECATED: Migrated to TypeScript (packages/core/src/session/manager.ts)
# Archive Date: 2026-03-26
# Use: @oml/core SessionManager instead

# OML Session Fork
# Fork 功能实现 - 支持会话分支、复制和派生

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

# ============================================================================
# 配置与常量
# ============================================================================

# Fork 策略
FORK_STRATEGY_FULL="full"       # 完整复制
FORK_STRATEGY_SHALLOW="shallow" # 浅复制（仅元数据）
FORK_STRATEGY_CHECKPOINT="checkpoint" # 从检查点复制

# 输出格式
OML_OUTPUT_FORMAT="${OML_OUTPUT_FORMAT:-text}"

# ============================================================================
# 工具函数
# ============================================================================

# 输出错误
oml_session_fork_error() {
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

# 生成 Fork ID
oml_session_fork_generate_id() {
    local parent_id="$1"
    echo "fork-$(date +%s)-$$-${RANDOM}"
}

# 获取当前时间戳
oml_session_fork_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# ============================================================================
# Fork 核心功能
# ============================================================================

# Fork 会话
oml_session_fork() {
    local parent_id="$1"
    local name="${2:-}"
    local strategy="${3:-$FORK_STRATEGY_FULL}"
    local checkpoint="${4:-}"

    # 验证父会话
    if ! oml_session_validate_id "$parent_id"; then
        oml_session_fork_error "Invalid parent session ID: ${parent_id}" 1
        return 1
    fi

    local parent_data_path
    parent_data_path="$(oml_session_get_data_path "$parent_id")"

    if [[ ! -f "$parent_data_path" ]]; then
        oml_session_fork_error "Parent session not found: ${parent_id}" 1
        return 1
    fi

    # 生成新会话 ID
    local fork_id
    fork_id="$(oml_session_fork_generate_id "$parent_id")"

    local timestamp
    timestamp="$(oml_session_fork_timestamp)"

    # 根据策略执行 Fork
    case "$strategy" in
        full)
            oml_session_fork_full "$parent_id" "$fork_id" "$name" "$timestamp"
            ;;
        shallow)
            oml_session_fork_shallow "$parent_id" "$fork_id" "$name" "$timestamp"
            ;;
        checkpoint)
            if [[ -z "$checkpoint" ]]; then
                oml_session_fork_error "Checkpoint required for checkpoint strategy" 1
                return 1
            fi
            oml_session_fork_checkpoint "$parent_id" "$fork_id" "$name" "$checkpoint" "$timestamp"
            ;;
        *)
            oml_session_fork_error "Unknown fork strategy: ${strategy}" 1
            return 1
            ;;
    esac

    # 更新父会话的 forks 列表
    oml_session_fork_update_parent "$parent_id" "$fork_id"

    # 输出结果
    if [[ "${OML_OUTPUT_FORMAT}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'fork_id': '${fork_id}',
    'parent_id': '${parent_id}',
    'name': '${name}',
    'strategy': '${strategy}',
    'created_at': '${timestamp}',
    'status': 'active'
}, indent=2))
"
    else
        echo "Forked session: ${fork_id}"
        echo "Parent: ${parent_id}"
        echo "Strategy: ${strategy}"
        echo "Name: ${name:-unnamed}"
    fi

    echo "$fork_id"
}

# 完整 Fork（复制所有数据）
oml_session_fork_full() {
    local parent_id="$1"
    local fork_id="$2"
    local name="$3"
    local timestamp="$4"

    local parent_data_path
    parent_data_path="$(oml_session_get_data_path "$parent_id")"
    local fork_data_path
    fork_data_path="$(oml_session_get_data_path "$fork_id")"
    local fork_meta_path
    fork_meta_path="$(oml_session_get_meta_path "$fork_id")"

    # 复制并修改数据
    python3 - "${parent_data_path}" "${fork_data_path}" "${fork_id}" "${name}" "${parent_id}" "${timestamp}" <<'PY'
import json
import sys

parent_path = sys.argv[1]
fork_path = sys.argv[2]
fork_id = sys.argv[3]
name = sys.argv[4]
parent_id = sys.argv[5]
timestamp = sys.argv[6]

with open(parent_path, 'r') as f:
    data = json.load(f)

# 创建 fork 数据
fork_data = {
    'session_id': fork_id,
    'name': name if name else data.get('name', '') + ' (fork)',
    'type': 'fork',
    'parent_id': parent_id,
    'status': 'pending',
    'created_at': timestamp,
    'updated_at': timestamp,
    'fork_info': {
        'parent_id': parent_id,
        'forked_at': timestamp,
        'strategy': 'full',
        'branch_point': len(data.get('messages', []))
    },
    'metadata': data.get('metadata', {}),
    'data': data.get('data', {}),
    'messages': list(data.get('messages', [])),  # 完整复制消息
    'context': data.get('context', {})
}

with open(fork_path, 'w') as f:
    json.dump(fork_data, f, indent=2, ensure_ascii=False)
PY

    # 创建元数据
    cat > "$fork_meta_path" <<EOF
session_id=${fork_id}
parent_id=${parent_id}
created_at=${timestamp}
updated_at=${timestamp}
status=active
type=fork
strategy=full
size=$(wc -c < "$fork_data_path")
EOF

    # 更新索引
    oml_session_update_index "$fork_id" "add" "$(cat "$fork_data_path")"
}

# 浅 Fork（仅复制元数据）
oml_session_fork_shallow() {
    local parent_id="$1"
    local fork_id="$2"
    local name="$3"
    local timestamp="$4"

    local parent_data_path
    parent_data_path="$(oml_session_get_data_path "$parent_id")"
    local fork_data_path
    fork_data_path="$(oml_session_get_data_path "$fork_id")"
    local fork_meta_path
    fork_meta_path="$(oml_session_get_meta_path "$fork_id")"

    # 创建浅 fork 数据
    python3 - "${parent_data_path}" "${fork_data_path}" "${fork_id}" "${name}" "${parent_id}" "${timestamp}" <<'PY'
import json
import sys

parent_path = sys.argv[1]
fork_path = sys.argv[2]
fork_id = sys.argv[3]
name = sys.argv[4]
parent_id = sys.argv[5]
timestamp = sys.argv[6]

with open(parent_path, 'r') as f:
    data = json.load(f)

# 创建浅 fork 数据（仅复制元数据，不复制消息）
fork_data = {
    'session_id': fork_id,
    'name': name if name else data.get('name', '') + ' (shallow-fork)',
    'type': 'fork',
    'parent_id': parent_id,
    'status': 'pending',
    'created_at': timestamp,
    'updated_at': timestamp,
    'fork_info': {
        'parent_id': parent_id,
        'forked_at': timestamp,
        'strategy': 'shallow',
        'branch_point': 0
    },
    'metadata': data.get('metadata', {}),
    'data': data.get('data', {}),
    'messages': [],  # 不复制消息
    'context': {}  # 不复制上下文
}

with open(fork_path, 'w') as f:
    json.dump(fork_data, f, indent=2, ensure_ascii=False)
PY

    # 创建元数据
    cat > "$fork_meta_path" <<EOF
session_id=${fork_id}
parent_id=${parent_id}
created_at=${timestamp}
updated_at=${timestamp}
status=active
type=fork
strategy=shallow
size=$(wc -c < "$fork_data_path")
EOF

    # 更新索引
    oml_session_update_index "$fork_id" "add" "$(cat "$fork_data_path")"
}

# 从检查点 Fork
oml_session_fork_checkpoint() {
    local parent_id="$1"
    local fork_id="$2"
    local name="$3"
    local checkpoint="$4"
    local timestamp="$5"

    local parent_data_path
    parent_data_path="$(oml_session_get_data_path "$parent_id")"
    local fork_data_path
    fork_data_path="$(oml_session_get_data_path "$fork_id")"
    local fork_meta_path
    fork_meta_path="$(oml_session_get_meta_path "$fork_id")"

    # 从检查点创建 fork
    python3 - "${parent_data_path}" "${fork_data_path}" "${fork_id}" "${name}" "${parent_id}" "${checkpoint}" "${timestamp}" <<'PY'
import json
import sys

parent_path = sys.argv[1]
fork_path = sys.argv[2]
fork_id = sys.argv[3]
name = sys.argv[4]
parent_id = sys.argv[5]
checkpoint = sys.argv[6]
timestamp = sys.argv[7]

with open(parent_path, 'r') as f:
    data = json.load(f)

messages = data.get('messages', [])

# 解析检查点（可以是消息索引或消息 ID）
try:
    checkpoint_idx = int(checkpoint)
    branch_point = checkpoint_idx
    fork_messages = messages[:checkpoint_idx]
except ValueError:
    # 尝试按消息 ID 查找
    branch_point = 0
    fork_messages = []
    for i, msg in enumerate(messages):
        if msg.get('id') == checkpoint or msg.get('timestamp') == checkpoint:
            branch_point = i
            fork_messages = messages[:i]
            break

# 创建 fork 数据
fork_data = {
    'session_id': fork_id,
    'name': name if name else data.get('name', '') + f' (checkpoint@{branch_point})',
    'type': 'fork',
    'parent_id': parent_id,
    'status': 'pending',
    'created_at': timestamp,
    'updated_at': timestamp,
    'fork_info': {
        'parent_id': parent_id,
        'forked_at': timestamp,
        'strategy': 'checkpoint',
        'branch_point': branch_point,
        'checkpoint': checkpoint
    },
    'metadata': data.get('metadata', {}),
    'data': data.get('data', {}),
    'messages': fork_messages,
    'context': data.get('context', {})
}

with open(fork_path, 'w') as f:
    json.dump(fork_data, f, indent=2, ensure_ascii=False)
PY

    # 创建元数据
    cat > "$fork_meta_path" <<EOF
session_id=${fork_id}
parent_id=${parent_id}
created_at=${timestamp}
updated_at=${timestamp}
status=active
type=fork
strategy=checkpoint
checkpoint=${checkpoint}
size=$(wc -c < "$fork_data_path")
EOF

    # 更新索引
    oml_session_update_index "$fork_id" "add" "$(cat "$fork_data_path")"
}

# 更新父会话的 forks 列表
oml_session_fork_update_parent() {
    local parent_id="$1"
    local fork_id="$2"

    local parent_data_path
    parent_data_path="$(oml_session_get_data_path "$parent_id")"

    if [[ ! -f "$parent_data_path" ]]; then
        return 0
    fi

    python3 - "${parent_data_path}" "${fork_id}" <<'PY'
import json
import sys
from datetime import datetime

data_path = sys.argv[1]
fork_id = sys.argv[2]

with open(data_path, 'r') as f:
    data = json.load(f)

if 'forks' not in data:
    data['forks'] = []

data['forks'].append({
    'fork_id': fork_id,
    'forked_at': datetime.utcnow().isoformat() + 'Z'
})

data['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(data_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
}

# ============================================================================
# Fork 管理
# ============================================================================

# 列出会话的所有 Fork
oml_session_fork_list() {
    local parent_id="$1"

    if ! oml_session_validate_id "$parent_id"; then
        oml_session_fork_error "Invalid session ID: ${parent_id}" 1
        return 1
    fi

    local parent_data_path
    parent_data_path="$(oml_session_get_data_path "$parent_id")"

    if [[ ! -f "$parent_data_path" ]]; then
        oml_session_fork_error "Session not found: ${parent_id}" 1
        return 1
    fi

    python3 - "${parent_data_path}" "${OML_SESSIONS_DATA_DIR}" <<'PY'
import json
import sys
import os
import glob

data_path = sys.argv[1]
sessions_dir = sys.argv[2]

with open(data_path, 'r') as f:
    data = json.load(f)

forks = data.get('forks', [])

# 获取每个 fork 的详细信息
result = []
for fork_info in forks:
    fork_id = fork_info.get('fork_id')
    fork_path = os.path.join(sessions_dir, 'data', f"{fork_id}.json")

    fork_detail = dict(fork_info)

    if os.path.exists(fork_path):
        with open(fork_path, 'r') as f:
            fork_data = json.load(f)
        fork_detail['name'] = fork_data.get('name', '')
        fork_detail['status'] = fork_data.get('status', 'unknown')
        fork_detail['updated_at'] = fork_data.get('updated_at', '')
    else:
        fork_detail['status'] = 'missing'

    result.append(fork_detail)

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'parent_id': '${parent_id}',
        'fork_count': len(result),
        'forks': result
    }, indent=2))
else:
    print(f"Forks of session: ${parent_id}")
    print(f"{'FORK_ID':<36} {'NAME':<20} {'STATUS':<10} {'FORKED_AT'}")
    print("=" * 80)
    for fork in result:
        name = fork.get('name', 'unnamed')[:18]
        status = fork.get('status', 'unknown')[:8]
        forked_at = fork.get('forked_at', 'unknown')[:10]
        print(f"{fork.get('fork_id', 'unknown'):<36} {name:<20} {status:<10} {forked_at}")
    print(f"\nTotal: {len(result)} forks")
PY
}

# 获取 Fork 树
oml_session_fork_tree() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        # 获取所有根会话（没有 parent_id 的会话）
        session_id=""
    fi

    python3 - "${OML_SESSIONS_DATA_DIR}" "${session_id}" <<'PY'
import json
import sys
import os
import glob

sessions_dir = sys.argv[1]
root_id = sys.argv[2] if len(sys.argv) > 2 else None

# 加载所有会话
sessions = {}
for data_file in glob.glob(os.path.join(sessions_dir, 'data', '*.json')):
    try:
        with open(data_file, 'r') as f:
            data = json.load(f)
        sessions[data.get('session_id')] = data
    except:
        pass

# 构建父子关系
children = {}
for session_id, data in sessions.items():
    parent_id = data.get('parent_id')
    if parent_id:
        if parent_id not in children:
            children[parent_id] = []
        children[parent_id].append(data)

def print_tree(session_data, indent=0):
    prefix = "  " * indent
    session_id = session_data.get('session_id', 'unknown')
    name = session_data.get('name', 'unnamed')
    type_ = session_data.get('type', 'default')
    status = session_data.get('status', 'unknown')

    icon = "🌿" if session_id in children else "🍃"
    print(f"{prefix}{icon} {session_id[:20]}... | {name[:20]} | {type_} | {status}")

    if session_id in children:
        for child in children[session_id]:
            print_tree(child, indent + 1)

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    def build_tree(session_id):
        if session_id not in sessions:
            return None

        data = sessions[session_id]
        result = dict(data)
        result['children'] = []

        if session_id in children:
            for child in children[session_id]:
                child_tree = build_tree(child.get('session_id'))
                if child_tree:
                    result['children'].append(child_tree)

        return result

    if root_id:
        tree = build_tree(root_id)
        print(json.dumps(tree, indent=2))
    else:
        # 返回所有根节点
        roots = [s for s in sessions.values() if not s.get('parent_id')]
        result = [build_tree(s.get('session_id')) for s in roots]
        print(json.dumps(result, indent=2))
else:
    print("=== Session Fork Tree ===")
    print("")

    if root_id:
        if root_id in sessions:
            print_tree(sessions[root_id])
        else:
            print(f"Session not found: {root_id}")
    else:
        # 打印所有根节点
        roots = [s for s in sessions.values() if not s.get('parent_id')]
        for root in roots[:10]:  # 限制显示数量
            print_tree(root)
        if len(roots) > 10:
            print(f"... and {len(roots) - 10} more root sessions")
PY
}

# 合并 Fork 回父会话
oml_session_fork_merge() {
    local fork_id="$1"
    local strategy="${2:-append}"  # append, replace, selective

    if ! oml_session_validate_id "$fork_id"; then
        oml_session_fork_error "Invalid fork ID: ${fork_id}" 1
        return 1
    fi

    local fork_data_path
    fork_data_path="$(oml_session_get_data_path "$fork_id")"

    if [[ ! -f "$fork_data_path" ]]; then
        oml_session_fork_error "Fork session not found: ${fork_id}" 1
        return 1
    fi

    # 获取父会话 ID
    local parent_id
    parent_id=$(python3 -c "
import json
with open('${fork_data_path}', 'r') as f:
    data = json.load(f)
print(data.get('fork_info', {}).get('parent_id', data.get('parent_id', '')))
")

    if [[ -z "$parent_id" ]]; then
        oml_session_fork_error "Fork has no parent: ${fork_id}" 1
        return 1
    fi

    local parent_data_path
    parent_data_path="$(oml_session_get_data_path "$parent_id")"

    if [[ ! -f "$parent_data_path" ]]; then
        oml_session_fork_error "Parent session not found: ${parent_id}" 1
        return 1
    fi

    # 执行合并
    python3 - "${parent_data_path}" "${fork_data_path}" "${strategy}" <<'PY'
import json
import sys
from datetime import datetime

parent_path = sys.argv[1]
fork_path = sys.argv[2]
strategy = sys.argv[3]

with open(parent_path, 'r') as f:
    parent = json.load(f)

with open(fork_path, 'r') as f:
    fork = json.load(f)

fork_info = fork.get('fork_info', {})
branch_point = fork_info.get('branch_point', 0)

if strategy == 'append':
    # 追加 fork 中的新消息
    parent_messages = parent.get('messages', [])
    fork_messages = fork.get('messages', [])

    # 只添加 branch_point 之后的消息
    new_messages = fork_messages[branch_point:]
    parent['messages'].extend(new_messages)

elif strategy == 'replace':
    # 用 fork 的消息替换 branch_point 之后的消息
    parent_messages = parent.get('messages', [])
    fork_messages = fork.get('messages', [])

    parent['messages'] = parent_messages[:branch_point] + fork_messages[branch_point:]

elif strategy == 'selective':
    # 选择性合并（需要 metadata 指定）
    selective_keys = fork.get('metadata', {}).get('selective_merge', [])
    for key in selective_keys:
        if key in fork.get('data', {}):
            parent.setdefault('data', {})[key] = fork['data'][key]

parent['updated_at'] = datetime.utcnow().isoformat() + 'Z'
parent['forks'] = parent.get('forks', [])
for f in parent['forks']:
    if f.get('fork_id') == fork.get('session_id'):
        f['merged_at'] = datetime.utcnow().isoformat() + 'Z'
        f['merged'] = True

with open(parent_path, 'w') as f:
    json.dump(parent, f, indent=2, ensure_ascii=False)

print(f"Merged fork {fork.get('session_id')} into parent {parent.get('session_id')}")
PY

    oml_session_text_output "Merged fork: ${fork_id} -> ${parent_id}"
}

# 删除 Fork
oml_session_fork_delete() {
    local fork_id="$1"
    local force="${2:-false}"

    if ! oml_session_validate_id "$fork_id"; then
        oml_session_fork_error "Invalid fork ID: ${fork_id}" 1
        return 1
    fi

    local fork_data_path
    fork_data_path="$(oml_session_get_data_path "$fork_id")"

    if [[ ! -f "$fork_data_path" ]]; then
        if [[ "$force" == "true" ]]; then
            oml_session_text_output "Fork not found (forced delete): ${fork_id}"
            return 0
        else
            oml_session_fork_error "Fork not found: ${fork_id}" 1
            return 1
        fi
    fi

    # 获取父会话 ID
    local parent_id
    parent_id=$(python3 -c "
import json
with open('${fork_data_path}', 'r') as f:
    data = json.load(f)
print(data.get('fork_info', {}).get('parent_id', data.get('parent_id', '')))
")

    # 删除会话
    oml_session_delete "$fork_id" "$force"

    # 从父会话的 forks 列表中移除
    if [[ -n "$parent_id" ]]; then
        local parent_data_path
        parent_data_path="$(oml_session_get_data_path "$parent_id")"

        if [[ -f "$parent_data_path" ]]; then
            python3 - "${parent_data_path}" "${fork_id}" <<'PY'
import json
import sys

data_path = sys.argv[1]
fork_id = sys.argv[2]

with open(data_path, 'r') as f:
    data = json.load(f)

if 'forks' in data:
    data['forks'] = [f for f in data['forks'] if f.get('fork_id') != fork_id]

with open(data_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
        fi
    fi

    oml_session_text_output "Deleted fork: ${fork_id}"
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
        fork|create)
            local parent_id="$1"
            local name="${2:-}"
            local strategy="${3:-full}"
            local checkpoint="${4:-}"
            oml_session_fork "$parent_id" "$name" "$strategy" "$checkpoint"
            ;;

        list)
            local parent_id="$1"
            if [[ -z "$parent_id" ]]; then
                oml_session_fork_error "Parent session ID required" 1
            fi
            oml_session_fork_list "$parent_id"
            ;;

        tree)
            local session_id="${1:-}"
            oml_session_fork_tree "$session_id"
            ;;

        merge)
            local fork_id="$1"
            local strategy="${2:-append}"
            oml_session_fork_merge "$fork_id" "$strategy"
            ;;

        delete|remove)
            local fork_id="$1"
            local force="${2:-false}"
            oml_session_fork_delete "$fork_id" "$force"
            ;;

        info)
            local fork_id="$1"
            if [[ -z "$fork_id" ]]; then
                oml_session_fork_error "Fork ID required" 1
            fi
            oml_session_read "$fork_id"
            ;;

        help|--help|-h)
            cat <<EOF
OML Session Fork

用法：oml session-fork <action> [args]

动作:
  fork <parent_id> [name] [strategy] [checkpoint]  创建会话分支
  list <parent_id>                                列出所有分支
  tree [session_id]                               显示分支树
  merge <fork_id> [strategy]                      合并分支回父会话
  delete <fork_id> [--force]                      删除分支
  info <fork_id>                                  显示分支信息

Fork 策略:
  full        完整复制所有数据和消息
  shallow     浅复制，仅复制元数据
  checkpoint  从指定检查点复制

示例:
  oml session-fork fork session-123 "Alternative approach" full
  oml session-fork fork session-123 "From checkpoint" checkpoint 5
  oml session-fork list session-123
  oml session-fork tree
  oml session-fork merge fork-456 append
  oml session-fork delete fork-456

环境变量:
  OML_OUTPUT_FORMAT    输出格式 (text|json)
EOF
            ;;

        *)
            oml_session_fork_error "Unknown action: ${action}" 1
            echo "Use 'oml session-fork help' for usage"
            return 1
            ;;
    esac
}

# 仅在直接执行时运行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
