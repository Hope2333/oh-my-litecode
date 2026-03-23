#!/usr/bin/env bash
# OML Unified Updater
# Self-update and component update
#
# Usage:
#   oml update [self|plugins|qwen|all]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
OML_ROOT="${OML_ROOT:-${HOME}/develop/oh-my-litecode}"
OML_BRANCH="${OML_BRANCH:-main}"
CONFIG_DIR="${HOME}/.oml"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

if [[ -f "${LIB_DIR}/system-detect.sh" ]]; then
    source "${LIB_DIR}/system-detect.sh"
    detect_system
fi

# Print step
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Print success
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print error
print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Print warning
print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# Get current version
get_current_version() {
    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r '.version // "unknown"' "$CONFIG_FILE"
    else
        echo "unknown"
    fi
}

# Get latest version
get_latest_version() {
    cd "$OML_ROOT"
    git ls-remote --tags origin | tail -1 | cut -d'/' -f3 || echo "unknown"
}

# Check for updates
check_updates() {
    print_step "Checking for updates..."
    
    local current
    current=$(get_current_version)
    
    cd "$OML_ROOT"
    git fetch origin "$OML_BRANCH"
    
    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD)
    remote_commit=$(git rev-parse origin/"$OML_BRANCH")
    
    if [[ "$local_commit" == "$remote_commit" ]]; then
        print_success "Already up to date (version: $current)"
        return 1
    else
        print_warning "Update available!"
        echo "  Current:  $local_commit"
        echo "  Latest:   $remote_commit"
        return 0
    fi
}

# Backup configuration
backup_config() {
    print_step "Backing up configuration..."
    
    local backup_dir="${CONFIG_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -r "$CONFIG_DIR"/* "$backup_dir/" 2>/dev/null || true
        print_success "Configuration backed up to: $backup_dir"
    fi
}

# Migrate configuration
migrate_config() {
    print_step "Migrating configuration..."
    
    if [[ -f "${OML_ROOT}/lib/config-migrate.sh" ]]; then
        source "${OML_ROOT}/lib/config-migrate.sh"
        migrate_all || print_warning "Configuration migration skipped"
    else
        print_warning "Migration script not found"
    fi
}

# Self-update
update_self() {
    print_step "Updating OML..."
    
    # Check for updates
    if ! check_updates; then
        return 0
    fi
    
    # Backup config
    backup_config
    
    # Pull latest changes
    cd "$OML_ROOT"
    git pull origin "$OML_BRANCH"
    
    # Migrate config
    migrate_config
    
    # Update version in config
    if [[ -f "$CONFIG_FILE" ]]; then
        local new_version
        new_version=$(git rev-parse HEAD)
        jq --arg v "$new_version" '.version = $v' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    
    print_success "OML updated successfully"
}

# Update plugins
update_plugins() {
    print_step "Updating plugins..."
    
    local plugins_dir="${OML_ROOT}/plugins"
    
    if [[ ! -d "$plugins_dir" ]]; then
        print_warning "Plugins directory not found"
        return 0
    fi
    
    local updated=0
    
    for plugin_dir in "$plugins_dir"/*/*/; do
        [[ -d "$plugin_dir" ]] || continue
        
        if [[ -d "${plugin_dir}.git" ]]; then
            print_step "Updating plugin: $(basename "$plugin_dir")"
            cd "$plugin_dir"
            git pull origin main 2>/dev/null && ((updated++)) || true
        fi
    done
    
    print_success "Updated $updated plugin(s)"
}

# Update Qwenx
update_qwen() {
    print_step "Updating Qwenx..."
    
    if [[ -f "${OML_ROOT}/plugins/agents/qwen/main.sh" ]]; then
        print_success "Qwenx is up to date (managed by OML)"
    else
        print_warning "Qwenx not found"
    fi
}

# Update all
update_all() {
    update_self
    update_plugins
    update_qwen
}

# Show status
show_status() {
    print_step "OML Status"
    echo ""
    
    # Version
    local version
    version=$(get_current_version)
    echo "Version: $version"
    
    # System
    echo "System: ${SYSTEM:-unknown}"
    
    # Root
    echo "Root: $OML_ROOT"
    
    # Config
    echo "Config: $CONFIG_FILE"
    
    # Git status
    cd "$OML_ROOT"
    local git_status
    git_status=$(git status --short)
    
    if [[ -z "$git_status" ]]; then
        echo "Status: Clean"
    else
        echo "Status: Modified"
        echo "$git_status" | head -5
    fi
}

# Print help
print_help() {
    cat <<EOF
OML Updater

Usage: oml update [command]

Commands:
  self      Update OML core
  plugins   Update plugins
  qwen      Update Qwenx
  all       Update everything
  status    Show update status
  check     Check for updates
  help      Show this help

Examples:
  oml update self      # Update OML core
  oml update plugins   # Update all plugins
  oml update all       # Update everything
  oml update status    # Show current status
  oml update check     # Check for updates

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        self)
            update_self
            ;;
        plugins)
            update_plugins
            ;;
        qwen)
            update_qwen
            ;;
        all)
            update_all
            ;;
        status)
            show_status
            ;;
        check)
            check_updates || true
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            print_error "Unknown command: $command"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
