#!/usr/bin/env bash
# OML Session Share
# Share/Unshare 功能实现 - 支持会话共享、导出和导入

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

# 共享级别
SHARE_LEVEL_PUBLIC="public"     # 完全公开
SHARE_LEVEL_LINK="link"         # 仅链接访问
SHARE_LEVEL_PRIVATE="private"   # 仅自己
SHARE_LEVEL_USER="user"         # 指定用户

# 导出格式
EXPORT_FORMAT_JSON="json"
EXPORT_FORMAT_MARKDOWN="markdown"
EXPORT_FORMAT_TEXT="text"

# 输出格式
OML_OUTPUT_FORMAT="${OML_OUTPUT_FORMAT:-text}"

# 共享索引文件
OML_SHARES_INDEX="${OML_SESSIONS_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/sessions}/shares.json"

# ============================================================================
# 工具函数
# ============================================================================

# 输出错误
oml_session_share_error() {
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

# 生成共享令牌
oml_session_share_generate_token() {
    python3 -c "
import secrets
import hashlib
import time

token = secrets.token_urlsafe(32)
timestamp = str(int(time.time()))
token_id = hashlib.sha256((token + timestamp).encode()).hexdigest()[:16]
print(f'share-{token_id}')
"
}

# 生成共享链接
oml_session_share_generate_link() {
    local session_id="$1"
    local token="$2"
    echo "oml://session/${session_id}?share=${token}"
}

# 获取当前时间戳
oml_session_share_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# 初始化共享索引
oml_session_share_init_index() {
    if [[ ! -f "${OML_SHARES_INDEX}" ]]; then
        cat > "${OML_SHARES_INDEX}" <<'EOF'
{
  "shares": {},
  "metadata": {
    "created_at": "",
    "updated_at": ""
  }
}
EOF
    fi
}

# ============================================================================
# 共享功能
# ============================================================================

# 共享会话
oml_session_share() {
    local session_id="$1"
    local level="${2:-$SHARE_LEVEL_LINK}"
    local expiry="${3:-0}"  # 过期时间（秒），0 表示永不过期
    local users="${4:-}"    # 逗号分隔的用户列表（user 级别时使用）

    # 验证会话
    if ! oml_session_validate_id "$session_id"; then
        oml_session_share_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_share_error "Session not found: ${session_id}" 1
        return 1
    fi

    # 初始化共享索引
    oml_session_share_init_index

    # 生成共享令牌
    local share_token
    share_token="$(oml_session_share_generate_token)"

    local timestamp
    timestamp="$(oml_session_share_timestamp)"

    # 计算过期时间
    local expires_at="null"
    if [[ "$expiry" -gt 0 ]]; then
        expires_at=$(python3 -c "
from datetime import datetime, timedelta
import sys
expiry_seconds = int(sys.argv[1])
expires = datetime.utcnow() + timedelta(seconds=expiry_seconds)
print(expires.isoformat() + 'Z')
" "$expiry")
    fi

    # 添加共享记录
    python3 - "${OML_SHARES_INDEX}" "${session_id}" "${share_token}" "${level}" "${expires_at}" "${users}" "${timestamp}" <<'PY'
import json
import sys

index_path = sys.argv[1]
session_id = sys.argv[2]
share_token = sys.argv[3]
level = sys.argv[4]
expires_at = sys.argv[5]
users = sys.argv[6]
timestamp = sys.argv[7]

with open(index_path, 'r') as f:
    data = json.load(f)

# 解析过期时间
if expires_at == 'null':
    expires_at = None

# 解析用户列表
allowed_users = None
if users:
    allowed_users = [u.strip() for u in users.split(',')]

share_info = {
    'session_id': session_id,
    'token': share_token,
    'level': level,
    'created_at': timestamp,
    'expires_at': expires_at,
    'allowed_users': allowed_users,
    'access_count': 0,
    'last_accessed': None,
    'active': True
}

data['shares'][share_token] = share_info
data['metadata']['updated_at'] = timestamp

with open(index_path, 'w') as f:
    json.dump(data, f, indent=2)

print(share_token)
PY

    # 生成共享链接
    local share_link
    share_link="$(oml_session_share_generate_link "$session_id" "$share_token")"

    # 输出结果
    if [[ "${OML_OUTPUT_FORMAT}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'share_token': '${share_token}',
    'level': '${level}',
    'share_link': '${share_link}',
    'expires_at': $(if [[ "$expiry" -gt 0 ]]; then echo "'${expires_at}'"; else echo "null"; fi),
    'created_at': '${timestamp}'
}, indent=2))
"
    else
        echo "Shared session: ${session_id}"
        echo "Level: ${level}"
        echo "Share Token: ${share_token}"
        echo "Share Link: ${share_link}"
        if [[ "$expiry" -gt 0 ]]; then
            echo "Expires: ${expires_at}"
        else
            echo "Expires: Never"
        fi
    fi

    echo "$share_token"
}

# 取消共享
oml_session_unshare() {
    local session_id="$1"
    local token="${2:-}"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_share_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    if [[ ! -f "${OML_SHARES_INDEX}" ]]; then
        oml_session_share_error "No shares found" 1
        return 1
    fi

    python3 - "${OML_SHARES_INDEX}" "${session_id}" "${token}" <<'PY'
import json
import sys
from datetime import datetime

index_path = sys.argv[1]
session_id = sys.argv[2]
token = sys.argv[3]

with open(index_path, 'r') as f:
    data = json.load(f)

removed = []

if token:
    # 移除指定 token
    if token in data['shares']:
        share = data['shares'][token]
        if share.get('session_id') == session_id:
            share['active'] = False
            share['revoked_at'] = datetime.utcnow().isoformat() + 'Z'
            removed.append(token)
else:
    # 移除会话的所有共享
    for t, share in list(data['shares'].items()):
        if share.get('session_id') == session_id:
            share['active'] = False
            share['revoked_at'] = datetime.utcnow().isoformat() + 'Z'
            removed.append(t)

data['metadata']['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(index_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Unshared {len(removed)} share(s)")
for t in removed:
    print(f"  - {t}")
PY
}

# 验证共享访问
oml_session_share_verify() {
    local token="$1"
    local user="${2:-}"

    if [[ ! -f "${OML_SHARES_INDEX}" ]]; then
        return 1
    fi

    python3 - "${OML_SHARES_INDEX}" "${token}" "${user}" <<'PY'
import json
import sys
from datetime import datetime

index_path = sys.argv[1]
token = sys.argv[2]
user = sys.argv[3] if len(sys.argv) > 3 else None

with open(index_path, 'r') as f:
    data = json.load(f)

if token not in data['shares']:
    print("invalid")
    sys.exit(1)

share = data['shares'][token]

# 检查是否激活
if not share.get('active', True):
    print("revoked")
    sys.exit(1)

# 检查过期
expires_at = share.get('expires_at')
if expires_at:
    try:
        expires = datetime.fromisoformat(expires_at.replace('Z', '+00:00'))
        if datetime.utcnow() > expires:
            print("expired")
            sys.exit(1)
    except:
        pass

# 检查用户权限
level = share.get('level', 'private')
if level == 'user':
    allowed_users = share.get('allowed_users', [])
    if user and user in allowed_users:
        pass  # 允许
    else:
        print("unauthorized")
        sys.exit(1)

# 验证通过，更新访问计数
share['access_count'] = share.get('access_count', 0) + 1
share['last_accessed'] = datetime.utcnow().isoformat() + 'Z'

with open(index_path, 'w') as f:
    json.dump(data, f, indent=2)

print("valid")
print(share.get('session_id'))
sys.exit(0)
PY
}

# 列出共享
oml_session_share_list() {
    local session_id="${1:-}"
    local active_only="${2:-true}"

    if [[ ! -f "${OML_SHARES_INDEX}" ]]; then
        if [[ "${OML_OUTPUT_FORMAT}" == "json" ]]; then
            echo '{"shares": [], "total": 0}'
        else
            echo "No shares found"
        fi
        return 0
    fi

    python3 - "${OML_SHARES_INDEX}" "${session_id}" "${active_only}" <<'PY'
import json
import sys

index_path = sys.argv[1]
session_id = sys.argv[2] if len(sys.argv) > 2 else None
active_only = sys.argv[3].lower() == 'true' if len(sys.argv) > 3 else True

with open(index_path, 'r') as f:
    data = json.load(f)

shares = data.get('shares', {})

# 过滤
result = []
for token, share in shares.items():
    if session_id and share.get('session_id') != session_id:
        continue
    if active_only and not share.get('active', True):
        continue
    result.append(share)

# 排序
result.sort(key=lambda x: x.get('created_at', ''), reverse=True)

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'total': len(result),
        'shares': result
    }, indent=2))
else:
    print(f"{'TOKEN':<20} {'SESSION_ID':<36} {'LEVEL':<10} {'ACTIVE':<8} {'ACCESSED'}")
    print("=" * 90)
    for share in result:
        token = share.get('token', 'unknown')[:18]
        sid = share.get('session_id', 'unknown')[:34]
        level = share.get('level', 'unknown')[:8]
        active = 'Yes' if share.get('active', True) else 'No'
        accessed = share.get('last_accessed', 'Never')[:10] if share.get('last_accessed') else 'Never'
        print(f"{token:<20} {sid:<36} {level:<10} {active:<8} {accessed}")
    print(f"\nTotal: {len(result)} shares")
PY
}

# ============================================================================
# 导出功能
# ============================================================================

# 导出会话
oml_session_export() {
    local session_id="$1"
    local format="${2:-$EXPORT_FORMAT_JSON}"
    local output_file="${3:-}"
    local include_metadata="${4:-true}"

    # 验证会话
    if ! oml_session_validate_id "$session_id"; then
        oml_session_share_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_share_error "Session not found: ${session_id}" 1
        return 1
    fi

    local output
    case "$format" in
        json)
            if [[ "$include_metadata" == "true" ]]; then
                output=$(cat "$data_path")
            else
                output=$(python3 -c "
import json
with open('${data_path}', 'r') as f:
    data = json.load(f)
# 移除元数据
export_data = {
    'session_id': data.get('session_id'),
    'messages': data.get('messages', []),
    'data': data.get('data', {}),
    'context': data.get('context', {})
}
print(json.dumps(export_data, indent=2, ensure_ascii=False))
")
            fi
            ;;
        markdown)
            output=$(python3 -c "
import json
from datetime import datetime

with open('${data_path}', 'r') as f:
    data = json.load(f)

output = []
output.append('# Session Export')
output.append('')
output.append(f\"**Session ID:** {data.get('session_id', 'unknown')}\")
output.append(f\"**Name:** {data.get('name', 'unnamed')}\")
output.append(f\"**Exported:** {datetime.utcnow().isoformat()}\")
output.append('')

messages = data.get('messages', [])
if messages:
    output.append('## Messages')
    output.append('')
    for msg in messages:
        role = msg.get('role', 'unknown')
        content = msg.get('content', '')
        timestamp = msg.get('timestamp', '')[:19]
        output.append(f'### {role} ({timestamp})')
        output.append('')
        output.append(content)
        output.append('')
else:
    output.append('No messages in this session.')

print('\n'.join(output))
")
            ;;
        text)
            output=$(python3 -c "
import json

with open('${data_path}', 'r') as f:
    data = json.load(f)

output = []
output.append('=== Session Export ===')
output.append(f\"Session ID: {data.get('session_id', 'unknown')}\")
output.append(f\"Name: {data.get('name', 'unnamed')}\")
output.append('')

messages = data.get('messages', [])
if messages:
    output.append('Messages:')
    output.append('-' * 40)
    for msg in messages:
        role = msg.get('role', 'unknown')
        content = msg.get('content', '')
        timestamp = msg.get('timestamp', '')[:19]
        output.append(f'[{timestamp}] {role}:')
        output.append(content)
        output.append('-' * 40)
else:
    output.append('No messages in this session.')

print('\n'.join(output))
")
            ;;
        *)
            oml_session_share_error "Unknown export format: ${format}" 1
            return 1
            ;;
    esac

    # 输出到文件或 stdout
    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        oml_session_text_output "Exported to: ${output_file}"
    else
        echo "$output"
    fi
}

# 导入会话
oml_session_import() {
    local input_file="$1"
    local session_id="${2:-}"
    local name="${3:-}"

    if [[ ! -f "$input_file" ]]; then
        oml_session_share_error "Input file not found: ${input_file}" 1
        return 1
    fi

    # 检测文件格式
    local format
    format=$(python3 -c "
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    print('json')
except:
    with open(sys.argv[1], 'r') as f:
        content = f.read()
    if content.startswith('#'):
        print('markdown')
    else:
        print('text')
" "$input_file")

    # 解析输入
    local import_data
    case "$format" in
        json)
            import_data=$(cat "$input_file")
            ;;
        markdown|text)
            # 文本格式需要转换
            import_data=$(python3 -c "
import json
import sys

with open(sys.argv[1], 'r') as f:
    content = f.read()

# 简单解析，提取消息
messages = []
current_role = None
current_content = []

for line in content.split('\n'):
    if line.startswith('### user:') or line.startswith('### assistant:') or line.startswith('### system:'):
        if current_role and current_content:
            messages.append({'role': current_role, 'content': '\n'.join(current_content)})
        current_role = line.split(':')[0].split()[-1]
        current_content = []
    elif current_role:
        current_content.append(line)

if current_role and current_content:
    messages.append({'role': current_role, 'content': '\n'.join(current_content)})

print(json.dumps({'messages': messages}))
" "$input_file")
            ;;
    esac

    # 生成或验证会话 ID
    if [[ -z "$session_id" ]]; then
        session_id="$(oml_session_generate_id "imported")"
    fi

    local timestamp
    timestamp="$(oml_session_timestamp)"

    # 创建会话
    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"
    local meta_path
    meta_path="$(oml_session_get_meta_path "$session_id")"

    python3 - "${data_path}" "${import_data}" "${session_id}" "${name}" "${timestamp}" <<'PY'
import json
import sys

data_path = sys.argv[1]
import_data_str = sys.argv[2]
session_id = sys.argv[3]
name = sys.argv[4]
timestamp = sys.argv[5]

import_data = json.loads(import_data_str)

session_data = {
    'session_id': session_id,
    'name': name if name else import_data.get('name', 'imported'),
    'type': 'imported',
    'status': 'pending',
    'created_at': timestamp,
    'updated_at': timestamp,
    'import_info': {
        'imported_at': timestamp,
        'original_format': import_data.get('format', 'unknown')
    },
    'metadata': import_data.get('metadata', {}),
    'data': import_data.get('data', {}),
    'messages': import_data.get('messages', []),
    'context': import_data.get('context', {})
}

with open(data_path, 'w') as f:
    json.dump(session_data, f, indent=2, ensure_ascii=False)
PY

    # 创建元数据
    cat > "$meta_path" <<EOF
session_id=${session_id}
created_at=${timestamp}
updated_at=${timestamp}
status=active
type=imported
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
    'name': '${name}',
    'status': 'active',
    'imported_from': '${input_file}'
}, indent=2))
"
    else
        echo "Imported session: ${session_id}"
        echo "From: ${input_file}"
        echo "Name: ${name:-imported}"
    fi

    echo "$session_id"
}

# ============================================================================
# 主入口（CLI）
# ============================================================================

main() {
    # 初始化存储
    oml_session_storage_init 2>/dev/null || true
    oml_session_share_init_index 2>/dev/null || true

    local action="${1:-help}"
    shift || true

    case "$action" in
        # 共享功能
        share)
            local session_id="$1"
            local level="${2:-link}"
            local expiry="${3:-0}"
            local users="${4:-}"
            oml_session_share "$session_id" "$level" "$expiry" "$users"
            ;;

        unshare)
            local session_id="$1"
            local token="${2:-}"
            oml_session_unshare "$session_id" "$token"
            ;;

        verify)
            local token="$1"
            local user="${2:-}"
            oml_session_share_verify "$token" "$user"
            ;;

        shares|list)
            local session_id="${1:-}"
            local active_only="${2:-true}"
            oml_session_share_list "$session_id" "$active_only"
            ;;

        # 导出功能
        export)
            local session_id="$1"
            local format="${2:-json}"
            local output_file="${3:-}"
            local no_metadata="${4:-false}"
            oml_session_export "$session_id" "$format" "$output_file" "$no_metadata"
            ;;

        import)
            local input_file="$1"
            local session_id="${2:-}"
            local name="${3:-}"
            oml_session_import "$input_file" "$session_id" "$name"
            ;;

        # 便捷命令
        publish)
            # 公开共享
            local session_id="$1"
            oml_session_share "$session_id" "public" "0"
            ;;

        revoke)
            # 撤销共享
            local session_id="$1"
            local token="${2:-}"
            oml_session_unshare "$session_id" "$token"
            ;;

        save)
            # 导出到文件
            local session_id="$1"
            local output_file="$2"
            local format="${3:-json}"
            oml_session_export "$session_id" "$format" "$output_file"
            ;;

        load)
            # 从文件导入
            local input_file="$1"
            local name="${2:-}"
            oml_session_import "$input_file" "" "$name"
            ;;

        help|--help|-h)
            cat <<EOF
OML Session Share

用法：oml session-share <action> [args]

共享功能:
  share <session_id> [level] [expiry] [users]  共享会话
  unshare <session_id> [token]                取消共享
  verify <token> [user]                       验证共享令牌
  list [session_id] [active_only]             列出共享

共享级别:
  public   完全公开
  link     仅链接访问
  private  仅自己
  user     指定用户

导出功能:
  export <session_id> [format] [output]       导出会话
  import <input_file> [id] [name]             导入会话

导出格式:
  json      JSON 格式（默认）
  markdown  Markdown 格式
  text      纯文本格式

便捷命令:
  publish <session_id>                        公开共享会话
  revoke <session_id> [token]                 撤销共享
  save <session_id> <file> [format]           保存到文件
  load <file> [name]                          从文件加载

示例:
  oml session-share share session-123 link 3600
  oml session-share share session-123 user 0 user1,user2
  oml session-share list
  oml session-share unshare session-123 share-abc123
  oml session-share export session-123 json output.json
  oml session-share export session-123 markdown report.md
  oml session-share import exported.json "My Session"
  oml session-share publish session-123
  oml session-share save session-123 backup.json

环境变量:
  OML_OUTPUT_FORMAT    输出格式 (text|json)
EOF
            ;;

        *)
            oml_session_share_error "Unknown action: ${action}" 1
            echo "Use 'oml session-share help' for usage"
            return 1
            ;;
    esac
}

# 仅在直接执行时运行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
