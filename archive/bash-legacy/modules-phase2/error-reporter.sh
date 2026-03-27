#!/usr/bin/env bash
# OML Error Reporter - Automatic error reporting
#
# Usage:
#   oml error report <message>
#   oml error list
#   oml error show <id>

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Configuration
ERROR_LOG="${HOME}/.oml/errors.log"
ERRORS_DB="${HOME}/.oml/errors.json"

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Initialize
init_errors() {
    mkdir -p "$(dirname "$ERROR_LOG")"
    if [[ ! -f "$ERRORS_DB" ]]; then
        echo '{"errors": []}' > "$ERRORS_DB"
    fi
}

# Report error
cmd_report() {
    local message="${1:-Unknown error}"
    
    init_errors
    
    local error_id timestamp
    error_id="ERR-$(date +%s)"
    timestamp=$(date -Iseconds)
    
    # Log error
    echo "[$timestamp] $error_id: $message" >> "$ERROR_LOG"
    
    # Add to database
    local temp_file
    temp_file=$(mktemp)
    jq --arg id "$error_id" \
       --arg msg "$message" \
       --arg time "$timestamp" \
       '.errors += [{"id": $id, "message": $msg, "timestamp": $time, "status": "new"}]' \
       "$ERRORS_DB" > "$temp_file" && mv "$temp_file" "$ERRORS_DB"
    
    print_success "Error reported: $error_id"
    echo "Message: $message"
    echo "Timestamp: $timestamp"
    echo ""
    echo "To view: oml error show $error_id"
}

# List errors
cmd_list() {
    init_errors
    
    echo -e "${BLUE}Error List:${NC}"
    echo ""
    
    if [[ -f "$ERRORS_DB" ]]; then
        jq -r '.errors[] | "\(.id) | \(.timestamp) | \(.status) | \(.message)"' "$ERRORS_DB" 2>/dev/null | \
        while IFS='|' read -r id time status msg; do
            local status_color
            case "$status" in
                new) status_color="$RED" ;;
                reviewed) status_color="$YELLOW" ;;
                resolved) status_color="$GREEN" ;;
                *) status_color="$NC" ;;
            esac
            echo -e "  ${BLUE}$id${NC} | $time | ${status_color}$status${NC} | $msg"
        done
    else
        echo "  No errors recorded"
    fi
}

# Show error details
cmd_show() {
    local error_id="${1:-}"
    
    if [[ -z "$error_id" ]]; then
        print_error "Error ID required"
        return 1
    fi
    
    init_errors
    
    local error
    error=$(jq -r --arg id "$error_id" '.errors[] | select(.id == $id)' "$ERRORS_DB" 2>/dev/null)
    
    if [[ -z "$error" ]] || [[ "$error" == "null" ]]; then
        print_error "Error not found: $error_id"
        return 1
    fi
    
    echo -e "${BLUE}Error Details:${NC}"
    echo ""
    echo "ID: $(echo "$error" | jq -r '.id')"
    echo "Message: $(echo "$error" | jq -r '.message')"
    echo "Timestamp: $(echo "$error" | jq -r '.timestamp')"
    echo "Status: $(echo "$error" | jq -r '.status')"
}

# Show help
show_help() {
    cat <<EOF
OML Error Reporter

Usage: oml error <command>

Commands:
  report <message>  Report new error
  list              List all errors
  show <id>         Show error details
  help              Show this help

Features:
  - Error logging
  - Status tracking
  - Automatic reporting (placeholder)
  - Privacy protection

Examples:
  oml error report "Command failed with exit code 1"
  oml error list
  oml error show ERR-1234567890

EOF
}

# Main
main() {
    local cmd="${1:-help}"; shift || true
    
    case "$cmd" in
        report) cmd_report "$@" ;;
        list) cmd_list ;;
        show) cmd_show "$@" ;;
        help|--help|-h) show_help ;;
        *) print_error "Unknown command: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
