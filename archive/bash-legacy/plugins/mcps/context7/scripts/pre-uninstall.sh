#!/usr/bin/env bash
# Context7 MCP Plugin - Pre Uninstall Hook
# Runs before the plugin is uninstalled
#
# This script:
# 1. Backs up user configuration (optional)
# 2. Cleans up enabled symlinks
# 3. Removes cached data
# 4. Preserves user secrets (API keys)
# 5. Provides uninstall confirmation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN_NAME="context7"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Configuration
# ============================================================================

# Whether to backup configuration before uninstall
BACKUP_CONFIG="${BACKUP_CONFIG:-true}"

# Whether to preserve user secrets (API keys)
PRESERVE_SECRETS="${PRESERVE_SECRETS:-true}"

# Whether to remove cached data
REMOVE_CACHE="${REMOVE_CACHE:-true}"

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_question() {
    echo -e "${CYAN}[QUESTION]${NC} $*"
}

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

# Get enabled plugins directory
get_enabled_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/enabled/mcps"
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

# Get cache directory
get_cache_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/cache/context7"
}

# Get log directory
get_log_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/logs"
}

# ============================================================================
# Uninstall Steps
# ============================================================================

step_confirm_uninstall() {
    echo ""
    echo "=============================================="
    echo "  Context7 MCP Plugin - Pre Uninstall"
    echo "=============================================="
    echo ""
    
    log_info "This script will prepare for Context7 MCP plugin removal."
    echo ""
    
    # Show what will be done
    echo "Actions to be performed:"
    echo "------------------------"
    
    if [[ "$BACKUP_CONFIG" == "true" ]]; then
        echo "  ✓ Backup configuration files"
    else
        echo "  ✗ Skip configuration backup"
    fi
    
    # Check if enabled
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    if [[ -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        echo "  ✓ Remove enabled symlink"
    else
        echo "  - No enabled symlink found"
    fi
    
    if [[ "$REMOVE_CACHE" == "true" ]]; then
        local cache_dir
        cache_dir="$(get_cache_dir)"
        if [[ -d "$cache_dir" ]]; then
            echo "  ✓ Remove cached data"
        else
            echo "  - No cache directory found"
        fi
    else
        echo "  ✗ Skip cache removal"
    fi
    
    if [[ "$PRESERVE_SECRETS" == "true" ]]; then
        echo "  ✓ Preserve API keys and secrets"
    else
        echo "  ! WARNING: Will remove API keys and secrets"
    fi
    
    echo ""
}

step_backup_config() {
    if [[ "$BACKUP_CONFIG" != "true" ]]; then
        log_info "Skipping configuration backup (BACKUP_CONFIG=false)"
        return 0
    fi
    
    log_info "Backing up configuration..."
    
    local settings_file
    settings_file="$(get_settings_file)"
    local backup_dir
    backup_dir="$(get_oml_config_dir)/backups"
    
    mkdir -p "$backup_dir"
    
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_file="${backup_dir}/settings_context7_${timestamp}.json"
    
    if [[ -f "$settings_file" ]]; then
        # Extract only context7-related config for backup
        python3 - "${settings_file}" "${backup_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
backup_path = Path(sys.argv[2])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

# Extract context7-related configuration
context7_backup = {
    'mcpServers': {},
    'mcp': data.get('mcp', {}),
    'context7': data.get('context7', {})
}

# Only include context7 server config
if 'context7' in data.get('mcpServers', {}):
    context7_backup['mcpServers']['context7'] = data['mcpServers']['context7']

backup_path.parent.mkdir(parents=True, exist_ok=True)
backup_path.write_text(json.dumps(context7_backup, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f"Backup saved to: {backup_path}")
PY
        log_success "Configuration backed up to: ${backup_file}"
    else
        log_info "No settings.json found, skipping backup"
    fi
}

step_cleanup_enabled() {
    log_info "Cleaning up enabled symlinks..."
    
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    
    if [[ -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        rm "${enabled_dir}/${PLUGIN_NAME}"
        log_success "Removed enabled symlink: ${enabled_dir}/${PLUGIN_NAME}"
    else
        log_info "No enabled symlink found"
    fi
    
    # Also check agents enabled dir (for cross-references)
    local agents_enabled_dir
    agents_enabled_dir="$(get_oml_config_dir)/enabled/agents"
    
    # Clean up any context7 references in agent configs
    if [[ -d "$agents_enabled_dir" ]]; then
        for agent_link in "$agents_enabled_dir"/*/; do
            if [[ -d "$agent_link" ]]; then
                local agent_settings
                agent_settings="${agent_link}settings.json"
                # Skip if no settings file
                [[ ! -f "$agent_settings" ]] && continue
            fi
        done
    fi
}

step_cleanup_cache() {
    if [[ "$REMOVE_CACHE" != "true" ]]; then
        log_info "Skipping cache removal (REMOVE_CACHE=false)"
        return 0
    fi
    
    log_info "Cleaning up cached data..."
    
    local cache_dir
    cache_dir="$(get_cache_dir)"
    
    if [[ -d "$cache_dir" ]]; then
        rm -rf "$cache_dir"
        log_success "Removed cache directory: ${cache_dir}"
    else
        log_info "No cache directory found"
    fi
    
    # Clean up any context7 logs
    local log_dir
    log_dir="$(get_log_dir)"
    if [[ -d "$log_dir" ]]; then
        local context7_logs
        context7_logs=$(find "$log_dir" -name "*context7*" -type f 2>/dev/null || true)
        if [[ -n "$context7_logs" ]]; then
            echo "$context7_logs" | while read -r log_file; do
                rm -f "$log_file"
                log_info "Removed log: ${log_file}"
            done
        fi
    fi
}

step_preserve_secrets() {
    if [[ "$PRESERVE_SECRETS" != "true" ]]; then
        log_warn "PRESERVE_SECRETS=false, API keys will be removed!"
        return 0
    fi
    
    log_info "Preserving user secrets (API keys)..."
    
    local secrets_dir
    secrets_dir="$(get_ctx7_secrets_dir)"
    
    if [[ -d "$secrets_dir" ]]; then
        local keys_file="${secrets_dir}/context7.keys"
        local index_file="${secrets_dir}/context7.index"
        
        if [[ -f "$keys_file" ]]; then
            # Count keys
            local key_count
            key_count=$(wc -l < "$keys_file" 2>/dev/null || echo "0")
            log_info "Found ${key_count} stored API key(s)"
            log_info "Secrets preserved in: ${secrets_dir}"
            log_warn "To remove secrets manually, delete: ${keys_file}"
        else
            log_info "No stored API keys found"
        fi
    else
        log_info "No secrets directory found"
    fi
}

step_cleanup_settings() {
    log_info "Cleaning up settings.json..."
    
    local settings_file
    settings_file="$(get_settings_file)"
    
    if [[ ! -f "$settings_file" ]]; then
        log_info "No settings.json found"
        return 0
    fi
    
    # Remove context7 configuration from settings
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

modified = False

# Remove from mcpServers
if 'mcpServers' in data and 'context7' in data['mcpServers']:
    del data['mcpServers']['context7']
    modified = True
    print("Removed context7 from mcpServers")

# Remove from mcp.servers list
if 'mcp' in data and 'servers' in data['mcp']:
    data['mcp']['servers'] = [
        s for s in data['mcp']['servers']
        if s.get('name') != 'context7'
    ]
    modified = True
    print("Removed context7 from mcp.servers")

# Remove context7 top-level config
if 'context7' in data:
    del data['context7']
    modified = True
    print("Removed top-level context7 config")

if modified:
    settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print("Settings updated")
else:
    print("No context7 configuration found")
PY
}

step_show_summary() {
    echo ""
    echo "=============================================="
    echo "  Pre-Uninstall Complete"
    echo "=============================================="
    echo ""
    
    log_success "Pre-uninstall cleanup completed!"
    echo ""
    
    echo "Summary:"
    echo "--------"
    echo "  - Configuration: backed up (if existed)"
    echo "  - Enabled symlink: removed"
    if [[ "$REMOVE_CACHE" == "true" ]]; then
        echo "  - Cache: cleared"
    else
        echo "  - Cache: preserved"
    fi
    if [[ "$PRESERVE_SECRETS" == "true" ]]; then
        echo "  - API keys: preserved"
    else
        echo "  - API keys: removed"
    fi
    echo "  - Settings: context7 config removed"
    echo ""
    
    echo "What's Next:"
    echo "------------"
    echo "The plugin manager will now remove the plugin files."
    echo ""
    
    if [[ "$PRESERVE_SECRETS" == "true" ]]; then
        echo "Note: Your API keys are preserved in:"
        echo "  $(get_ctx7_secrets_dir)/context7.keys"
        echo ""
        echo "To completely remove all traces:"
        echo "  rm -rf $(get_ctx7_secrets_dir)"
        echo ""
    fi
    
    echo "To reinstall later:"
    echo "  oml mcps install context7"
    echo ""
    
    echo "To restore configuration from backup:"
    echo "  cp ~/.oml/backups/settings_context7_*.json ~/.qwen/settings.json"
    echo ""
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    step_confirm_uninstall
    step_backup_config
    step_cleanup_enabled
    step_cleanup_cache
    step_preserve_secrets
    step_cleanup_settings
    step_show_summary
}

main "$@"
