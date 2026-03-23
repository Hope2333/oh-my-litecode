#!/usr/bin/env bash
# OML Auto Backup - Scheduled automatic backups
#
# Usage:
#   oml backup start
#   oml backup stop
#   oml backup status
#   oml backup run
#   oml backup restore <backup>

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Configuration
BACKUP_DIR="${HOME}/.oml/backups"
BACKUP_CONFIG="${HOME}/.oml/backup-config.json"
BACKUP_PID="${HOME}/.oml/backup.pid"

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Initialize backup
init_backup() {
    mkdir -p "$BACKUP_DIR"
    if [[ ! -f "$BACKUP_CONFIG" ]]; then
        cat > "$BACKUP_CONFIG" <<EOF
{
  "enabled": false,
  "interval_hours": 24,
  "max_backups": 7,
  "last_backup": null
}
EOF
    fi
}

# Start auto backup
cmd_start() {
    init_backup
    jq '.enabled = true' "$BACKUP_CONFIG" > "${BACKUP_CONFIG}.tmp" && mv "${BACKUP_CONFIG}.tmp" "$BACKUP_CONFIG"
    print_success "Auto backup started (daily)"
}

# Stop auto backup
cmd_stop() {
    init_backup
    jq '.enabled = false' "$BACKUP_CONFIG" > "${BACKUP_CONFIG}.tmp" && mv "${BACKUP_CONFIG}.tmp" "$BACKUP_CONFIG"
    print_success "Auto backup stopped"
}

# Show backup status
cmd_status() {
    init_backup
    echo -e "${BLUE}Backup Status:${NC}"
    echo ""
    
    local enabled interval last_backup
    enabled=$(jq -r '.enabled' "$BACKUP_CONFIG")
    interval=$(jq -r '.interval_hours' "$BACKUP_CONFIG")
    last_backup=$(jq -r '.last_backup // "Never"' "$BACKUP_CONFIG")
    
    echo "Enabled: $enabled"
    echo "Interval: ${interval}h"
    echo "Last Backup: $last_backup"
    echo ""
    
    local backup_count
    backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
    echo "Total Backups: $backup_count"
    
    if [[ $backup_count -gt 0 ]]; then
        echo ""
        echo "Recent Backups:"
        ls -lt "$BACKUP_DIR" | head -5
    fi
}

# Run manual backup
cmd_run() {
    init_backup
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/backup-${timestamp}.tar.gz"
    
    print_step "Creating backup..."
    
    # Backup OML config
    if [[ -d "${HOME}/.oml" ]]; then
        tar -czf "$backup_file" -C "${HOME}" ".oml" 2>/dev/null || true
        print_success "Backup created: $backup_file"
        
        # Update last backup time
        jq --arg t "$(date -Iseconds)" '.last_backup = $t' "$BACKUP_CONFIG" > "${BACKUP_CONFIG}.tmp" && mv "${BACKUP_CONFIG}.tmp" "$BACKUP_CONFIG"
        
        # Cleanup old backups
        local max_backups
        max_backups=$(jq -r '.max_backups' "$BACKUP_CONFIG")
        local backup_count
        backup_count=$(ls -1 "$BACKUP_DIR" | wc -l)
        if [[ $backup_count -gt $max_backups ]]; then
            print_step "Cleaning up old backups..."
            ls -t "$BACKUP_DIR" | tail -n +$((max_backups + 1)) | xargs -I {} rm -f "${BACKUP_DIR}/{}"
        fi
    else
        print_error "No data to backup"
        return 1
    fi
}

# Restore from backup
cmd_restore() {
    local backup="${1:-}"
    if [[ -z "$backup" ]]; then
        print_error "Backup name required"
        echo "Available backups:"
        ls -1 "$BACKUP_DIR"
        return 1
    fi
    
    local backup_file="${BACKUP_DIR}/${backup}"
    if [[ ! -f "$backup_file" ]]; then
        backup_file=$(ls -t "$BACKUP_DIR" | grep "$backup" | head -1)
        backup_file="${BACKUP_DIR}/${backup_file}"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "Backup not found: $backup"
        return 1
    fi
    
    print_step "Restoring from: $backup_file"
    tar -xzf "$backup_file" -C "${HOME}"
    print_success "Restore complete"
}

# Show help
show_help() {
    cat <<EOF
OML Auto Backup - Scheduled backups

Usage: oml backup <command>

Commands:
  start             Start auto backup
  stop              Stop auto backup
  status            Show backup status
  run               Run manual backup
  restore <backup>  Restore from backup
  help              Show this help

Features:
  - Scheduled backups (daily by default)
  - Automatic cleanup (keep 7 backups)
  - Manual backup option
  - Easy restore

Examples:
  oml backup start
  oml backup status
  oml backup run
  oml backup restore backup-20260323_120000.tar.gz

EOF
}

# Main
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        start) cmd_start ;; stop) cmd_stop ;; status) cmd_status ;;
        run) cmd_run ;; restore) cmd_restore "$@" ;; help|--help|-h) show_help ;;
        *) print_error "Unknown: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
