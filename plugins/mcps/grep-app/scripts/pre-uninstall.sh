#!/usr/bin/env bash
# Grep-App MCP Plugin - Pre Uninstall Hook
# Runs before the plugin is uninstalled
#
# This script:
# 1. Backs up user configuration (optional)
# 2. Cleans up enabled symlinks
# 3. Removes cached data
# 4. Preserves user settings
# 5. Provides uninstall confirmation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN_NAME="grep-app"

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

# Whether to preserve user config
PRESERVE_CONFIG="${PRESERVE_CONFIG:-true}"

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
    local fake_home="${_FAKEHOME:-$HOME}"
    echo "${fake_home}/.qwen/settings.json"
}

# Get enabled plugins directory
get_enabled_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/enabled/${PLUGIN_TYPE:-mcps}"
}

# Get cache directory
get_cache_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/cache/grep-app"
}

# Get config directory
get_config_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/grep-app"
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
    echo "  Grep-App MCP Plugin - Pre Uninstall"
    echo "=============================================="
    echo ""

    log_info "This script will prepare for Grep-App MCP plugin removal."
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

    if [[ "$PRESERVE_CONFIG" == "true" ]]; then
        echo "  ✓ Preserve user configuration"
    else
        echo "  ! WARNING: Will remove user configuration"
    fi

    echo ""
}

step_backup_config() {
    if [[ "$BACKUP_CONFIG" != "true" ]]; then
        log_info "Skipping configuration backup (BACKUP_CONFIG=false)"
        return 0
    fi

    log_info "Backing up configuration..."

    local config_dir
    config_dir="$(get_config_dir)"
    local backup_dir
    backup_dir="$(get_oml_config_dir)/backups"

    mkdir -p "$backup_dir"

    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_file="${backup_dir}/grep-app_${timestamp}.tar.gz"

    if [[ -d "$config_dir" ]]; then
        tar -czf "$backup_file" -C "$(dirname "$config_dir")" "$(basename "$config_dir")" 2>/dev/null || true
        log_success "Configuration backed up to: ${backup_file}"
    else
        log_info "No config directory found, skipping backup"
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
}

step_cleanup_settings() {
    log_info "Cleaning up settings.json..."

    local settings_file
    settings_file="$(get_settings_file)"

    if [[ ! -f "$settings_file" ]]; then
        log_info "No settings.json found"
        return 0
    fi

    # Remove grep-app configuration from settings
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
if 'mcpServers' in data and 'grep-app' in data['mcpServers']:
    del data['mcpServers']['grep-app']
    modified = True
    print("Removed grep-app from mcpServers")

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
if modified:
    print("Settings updated")
else:
    print("No grep-app configuration found")
PY
}

step_preserve_config() {
    if [[ "$PRESERVE_CONFIG" != "true" ]]; then
        log_warn "PRESERVE_CONFIG=false, configuration will be removed!"
        local config_dir
        config_dir="$(get_config_dir)"
        if [[ -d "$config_dir" ]]; then
            rm -rf "$config_dir"
            log_info "Removed config directory: ${config_dir}"
        fi
        return 0
    fi

    log_info "Preserving user configuration..."

    local config_dir
    config_dir="$(get_config_dir)"

    if [[ -d "$config_dir" ]]; then
        log_info "Configuration preserved in: ${config_dir}"
        log_warn "To remove config manually: rm -rf ${config_dir}"
    else
        log_info "No config directory found"
    fi
}

step_cleanup_logs() {
    log_info "Cleaning up log files..."

    local log_dir
    log_dir="$(get_log_dir)"

    if [[ -d "$log_dir" ]]; then
        local grep_app_logs
        grep_app_logs=$(find "$log_dir" -name "*grep-app*" -type f 2>/dev/null || true)
        if [[ -n "$grep_app_logs" ]]; then
            echo "$grep_app_logs" | while read -r log_file; do
                rm -f "$log_file"
                log_info "Removed log: ${log_file}"
            done
        else
            log_info "No grep-app log files found"
        fi
    fi
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
    if [[ "$PRESERVE_CONFIG" == "true" ]]; then
        echo "  - User config: preserved"
    else
        echo "  - User config: removed"
    fi
    echo "  - Settings: grep-app config removed"
    echo "  - Logs: cleaned up"
    echo ""

    echo "What's Next:"
    echo "------------"
    echo "The plugin manager will now remove the plugin files."
    echo ""

    if [[ "$PRESERVE_CONFIG" == "true" ]]; then
        echo "Note: Your configuration is preserved in:"
        echo "  $(get_config_dir)"
        echo ""
        echo "To completely remove all traces:"
        echo "  rm -rf $(get_config_dir)"
        echo ""
    fi

    echo "To reinstall later:"
    echo "  oml mcps install grep-app"
    echo ""

    local backup_dir
    backup_dir="$(get_oml_config_dir)/backups"
    echo "To restore configuration from backup:"
    echo "  tar -xzf ${backup_dir}/grep-app_*.tar.gz -C ~/"
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
    step_cleanup_settings
    step_preserve_config
    step_cleanup_logs
    step_show_summary
}

main "$@"
