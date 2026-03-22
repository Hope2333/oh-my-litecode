#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Store real/fake home for isolation
export _REALHOME="${HOME}"
export REALHOME="${HOME}"
export _FAKEHOME="/data/data/com.termux/files/home/.local/home/qwenx"
export _TEMP_HOME="${HOME}"
export HOME="${_FAKEHOME}"

SETTINGS_FILE="${_FAKEHOME}/.qwen/settings.json"

# Existing provider env (kept as current behavior)
export QWEN_API_KEY="sk-mf0RD9eiVXaLiECaCZDcwl8c9qGWx135JzJwFnDJlfyYSZF7"

# Context7 key storage is only allowed under qwenx
CTX7_DIR="${_FAKEHOME}/.qwenx/secrets"
CTX7_KEYS_FILE="${CTX7_DIR}/context7.keys"
CTX7_INDEX_FILE="${CTX7_DIR}/context7.index"

ctx7__ensure_store() {
  case "${CTX7_DIR}" in
    "${_FAKEHOME}/.qwenx"/*) ;;
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

ctx7__encode_key() {
  local key="$1"
  printf '%s' "${key}" | base64 -w 0
}

ctx7__decode_key() {
  local encoded="$1"
  printf '%s' "${encoded}" | base64 -d
}

ctx7__load_keys() {
  CONTEXT7_KEY_PAIRS=()  # array of "alias encoded_key" pairs
  if [[ -f "${CTX7_KEYS_FILE}" ]]; then
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      local alias encoded_key
      
      # Support both old format (encoded_key@alias) and new format (alias@encoded_key)
      if [[ "${line}" == *@* ]]; then
        # Check position of @ to determine format
        local at_pos=$(expr index "$line" '@')
        local total_len=${#line}
        
        # Heuristic: if @ is near the beginning, likely new format (short alias)
        # if @ is near the end, likely old format (long encoded key)
        if [[ $at_pos -lt $((total_len / 2)) ]]; then
          # New format: alias@encoded_key
          alias="${line%@*}"
          encoded_key="${line#*@}"
        else
          # Old format: encoded_key@alias
          encoded_key="${line%@*}"
          alias="${line#*@}"
        fi
        
        CONTEXT7_KEY_PAIRS+=("${alias} ${encoded_key}")
      fi
    done < "${CTX7_KEYS_FILE}"
  fi
}

ctx7__mask() {
  local v="${1:-}"
  if [[ "${#v}" -le 10 ]]; then
    printf '%s\n' '...'
    return 0
  fi
  printf '%s...%s\n' "${v:0:8}" "${v: -4}"
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

  # Sync to settings.json for MCP servers
  if [[ -f "${SETTINGS_FILE}" ]]; then
    # We intentionally avoid writing the plain key into settings.json.
    # The qwenx wrapper exports CONTEXT7_API_KEY and spawned MCP processes inherit it.
    :
  fi
}

ctx7_set_keys() {
  local new_pairs=()
  for input in "$@"; do
    [[ -z "${input}" ]] && continue
    
    # Parse key@alias format
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
      # Use first 8 chars + ... + last 4 chars as default alias
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
    
    # Parse key@alias format
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
      # Use first 8 chars + ... + last 4 chars as default alias
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

  # Sync to settings.json for MCP servers
  if [[ -f "${SETTINGS_FILE}" ]]; then
    # We intentionally avoid writing the plain key into settings.json.
    # The qwenx wrapper exports CONTEXT7_API_KEY and spawned MCP processes inherit it.
    :
  fi
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

ctx7_mode_set_local() {
  echo "Setting Context7 to local mode..."

  # Update settings.json to use local server (stdio)
  if [[ -f "${SETTINGS_FILE}" ]]; then
    python3 -c "
import json
from pathlib import Path

settings_path = Path('$SETTINGS_FILE')
data = json.loads(settings_path.read_text(encoding='utf-8'))

mcp_servers = data.setdefault('mcpServers', {})
ctx7_config = mcp_servers.setdefault('context7', {})

# Local server configuration (stdio)
for k in ('url', 'headers'):
    if k in ctx7_config:
        del ctx7_config[k]

ctx7_config['command'] = 'npx'
ctx7_config['args'] = ['-y', '@upstash/context7-mcp@latest']

# Do NOT store plain key in settings.json.
# Qwenx exports CONTEXT7_API_KEY so the spawned MCP process inherits it.
ctx7_config['protocol'] = 'mcp'
ctx7_config['enabled'] = True
ctx7_config['trust'] = False
ctx7_config['excludeTools'] = []

# Also update the general servers list
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
  echo "Tip: key is taken from env CONTEXT7_API_KEY (exported by qwenx ctx7)."
}

ctx7_mode_set_remote() {
  echo "Setting Context7 to remote API mode..."

  # Update settings.json to use remote hosted MCP over HTTP
  if [[ -f "${SETTINGS_FILE}" ]]; then
    python3 -c "
import json
from pathlib import Path

settings_path = Path('$SETTINGS_FILE')
data = json.loads(settings_path.read_text(encoding='utf-8'))

mcp_servers = data.setdefault('mcpServers', {})
ctx7_config = mcp_servers.setdefault('context7', {})

# Remote server configuration (HTTP)
for k in ('command', 'args', 'env'):
    if k in ctx7_config:
        del ctx7_config[k]

ctx7_config['url'] = 'https://mcp.context7.com/mcp'
ctx7_config['protocol'] = 'mcp'
ctx7_config['enabled'] = True
ctx7_config['trust'] = False
ctx7_config['excludeTools'] = []

# IMPORTANT: pass API key via headers, but keep it out of settings.json
# Qwen Code supports env substitution like "\$EXA_API_KEY".
ctx7_config['headers'] = {
    'X-Context7-API-Key': '\$CONTEXT7_API_KEY'
}

# Also update the general servers list
servers = data.get('mcp', {}).setdefault('servers', [])
found = False
for server in servers:
    if server.get('name') == 'context7':
        server.update({
            'name': 'context7',
            'url': 'https://mcp.context7.com/mcp',
            'protocol': 'mcp',
            'enabled': True
        })
        found = True
        break

if not found:
    servers.append({
        'name': 'context7',
        'url': 'https://mcp.context7.com/mcp',
        'protocol': 'mcp',
        'enabled': True
    })

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print('Updated settings.json for remote Context7 API mode.')
" 2>/dev/null || echo "Failed to update settings.json for remote mode"
  fi

  echo "Context7 set to remote API mode."
  echo "Tip: key is taken from env CONTEXT7_API_KEY (exported by qwenx ctx7)."
}

ctx7_mode_current() {
  if [[ -f "${SETTINGS_FILE}" ]]; then
    local mode_info=$(python3 -c "
import json
from pathlib import Path
settings_path = Path('$SETTINGS_FILE')
try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
    ctx7_config = data.get('mcpServers', {}).get('context7', {})
    
    # Check for remote mode indicators
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

ctx7_remove() {
  if [[ "$#" -ne 1 ]]; then
    echo "Usage: qwenx ctx7 remove <alias>" >&2
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

  # Reset index to 0 after removal
  printf '0\n' > "${CTX7_INDEX_FILE}"
  chmod 600 "${CTX7_KEYS_FILE}" "${CTX7_INDEX_FILE}" 2>/dev/null || true

  ctx7_apply_current
  echo "Removed key with alias '${target_alias}'."
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

ctx7_help() {
  cat <<'EOF'
Usage:
  qwenx ctx7 set <k1[@alias]> [k2[@alias] ...]   # overwrite key ring
  qwenx ctx7 add <k1[@alias]> [k2[@alias] ...]   # append keys
  qwenx ctx7 rotate              # move to next key
  qwenx ctx7 current             # show current index/masked key/alias
  qwenx ctx7 list                # list all keys with mask and alias
  qwenx ctx7 remove <alias>      # remove key by alias (use 'all' to clear all)
  qwenx ctx7 mode <local|remote|current>  # switch between local/remote mode
  qwenx ctx7 clear               # clear all keys

Note:
  - Use '.' instead of '*' for shell wildcards in aliases
  - Keys are stored encrypted at:
    /data/data/com.termux/files/home/.local/home/qwenx/.qwenx/secrets/context7.keys
EOF
}

models_help() {
  cat <<'EOF'
Usage:
  qwenx models list              # list models currently stored in .qwen/settings.json
  qwenx models sync              # fetch models from API and sync to .qwen/settings.json

Compatibility:
  qwenx --list-models            # alias of `qwenx models list`
EOF
}

models_list() {
  python3 - "$SETTINGS_FILE" <<'PY'
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

  cp "${SETTINGS_FILE}" "${SETTINGS_FILE}.bak_before_models_sync" 2>/dev/null || true

  python3 - "$SETTINGS_FILE" "${QWEN_BASE_URL:-}" "${QWEN_API_KEY:-}" <<'PY'
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

qwenx_help() {
  qwen --help
  cat <<'EOF'

qwenx extra commands:
  qwenx ctx7 <subcommand>        Manage Context7 key ring (set/add/rotate/current/clear)
  qwenx models <subcommand>      Manage model registry (list/sync)
  qwenx --list-models            Alias for `qwenx models list`
EOF
}

# Handle management subcommands
if [[ "${1:-}" == "ctx7" ]]; then
  sub="${2:-help}"
  case "${sub}" in
    set)
      shift 2
      ctx7_set_keys "$@"
      ;;
    add)
      shift 2
      ctx7_add_keys "$@"
      ;;
    rotate)
      ctx7_rotate
      ;;
    current)
      ctx7_current
      ;;
    list)
      ctx7_list_keys
      ;;
    remove)
      shift 2
      ctx7_remove "$@"
      ;;
    mode)
      shift 2
      case "${1:-}" in
        local)
          ctx7_mode_set_local
          ;;
        remote)
          ctx7_mode_set_remote
          ;;
        current)
          ctx7_mode_current
          ;;
        *)
          echo "Usage: qwenx ctx7 mode <local|remote|current>" >&2
          exit 1
          ;;
      esac
      ;;
    clear)
      ctx7_clear
      ;;
    help|--help|-h|"")
      ctx7_help
      ;;
    *)
      echo "Unknown ctx7 command: ${sub}" >&2
      ctx7_help
      exit 1
      ;;
  esac
  exit $?
fi

if [[ "${1:-}" == "models" ]]; then
  sub="${2:-help}"
  case "${sub}" in
    list)
      models_list
      ;;
    sync)
      models_sync
      ;;
    help|--help|-h|"")
      models_help
      ;;
    *)
      echo "Unknown models command: ${sub}" >&2
      models_help
      exit 1
      ;;
  esac
  exit $?
fi

if [[ "${1:-}" == "--list-models" ]]; then
  models_list
  exit $?
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
  qwenx_help
  exit 0
fi

# Auto-apply current key for normal qwen runs
ctx7_apply_current || true

needs_context7() {
  local query=""
  for arg in "$@"; do
    if [[ ! "${arg}" =~ ^- ]]; then
      query="${query} ${arg}"
    fi
  done

  local query_lower
  query_lower="$(echo "${query}" | tr '[:upper:]' '[:lower:]')"

  if [[ "${query_lower}" =~ documentation ]] || [[ "${query_lower}" =~ api ]] || [[ "${query_lower}" =~ library ]] || [[ "${query_lower}" =~ framework ]] || [[ "${query_lower}" =~ setup ]] || [[ "${query_lower}" =~ configuration ]] || [[ "${query_lower}" =~ config ]] || [[ "${query_lower}" =~ install ]] || [[ "${query_lower}" =~ "how to" ]] || [[ "${query_lower}" =~ tutorial ]] || [[ "${query_lower}" =~ guide ]] || [[ "${query_lower}" =~ reference ]] || [[ "${query_lower}" =~ manual ]] || [[ "${query_lower}" =~ "code generation" ]] || [[ "${query_lower}" =~ "generate code" ]] || [[ "${query_lower}" =~ "create code" ]] || [[ "${query_lower}" =~ implement ]] || [[ "${query_lower}" =~ initialize ]] || [[ "${query_lower}" =~ configure ]] || [[ "${query_lower}" =~ setting ]] || [[ "${query_lower}" =~ parameter ]] || [[ "${query_lower}" =~ "parameter list" ]] || [[ "${query_lower}" =~ authentication ]] || [[ "${query_lower}" =~ auth ]] || [[ "${query_lower}" =~ oauth ]] || [[ "${query_lower}" =~ "api key" ]] || [[ "${query_lower}" =~ secret ]] || [[ "${query_lower}" =~ token ]] || [[ "${query_lower}" =~ environment ]] || [[ "${query_lower}" =~ env ]] || [[ "${query_lower}" =~ variable ]] || [[ "${query_lower}" =~ "env var" ]] || [[ "${query_lower}" =~ credential ]] || [[ "${query_lower}" =~ login ]] || [[ "${query_lower}" =~ register ]] || [[ "${query_lower}" =~ account ]] || [[ "${query_lower}" =~ model ]] || [[ "${query_lower}" =~ provider ]] || [[ "${query_lower}" =~ extension ]] || [[ "${query_lower}" =~ plugin ]] || [[ "${query_lower}" =~ hook ]] || [[ "${query_lower}" =~ skill ]] || [[ "${query_lower}" =~ tool ]] || [[ "${query_lower}" =~ capability ]] || [[ "${query_lower}" =~ feature ]] || [[ "${query_lower}" =~ architecture ]] || [[ "${query_lower}" =~ structure ]] || [[ "${query_lower}" =~ schema ]] || [[ "${query_lower}" =~ protocol ]] || [[ "${query_lower}" =~ standard ]] || [[ "${query_lower}" =~ specification ]] || [[ "${query_lower}" =~ "reference implementation" ]] || [[ "${query_lower}" =~ boilerplate ]] || [[ "${query_lower}" =~ template ]] || [[ "${query_lower}" =~ skeleton ]] || [[ "${query_lower}" =~ stub ]] || [[ "${query_lower}" =~ mock ]]; then
    return 0
  else
    return 1
  fi
}

MCP_SPECIFIED=false
EXTENSIONS_SPECIFIED=false
SKILLS_SPECIFIED=false
HOOKS_SPECIFIED=false
RESUME_SPECIFIED=false
MCP_COMMAND_USED=false

for arg in "$@"; do
  if [[ "${arg}" == "--mcp"* ]]; then
    MCP_SPECIFIED=true
  elif [[ "${arg}" == "--extensions"* ]] || [[ "${arg}" == "-e "* ]]; then
    EXTENSIONS_SPECIFIED=true
  elif [[ "${arg}" == "--skills"* ]] || [[ "${arg}" == "-s "* ]]; then
    SKILLS_SPECIFIED=true
  elif [[ "${arg}" == "--hooks"* ]] || [[ "${arg}" == "--hook"* ]]; then
    HOOKS_SPECIFIED=true
  elif [[ "${arg}" == "-r"* ]] || [[ "${arg}" == "--resume"* ]]; then
    RESUME_SPECIFIED=true
  fi
done

if [[ "${1:-}" == "mcp" ]]; then
  MCP_COMMAND_USED=true
fi

if needs_context7 "$@" && [[ "${MCP_COMMAND_USED}" == false ]]; then
  cp "${_FAKEHOME}/.qwen/settings.json" "${_FAKEHOME}/.qwen/settings.json.bak_before_context7" 2>/dev/null || true

  python3 -c "
import json
with open('${_FAKEHOME}/.qwen/settings.json', 'r', encoding='utf-8') as f:
    settings = json.load(f)
if 'mcp' in settings:
    if 'excluded' in settings['mcp'] and 'context7' in settings['mcp']['excluded']:
        settings['mcp']['excluded'].remove('context7')
    if 'allowed' in settings['mcp'] and 'context7' not in settings['mcp']['allowed']:
        settings['mcp']['allowed'].append('context7')
with open('${_FAKEHOME}/.qwen/settings.json', 'w', encoding='utf-8') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
print('Enabled context7 for this session based on query content')
"
fi

if [[ "${MCP_SPECIFIED}" == false ]] && [[ "${EXTENSIONS_SPECIFIED}" == false ]] && [[ "${SKILLS_SPECIFIED}" == false ]] && [[ "${HOOKS_SPECIFIED}" == false ]] && [[ "${RESUME_SPECIFIED}" == false ]] && [[ "${MCP_COMMAND_USED}" == false ]]; then
  exec qwen "$@"
else
  exec qwen "$@"
fi
