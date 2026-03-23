#!/usr/bin/env bash
# Qwen OAuth Switcher - Manage multiple free accounts via config file switching
#
# Principle:
#   Store multiple OAuth config files, switch by copying to Qwen config directory
#
# Storage: ~/.oml/qwen-oauth/
#   - accounts/<name>/settings.json  # OAuth config for each account
#   - current                        # Current active account name
#   - backups/<timestamp>/           # Config backups
#
# Usage:
#   qwen-oauth list              # List all accounts
#   qwen-oauth add <name>        # Add new account (login to get config)
#   qwen-oauth use <name>        # Switch to account
#   qwen-oauth current           # Show current account
#   qwen-oauth remove <name>     # Remove account
#   qwen-oauth rotate            # Rotate to next account
#   qwen-oauth backup            # Backup current config
#   qwen-oauth restore <backup>  # Restore from backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="qwen-oauth-switcher"

# Configuration
QWEN_OAUTH_DIR="${QWEN_OAUTH_DIR:-${HOME}/.oml/qwen-oauth}"
QWEN_CONFIG_DIR="${QWEN_CONFIG_DIR:-${HOME}/.local/home/qwenx/.qwen}"
ACCOUNTS_DIR="${QWEN_OAUTH_DIR}/accounts"
CURRENT_FILE="${QWEN_OAUTH_DIR}/current"
BACKUPS_DIR="${QWEN_OAUTH_DIR}/backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize storage
init_storage() {
    mkdir -p "${ACCOUNTS_DIR}"
    mkdir -p "${BACKUPS_DIR}"
    chmod 700 "${QWEN_OAUTH_DIR}"
    chmod 700 "${ACCOUNTS_DIR}"
    chmod 700 "${BACKUPS_DIR}"
}

# Get account count
get_account_count() {
    find "${ACCOUNTS_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l
}

# Check if account exists
account_exists() {
    local name="$1"
    [[ -d "${ACCOUNTS_DIR}/${name}" ]]
}

# Get current account
get_current_account() {
    cat "${CURRENT_FILE}" 2>/dev/null || echo ""
}

# Add new account
cmd_add() {
    local name="${1:-}"
    
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: Account name required${NC}"
        echo "Usage: qwen-oauth add <name>"
        return 1
    fi
    
    if account_exists "$name"; then
        echo -e "${RED}Error: Account '${name}' already exists${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Adding new OAuth account: ${name}${NC}"
    echo ""
    echo "Instructions:"
    echo "1. Login to Qwen Code with this account in a browser"
    echo "2. Copy the config file from ~/.local/home/qwenx/.qwen/settings.json"
    echo "3. Paste it below (Ctrl+D to finish):"
    echo ""
    
    # Create account directory
    mkdir -p "${ACCOUNTS_DIR}/${name}"
    
    # Read config from stdin
    local config_file="${ACCOUNTS_DIR}/${name}/settings.json"
    cat > "$config_file"
    
    # Validate JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "${RED}Error: Invalid JSON${NC}"
        rm -f "$config_file"
        return 1
    fi
    
    # Set permissions
    chmod 600 "$config_file"
    
    echo ""
    echo -e "${GREEN}✓ Account added: ${name}${NC}"
    echo ""
    echo "To activate this account, run:"
    echo "  qwen-oauth use ${name}"
}

# Import account from existing config
cmd_import() {
    local name="${1:-}"
    local source="${2:-}"
    
    if [[ -z "$name" ]] || [[ -z "$source" ]]; then
        echo -e "${RED}Error: Name and source required${NC}"
        echo "Usage: qwen-oauth import <name> <source_config>"
        return 1
    fi
    
    if account_exists "$name"; then
        echo -e "${RED}Error: Account '${name}' already exists${NC}"
        return 1
    fi
    
    if [[ ! -f "$source" ]]; then
        echo -e "${RED}Error: Source config not found: ${source}${NC}"
        return 1
    fi
    
    # Create account directory
    mkdir -p "${ACCOUNTS_DIR}/${name}"
    
    # Copy config
    cp "$source" "${ACCOUNTS_DIR}/${name}/settings.json"
    chmod 600 "${ACCOUNTS_DIR}/${name}/settings.json"
    
    echo -e "${GREEN}✓ Account imported: ${name}${NC}"
}

# List all accounts
cmd_list() {
    echo -e "${BLUE}OAuth Accounts:${NC}"
    echo ""
    
    local current
    current=$(get_current_account)
    
    local count
    count=$(get_account_count)
    
    if [[ "$count" -eq 0 ]]; then
        echo "  No accounts stored"
        echo ""
        echo "To add an account:"
        echo "  1. Login to Qwen Code with the account"
        echo "  2. Run: qwen-oauth add <name>"
        echo "  3. Paste your settings.json content"
        return 0
    fi
    
    for account_dir in "${ACCOUNTS_DIR}"/*/; do
        [[ -d "$account_dir" ]] || continue
        
        local name
        name=$(basename "$account_dir")
        
        local marker="  "
        if [[ "$name" == "$current" ]]; then
            marker="* "
        fi
        
        local config_file="${account_dir}settings.json"
        local added_at="Unknown"
        
        if [[ -f "$config_file" ]]; then
            added_at=$(jq -r '.created_at // "Unknown"' "$config_file" 2>/dev/null || echo "Unknown")
        fi
        
        echo -e "${marker}${GREEN}${name}${NC}"
        echo "      Added: ${added_at}"
        echo ""
    done
    
    if [[ -n "$current" ]]; then
        echo -e "${BLUE}Current account: ${GREEN}${current}${NC}"
    fi
}

# Use specified account
cmd_use() {
    local name="${1:-}"
    
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: Account name required${NC}"
        echo "Usage: qwen-oauth use <name>"
        return 1
    fi
    
    if ! account_exists "$name"; then
        echo -e "${RED}Error: Account '${name}' not found${NC}"
        return 1
    fi
    
    # Backup current config if exists
    if [[ -f "${QWEN_CONFIG_DIR}/settings.json" ]]; then
        cmd_backup silent
    fi
    
    # Create Qwen config directory if needed
    mkdir -p "${QWEN_CONFIG_DIR}"
    
    # Copy account config to Qwen config directory
    cp "${ACCOUNTS_DIR}/${name}/settings.json" "${QWEN_CONFIG_DIR}/settings.json"
    chmod 600 "${QWEN_CONFIG_DIR}/settings.json"
    
    # Save current account
    echo "$name" > "${CURRENT_FILE}"
    chmod 600 "${CURRENT_FILE}"
    
    echo -e "${GREEN}✓ Switched to account: ${name}${NC}"
    echo ""
    echo "Config copied to: ${QWEN_CONFIG_DIR}/settings.json"
    echo ""
    echo "Now you can use: oml qwen"
}

# Show current account
cmd_current() {
    local current
    current=$(get_current_account)
    
    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}No active account${NC}"
        echo "Use 'qwen-oauth use <name>' to activate an account"
        return 0
    fi
    
    if ! account_exists "$current"; then
        echo -e "${RED}Current account '${current}' not found${NC}"
        return 1
    fi
    
    local config_file="${ACCOUNTS_DIR}/${current}/settings.json"
    local added_at
    
    if [[ -f "$config_file" ]]; then
        added_at=$(jq -r '.created_at // "Unknown"' "$config_file" 2>/dev/null || echo "Unknown")
    fi
    
    echo -e "${BLUE}Current OAuth Account:${NC}"
    echo ""
    echo -e "  Name: ${GREEN}${current}${NC}"
    echo "  Added: ${added_at}"
    echo "  Config: ${QWEN_CONFIG_DIR}/settings.json"
}

# Remove account
cmd_remove() {
    local name="${1:-}"
    
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error: Account name required${NC}"
        echo "Usage: qwen-oauth remove <name>"
        return 1
    fi
    
    if ! account_exists "$name"; then
        echo -e "${RED}Error: Account '${name}' not found${NC}"
        return 1
    fi
    
    # Confirm
    echo -n "Are you sure you want to remove account '${name}'? (y/N): "
    read -r confirm
    
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    # Remove account directory
    rm -rf "${ACCOUNTS_DIR}/${name}"
    
    # Clear current if needed
    local current
    current=$(get_current_account)
    if [[ "$current" == "$name" ]]; then
        rm -f "${CURRENT_FILE}"
    fi
    
    echo -e "${GREEN}✓ Account removed: ${name}${NC}"
}

# Rotate to next account
cmd_rotate() {
    local count
    count=$(get_account_count)
    
    if [[ "$count" -eq 0 ]]; then
        echo -e "${RED}Error: No accounts stored${NC}"
        return 1
    fi
    
    local current
    current=$(get_current_account)
    
    # Get all account names
    local accounts=()
    for account_dir in "${ACCOUNTS_DIR}"/*/; do
        [[ -d "$account_dir" ]] || continue
        accounts+=("$(basename "$account_dir")")
    done
    
    # Find next index
    local next_index=0
    for i in "${!accounts[@]}"; do
        if [[ "${accounts[$i]}" == "$current" ]]; then
            next_index=$(( (i + 1) % ${#accounts[@]} ))
            break
        fi
    done
    
    local next_account="${accounts[$next_index]}"
    
    # Use next account
    cmd_use "$next_account"
}

# Backup current config
cmd_backup() {
    local silent="${1:-}"
    
    if [[ ! -f "${QWEN_CONFIG_DIR}/settings.json" ]]; then
        if [[ "$silent" != "silent" ]]; then
            echo -e "${YELLOW}No config to backup${NC}"
        fi
        return 0
    fi
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BACKUPS_DIR}/${timestamp}"
    
    mkdir -p "$backup_dir"
    cp "${QWEN_CONFIG_DIR}/settings.json" "$backup_dir/"
    
    if [[ "$silent" != "silent" ]]; then
        echo -e "${GREEN}✓ Backup created: ${backup_dir}${NC}"
    fi
}

# Restore from backup
cmd_restore() {
    local backup="${1:-}"
    
    if [[ -z "$backup" ]]; then
        echo -e "${RED}Error: Backup path required${NC}"
        echo "Usage: qwen-oauth restore <backup_path>"
        echo ""
        echo "Available backups:"
        ls -1 "${BACKUPS_DIR}" 2>/dev/null || echo "  None"
        return 1
    fi
    
    local backup_dir="${BACKUPS_DIR}/${backup}"
    if [[ ! -d "$backup_dir" ]]; then
        backup_dir="$backup"
    fi
    
    if [[ ! -f "${backup_dir}/settings.json" ]]; then
        echo -e "${RED}Error: Backup not found: ${backup}${NC}"
        return 1
    fi
    
    # Restore
    mkdir -p "${QWEN_CONFIG_DIR}"
    cp "${backup_dir}/settings.json" "${QWEN_CONFIG_DIR}/settings.json"
    
    echo -e "${GREEN}✓ Config restored from: ${backup}${NC}"
}

# Show help
show_help() {
    cat <<EOF
Qwen OAuth Switcher - Manage multiple free accounts via config file switching

Usage: qwen-oauth <command> [args]

Commands:
  list                  List all OAuth accounts
  add <name>            Add new account (paste settings.json)
  import <name> <src>   Import account from existing config
  use <name>            Switch to specified account
  current               Show current active account
  remove <name>         Remove OAuth account
  rotate                Rotate to next account
  backup                Backup current config
  restore <backup>      Restore from backup
  help                  Show this help message

Principle:
  This tool manages multiple OAuth accounts by storing config files
  and switching them by copying to ~/.local/home/qwenx/.qwen/settings.json

Examples:
  # Add account (interactive)
  qwen-oauth add work
  # Then paste your settings.json content

  # Import from existing config
  qwen-oauth import personal ~/.local/home/qwenx/.qwen/settings.json

  # List accounts
  qwen-oauth list

  # Switch account
  qwen-oauth use work

  # Rotate to next account
  qwen-oauth rotate

  # Backup current config
  qwen-oauth backup

  # Restore from backup
  qwen-oauth restore 20260323_120000

Storage:
  ~/.oml/qwen-oauth/
  ├── accounts/<name>/settings.json  # OAuth config for each account
  ├── current                        # Current account name
  └── backups/<timestamp>/           # Config backups

Security:
  - Directory permissions: 700 (owner only)
  - File permissions: 600 (owner read/write)

EOF
}

# Main entry point
main() {
    init_storage
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        list)
            cmd_list
            ;;
        add)
            cmd_add "$@"
            ;;
        import)
            cmd_import "$@"
            ;;
        use)
            cmd_use "$@"
            ;;
        current)
            cmd_current
            ;;
        remove)
            cmd_remove "$@"
            ;;
        rotate)
            cmd_rotate
            ;;
        backup)
            cmd_backup
            ;;
        restore)
            cmd_restore "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo "Use 'qwen-oauth help' for usage"
            return 1
            ;;
    esac
}

main "$@"
