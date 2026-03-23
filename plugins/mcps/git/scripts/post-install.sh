#!/usr/bin/env bash
# Git MCP Plugin - Post Install Script
# Sets up git MCP plugin after installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="git"

log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo "[OK] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Check git availability
check_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Main installation
main() {
    log_info "Installing Git MCP Plugin..."
    
    # Check git
    if ! check_git; then
        log_error "Git is not installed"
        echo ""
        echo "Please install git first:"
        if command -v pkg >/dev/null 2>&1; then
            echo "  Termux: pkg install git"
        elif command -v apt >/dev/null 2>&1; then
            echo "  Debian/Ubuntu: apt install git"
        elif command -v yum >/dev/null 2>&1; then
            echo "  RHEL/CentOS: yum install git"
        else
            echo "  Please install git from your package manager"
        fi
        exit 1
    fi
    
    log_success "Git found: $(git --version)"
    
    # Create config directory
    local config_dir="${HOME}/.oml"
    mkdir -p "$config_dir"
    
    log_success "Configuration directory ready: $config_dir"
    
    # Show usage
    echo ""
    echo "Git MCP Plugin installed successfully!"
    echo ""
    echo "Usage:"
    echo "  oml mcps git status          # Check repository status"
    echo "  oml mcps git diff            # View changes"
    echo "  oml mcps git add <files>     # Stage files"
    echo "  oml mcps git commit -m 'msg' # Commit changes"
    echo "  oml mcps git log             # View history"
    echo "  oml mcps git branch          # Manage branches"
    echo ""
    echo "Run 'oml mcps git help' for more information."
}

main "$@"
