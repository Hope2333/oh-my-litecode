#!/usr/bin/env bash
# Git MCP Plugin - Pre Uninstall Script
# Cleans up before removing git MCP plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="git"

log_info() {
    echo "[INFO] $*"
}

log_success() {
    echo "[OK] $*"
}

# Main uninstallation
main() {
    log_info "Preparing to uninstall Git MCP Plugin..."
    
    # Check for any pending operations
    echo ""
    echo "Warning: This will remove the Git MCP plugin."
    echo "Your git repositories and configurations will NOT be affected."
    echo ""
    
    # No cleanup needed - git repos are independent
    log_success "Ready for uninstallation"
}

main "$@"
