#!/usr/bin/env bash
# Qwen Agent Plugin for OML
# Migrates qwenx functionality to OML plugin system
# Enhanced with Session and Hooks integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"
PLUGIN_NAME="qwen"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi
if [[ -f "${OML_CORE_DIR}/plugin-loader.sh" ]]; then
    source "${OML_CORE_DIR}/plugin-loader.sh"
fi

# Source OML session and hooks modules (if available)
if [[ -f "${OML_CORE_DIR}/session-manager.sh" ]]; then
    source "${OML_CORE_DIR}/session-manager.sh" 2>/dev/null || true
fi
if [[ -f "${OML_CORE_DIR}/hooks-engine.sh" ]]; then
    source "${OML_CORE_DIR}/hooks-engine.sh" 2>/dev/null || true
fi

# Configuration
SETTINGS_FILE=""
CTX7_DIR=""
CTX7_KEYS_FILE=""
CTX7_INDEX_FILE=""
OAUTH_CREDS_FILE=""

# ============================================================================
# Session Configuration
# ============================================================================
QWEN_SESSION_ENABLED="${QWEN_SESSION_ENABLED:-true}"
QWEN_SESSION_DIR=""
QWEN_SESSION_ID=""
QWEN_SESSION_MESSAGES_FILE=""

# ============================================================================
# Hooks Configuration
# ============================================================================
QWEN_HOOKS_ENABLED="${QWEN_HOOKS_ENABLED:-true}"
QWEN_HOOKS_DIR="${PLUGIN_DIR}/hooks"

# Hook events
readonly HOOK_USER_PROMPT_SUBMIT="qwen:user_prompt_submit"
readonly HOOK_PRE_TOOL_USE="qwen:pre_tool_use"
readonly HOOK_POST_TOOL_USE="qwen:post_tool_use"
readonly HOOK_STOP="qwen:stop"


# ============================================================================
# ============================================================================
# Check and load OAuth credentials if available
qwen_check_oauth() {
    # Skip if QWEN_API_KEY is already set
    if [[ -n "${QWEN_API_KEY:-}" ]]; then
        return 0
    fi
    
    local oauth_creds_file="${OAUTH_CREDS_FILE:-}"
    
    # Also check base qwenx config directory for oauth credentials
    if [[ -z "$oauth_creds_file" || ! -f "$oauth_creds_file" ]]; then
        local base_qwenx_config="${HOME}/.local/home/qwenx/.qwen/oauth_creds.json"
        if [[ -f "$base_qwenx_config" ]]; then
            oauth_creds_file="$base_qwenx_config"
        fi
    fi
    
    if [[ -f "$oauth_creds_file" ]]; then
        # Parse OAuth credentials using Python
        local token_info
        token_info=$(python3 - "$oauth_creds_file" << 'PY'
import json
import sys
from pathlib import Path
from datetime import datetime

creds_file = Path(sys.argv[1])
if not creds_file.exists():
    sys.exit(1)

try:
    data = json.loads(creds_file.read_text(encoding='utf-8'))
    access_token = data.get('access_token', '')
    expiry_date = data.get('expiry_date', 0)
    
    # Check if token is expired (expiry_date is in milliseconds)
    if expiry_date:
        expiry_ms = int(expiry_date)
        expiry_sec = expiry_ms // 1000
        now_sec = int(datetime.now().timestamp())
        # Add 5 minute buffer
        if expiry_sec < now_sec + 300:
            print("EXPIRED")
            sys.exit(0)
    
    if access_token:
        print(access_token)
except Exception:
    sys.exit(1)
PY
)
        
        if [[ -n "$token_info" && "$token_info" != "EXPIRED" ]]; then
            export QWEN_API_KEY="$token_info"
            export QWEN_BASE_URL="https://chat.qwen.ai/api"
        fi
    fi
}

# Initialization
# ============================================================================

# Initialize qwen environment
qwen_init() {
    # Setup fake home
    local fake_home
    if [[ -n "${_FAKEHOME:-}" ]]; then
        fake_home="${_FAKEHOME}"
    else
        fake_home="$(oml_get_fake_home "$PLUGIN_NAME" 2>/dev/null || echo "${HOME}/.local/home/qwen")"
    fi

    export _REALHOME="${HOME}"
    export HOME="${fake_home}"

    SETTINGS_FILE="${fake_home}/.qwen/settings.json"
    CTX7_DIR="${fake_home}/.qwenx/secrets"
    CTX7_KEYS_FILE="${CTX7_DIR}/context7.keys"
    CTX7_INDEX_FILE="${CTX7_DIR}/context7.index"
    OAUTH_CREDS_FILE="${fake_home}/.qwen/oauth_creds.json"

    # Ensure directories exist
    mkdir -p "${fake_home}/.qwen"
    mkdir -p "${CTX7_DIR}"
    chmod 700 "${CTX7_DIR}" 2>/dev/null || true

    # Initialize session directory
    if [[ "${QWEN_SESSION_ENABLED}" == "true" ]]; then
        qwen_session_init
    fi

    # Initialize hooks
    if [[ "${QWEN_HOOKS_ENABLED}" == "true" ]]; then
        qwen_hooks_init
    fi

    # Check and load OAuth credentials if available
    qwen_check_oauth
}

# ============================================================================
# Session Management
# ============================================================================

# Initialize session system
qwen_session_init() {
    QWEN_SESSION_DIR="${HOME}/.qwen/sessions"
    mkdir -p "${QWEN_SESSION_DIR}"
}

# Generate session ID
qwen_session_generate_id() {
    echo "qwen-session-$(date +%s)-$$-${RANDOM}"
}

# Create new session
qwen_session_create() {
    local name="${1:-}"
    local metadata="${2:-}"

    if [[ "${QWEN_SESSION_ENABLED}" != "true" ]]; then
        echo "Session is disabled" >&2
        return 1
    fi

    local session_id
    session_id="$(qwen_session_generate_id)"

    local timestamp
    timestamp="$(date -Iseconds)"

    # Create session data
    local session_data
    session_data=$(python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'created_at': '${timestamp}',
    'updated_at': '${timestamp}',
    'status': 'active',
    'metadata': ${metadata:-'{}'},
    'messages': [],
    'context': {}
}, indent=2))
")

    local session_file="${QWEN_SESSION_DIR}/${session_id}.json"
    echo "$session_data" > "$session_file"
    chmod 600 "$session_file"

    QWEN_SESSION_ID="$session_id"
    QWEN_SESSION_MESSAGES_FILE="${session_file}"

    # Trigger hook
    qwen_hooks_trigger "$HOOK_STOP" "session_create" "$session_id" 2>/dev/null || true

    if [[ "${OML_OUTPUT_FORMAT:-text}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'status': 'active',
    'created_at': '${timestamp}'
}, indent=2))
"
    else
        echo "Created session: ${session_id}"
    fi

    echo "$session_id"
}

# Switch to existing session
qwen_session_switch() {
    local session_id="$1"

    if [[ "${QWEN_SESSION_ENABLED}" != "true" ]]; then
        echo "Session is disabled" >&2
        return 1
    fi

    local session_file="${QWEN_SESSION_DIR}/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: ${session_id}" >&2
        return 1
    fi

    QWEN_SESSION_ID="$session_id"
    QWEN_SESSION_MESSAGES_FILE="$session_file"

    # Update session status
    python3 -c "
import json
from datetime import datetime

with open('${session_file}', 'r') as f:
    data = json.load(f)

data['status'] = 'active'
data['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open('${session_file}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

    if [[ "${OML_OUTPUT_FORMAT:-text}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'status': 'active',
    'switched_at': '$(date -Iseconds)'
}, indent=2))
"
    else
        echo "Switched to session: ${session_id}"
    fi
}

# Get current session
qwen_session_current() {
    if [[ -z "${QWEN_SESSION_ID:-}" ]]; then
        echo "No active session" >&2
        return 1
    fi

    if [[ "${OML_OUTPUT_FORMAT:-text}" == "json" ]]; then
        cat "${QWEN_SESSION_MESSAGES_FILE}" 2>/dev/null || echo '{"error": "Session file not found"}'
    else
        echo "Current session: ${QWEN_SESSION_ID}"
    fi
}

# List sessions
qwen_session_list() {
    local limit="${1:-10}"

    if [[ "${QWEN_SESSION_ENABLED}" != "true" ]]; then
        echo "Session is disabled" >&2
        return 1
    fi

    python3 - "${QWEN_SESSION_DIR}" "${limit}" <<'PY'
import json
import sys
import os
import glob

sessions_dir = sys.argv[1]
limit = int(sys.argv[2])

sessions = []
for session_file in glob.glob(os.path.join(sessions_dir, '*.json')):
    try:
        with open(session_file, 'r') as f:
            data = json.load(f)
        sessions.append({
            'session_id': data.get('session_id', ''),
            'name': data.get('name', ''),
            'status': data.get('status', ''),
            'created_at': data.get('created_at', ''),
            'updated_at': data.get('updated_at', ''),
            'message_count': len(data.get('messages', []))
        })
    except:
        pass

# Sort by updated_at descending
sessions.sort(key=lambda x: x.get('updated_at', ''), reverse=True)
sessions = sessions[:limit]

output_format = os.environ.get('OML_OUTPUT_FORMAT', 'text')

if output_format == 'json':
    print(json.dumps({'sessions': sessions, 'total': len(sessions)}, indent=2))
else:
    if not sessions:
        print("No sessions found")
    else:
        print(f"{'SESSION_ID':<40} {'NAME':<20} {'STATUS':<10} {'MESSAGES':<10} {'UPDATED'}")
        print("=" * 95)
        for s in sessions:
            name = (s['name'] or 'unnamed')[:18]
            print(f"{s['session_id']:<40} {name:<20} {s['status']:<10} {s['message_count']:<10} {s['updated_at'][:19] if s['updated_at'] else 'N/A'}")
        print(f"\nTotal: {len(sessions)} sessions")
PY
}

# Add message to session
qwen_session_add_message() {
    local role="$1"  # user, assistant, system
    local content="$2"
    local metadata="${3:-}"

    if [[ "${QWEN_SESSION_ENABLED}" != "true" ]]; then
        return 0
    fi

    if [[ -z "${QWEN_SESSION_ID:-}" ]]; then
        return 0  # Silently skip if no active session
    fi

    local session_file="${QWEN_SESSION_MESSAGES_FILE}"

    if [[ ! -f "$session_file" ]]; then
        return 0
    fi

    local timestamp
    timestamp="$(date -Iseconds)"

    python3 - "${session_file}" "${role}" "${content}" "${timestamp}" "${metadata:-{}}" <<'PY'
import json
import sys

session_file = sys.argv[1]
role = sys.argv[2]
content = sys.argv[3]
timestamp = sys.argv[4]
metadata = json.loads(sys.argv[5]) if sys.argv[5] else {}

with open(session_file, 'r') as f:
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

with open(session_file, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
}

# Get session messages
qwen_session_get_messages() {
    local role="${1:-}"
    local limit="${2:-0}"

    if [[ -z "${QWEN_SESSION_ID:-}" ]]; then
        echo "No active session" >&2
        return 1
    fi

    local session_file="${QWEN_SESSION_MESSAGES_FILE}"

    if [[ ! -f "$session_file" ]]; then
        echo "Session file not found" >&2
        return 1
    fi

    python3 - "${session_file}" "${role}" "${limit}" <<'PY'
import json
import sys

session_file = sys.argv[1]
role_filter = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
limit = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] != '0' else None

with open(session_file, 'r') as f:
    data = json.load(f)

messages = data.get('messages', [])

if role_filter:
    messages = [m for m in messages if m.get('role') == role_filter]

if limit and limit > 0:
    messages = messages[-limit:]

output_format = '${OML_OUTPUT_FORMAT:-text}'

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

# Clear session messages
qwen_session_clear_messages() {
    if [[ -z "${QWEN_SESSION_ID:-}" ]]; then
        echo "No active session" >&2
        return 1
    fi

    local session_file="${QWEN_SESSION_MESSAGES_FILE}"

    if [[ ! -f "$session_file" ]]; then
        echo "Session file not found" >&2
        return 1
    fi

    python3 -c "
import json

with open('${session_file}', 'r') as f:
    data = json.load(f)

data['messages'] = []

with open('${session_file}', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

    echo "Cleared messages for session: ${QWEN_SESSION_ID}"
}

# Delete session
qwen_session_delete() {
    local session_id="${1:-${QWEN_SESSION_ID:-}}"

    if [[ -z "$session_id" ]]; then
        echo "No session specified" >&2
        return 1
    fi

    local session_file="${QWEN_SESSION_DIR}/${session_id}.json"

    if [[ ! -f "$session_file" ]]; then
        echo "Session not found: ${session_id}" >&2
        return 1
    fi

    # Trigger stop hook before deletion
    qwen_hooks_trigger "$HOOK_STOP" "session_delete" "$session_id" 2>/dev/null || true

    rm -f "$session_file"

    if [[ "${QWEN_SESSION_ID}" == "$session_id" ]]; then
        QWEN_SESSION_ID=""
        QWEN_SESSION_MESSAGES_FILE=""
    fi

    echo "Deleted session: ${session_id}"
}

# ============================================================================
# Hooks Management
# ============================================================================

# Initialize hooks system
qwen_hooks_init() {
    mkdir -p "${QWEN_HOOKS_DIR}"

    # Register built-in hooks if they exist
    for hook_script in "${QWEN_HOOKS_DIR}"/*.sh; do
        if [[ -x "$hook_script" ]]; then
            local hook_name
            hook_name="$(basename "$hook_script" .sh)"
            # Hooks are auto-discovered and executed by trigger
        fi
    done
}

# Trigger hooks for an event
qwen_hooks_trigger() {
    local event="$1"
    shift
    local payload=("$@")

    if [[ "${QWEN_HOOKS_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Check if hooks directory exists
    if [[ ! -d "${QWEN_HOOKS_DIR}" ]]; then
        return 0
    fi

    # Find and execute matching hook scripts
    for hook_script in "${QWEN_HOOKS_DIR}"/*.sh; do
        if [[ ! -x "$hook_script" ]]; then
            continue
        fi

        # Check if hook script handles this event
        local handles_event
        handles_event=$("$hook_script" --check-event "$event" 2>/dev/null || echo "false")

        if [[ "$handles_event" == "true" ]]; then
            "$hook_script" "$event" "${payload[@]}" || true
        fi
    done

    # Also try to use OML hooks dispatcher if available
    if type -t oml_hooks_dispatch >/dev/null 2>&1; then
        oml_hooks_dispatch "$event" "${payload[@]}" --timeout 10 2>/dev/null || true
    fi
}

# Check if hook is enabled
qwen_hooks_is_enabled() {
    [[ "${QWEN_HOOKS_ENABLED}" == "true" ]]
}

# Enable hooks
qwen_hooks_enable() {
    export QWEN_HOOKS_ENABLED="true"
    echo "Hooks enabled"
}

# Disable hooks
qwen_hooks_disable() {
    export QWEN_HOOKS_ENABLED="false"
    echo "Hooks disabled"
}

# Context7 key management
ctx7__encode_key() {
    local key="$1"
    printf '%s' "${key}" | base64 -w 0
}

ctx7__decode_key() {
    local encoded="$1"
    printf '%s' "${encoded}" | base64 -d
}

ctx7__mask() {
    local v="${1:-}"
    if [[ "${#v}" -le 10 ]]; then
        printf '%s\n' '...'
        return 0
    fi
    printf '%s...%s\n' "${v:0:8}" "${v: -4}"
}

ctx7__ensure_store() {
    case "${CTX7_DIR}" in
        */.qwenx/*) ;;
        *)
            echo "Refusing to use non-qwenx key path: ${CTX7_DIR}" >&2
            return 1
            ;;
    esac
    
    mkdir -p "${CTX7_DIR}"
    chmod 700 "${CTX7_DIR}" 2>/dev/null || true
    
    if [[ ! -f "${CTX7_KEYS_FILE}" ]]; then
        : > "${CTX7_KEYS_FILE}"
    fi
    if [[ ! -f "${CTX7_INDEX_FILE}" ]]; then
        printf '0\n' > "${CTX7_INDEX_FILE}"
    fi
    
    chmod 600 "${CTX7_KEYS_FILE}" "${CTX7_INDEX_FILE}" 2>/dev/null || true
}

ctx7__load_keys() {
    CONTEXT7_KEY_PAIRS=()
    if [[ -f "${CTX7_KEYS_FILE}" ]]; then
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            local alias encoded_key
            
            if [[ "${line}" == *@* ]]; then
                local at_pos
                at_pos=$(expr index "$line" '@')
                local total_len=${#line}
                
                if [[ $at_pos -lt $((total_len / 2)) ]]; then
                    alias="${line%@*}"
                    encoded_key="${line#*@}"
                else
                    encoded_key="${line%@*}"
                    alias="${line#*@}"
                fi
                
                CONTEXT7_KEY_PAIRS+=("${alias} ${encoded_key}")
            fi
        done < "${CTX7_KEYS_FILE}"
    fi
}

ctx7_apply_current() {
    ctx7__ensure_store || return 1
    ctx7__load_keys
    
    local total="${#CONTEXT7_KEY_PAIRS[@]}"
    if [[ "${total}" -eq 0 ]]; then
        unset CONTEXT7_API_KEY || true
        return 0
    fi
    
    local idx
    idx="$(tr -d '[:space:]' < "${CTX7_INDEX_FILE}" 2>/dev/null || true)"
    [[ "${idx}" =~ ^[0-9]+$ ]] || idx=0
    idx=$(( idx % total ))
    
    local pair="${CONTEXT7_KEY_PAIRS[$idx]}"
    local alias="${pair%% *}"
    local encoded_key="${pair#* }"
    local decoded_key
    decoded_key="$(ctx7__decode_key "${encoded_key}")"
    export CONTEXT7_API_KEY="${decoded_key}"
}

ctx7_set_keys() {
    local new_pairs=()
    for input in "$@"; do
        [[ -z "${input}" ]] && continue
        
        local key alias
        if [[ "${input}" == *@* ]]; then
            key="${input%@*}"
            alias="${input#*@}"
            if [[ -z "${key}" || -z "${alias}" || "${alias}" == "all" ]]; then
                echo "Invalid key@alias format: ${input}" >&2
                return 1
            fi
        else
            key="${input}"
            alias="${key:0:8}...${key: -4}"
        fi
        
        local encoded_key
        encoded_key="$(ctx7__encode_key "${key}")"
        new_pairs+=("${alias}@${encoded_key}")
    done
    
    ctx7__ensure_store || return 1
    : > "${CTX7_KEYS_FILE}"
    for pair in "${new_pairs[@]}"; do
        printf '%s\n' "${pair}" >> "${CTX7_KEYS_FILE}"
    done
    printf '0\n' > "${CTX7_INDEX_FILE}"
    chmod 600 "${CTX7_KEYS_FILE}" "${CTX7_INDEX_FILE}" 2>/dev/null || true
    ctx7_apply_current
    echo "Stored ${#new_pairs[@]} key(s) in ${CTX7_KEYS_FILE}."
}

ctx7_add_keys() {
    local new_pairs=()
    for input in "$@"; do
        [[ -z "${input}" ]] && continue
        
        local key alias
        if [[ "${input}" == *@* ]]; then
            key="${input%@*}"
            alias="${input#*@}"
            if [[ -z "${key}" || -z "${alias}" || "${alias}" == "all" ]]; then
                echo "Invalid key@alias format: ${input}" >&2
                return 1
            fi
        else
            key="${input}"
            alias="${key:0:8}...${key: -4}"
        fi
        
        local encoded_key
        encoded_key="$(ctx7__encode_key "${key}")"
        new_pairs+=("${alias}@${encoded_key}")
    done
    
    ctx7__ensure_store || return 1
    for pair in "${new_pairs[@]}"; do
        printf '%s\n' "${pair}" >> "${CTX7_KEYS_FILE}"
    done
    chmod 600 "${CTX7_KEYS_FILE}" 2>/dev/null || true
    ctx7_apply_current
    echo "Appended ${#new_pairs[@]} key(s) to ${CTX7_KEYS_FILE}."
}

ctx7_rotate() {
    ctx7__ensure_store || return 1
    ctx7__load_keys
    
    local total="${#CONTEXT7_KEY_PAIRS[@]}"
    if [[ "${total}" -eq 0 ]]; then
        echo "No keys in ${CTX7_KEYS_FILE}" >&2
        return 1
    fi
    
    local idx
    idx="$(tr -d '[:space:]' < "${CTX7_INDEX_FILE}" 2>/dev/null || true)"
    [[ "${idx}" =~ ^[0-9]+$ ]] || idx=0
    idx=$(( (idx + 1) % total ))
    printf '%s\n' "${idx}" > "${CTX7_INDEX_FILE}"
    
    local pair="${CONTEXT7_KEY_PAIRS[$idx]}"
    local alias="${pair%% *}"
    local encoded_key="${pair#* }"
    local decoded_key
    decoded_key="$(ctx7__decode_key "${encoded_key}")"
    export CONTEXT7_API_KEY="${decoded_key}"
    echo "Rotated to index=${idx}/${total}."
}

ctx7_current() {
    ctx7__ensure_store || return 1
    ctx7__load_keys
    
    local total="${#CONTEXT7_KEY_PAIRS[@]}"
    if [[ "${total}" -eq 0 ]]; then
        echo "No keys in ${CTX7_KEYS_FILE}"
        return 0
    fi
    
    local idx
    idx="$(tr -d '[:space:]' < "${CTX7_INDEX_FILE}" 2>/dev/null || true)"
    [[ "${idx}" =~ ^[0-9]+$ ]] || idx=0
    idx=$(( idx % total ))
    
    local pair="${CONTEXT7_KEY_PAIRS[$idx]}"
    local alias="${pair%% *}"
    local encoded_key="${pair#* }"
    local decoded_key
    decoded_key="$(ctx7__decode_key "${encoded_key}")"
    local masked
    masked="$(ctx7__mask "${decoded_key}")"
    echo "Current index=${idx}/${total}; key=${masked}; alias=${alias}"
}

ctx7_clear() {
    ctx7__ensure_store || return 1
    : > "${CTX7_KEYS_FILE}"
    printf '0\n' > "${CTX7_INDEX_FILE}"
    chmod 600 "${CTX7_KEYS_FILE}" "${CTX7_INDEX_FILE}" 2>/dev/null || true
    unset CONTEXT7_API_KEY || true
    echo "Cleared all Context7 keys from ${CTX7_KEYS_FILE}."
}

ctx7_list_keys() {
    ctx7__ensure_store || return 1
    ctx7__load_keys
    
    local total="${#CONTEXT7_KEY_PAIRS[@]}"
    if [[ "${total}" -eq 0 ]]; then
        echo "No keys in ${CTX7_KEYS_FILE}"
        return 0
    fi
    
    local current_idx
    current_idx="$(tr -d '[:space:]' < "${CTX7_INDEX_FILE}" 2>/dev/null || true)"
    [[ "${current_idx}" =~ ^[0-9]+$ ]] || current_idx=0
    current_idx=$(( current_idx % total ))
    
    for i in "${!CONTEXT7_KEY_PAIRS[@]}"; do
        local pair="${CONTEXT7_KEY_PAIRS[$i]}"
        local alias="${pair%% *}"
        local encoded_key="${pair#* }"
        local decoded_key
        decoded_key="$(ctx7__decode_key "${encoded_key}")"
        local masked
        masked="$(ctx7__mask "${decoded_key}")"
        local marker=" "
        if [[ "${i}" == "${current_idx}" ]]; then
            marker="*"
        fi
        echo "${marker} ${i}: ${masked} (${alias})"
    done
}

ctx7_remove() {
    if [[ "$#" -ne 1 ]]; then
        echo "Usage: qwen ctx7 remove <alias>" >&2
        return 1
    fi
    
    local target_alias="$1"
    if [[ "${target_alias}" == "all" ]]; then
        ctx7_clear
        return $?
    fi
    
    ctx7__ensure_store || return 1
    ctx7__load_keys
    
    local new_pairs=()
    local found=0
    for pair in "${CONTEXT7_KEY_PAIRS[@]}"; do
        local alias="${pair%% *}"
        local encoded_key="${pair#* }"
        if [[ "${alias}" == "${target_alias}" ]]; then
            found=1
            continue
        fi
        new_pairs+=("${alias}@${encoded_key}")
    done
    
    if [[ "${found}" -eq 0 ]]; then
        echo "Alias '${target_alias}' not found" >&2
        return 1
    fi
    
    : > "${CTX7_KEYS_FILE}"
    for pair in "${new_pairs[@]}"; do
        printf '%s\n' "${pair}" >> "${CTX7_KEYS_FILE}"
    done
    
    printf '0\n' > "${CTX7_INDEX_FILE}"
    chmod 600 "${CTX7_KEYS_FILE}" "${CTX7_INDEX_FILE}" 2>/dev/null || true
    
    ctx7_apply_current
    echo "Removed key with alias '${target_alias}'."
}

ctx7_mode_set_local() {
    echo "Setting Context7 to local mode..."
    
    if [[ -f "${SETTINGS_FILE}" ]]; then
        python3 -c "
import json
from pathlib import Path

settings_path = Path('${SETTINGS_FILE}')
data = json.loads(settings_path.read_text(encoding='utf-8'))

mcp_servers = data.setdefault('mcpServers', {})
ctx7_config = mcp_servers.setdefault('context7', {})

for k in ('url', 'headers'):
    if k in ctx7_config:
        del ctx7_config[k]

ctx7_config['command'] = 'npx'
ctx7_config['args'] = ['-y', '@upstash/context7-mcp@latest']
ctx7_config['protocol'] = 'mcp'
ctx7_config['enabled'] = True
ctx7_config['trust'] = False
ctx7_config['excludeTools'] = []

servers = data.get('mcp', {}).setdefault('servers', [])
found = False
for server in servers:
    if server.get('name') == 'context7':
        server.update({
            'name': 'context7',
            'protocol': 'mcp',
            'enabled': True
        })
        if 'url' in server:
            del server['url']
        found = True
        break

if not found:
    servers.append({
        'name': 'context7',
        'protocol': 'mcp',
        'enabled': True
    })

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('Updated settings.json for local Context7 server mode.')
" 2>/dev/null || echo "Failed to update settings.json for local mode"
    fi
    
    echo "Context7 set to local mode."
}

ctx7_mode_set_remote() {
    echo "Setting Context7 to remote API mode..."
    
    if [[ -f "${SETTINGS_FILE}" ]]; then
        python3 -c "
import json
from pathlib import Path

settings_path = Path('${SETTINGS_FILE}')
data = json.loads(settings_path.read_text(encoding='utf-8'))

mcp_servers = data.setdefault('mcpServers', {})
ctx7_config = mcp_servers.setdefault('context7', {})

for k in ('command', 'args', 'env'):
    if k in ctx7_config:
        del ctx7_config[k]

ctx7_config['url'] = ''  # Empty URL for disabled state
ctx7_config['protocol'] = 'mcp'
ctx7_config['enabled'] = True
ctx7_config['trust'] = False
ctx7_config['excludeTools'] = []
ctx7_config['headers'] = {
    'X-Context7-API-Key': '\$CONTEXT7_API_KEY'
}

servers = data.get('mcp', {}).setdefault('servers', [])
found = False
for server in servers:
    if server.get('name') == 'context7':
        server.update({
            'name': 'context7',
            'url': '',  # Empty URL for disabled state
            'protocol': 'mcp',
            'enabled': True
        })
        found = True
        break

if not found:
    servers.append({
        'name': 'context7',
        'url': '',  # Empty URL for disabled state
        'protocol': 'mcp',
        'enabled': True
    })

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('Updated settings.json for remote Context7 API mode.')
" 2>/dev/null || echo "Failed to update settings.json for remote mode"
    fi
    
    echo "Context7 set to remote API mode."
}

ctx7_mode_current() {
    if [[ -f "${SETTINGS_FILE}" ]]; then
        local mode_info
        mode_info=$(python3 -c "
import json
from pathlib import Path
settings_path = Path('${SETTINGS_FILE}')
try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
    ctx7_config = data.get('mcpServers', {}).get('context7', {})
    
    url = ctx7_config.get('url', '')
    if url.startswith('https://'):
        print('remote')
    elif url.startswith('http://') and not url.startswith('http://localhost'):
        print('remote')
    elif 'command' in ctx7_config:
        print('local')
    elif url.startswith('http://localhost'):
        print('local')
    else:
        print('unknown')
except:
    print('error')
")
        
        case "${mode_info}" in
            local)
                echo "Current mode: local server (using npx @upstash/context7-mcp)"
                ;;
            remote)
                echo "Current mode: remote API (using https://mcp.context7.com/mcp)"
                ;;
            *)
                echo "Current mode: unknown or error"
                ;;
        esac
    else
        echo "Current mode: settings.json not found"
    fi
}

ctx7_help() {
    cat <<'EOF'
Usage:
  qwen ctx7 set <k1[@alias]> [k2[@alias] ...]   # overwrite key ring
  qwen ctx7 add <k1[@alias]> [k2[@alias] ...]   # append keys
  qwen ctx7 rotate              # move to next key
  qwen ctx7 current             # show current index/masked key/alias
  qwen ctx7 list                # list all keys with mask and alias
  qwen ctx7 remove <alias>      # remove key by alias (use 'all' to clear all)
  qwen ctx7 mode <local|remote|current>  # switch between local/remote mode
  qwen ctx7 clear               # clear all keys

Note:
  - Use '.' instead of '*' for shell wildcards in aliases
  - Keys are stored encrypted at:
    ~/.local/home/qwen/.qwenx/secrets/context7.keys
EOF
}

# Models management
models_list() {
    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        echo "settings.json not found: ${SETTINGS_FILE}"
        return 1
    fi
    
    python3 - "${SETTINGS_FILE}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
if not settings_path.exists():
    print(f"settings not found: {settings_path}")
    sys.exit(1)

data = json.loads(settings_path.read_text(encoding='utf-8'))
models = data.get('modelProviders', {}).get('openai', [])
if not isinstance(models, list) or not models:
    print('No models configured under modelProviders.openai')
    sys.exit(0)

for i, m in enumerate(models, start=1):
    mid = m.get('id', '') if isinstance(m, dict) else ''
    name = m.get('name', '') if isinstance(m, dict) else ''
    print(f"{i:>3}. {mid} | {name}")
PY
}

models_sync() {
    if [[ -z "${QWEN_API_KEY:-}" ]]; then
        echo "QWEN_API_KEY is empty, cannot sync models." >&2
        return 1
    fi
    
    if [[ -z "${QWEN_BASE_URL:-}" ]]; then
        echo "QWEN_BASE_URL is empty, cannot sync models." >&2
        return 1
    fi
    
    cp "${SETTINGS_FILE}" "${SETTINGS_FILE}.bak_before_models_sync" 2>/dev/null || true
    
    python3 - "${SETTINGS_FILE}" "${QWEN_BASE_URL:-}" "${QWEN_API_KEY:-}" <<'PY'
import json
import sys
import urllib.request
from pathlib import Path

settings_path = Path(sys.argv[1])
base_url = (sys.argv[2] or '').rstrip('/')
api_key = sys.argv[3] or ''

if not settings_path.exists():
    print(f"settings not found: {settings_path}")
    sys.exit(1)
if not base_url:
    print('QWEN_BASE_URL is empty')
    sys.exit(1)
if not api_key:
    print('QWEN_API_KEY is empty')
    sys.exit(1)

url = f"{base_url}/models"
req = urllib.request.Request(
    url,
    headers={
        'Authorization': f'Bearer {api_key}',
        'Accept': 'application/json',
        'User-Agent': 'qwenx-model-sync/1.0',
    },
    method='GET',
)

try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode('utf-8', errors='replace')
except Exception as e:
    print(f"fetch models failed: {e}")
    sys.exit(1)

try:
    payload = json.loads(body)
except Exception as e:
    print(f"invalid json response: {e}")
    sys.exit(1)

items = payload.get('data', [])
if not isinstance(items, list):
    print('invalid models payload: data is not list')
    sys.exit(1)

models = []
seen = set()
for item in items:
    if not isinstance(item, dict):
        continue
    mid = item.get('id')
    if not mid or not isinstance(mid, str):
        continue
    if mid in seen:
        continue
    seen.add(mid)
    models.append({
        'id': mid,
        'name': f'{mid} (via custom API)',
        'envKey': 'QWEN_API_KEY',
        'baseUrl': base_url,
    })

if not models:
    print('no valid models from api response')
    sys.exit(1)

settings = json.loads(settings_path.read_text(encoding='utf-8'))
if not isinstance(settings, dict):
    print('invalid settings root')
    sys.exit(1)

providers = settings.setdefault('modelProviders', {})
if not isinstance(providers, dict):
    providers = {}
    settings['modelProviders'] = providers
providers['openai'] = models

current = settings.get('model')
if not isinstance(current, dict) or current.get('id') not in seen:
    first = models[0]
    settings['model'] = {'id': first['id'], 'name': first['id']}

settings_path.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f"synced {len(models)} models to {settings_path}")
PY
}

models_help() {
    cat <<'EOF'
Usage:
  qwen models list              # list models from settings.json
  qwen models sync              # fetch models from API (requires QWEN_API_KEY and QWEN_BASE_URL)

Note:
  - models sync is disabled when QWEN_API_KEY or QWEN_BASE_URL is empty
EOF
}

# MCP management
mcp_list() {
    if command -v qwen >/dev/null 2>&1; then
        qwen mcp list
    else
        echo "qwen command not found. Please install qwen first." >&2
        return 1
    fi
}

# Chat command - forward to qwen
qwen_chat() {
    if command -v qwen >/dev/null 2>&1; then
        exec qwen "$@"
    else
        echo "qwen command not found. Please install qwen first." >&2
        return 1
    fi
}

# Main entry point
main() {
    # Initialize environment
    qwen_init
    
    # Auto-apply Context7 key
    ctx7_apply_current || true
    
    local action="${1:-help}"
    shift || true
    
    case "$action" in
        # Chat passthrough
        chat|c|"")
            qwen_chat "$@"
            ;;
        
        # Context7 management
        ctx7)
            local sub="${1:-help}"
            shift || true
            case "$sub" in
                set) ctx7_set_keys "$@" ;;
                add) ctx7_add_keys "$@" ;;
                rotate) ctx7_rotate ;;
                current) ctx7_current ;;
                list) ctx7_list_keys ;;
                remove) ctx7_remove "$@" ;;
                mode)
                    case "${1:-}" in
                        local) ctx7_mode_set_local ;;
                        remote) ctx7_mode_set_remote ;;
                        current) ctx7_mode_current ;;
                        *) echo "Usage: qwen ctx7 mode <local|remote|current>" >&2; exit 1 ;;
                    esac
                    ;;
                clear) ctx7_clear ;;
                help|--help|-h|"") ctx7_help ;;
                *) echo "Unknown ctx7 command: ${sub}" >&2; ctx7_help; exit 1 ;;
            esac
            ;;
        
        # Models management
        models)
            local sub="${1:-help}"
            shift || true
            case "$sub" in
                list) models_list ;;
                sync) models_sync ;;
                help|--help|-h|"") models_help ;;
                *) echo "Unknown models command: ${sub}" >&2; models_help; exit 1 ;;
            esac
            ;;
        
        # MCP management
        mcp)
            mcp_list "$@"
            ;;

        # Session management
        session|s)
            local sub="${1:-help}"
            shift || true
            case "$sub" in
                create) qwen_session_create "$@" ;;
                switch|use) qwen_session_switch "$@" ;;
                current) qwen_session_current ;;
                list) qwen_session_list "$@" ;;
                messages|get-messages) qwen_session_get_messages "$@" ;;
                add-message)
                    local role="$1"
                    local content="$2"
                    shift 2 || true
                    local metadata="${1:-}"
                    qwen_session_add_message "$role" "$content" "$metadata"
                    ;;
                clear) qwen_session_clear_messages ;;
                delete) qwen_session_delete "$@" ;;
                help|--help|-h|"")
                    cat <<EOF
Session Management

Usage: qwen session <action> [args]

Actions:
  create [name] [metadata]    Create new session
  switch <session_id>         Switch to existing session
  current                     Show current session info
  list [limit]                List sessions
  messages [role] [limit]     Get session messages
  add-message <role> <content> [metadata]  Add message to session
  clear                       Clear session messages
  delete [session_id]         Delete session

Roles: user, assistant, system
EOF
                    ;;
                *) echo "Unknown session command: ${sub}" >&2; exit 1 ;;
            esac
            ;;

        # Hooks management
        hooks|h)
            local sub="${1:-help}"
            shift || true
            case "$sub" in
                enable) qwen_hooks_enable ;;
                disable) qwen_hooks_disable ;;
                status)
                    if qwen_hooks_is_enabled; then
                        echo "Hooks: enabled"
                        echo "Hooks directory: ${QWEN_HOOKS_DIR}"
                        if [[ -d "${QWEN_HOOKS_DIR}" ]]; then
                            echo "Available hooks:"
                            ls -la "${QWEN_HOOKS_DIR}"/*.sh 2>/dev/null || echo "  (none)"
                        fi
                    else
                        echo "Hooks: disabled"
                    fi
                    ;;
                trigger)
                    local event="$1"
                    shift || true
                    qwen_hooks_trigger "$event" "$@"
                    ;;
                help|--help|-h|"")
                    cat <<EOF
Hooks Management

Usage: qwen hooks <action> [args]

Actions:
  enable              Enable hooks
  disable             Disable hooks
  status              Show hooks status
  trigger <event> [args]  Trigger hooks for event

Events:
  qwen:user_prompt_submit  - When user submits a prompt
  qwen:pre_tool_use        - Before using a tool
  qwen:post_tool_use       - After using a tool
  qwen:stop                - On session stop
EOF
                    ;;
                *) echo "Unknown hooks command: ${sub}" >&2; exit 1 ;;
            esac
            ;;

        # Help
        help|--help|-h)
            cat <<EOF
Qwen Agent Plugin for OML

Usage: qwen <command> [args]

Commands:
  (no command)    Start chat session (passthrough to qwen)
  chat            Start chat session
  session         Manage sessions
  hooks           Manage hooks
  ctx7            Manage Context7 API keys
  models          Manage model registry
  mcp             List MCP servers

Session Commands:
  qwen session create [name]           Create new session
  qwen session switch <id>             Switch to session
  qwen session current                 Show current session
  qwen session list [limit]            List sessions
  qwen session messages [role] [limit] Get messages
  qwen session add-message <r> <c>     Add message
  qwen session clear                   Clear messages
  qwen session delete [id]             Delete session

Hooks Commands:
  qwen hooks enable                    Enable hooks
  qwen hooks disable                   Disable hooks
  qwen hooks status                    Show status
  qwen hooks trigger <event> [args]    Trigger hooks

Context7 Commands:
  qwen ctx7 set <k1[@alias]> [k2...]   Set key ring
  qwen ctx7 add <k1[@alias]> [k2...]   Append keys
  qwen ctx7 rotate                     Rotate to next key
  qwen ctx7 current                    Show current key
  qwen ctx7 list                       List all keys
  qwen ctx7 remove <alias>             Remove key
  qwen ctx7 mode <local|remote>        Switch mode
  qwen ctx7 clear                      Clear all keys

Models Commands:
  qwen models list                     List configured models
  qwen models sync                     Sync from API (disabled)

Environment Variables:
  QWEN_API_KEY         API key for Qwen (empty = disabled)
  QWEN_BASE_URL        Base URL for Qwen API (empty = disabled)
  CONTEXT7_API_KEY     Context7 API key (managed by ctx7)
  QWEN_SESSION_ENABLED Enable session management (default: true)
  QWEN_HOOKS_ENABLED   Enable hooks (default: true)

Note:
  This plugin migrates qwenx functionality to OML.
  Configuration is isolated in ~/.local/home/qwen/
EOF
            ;;
        
        # Unknown - try passthrough to qwen
        *)
            qwen_chat "$action" "$@"
            ;;
    esac
}

main "$@"
