#!/usr/bin/env bash
# Context7 MCP Plugin for OML
# Provides MCP (Model Context Protocol) service management for Context7
#
# Usage:
#   oml mcps context7 list              # List MCP services
#   oml mcps context7 enable            # Enable Context7 MCP
#   oml mcps context7 disable           # Disable Context7 MCP
#   oml mcps context7 status            # Check service status
#   oml mcps context7 config <key> <val> # Configure settings
#
# Examples:
#   # Enable local mode (runs npx @upstash/context7-mcp locally)
#   oml mcps context7 enable --mode local
#
#   # Enable remote mode (uses Context7 API)
#   oml mcps context7 enable --mode remote --api-key "your-key"
#
#   # Check current status
#   oml mcps context7 status
#
#   # Configure API key
#   oml mcps context7 config api_key "sk-xxx"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"
PLUGIN_NAME="context7"
PLUGIN_TYPE="mcps"

# OML core paths
OML_CORE_DIR="${OML_CORE_DIR:-}"
if [[ -z "$OML_CORE_DIR" ]]; then
    # Try to find core directory relative to plugin
    if [[ -d "${SCRIPT_DIR}/../../core" ]]; then
        OML_CORE_DIR="$(cd "${SCRIPT_DIR}/../../core" && pwd)"
    fi
fi

# Source OML core modules
if [[ -n "$OML_CORE_DIR" && -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi
if [[ -n "$OML_CORE_DIR" && -f "${OML_CORE_DIR}/plugin-loader.sh" ]]; then
    source "${OML_CORE_DIR}/plugin-loader.sh"
fi

# ============================================================================
# Configuration
# ============================================================================

# Get OML config directory
get_oml_config_dir() {
    if [[ -n "${_FAKEHOME:-}" ]]; then
        echo "${_FAKEHOME}/.oml"
    else
        echo "${HOME}/.oml"
    fi
}

# Get settings file path
get_settings_file() {
    local fake_home
    if [[ -n "${_FAKEHOME:-}" ]]; then
        fake_home="${_FAKEHOME}"
    else
        fake_home="${HOME}"
    fi
    echo "${fake_home}/.qwen/settings.json"
}

# Get Context7 secrets directory
get_ctx7_secrets_dir() {
    local fake_home
    if [[ -n "${_FAKEHOME:-}" ]]; then
        fake_home="${_FAKEHOME}"
    else
        fake_home="${HOME}"
    fi
    echo "${fake_home}/.qwenx/secrets"
}

# Get enabled plugins directory
get_enabled_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/enabled/${PLUGIN_TYPE}"
}

# ============================================================================
# Utility Functions
# ============================================================================

# Log message with timestamp
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Check if running on Termux
is_termux() {
    [[ -d "/data/data/com.termux/files/usr" ]]
}

# Check if running on GNU/Linux
is_gnu_linux() {
    ! is_termux
}

# Check if npx is available
check_npx() {
    if command -v npx >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if node is available
check_node() {
    if command -v node >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ============================================================================
# MCP List Command
# ============================================================================

mcp_list() {
    local format="${1:-plain}"
    
    log_info "Listing MCP services..."
    
    # Check settings file
    local settings_file
    settings_file="$(get_settings_file)"
    
    if [[ ! -f "$settings_file" ]]; then
        echo "No MCP services configured (settings.json not found)"
        echo "Run 'oml qwen init' to initialize configuration"
        return 0
    fi
    
    # Parse MCP servers from settings.json
    python3 - "${settings_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
if not settings_path.exists():
    print("settings.json not found")
    sys.exit(0)

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

mcp_servers = data.get('mcpServers', {})
if not mcp_servers:
    print("No MCP servers configured")
    sys.exit(0)

print(f"Configured MCP Servers ({len(mcp_servers)}):")
print("-" * 50)

for name, config in mcp_servers.items():
    if not isinstance(config, dict):
        continue
    
    enabled = config.get('enabled', False)
    protocol = config.get('protocol', 'unknown')
    
    # Determine mode
    if 'command' in config:
        mode = "local"
        command = config.get('command', '')
        args = config.get('args', [])
        detail = f"{command} {' '.join(args)}" if args else command
    elif 'url' in config:
        url = config.get('url', '')
        if url:
            mode = "remote"
            detail = url
        else:
            mode = "disabled"
            detail = "(no URL)"
    else:
        mode = "unknown"
        detail = "(no configuration)"
    
    status = "✓" if enabled else "✗"
    print(f"[{status}] {name}")
    print(f"    Mode: {mode}")
    print(f"    Protocol: {protocol}")
    print(f"    Config: {detail}")
    
    # Show tools if available
    tools = config.get('tools', [])
    if tools:
        print(f"    Tools: {', '.join(tools[:3])}{'...' if len(tools) > 3 else ''}")
    
    print()
PY
}

# ============================================================================
# MCP Enable Command
# ============================================================================

mcp_enable() {
    local mode="local"
    local api_key=""
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode|-m)
                mode="$2"
                shift 2
                ;;
            --api-key|-k)
                api_key="$2"
                shift 2
                ;;
            --force|-f)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: oml mcps context7 enable [--mode local|remote] [--api-key KEY]"
                return 1
                ;;
        esac
    done
    
    # Validate mode
    case "$mode" in
        local|remote)
            ;;
        *)
            log_error "Invalid mode: $mode (must be 'local' or 'remote')"
            return 1
            ;;
    esac
    
    log_info "Enabling Context7 MCP in ${mode} mode..."
    
    local settings_file
    settings_file="$(get_settings_file)"
    
    # Ensure settings file exists
    if [[ ! -f "$settings_file" ]]; then
        log_warn "settings.json not found, creating default configuration..."
        local fake_home
        fake_home="$(dirname "$settings_file")"
        mkdir -p "$fake_home"
        
        cat > "$settings_file" <<'EOF'
{
  "mcpServers": {},
  "modelProviders": {},
  "model": {}
}
EOF
    fi
    
    # Update settings based on mode
    if [[ "$mode" == "local" ]]; then
        enable_local_mode "$settings_file"
    else
        enable_remote_mode "$settings_file" "$api_key"
    fi
    
    # Create enabled symlink
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    mkdir -p "$enabled_dir"
    
    if [[ ! -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        ln -sf "$PLUGIN_DIR" "${enabled_dir}/${PLUGIN_NAME}"
        log_info "Created enabled symlink: ${enabled_dir}/${PLUGIN_NAME}"
    fi
    
    log_info "Context7 MCP enabled successfully!"
    echo ""
    echo "To use Context7, run: oml qwen ctx7 mode ${mode}"
}

# Enable local mode (runs npx locally)
enable_local_mode() {
    local settings_file="$1"
    
    log_info "Configuring local mode (npx @upstash/context7-mcp)..."
    
    # Check dependencies
    if ! check_node; then
        log_error "Node.js not found. Please install nodejs first."
        if is_termux; then
            echo "  Termux: pkg install nodejs"
        else
            echo "  GNU/Linux: apt install nodejs npm"
        fi
        return 1
    fi
    
    if ! check_npx; then
        log_error "npx not found. Please install npm first."
        return 1
    fi
    
    python3 - "${settings_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

mcp_servers = data.setdefault('mcpServers', {})

# Configure context7 for local mode
mcp_servers['context7'] = {
    'command': 'npx',
    'args': ['-y', '@upstash/context7-mcp@latest'],
    'protocol': 'mcp',
    'enabled': True,
    'trust': False,
    'excludeTools': []
}

# Also update mcp.servers list
mcp_list = data.setdefault('mcp', {}).setdefault('servers', [])
found = False
for server in mcp_list:
    if server.get('name') == 'context7':
        server.update({
            'name': 'context7',
            'protocol': 'mcp',
            'enabled': True
        })
        # Remove URL for local mode
        if 'url' in server:
            del server['url']
        found = True
        break

if not found:
    mcp_list.append({
        'name': 'context7',
        'protocol': 'mcp',
        'enabled': True
    })

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print("Updated settings.json for local Context7 mode")
PY
    
    log_info "Local mode configured. Context7 will run via npx."
}

# Enable remote mode (uses Context7 API)
enable_remote_mode() {
    local settings_file="$1"
    local api_key="${2:-}"
    
    log_info "Configuring remote mode (Context7 API)..."
    
    # If API key provided, store it
    if [[ -n "$api_key" ]]; then
        store_api_key "$api_key"
    fi
    
    python3 - "${settings_file}" "${api_key}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
api_key = sys.argv[2] if len(sys.argv) > 2 else ""

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

mcp_servers = data.setdefault('mcpServers', {})

# Configure context7 for remote mode
ctx7_config = {
    'url': 'https://mcp.context7.com/mcp',
    'protocol': 'mcp',
    'enabled': True,
    'trust': False,
    'excludeTools': [],
    'headers': {}
}

if api_key:
    ctx7_config['headers']['X-Context7-API-Key'] = '${CONTEXT7_API_KEY}'

mcp_servers['context7'] = ctx7_config

# Also update mcp.servers list
mcp_list = data.setdefault('mcp', {}).setdefault('servers', [])
found = False
for server in mcp_list:
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
    mcp_list.append({
        'name': 'context7',
        'url': 'https://mcp.context7.com/mcp',
        'protocol': 'mcp',
        'enabled': True
    })

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print("Updated settings.json for remote Context7 mode")
PY
    
    log_info "Remote mode configured. Set CONTEXT7_API_KEY environment variable or use 'oml qwen ctx7 set <key>'"
}

# ============================================================================
# MCP Disable Command
# ============================================================================

mcp_disable() {
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    log_info "Disabling Context7 MCP..."
    
    local settings_file
    settings_file="$(get_settings_file)"
    
    if [[ ! -f "$settings_file" ]]; then
        log_warn "settings.json not found, nothing to disable"
        return 0
    fi
    
    python3 - "${settings_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

# Disable in mcpServers
mcp_servers = data.get('mcpServers', {})
if 'context7' in mcp_servers:
    mcp_servers['context7']['enabled'] = False
    print("Disabled context7 in mcpServers")
else:
    print("context7 not found in mcpServers")

# Disable in mcp.servers list
mcp_list = data.get('mcp', {}).get('servers', [])
for server in mcp_list:
    if server.get('name') == 'context7':
        server['enabled'] = False
        print("Disabled context7 in mcp.servers")
        break

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print("Settings updated")
PY
    
    # Remove enabled symlink
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    if [[ -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        rm "${enabled_dir}/${PLUGIN_NAME}"
        log_info "Removed enabled symlink"
    fi
    
    log_info "Context7 MCP disabled"
}

# ============================================================================
# MCP Status Command
# ============================================================================

mcp_status() {
    log_info "Checking Context7 MCP status..."
    echo ""
    
    local settings_file
    settings_file="$(get_settings_file)"
    
    # Check if enabled
    local enabled=false
    local mode="unknown"
    local api_key_set=false
    
    if [[ -f "$settings_file" ]]; then
        local status_info
        status_info=$(python3 - "${settings_file}" <<'PY'
import json
import sys
import os
from pathlib import Path

settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except:
    print("disabled|unknown|false")
    sys.exit(0)

mcp_servers = data.get('mcpServers', {})
ctx7 = mcp_servers.get('context7', {})

enabled = ctx7.get('enabled', False)

# Determine mode
if 'command' in ctx7:
    mode = "local"
elif 'url' in ctx7:
    url = ctx7.get('url', '')
    if url.startswith('https://'):
        mode = "remote"
    elif url:
        mode = "custom"
    else:
        mode = "disabled"
else:
    mode = "unknown"

# Check API key
api_key_set = bool(os.environ.get('CONTEXT7_API_KEY', ''))
if not api_key_set:
    # Check if key file exists
    fake_home = os.environ.get('_FAKEHOME', os.environ.get('HOME', ''))
    key_file = Path(fake_home) / '.qwenx' / 'secrets' / 'context7.keys'
    if key_file.exists():
        try:
            content = key_file.read_text().strip()
            api_key_set = bool(content)
        except:
            pass

print(f"{'enabled' if enabled else 'disabled'}|{mode}|{'true' if api_key_set else 'false'}")
PY
)
        enabled=$(echo "$status_info" | cut -d'|' -f1)
        mode=$(echo "$status_info" | cut -d'|' -f2)
        api_key_set=$(echo "$status_info" | cut -d'|' -f3)
    fi
    
    # Check if plugin is enabled
    local plugin_enabled=false
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    if [[ -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        plugin_enabled=true
    fi
    
    # Display status
    echo "Context7 MCP Status"
    echo "==================="
    echo ""
    
    # Plugin status
    if [[ "$plugin_enabled" == "true" ]]; then
        echo "Plugin:      ✓ Enabled"
    else
        echo "Plugin:      ✗ Disabled"
    fi
    
    # Service status
    if [[ "$enabled" == "enabled" ]]; then
        echo "Service:     ✓ Enabled"
    else
        echo "Service:     ✗ Disabled"
    fi
    
    # Mode
    echo "Mode:        ${mode}"
    
    # API Key
    if [[ "$api_key_set" == "true" ]]; then
        echo "API Key:     ✓ Configured"
    else
        if [[ "$mode" == "remote" ]]; then
            echo "API Key:     ✗ Not set (required for remote mode)"
        else
            echo "API Key:     - Not required (local mode)"
        fi
    fi
    
    # Platform info
    echo ""
    echo "Platform:"
    if is_termux; then
        echo "  - Running on: Termux (Android)"
    else
        echo "  - Running on: GNU/Linux"
    fi
    
    # Dependency check
    echo ""
    echo "Dependencies:"
    if check_node; then
        echo "  - Node.js:   ✓ Installed ($(node --version 2>/dev/null || echo 'unknown'))"
    else
        echo "  - Node.js:   ✗ Not installed"
    fi
    
    if check_npx; then
        echo "  - npx:       ✓ Installed"
    else
        echo "  - npx:       ✗ Not installed"
    fi
    
    echo ""
    
    # Recommendations
    if [[ "$enabled" == "disabled" ]]; then
        echo "Recommendation: Run 'oml mcps context7 enable' to enable"
    elif [[ "$mode" == "remote" && "$api_key_set" == "false" ]]; then
        echo "Recommendation: Set API key with 'oml qwen ctx7 set <your-key>'"
    elif [[ "$mode" == "local" ]]; then
        if ! check_npx; then
            echo "Recommendation: Install npm for local mode support"
        fi
    fi
}

# ============================================================================
# MCP Config Command
# ============================================================================

mcp_config() {
    local key="${1:-}"
    local value="${2:-}"
    
    if [[ -z "$key" ]]; then
        show_config
        return 0
    fi
    
    case "$key" in
        mode)
            set_config_mode "$value"
            ;;
        api_key)
            set_config_api_key "$value"
            ;;
        url)
            set_config_url "$value"
            ;;
        *)
            log_error "Unknown config key: $key"
            echo "Available keys: mode, api_key, url"
            return 1
            ;;
    esac
}

# Show current configuration
show_config() {
    local settings_file
    settings_file="$(get_settings_file)"
    
    echo "Current Context7 Configuration"
    echo "=============================="
    echo ""
    
    if [[ ! -f "$settings_file" ]]; then
        echo "settings.json not found"
        return 0
    fi
    
    python3 - "${settings_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

mcp_servers = data.get('mcpServers', {})
ctx7 = mcp_servers.get('context7', {})

if not ctx7:
    print("Context7 not configured")
    sys.exit(0)

print(f"Enabled:     {ctx7.get('enabled', False)}")
print(f"Protocol:    {ctx7.get('protocol', 'unknown')}")

if 'command' in ctx7:
    cmd = ctx7.get('command', '')
    args = ctx7.get('args', [])
    print(f"Command:     {cmd} {' '.join(args)}")
    print("Mode:        local")
elif 'url' in ctx7:
    url = ctx7.get('url', '')
    print(f"URL:         {url if url else '(empty)'}")
    if url.startswith('https://'):
        print("Mode:        remote")
    else:
        print("Mode:        custom")

headers = ctx7.get('headers', {})
if headers:
    print(f"Headers:     {list(headers.keys())}")

tools = ctx7.get('tools', [])
if tools:
    print(f"Tools:       {len(tools)} configured")

exclude = ctx7.get('excludeTools', [])
if exclude:
    print(f"Excluded:    {exclude}")
PY
}

# Set configuration mode
set_config_mode() {
    local mode="$1"
    
    case "$mode" in
        local)
            local settings_file
            settings_file="$(get_settings_file)"
            enable_local_mode "$settings_file"
            ;;
        remote)
            local settings_file
            settings_file="$(get_settings_file)"
            enable_remote_mode "$settings_file"
            ;;
        *)
            log_error "Invalid mode: $mode (must be 'local' or 'remote')"
            return 1
            ;;
    esac
}

# Set API key
set_config_api_key() {
    local api_key="$1"
    
    if [[ -z "$api_key" ]]; then
        log_error "API key cannot be empty"
        return 1
    fi
    
    store_api_key "$api_key"
    log_info "API key stored successfully"
}

# Store API key in secrets
store_api_key() {
    local api_key="$1"
    local secrets_dir
    secrets_dir="$(get_ctx7_secrets_dir)"
    
    mkdir -p "$secrets_dir"
    chmod 700 "$secrets_dir" 2>/dev/null || true
    
    # Encode key in base64
    local encoded_key
    encoded_key=$(printf '%s' "$api_key" | base64 -w 0)
    
    # Store with alias
    local keys_file="${secrets_dir}/context7.keys"
    local index_file="${secrets_dir}/context7.index"
    
    echo "default@${encoded_key}" > "$keys_file"
    echo "0" > "$index_file"
    
    chmod 600 "$keys_file" "$index_file" 2>/dev/null || true
    
    log_info "API key stored in: $keys_file"
}

# Set custom URL
set_config_url() {
    local url="$1"
    local settings_file
    settings_file="$(get_settings_file)"
    
    if [[ ! -f "$settings_file" ]]; then
        log_error "settings.json not found"
        return 1
    fi
    
    python3 - "${settings_file}" "${url}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
url = sys.argv[2]

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

mcp_servers = data.setdefault('mcpServers', {})
ctx7 = mcp_servers.setdefault('context7', {})

# Remove local mode settings
if 'command' in ctx7:
    del ctx7['command']
if 'args' in ctx7:
    del ctx7['args']

# Set URL
ctx7['url'] = url
ctx7['enabled'] = True

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f"Set Context7 URL to: {url}")
PY
}

# ============================================================================
# Help Command
# ============================================================================

show_help() {
    cat <<'EOF'
Context7 MCP Plugin for OML

Usage: oml mcps context7 <command> [options]

Commands:
  list                      List all configured MCP services
  enable                    Enable Context7 MCP service
  disable                   Disable Context7 MCP service
  status                    Show current status and configuration
  config <key> [value]      Configure Context7 settings

Enable Options:
  --mode, -m <local|remote>   Set operation mode (default: local)
  --api-key, -k <key>         Set API key for remote mode
  --force, -f                 Force enable even if dependencies missing

Config Keys:
  mode <local|remote>         Switch between local/remote mode
  api_key <key>               Set Context7 API key
  url <url>                   Set custom MCP server URL

Examples:
  # Enable local mode (recommended for most users)
  oml mcps context7 enable --mode local

  # Enable remote mode with API key
  oml mcps context7 enable --mode remote --api-key "sk-xxx"

  # Check status
  oml mcps context7 status

  # Switch to remote mode
  oml mcps context7 config mode remote

  # Set API key
  oml mcps context7 config api_key "sk-xxx"

Modes:
  local   - Runs npx @upstash/context7-mcp@latest locally
            Requires: nodejs, npm/npx
            No API key needed

  remote  - Connects to https://mcp.context7.com/mcp
            Requires: CONTEXT7_API_KEY
            Lower latency, no local execution

Notes:
  - Local mode is recommended for privacy and offline use
  - Remote mode requires a valid Context7 API key
  - Configuration is stored in ~/.qwen/settings.json
  - API keys are stored encrypted in ~/.qwenx/secrets/

Platform Support:
  - Termux (Android): Full support
  - GNU/Linux: Full support

See also:
  oml qwen ctx7 help    - Context7 key management
  oml qwen mcp          - General MCP management
EOF
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    local action="${1:-help}"
    shift || true
    
    case "$action" in
        # MCP management commands
        list)
            mcp_list "$@"
            ;;
        enable)
            mcp_enable "$@"
            ;;
        disable)
            mcp_disable "$@"
            ;;
        status)
            mcp_status "$@"
            ;;
        config)
            mcp_config "$@"
            ;;
        
        # Help
        help|--help|-h|"")
            show_help
            ;;
        
        # Unknown command
        *)
            log_error "Unknown command: $action"
            echo ""
            show_help
            return 1
            ;;
    esac
}

main "$@"
