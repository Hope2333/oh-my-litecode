#!/usr/bin/env bash
# DEPRECATED: Migrated to TypeScript (packages/core/src/session/manager.ts)
# Archive Date: 2026-03-26
# Use: @oml/core SessionManager instead

# OML Session Search
# 搜索功能实现 - 支持会话内容搜索、过滤和索引

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

# 搜索范围
SEARCH_SCOPE_ALL="all"           # 全部
SEARCH_SCOPE_MESSAGES="messages" # 仅消息
SEARCH_SCOPE_DATA="data"         # 仅数据
SEARCH_SCOPE_CONTEXT="context"   # 仅上下文
SEARCH_SCOPE_METADATA="metadata" # 仅元数据

# 搜索模式
SEARCH_MODE_EXACT="exact"       # 精确匹配
SEARCH_MODE_CONTAINS="contains" # 包含匹配（默认）
SEARCH_MODE_REGEX="regex"       # 正则表达式
SEARCH_MODE_FUZZY="fuzzy"       # 模糊匹配

# 排序方式
SORT_BY_RELEVANCE="relevance"
SORT_BY_DATE="date"
SORT_BY_NAME="name"

# 输出格式
OML_OUTPUT_FORMAT="${OML_OUTPUT_FORMAT:-text}"

# 索引文件
OML_SEARCH_INDEX="${OML_SESSIONS_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/sessions}/search_index.json"

# ============================================================================
# 工具函数
# ============================================================================

# 输出错误
oml_session_search_error() {
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

# 获取当前时间戳
oml_session_search_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# 初始化搜索索引
oml_session_search_init_index() {
    if [[ ! -f "${OML_SEARCH_INDEX}" ]]; then
        cat > "${OML_SEARCH_INDEX}" <<'EOF'
{
  "index": {},
  "metadata": {
    "created_at": "",
    "updated_at": "",
    "total_sessions": 0,
    "total_messages": 0
  }
}
EOF
    fi
}

# ============================================================================
# 索引管理
# ============================================================================

# 构建搜索索引
oml_session_search_index() {
    local rebuild="${1:-false}"

    oml_session_search_init_index

    python3 - "${OML_SESSIONS_DATA_DIR}" "${OML_SEARCH_INDEX}" "${rebuild}" <<'PY'
import json
import sys
import os
import glob
from datetime import datetime

sessions_dir = sys.argv[1]
index_path = sys.argv[2]
rebuild = sys.argv[3].lower() == 'true'

# 加载现有索引
if os.path.exists(index_path) and not rebuild:
    with open(index_path, 'r') as f:
        index_data = json.load(f)
else:
    index_data = {
        'index': {},
        'metadata': {
            'created_at': datetime.utcnow().isoformat() + 'Z',
            'updated_at': datetime.utcnow().isoformat() + 'Z',
            'total_sessions': 0,
            'total_messages': 0
        }
    }

# 扫描所有会话
index = {}
total_messages = 0

for data_file in glob.glob(os.path.join(sessions_dir, 'data', '*.json')):
    try:
        with open(data_file, 'r') as f:
            session = json.load(f)

        session_id = session.get('session_id')
        if not session_id:
            continue

        # 索引会话元数据
        index[session_id] = {
            'name': session.get('name', ''),
            'type': session.get('type', 'default'),
            'status': session.get('status', 'unknown'),
            'created_at': session.get('created_at', ''),
            'updated_at': session.get('updated_at', ''),
            'message_count': len(session.get('messages', [])),
            'data_keys': list(session.get('data', {}).keys()),
            'context_keys': list(session.get('context', {}).keys()),
            'file_path': data_file
        }

        # 索引消息内容（用于全文搜索）
        messages = session.get('messages', [])
        total_messages += len(messages)

        for i, msg in enumerate(messages):
            content = msg.get('content', '')
            role = msg.get('role', '')

            # 简单的词索引
            words = content.lower().split()
            for word in words:
                # 只索引长度 >= 2 的词
                if len(word) >= 2:
                    # 清理标点
                    word = ''.join(c for c in word if c.isalnum())
                    if word:
                        if word not in index[session_id]:
                            index[session_id][word] = []
                        index[session_id][word].append({
                            'message_index': i,
                            'role': role,
                            'preview': content[:100]
                        })

    except Exception as e:
        print(f"Error indexing {data_file}: {e}", file=sys.stderr)

# 更新索引
index_data['index'] = index
index_data['metadata']['updated_at'] = datetime.utcnow().isoformat() + 'Z'
index_data['metadata']['total_sessions'] = len(index)
index_data['metadata']['total_messages'] = total_messages

with open(index_path, 'w') as f:
    json.dump(index_data, f, indent=2)

print(f"Indexed {len(index)} sessions, {total_messages} messages")
PY
}

# 更新单个会话索引
oml_session_search_index_session() {
    local session_id="$1"

    if ! oml_session_validate_id "$session_id"; then
        oml_session_search_error "Invalid session ID: ${session_id}" 1
        return 1
    fi

    local data_path
    data_path="$(oml_session_get_data_path "$session_id")"

    if [[ ! -f "$data_path" ]]; then
        oml_session_search_error "Session not found: ${session_id}" 1
        return 1
    fi

    oml_session_search_init_index

    python3 - "${data_path}" "${OML_SEARCH_INDEX}" <<'PY'
import json
import sys
from datetime import datetime

data_path = sys.argv[1]
index_path = sys.argv[2]

with open(data_path, 'r') as f:
    session = json.load(f)

with open(index_path, 'r') as f:
    index_data = json.load(f)

session_id = session.get('session_id')

# 更新索引
index_data['index'][session_id] = {
    'name': session.get('name', ''),
    'type': session.get('type', 'default'),
    'status': session.get('status', 'unknown'),
    'created_at': session.get('created_at', ''),
    'updated_at': session.get('updated_at', ''),
    'message_count': len(session.get('messages', [])),
    'data_keys': list(session.get('data', {}).keys()),
    'context_keys': list(session.get('context', {}).keys()),
    'file_path': data_path
}

index_data['metadata']['updated_at'] = datetime.utcnow().isoformat() + 'Z'
index_data['metadata']['total_sessions'] = len(index_data['index'])

with open(index_path, 'w') as f:
    json.dump(index_data, f, indent=2)

print(f"Indexed session: {session_id}")
PY
}

# ============================================================================
# 搜索功能
# ============================================================================

# 搜索会话
oml_session_search() {
    local query="$1"
    local scope="${2:-$SEARCH_SCOPE_ALL}"
    local mode="${3:-$SEARCH_MODE_CONTAINS}"
    local limit="${4:-20}"
    local sort="${5:-$SORT_BY_RELEVANCE}"

    oml_session_search_init_index

    # 如果索引不存在或为空，先构建索引
    if [[ ! -f "${OML_SEARCH_INDEX}" ]]; then
        oml_session_search_index "false" >/dev/null 2>&1 || true
    fi

    python3 - "${OML_SESSIONS_DATA_DIR}" "${OML_SEARCH_INDEX}" "${query}" "${scope}" "${mode}" "${limit}" "${sort}" <<'PY'
import json
import sys
import os
import re
import glob
from datetime import datetime

sessions_dir = sys.argv[1]
index_path = sys.argv[2]
query = sys.argv[3]
scope = sys.argv[4]
mode = sys.argv[5]
limit = int(sys.argv[6]) if sys.argv[6] != '0' else 20
sort_by = sys.argv[7]

# 加载索引
with open(index_path, 'r') as f:
    index_data = json.load(f)

index = index_data.get('index', {})

results = []

def matches_query(session, query, mode):
    """检查会话是否匹配查询"""
    if mode == 'exact':
        return query.lower() in session.get('name', '').lower()
    elif mode == 'regex':
        try:
            return bool(re.search(query, session.get('name', ''), re.IGNORECASE))
        except:
            return False
    else:  # contains
        return query.lower() in session.get('name', '').lower()

def search_messages(session_data, query, mode):
    """在消息中搜索"""
    matches = []
    messages = session_data.get('messages', [])

    for i, msg in enumerate(messages):
        content = msg.get('content', '')
        role = msg.get('role', '')

        match = False
        if mode == 'exact':
            match = query.lower() == content.lower()
        elif mode == 'regex':
            try:
                match = bool(re.search(query, content, re.IGNORECASE))
            except:
                pass
        else:  # contains
            match = query.lower() in content.lower()

        if match:
            matches.append({
                'message_index': i,
                'role': role,
                'content': content[:200],
                'timestamp': msg.get('timestamp', '')
            })

    return matches

def search_data(session_data, query, mode):
    """在数据中搜索"""
    matches = []
    data = session_data.get('data', {})

    data_str = json.dumps(data).lower()
    if mode == 'exact':
        if query.lower() == data_str:
            matches.append({'key': 'data', 'value': data})
    elif mode == 'regex':
        try:
            if re.search(query, data_str, re.IGNORECASE):
                matches.append({'key': 'data', 'value': data})
        except:
            pass
    else:  # contains
        if query.lower() in data_str:
            matches.append({'key': 'data', 'value': data})

    return matches

def search_context(session_data, query, mode):
    """在上下文中搜索"""
    matches = []
    context = session_data.get('context', {})

    context_str = json.dumps(context).lower()
    if mode == 'regex':
        try:
            if re.search(query, context_str, re.IGNORECASE):
                matches.append({'key': 'context', 'value': context})
        except:
            pass
    elif query.lower() in context_str:
        matches.append({'key': 'context', 'value': context})

    return matches

# 扫描所有会话
for session_id, info in index.items():
    data_path = info.get('file_path')
    if not data_path or not os.path.exists(data_path):
        continue

    try:
        with open(data_path, 'r') as f:
            session = json.load(f)
    except:
        continue

    match_info = {
        'session_id': session_id,
        'name': session.get('name', ''),
        'type': session.get('type', 'default'),
        'status': session.get('status', 'unknown'),
        'updated_at': session.get('updated_at', ''),
        'matches': {
            'name': False,
            'messages': [],
            'data': [],
            'context': []
        },
        'relevance_score': 0
    }

    # 搜索名称/元数据
    if scope in ['all', 'metadata', 'name']:
        if matches_query(session, query, mode):
            match_info['matches']['name'] = True
            match_info['relevance_score'] += 10

    # 搜索消息
    if scope in ['all', 'messages']:
        msg_matches = search_messages(session, query, mode)
        if msg_matches:
            match_info['matches']['messages'] = msg_matches
            match_info['relevance_score'] += len(msg_matches) * 5

    # 搜索数据
    if scope in ['all', 'data']:
        data_matches = search_data(session, query, mode)
        if data_matches:
            match_info['matches']['data'] = data_matches
            match_info['relevance_score'] += len(data_matches) * 3

    # 搜索上下文
    if scope in ['all', 'context']:
        ctx_matches = search_context(session, query, mode)
        if ctx_matches:
            match_info['matches']['context'] = ctx_matches
            match_info['relevance_score'] += len(ctx_matches) * 2

    # 只添加有匹配的结果
    if match_info['relevance_score'] > 0:
        results.append(match_info)

# 排序
if sort_by == 'relevance':
    results.sort(key=lambda x: x['relevance_score'], reverse=True)
elif sort_by == 'date':
    results.sort(key=lambda x: x.get('updated_at', ''), reverse=True)
elif sort_by == 'name':
    results.sort(key=lambda x: x.get('name', '').lower())

# 限制数量
results = results[:limit]

# 输出
output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'query': query,
        'scope': scope,
        'mode': mode,
        'total_results': len(results),
        'results': results
    }, indent=2, ensure_ascii=False))
else:
    print(f"Search results for: {query}")
    print(f"Scope: {scope}, Mode: {mode}")
    print(f"Found {len(results)} matches")
    print("")

    if not results:
        print("No matches found.")
    else:
        for i, result in enumerate(results, 1):
            print(f"{i}. {result['session_id']}")
            print(f"   Name: {result['name']}")
            print(f"   Score: {result['relevance_score']}")

            if result['matches']['name']:
                print(f"   [Name match]")

            if result['matches']['messages']:
                print(f"   [Messages: {len(result['matches']['messages'])} matches]")
                for msg in result['matches']['messages'][:2]:
                    preview = msg['content'][:80].replace('\n', ' ')
                    print(f"     - [{msg['role']}] {preview}...")

            if result['matches']['data']:
                print(f"   [Data match]")

            if result['matches']['context']:
                print(f"   [Context match]")

            print("")
PY
}

# ============================================================================
# 高级搜索
# ============================================================================

# 按过滤器搜索
oml_session_search_filter() {
    local status="${1:-}"
    local type_filter="${2:-}"
    local date_from="${3:-}"
    local date_to="${4:-}"
    local limit="${5:-20}"

    oml_session_search_init_index

    python3 - "${OML_SEARCH_INDEX}" "${status}" "${type_filter}" "${date_from}" "${date_to}" "${limit}" <<'PY'
import json
import sys
from datetime import datetime

index_path = sys.argv[1]
status = sys.argv[2] if len(sys.argv) > 2 else None
type_filter = sys.argv[3] if len(sys.argv) > 3 else None
date_from = sys.argv[4] if len(sys.argv) > 4 else None
date_to = sys.argv[5] if len(sys.argv) > 5 else None
limit = int(sys.argv[6]) if len(sys.argv) > 6 else 20

with open(index_path, 'r') as f:
    index_data = json.load(f)

index = index_data.get('index', {})

results = []

for session_id, info in index.items():
    # 过滤状态
    if status and info.get('status') != status:
        continue

    # 过滤类型
    if type_filter and info.get('type') != type_filter:
        continue

    # 过滤日期
    updated_at = info.get('updated_at', '')
    if date_from and updated_at < date_from:
        continue
    if date_to and updated_at > date_to:
        continue

    results.append({
        'session_id': session_id,
        'name': info.get('name', ''),
        'type': info.get('type', 'default'),
        'status': info.get('status', 'unknown'),
        'updated_at': updated_at,
        'message_count': info.get('message_count', 0)
    })

# 按日期排序
results.sort(key=lambda x: x.get('updated_at', ''), reverse=True)
results = results[:limit]

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'filters': {
            'status': status,
            'type': type_filter,
            'date_from': date_from,
            'date_to': date_to
        },
        'total_results': len(results),
        'results': results
    }, indent=2))
else:
    print(f"Filtered sessions")
    print(f"Status: {status or 'any'}, Type: {type_filter or 'any'}")
    print(f"Found {len(results)} matches")
    print("")

    for r in results:
        print(f"{r['session_id'][:36]} | {r['name'][:20]} | {r['type']} | {r['status']} | {r['updated_at'][:10]}")
PY
}

# 全文搜索
oml_session_search_fulltext() {
    local query="$1"
    local limit="${2:-20}"

    oml_session_search_init_index

    python3 - "${OML_SESSIONS_DATA_DIR}" "${query}" "${limit}" <<'PY'
import json
import sys
import os
import glob
import re

sessions_dir = sys.argv[1]
query = sys.argv[2].lower()
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 20

results = []

# 扫描所有会话文件
for data_file in glob.glob(os.path.join(sessions_dir, 'data', '*.json')):
    try:
        with open(data_file, 'r') as f:
            session = json.load(f)

        session_id = session.get('session_id')
        matches = []

        # 搜索所有消息
        for i, msg in enumerate(session.get('messages', [])):
            content = msg.get('content', '')
            if query in content.lower():
                # 计算相关性（基于出现次数）
                count = content.lower().count(query)
                matches.append({
                    'message_index': i,
                    'role': msg.get('role', ''),
                    'content': content,
                    'count': count
                })

        if matches:
            total_count = sum(m['count'] for m in matches)
            results.append({
                'session_id': session_id,
                'name': session.get('name', ''),
                'total_matches': total_count,
                'message_matches': len(matches),
                'matches': matches[:5]  # 限制每个会话的匹配数
            })

    except Exception as e:
        pass

# 按相关性排序
results.sort(key=lambda x: x['total_matches'], reverse=True)
results = results[:limit]

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'query': query,
        'total_results': len(results),
        'results': results
    }, indent=2, ensure_ascii=False))
else:
    print(f"Full-text search: {query}")
    print(f"Found {len(results)} sessions")
    print("")

    for r in results:
        print(f"Session: {r['session_id']}")
        print(f"  Name: {r['name']}")
        print(f"  Total matches: {r['total_matches']}")
        print(f"  Messages with matches: {r['message_matches']}")
        for m in r['matches'][:2]:
            preview = m['content'][:100].replace('\n', ' ')
            print(f"    [{m['role']}] ...{preview}...")
        print("")
PY
}

# ============================================================================
# 搜索建议
# ============================================================================

# 获取搜索建议
oml_session_search_suggest() {
    local prefix="$1"
    local limit="${2:-10}"

    oml_session_search_init_index

    python3 - "${OML_SEARCH_INDEX}" "${prefix}" "${limit}" <<'PY'
import json
import sys

index_path = sys.argv[1]
prefix = sys.argv[2].lower()
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 10

with open(index_path, 'r') as f:
    index_data = json.load(f)

index = index_data.get('index', {})

# 收集所有可能的建议
suggestions = {}

for session_id, info in index.items():
    # 从名称中提取
    name = info.get('name', '')
    words = name.lower().split()
    for word in words:
        if word.startswith(prefix):
            suggestions[word] = suggestions.get(word, 0) + 1

    # 从数据键中提取
    for key in info.get('data_keys', []):
        if key.lower().startswith(prefix):
            suggestions[key] = suggestions.get(key, 0) + 1

    # 从上下文键中提取
    for key in info.get('context_keys', []):
        if key.lower().startswith(prefix):
            suggestions[key] = suggestions.get(key, 0) + 1

# 按频率排序
sorted_suggestions = sorted(suggestions.items(), key=lambda x: x[1], reverse=True)
sorted_suggestions = sorted_suggestions[:limit]

output_format = '${OML_OUTPUT_FORMAT}'

if output_format == 'json':
    print(json.dumps({
        'prefix': prefix,
        'suggestions': [{'text': s[0], 'frequency': s[1]} for s in sorted_suggestions]
    }, indent=2))
else:
    print(f"Suggestions for: {prefix}")
    for s in sorted_suggestions:
        print(f"  {s[0]} ({s[1]})")
PY
}

# ============================================================================
# 主入口（CLI）
# ============================================================================

main() {
    # 初始化存储
    oml_session_storage_init 2>/dev/null || true
    oml_session_search_init_index 2>/dev/null || true

    local action="${1:-help}"
    shift || true

    case "$action" in
        search|find)
            local query="$1"
            local scope="${2:-all}"
            local mode="${3:-contains}"
            local limit="${4:-20}"
            local sort="${5:-relevance}"
            oml_session_search "$query" "$scope" "$mode" "$limit" "$sort"
            ;;

        index|reindex)
            local rebuild="${1:-false}"
            oml_session_search_index "$rebuild"
            ;;

        index-session)
            local session_id="$1"
            oml_session_search_index_session "$session_id"
            ;;

        filter)
            local status="${1:-}"
            local type_filter="${2:-}"
            local date_from="${3:-}"
            local date_to="${4:-}"
            local limit="${5:-20}"
            oml_session_search_filter "$status" "$type_filter" "$date_from" "$date_to" "$limit"
            ;;

        fulltext)
            local query="$1"
            local limit="${2:-20}"
            oml_session_search_fulltext "$query" "$limit"
            ;;

        suggest)
            local prefix="$1"
            local limit="${2:-10}"
            oml_session_search_suggest "$prefix" "$limit"
            ;;

        stats)
            if [[ -f "${OML_SEARCH_INDEX}" ]]; then
                python3 -c "
import json
with open('${OML_SEARCH_INDEX}', 'r') as f:
    data = json.load(f)
meta = data.get('metadata', {})
print(f\"Indexed sessions: {meta.get('total_sessions', 0)}\")
print(f\"Indexed messages: {meta.get('total_messages', 0)}\")
print(f\"Last updated: {meta.get('updated_at', 'never')}\")
"
            else
                echo "Search index not found. Run 'oml session-search index' first."
            fi
            ;;

        help|--help|-h)
            cat <<EOF
OML Session Search

用法：oml session-search <action> [args]

动作:
  search <query> [scope] [mode] [limit] [sort]  搜索会话
  index [--rebuild]                             构建搜索索引
  index-session <session_id>                    索引单个会话
  filter [status] [type] [from] [to] [limit]    按条件过滤
  fulltext <query> [limit]                      全文搜索
  suggest <prefix> [limit]                      获取搜索建议
  stats                                         显示索引统计

搜索范围 (scope):
  all       全部（默认）
  messages  仅消息
  data      仅数据
  context   仅上下文
  metadata  仅元数据

搜索模式 (mode):
  contains  包含匹配（默认）
  exact     精确匹配
  regex     正则表达式
  fuzzy     模糊匹配

排序方式 (sort):
  relevance 按相关性（默认）
  date      按日期
  name      按名称

示例:
  oml session-search search "python code"
  oml session-search search "error" messages contains 50
  oml session-search index --rebuild
  oml session-search filter running default
  oml session-search fulltext "import os"
  oml session-search suggest py
  oml session-search stats

环境变量:
  OML_OUTPUT_FORMAT    输出格式 (text|json)
EOF
            ;;

        *)
            oml_session_search_error "Unknown action: ${action}" 1
            echo "Use 'oml session-search help' for usage"
            return 1
            ;;
    esac
}

# 仅在直接执行时运行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
