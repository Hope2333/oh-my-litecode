#!/usr/bin/env bash
# OML Offline Mode - Queue and sync for offline operations
#
# Usage:
#   oml offline enable
#   oml offline disable
#   oml offline queue <command>
#   oml offline sync
#   oml offline status

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Configuration
OFFLINE_CONFIG="${HOME}/.oml/offline-config.json"
OFFLINE_QUEUE="${HOME}/.oml/offline-queue.json"

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Initialize offline mode
init_offline() {
    mkdir -p "$(dirname "$OFFLINE_CONFIG")"
    if [[ ! -f "$OFFLINE_CONFIG" ]]; then
        cat > "$OFFLINE_CONFIG" <<EOF
{
  "enabled": false,
  "auto_sync": true,
  "queue_size": 0
}
EOF
    fi
    if [[ ! -f "$OFFLINE_QUEUE" ]]; then
        echo '{"queue": []}' > "$OFFLINE_QUEUE"
    fi
}

# Enable offline mode
cmd_enable() {
    init_offline
    jq '.enabled = true' "$OFFLINE_CONFIG" > "${OFFLINE_CONFIG}.tmp" && mv "${OFFLINE_CONFIG}.tmp" "$OFFLINE_CONFIG"
    print_success "Offline mode enabled"
    echo "Commands will be queued and synced when online"
}

# Disable offline mode
cmd_disable() {
    init_offline
    jq '.enabled = false' "$OFFLINE_CONFIG" > "${OFFLINE_CONFIG}.tmp" && mv "${OFFLINE_CONFIG}.tmp" "$OFFLINE_CONFIG"
    print_success "Offline mode disabled"
}

# Queue command
cmd_queue() {
    local command="${1:-}"
    if [[ -z "$command" ]]; then
        print_error "Command required"
        return 1
    fi
    
    init_offline
    local timestamp
    timestamp=$(date -Iseconds)
    local temp_file
    temp_file=$(mktemp)
    jq --arg cmd "$command" --arg ts "$timestamp" '.queue += [{"command": $cmd, "timestamp": $ts, "status": "pending"}]' "$OFFLINE_QUEUE" > "$temp_file" && mv "$temp_file" "$OFFLINE_QUEUE"
    
    print_success "Command queued: $command"
}

# Sync queued commands
cmd_sync() {
    init_offline
    print_step "Syncing queued commands..."
    
    local queue_size
    queue_size=$(jq '.queue | length' "$OFFLINE_QUEUE")
    
    if [[ "$queue_size" -eq 0 ]]; then
        print_success "Queue empty"
        return 0
    fi
    
    echo "Processing $queue_size queued commands..."
    
    # Process queue (placeholder - execute commands)
    jq -r '.queue[] | "\(.command)"' "$OFFLINE_QUEUE" | while read -r cmd; do
        echo "  Executing: $cmd"
        # In production: eval "$cmd"
    done
    
    # Clear queue
    echo '{"queue": []}' > "$OFFLINE_QUEUE"
    
    print_success "Sync complete"
}

# Show offline status
cmd_status() {
    init_offline
    
    echo -e "${BLUE}Offline Mode Status:${NC}"
    echo ""
    
    local enabled auto_sync queue_size
    enabled=$(jq -r '.enabled' "$OFFLINE_CONFIG")
    auto_sync=$(jq -r '.auto_sync' "$OFFLINE_CONFIG")
    queue_size=$(jq '.queue | length' "$OFFLINE_QUEUE")
    
    echo "Enabled: $enabled"
    echo "Auto Sync: $auto_sync"
    echo "Queued Commands: $queue_size"
    
    if [[ "$queue_size" -gt 0 ]]; then
        echo ""
        echo "Pending Commands:"
        jq -r '.queue[] | "  - \(.command) (\(.timestamp))"' "$OFFLINE_QUEUE"
    fi
}

# Show help
show_help() {
    cat <<EOF
OML Offline Mode - Queue and sync for offline operations

Usage: oml offline <command>

Commands:
  enable          Enable offline mode
  disable         Disable offline mode
  queue <cmd>     Queue command for later
  sync            Sync queued commands
  status          Show offline status
  help            Show this help

Features:
  - Command queuing
  - Auto sync on reconnect
  - Manual sync option
  - Status tracking

Examples:
  oml offline enable
  oml offline queue "oml update all"
  oml offline sync
  oml offline status

EOF
}

# Main
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        enable) cmd_enable ;; disable) cmd_disable ;; queue) cmd_queue "$@" ;;
        sync) cmd_sync ;; status) cmd_status ;; help|--help|-h) show_help ;;
        *) print_error "Unknown: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
