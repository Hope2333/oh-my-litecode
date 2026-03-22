#!/usr/bin/env bash
# OML Session Diff
# Diff 功能实现 - 支持会话比较、差异分析和变更追踪

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

# 比较模式
DIFF_MODE_FULL="full"           # 完整比较
DIFF_MODE_MESSAGES="messages"   # 仅比较消息
DIFF_MODE_DATA="data"           # 仅比较数据
DIFF_MODE_CONTEXT="context"     # 仅比较上下文
DIFF_MODE_METADATA="metadata"   # 仅比较元数据

# 输出格式
DIFF_OUTPUT_FORMAT="${OML_OUTPUT_FORMAT:-text}"

# 差异类型
DIFF_TYPE_ADDED="added"
DIFF_TYPE_REMOVED="removed"
DIFF_TYPE_MODIFIED="modified"
DIFF_TYPE_UNCHANGED="unchanged"

# ============================================================================
# 工具函数
# ============================================================================

# 输出错误
oml_session_diff_error() {
    local msg="$1"
    local code="${2:-1}"

    if [[ "${DIFF_OUTPUT_FORMAT}" == "json" ]]; then
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

# 获取当前时间戳
oml_session_diff_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# ============================================================================
# 核心 Diff 功能
# ============================================================================

# 比较两个会话
oml_session_diff() {
    local session_a="$1"
    local session_b="$2"
    local mode="${3:-$DIFF_MODE_FULL}"
    local context_lines="${4:-3}"

    # 验证会话
    for session_id in "$session_a" "$session_b"; do
        if ! oml_session_validate_id "$session_id"; then
            oml_session_diff_error "Invalid session ID: ${session_id}" 1
            return 1
        fi

        local data_path
        data_path="$(oml_session_get_data_path "$session_id")"

        if [[ ! -f "$data_path" ]]; then
            oml_session_diff_error "Session not found: ${session_id}" 1
            return 1
        fi
    done

    local data_a
    data_a="$(oml_session_get_data_path "$session_a")"
    local data_b
    data_b="$(oml_session_get_data_path "$session_b")"

    # 执行比较
    python3 - "${data_a}" "${data_b}" "${mode}" "${context_lines}" <<'PY'
import json
import sys
import difflib
from datetime import datetime

data_path_a = sys.argv[1]
data_path_b = sys.argv[2]
mode = sys.argv[3]
context_lines = int(sys.argv[4]) if len(sys.argv) > 4 else 3

with open(data_path_a, 'r') as f:
    session_a = json.load(f)

with open(data_path_b, 'r') as f:
    session_b = json.load(f)

def compare_messages(msgs_a, msgs_b):
    """比较消息列表"""
    diff = {
        'added': [],
        'removed': [],
        'modified': [],
        'unchanged': []
    }

    # 创建消息映射
    a_by_content = {m.get('content', ''): m for m in msgs_a}
    b_by_content = {m.get('content', ''): m for m in msgs_b}

    # 查找移除的消息
    for content, msg in a_by_content.items():
        if content not in b_by_content:
            diff['removed'].append(msg)
        else:
            # 检查是否修改
            msg_b = b_by_content[content]
            if msg.get('role') != msg_b.get('role'):
                diff['modified'].append({
                    'old': msg,
                    'new': msg_b
                })
            else:
                diff['unchanged'].append(msg)

    # 查找添加的消息
    for content, msg in b_by_content.items():
        if content not in a_by_content:
            diff['added'].append(msg)

    return diff

def compare_dicts(dict_a, dict_b, path=''):
    """递归比较字典"""
    diff = {
        'added': {},
        'removed': {},
        'modified': {}
    }

    all_keys = set(dict_a.keys()) | set(dict_b.keys())

    for key in all_keys:
        current_path = f"{path}.{key}" if path else key

        if key not in dict_a:
            diff['added'][key] = dict_b[key]
        elif key not in dict_b:
            diff['removed'][key] = dict_a[key]
        elif dict_a[key] != dict_b[key]:
            if isinstance(dict_a[key], dict) and isinstance(dict_b[key], dict):
                nested = compare_dicts(dict_a[key], dict_b[key], current_path)
                for k in ['added', 'removed', 'modified']:
                    if nested[k]:
                        diff[k][key] = nested[k]
            else:
                diff['modified'][key] = {
                    'old': dict_a[key],
                    'new': dict_b[key]
                }

    return diff

def format_diff_text(diff, session_a_id, session_b_id):
    """格式化文本输出"""
    output = []
    output.append(f"=== Session Diff ===")
    output.append(f"Session A: {session_a_id}")
    output.append(f"Session B: {session_b_id}")
    output.append(f"Generated: {datetime.utcnow().isoformat()}")
    output.append("")

    # 消息差异
    if 'messages' in diff:
        msg_diff = diff['messages']
        output.append("--- Messages ---")

        if msg_diff['added']:
            output.append(f"\n+ Added ({len(msg_diff['added'])}):")
            for msg in msg_diff['added']:
                role = msg.get('role', 'unknown')
                content = msg.get('content', '')[:100]
                output.append(f"  + [{role}] {content}...")

        if msg_diff['removed']:
            output.append(f"\n- Removed ({len(msg_diff['removed'])}):")
            for msg in msg_diff['removed']:
                role = msg.get('role', 'unknown')
                content = msg.get('content', '')[:100]
                output.append(f"  - [{role}] {content}...")

        if msg_diff['modified']:
            output.append(f"\n~ Modified ({len(msg_diff['modified'])}):")
            for mod in msg_diff['modified']:
                old_role = mod['old'].get('role', 'unknown')
                new_role = mod['new'].get('role', 'unknown')
                output.append(f"  ~ [{old_role} -> {new_role}]")

        output.append("")

    # 数据差异
    if 'data' in diff:
        data_diff = diff['data']
        output.append("--- Data ---")

        if data_diff['added']:
            output.append(f"\n+ Added keys: {list(data_diff['added'].keys())}")

        if data_diff['removed']:
            output.append(f"\n- Removed keys: {list(data_diff['removed'].keys())}")

        if data_diff['modified']:
            output.append(f"\n~ Modified keys: {list(data_diff['modified'].keys())}")
            for key, change in data_diff['modified'].items():
                old_val = str(change['old'])[:50]
                new_val = str(change['new'])[:50]
                output.append(f"    {key}: '{old_val}' -> '{new_val}'")

        output.append("")

    # 上下文差异
    if 'context' in diff:
        ctx_diff = diff['context']
        output.append("--- Context ---")

        if ctx_diff['added']:
            output.append(f"\n+ Added: {list(ctx_diff['added'].keys())}")

        if ctx_diff['removed']:
            output.append(f"\n- Removed: {list(ctx_diff['removed'].keys())}")

        if ctx_diff['modified']:
            output.append(f"\n~ Modified: {list(ctx_diff['modified'].keys())}")

        output.append("")

    # 统计
    output.append("--- Summary ---")
    total_changes = 0
    if 'messages' in diff:
        total_changes += len(diff['messages']['added'])
        total_changes += len(diff['messages']['removed'])
        total_changes += len(diff['messages']['modified'])
    if 'data' in diff:
        total_changes += len(diff['data']['added'])
        total_changes += len(diff['data']['removed'])
        total_changes += len(diff['data']['modified'])

    if total_changes == 0:
        output.append("No changes detected.")
    else:
        output.append(f"Total changes: {total_changes}")

    return '\n'.join(output)

# 执行比较
result = {
    'session_a': session_a.get('session_id'),
    'session_b': session_b.get('session_id'),
    'generated_at': datetime.utcnow().isoformat() + 'Z',
    'mode': mode,
    'diff': {}
}

# 根据模式比较
if mode in ['full', 'messages']:
    msgs_a = session_a.get('messages', [])
    msgs_b = session_b.get('messages', [])
    result['diff']['messages'] = compare_messages(msgs_a, msgs_b)

if mode in ['full', 'data']:
    data_a = session_a.get('data', {})
    data_b = session_b.get('data', {})
    result['diff']['data'] = compare_dicts(data_a, data_b)

if mode in ['full', 'context']:
    ctx_a = session_a.get('context', {})
    ctx_b = session_b.get('context', {})
    result['diff']['context'] = compare_dicts(ctx_a, ctx_b)

if mode in ['full', 'metadata']:
    meta_keys = ['name', 'type', 'status']
    meta_a = {k: session_a.get(k) for k in meta_keys}
    meta_b = {k: session_b.get(k) for k in meta_keys}
    result['diff']['metadata'] = compare_dicts(meta_a, meta_b)

# 输出
output_format = '${DIFF_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps(result, indent=2, ensure_ascii=False))
else:
    print(format_diff_text(result['diff'], result['session_a'], result['session_b']))
PY
}

# ============================================================================
# 会话历史比较
# ============================================================================

# 比较会话的两个版本（如果有版本历史）
oml_session_diff_versions() {
    local session_id="$1"
    local version_a="${2:-}"
    local version_b="${3:-}"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_diff_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_diff_error "Session not found: ${session_id}" 1
        return 1
    fi

    # 检查是否有版本历史
    python3 -c "
import json
import sys

with open('${data_path}', 'r') as f:
    data = json.load(f)

versions = data.get('versions', [])
if not versions:
    print('No version history available')
    sys.exit(1)

print('Available versions:')
for v in versions:
    print(f\"  {v.get('version', 'unknown')} - {v.get('timestamp', 'unknown')}\")
"
}

# ============================================================================
# Fork 差异比较
# ============================================================================

# 比较 Fork 与父会话
oml_session_diff_fork() {
    local fork_id="$1"
    local mode="${2:-$DIFF_MODE_MESSAGES}"

    if ! oml_session_validate_id "$fork_id"; then
        oml_session_diff_error "Invalid fork ID: ${fork_id}" 1
        return 1
    fi

    local fork_data_path
    fork_data_path="$(oml_session_get_data_path "$fork_id")"

    if [[ ! -f "$fork_data_path" ]]; then
        oml_session_diff_error "Fork not found: ${fork_id}" 1
        return 1
    fi

    # 获取父会话 ID
    local parent_id
    parent_id=$(python3 -c "
import json
with open('${fork_data_path}', 'r') as f:
    data = json.load(f)
fork_info = data.get('fork_info', {})
print(fork_info.get('parent_id', data.get('parent_id', '')))
")

    if [[ -z "$parent_id" ]]; then
        oml_session_diff_error "Fork has no parent: ${fork_id}" 1
        return 1
    fi

    # 执行比较
    oml_session_diff "$parent_id" "$fork_id" "$mode"
}

# ============================================================================
# 变更统计
# ============================================================================

# 获取会话变更统计
oml_session_diff_stats() {
    local session_id="$1"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_diff_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_diff_error "Session not found: ${session_id}" 1
        return 1
    fi

    python3 - "${data_path}" <<'PY'
import json
import sys

data_path = sys.argv[1]

with open(data_path, 'r') as f:
    data = json.load(f)

messages = data.get('messages', [])
data_content = data.get('data', {})
context = data.get('context', {})

# 按角色统计消息
by_role = {}
for msg in messages:
    role = msg.get('role', 'unknown')
    by_role[role] = by_role.get(role, 0) + 1

# 计算令牌数（估算）
total_tokens = sum(len(msg.get('content', '')) // 4 for msg in messages)

output_format = '${DIFF_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'session_id': data.get('session_id'),
        'message_count': len(messages),
        'by_role': by_role,
        'data_keys': len(data_content),
        'context_keys': len(context),
        'estimated_tokens': total_tokens,
        'created_at': data.get('created_at'),
        'updated_at': data.get('updated_at')
    }, indent=2))
else:
    print("=== Session Statistics ===")
    print(f"Session ID: {data.get('session_id')}")
    print(f"Total Messages: {len(messages)}")
    print("")
    print("By Role:")
    for role, count in sorted(by_role.items()):
        print(f"  {role}: {count}")
    print("")
    print(f"Data Keys: {len(data_content)}")
    print(f"Context Keys: {len(context)}")
    print(f"Estimated Tokens: {total_tokens}")
PY
}

# ============================================================================
# 消息级 Diff
# ============================================================================

# 比较两条消息
oml_session_diff_messages() {
    local msg_a="$1"
    local msg_b="$2"

    python3 - "${msg_a}" "${msg_b}" <<'PY'
import json
import sys
import difflib

msg_a_path = sys.argv[1]
msg_b_path = sys.argv[2]

# 尝试解析为 JSON 或文件路径
def load_message(path):
    try:
        # 尝试作为 JSON
        return json.loads(path)
    except:
        # 尝试作为文件
        try:
            with open(path, 'r') as f:
                return json.load(f)
        except:
            return {'content': path}

msg_a = load_message(msg_a_path)
msg_b = load_message(msg_b_path)

content_a = msg_a.get('content', '')
content_b = msg_b.get('content', '')

# 生成差异
diff = list(difflib.unified_diff(
    content_a.splitlines(keepends=True),
    content_b.splitlines(keepends=True),
    fromfile='message_a',
    tofile='message_b',
    n=3
))

output_format = '${DIFF_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'message_a_length': len(content_a),
        'message_b_length': len(content_b),
        'diff_lines': diff,
        'is_identical': content_a == content_b
    }, indent=2))
else:
    if content_a == content_b:
        print("Messages are identical")
    else:
        print("=== Message Diff ===")
        print('\n'.join(diff))
PY
}

# ============================================================================
# 批量比较
# ============================================================================

# 批量比较多个会话
oml_session_diff_batch() {
    local session_ids="$1"  # 逗号分隔的会话 ID 列表
    local mode="${2:-$DIFF_MODE_MESSAGES}"

    IFS=',' read -ra ids <<< "$session_ids"

    if [[ ${#ids[@]} -lt 2 ]]; then
        oml_session_diff_error "At least 2 session IDs required for batch diff" 1
        return 1
    fi

    # 两两比较
    local results=()
    for ((i=0; i<${#ids[@]}; i++)); do
        for ((j=i+1; j<${#ids[@]}; j++)); do
            local result
            result=$(oml_session_diff "${ids[$i]}" "${ids[$j]}" "$mode" 2>/dev/null)
            results+=("{\"pair\": [\"${ids[$i]}\", \"${ids[$j]}\"], \"diff\": $result}")
        done
    done

    if [[ "${DIFF_OUTPUT_FORMAT}" == "json" ]]; then
        echo "["
        local first=true
        for result in "${results[@]}"; do
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo "$result"
        done
        echo "]"
    else
        for result in "${results[@]}"; do
            echo "$result"
            echo ""
            echo "---"
            echo ""
        done
    fi
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
        diff|compare)
            local session_a="$1"
            local session_b="$2"
            local mode="${3:-full}"
            local context="${4:-3}"
            oml_session_diff "$session_a" "$session_b" "$mode" "$context"
            ;;

        fork)
            local fork_id="$1"
            local mode="${2:-messages}"
            oml_session_diff_fork "$fork_id" "$mode"
            ;;

        versions)
            local session_id="$1"
            local version_a="${2:-}"
            local version_b="${3:-}"
            oml_session_diff_versions "$session_id" "$version_a" "$version_b"
            ;;

        messages)
            local msg_a="$1"
            local msg_b="$2"
            oml_session_diff_messages "$msg_a" "$msg_b"
            ;;

        stats)
            local session_id="$1"
            oml_session_diff_stats "$session_id"
            ;;

        batch)
            local session_ids="$1"
            local mode="${2:-messages}"
            oml_session_diff_batch "$session_ids" "$mode"
            ;;

        help|--help|-h)
            cat <<EOF
OML Session Diff

用法：oml session-diff <action> [args]

动作:
  diff <session_a> <session_b> [mode] [context]  比较两个会话
  fork <fork_id> [mode]                         比较 Fork 与父会话
  versions <session_id> [v1] [v2]               比较会话版本
  messages <msg_a> <msg_b>                      比较两条消息
  stats <session_id>                            显示会话统计
  batch <ids> [mode]                            批量比较

比较模式:
  full       完整比较（默认）
  messages   仅比较消息
  data       仅比较数据
  context    仅比较上下文
  metadata   仅比较元数据

输出格式:
  通过 OML_OUTPUT_FORMAT 环境变量控制 (text|json)

示例:
  oml session-diff diff session-a session-b
  oml session-diff diff session-a session-b messages
  OML_OUTPUT_FORMAT=json oml session-diff diff session-a session-b
  oml session-diff fork fork-123
  oml session-diff stats session-123
  oml session-diff batch "session-a,session-b,session-c"

环境变量:
  OML_OUTPUT_FORMAT    输出格式 (text|json)
  DIFF_OUTPUT_FORMAT   Diff 输出格式 (text|json)
EOF
            ;;

        *)
            oml_session_diff_error "Unknown action: ${action}" 1
            echo "Use 'oml session-diff help' for usage"
            return 1
            ;;
    esac
}

# 仅在直接执行时运行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
