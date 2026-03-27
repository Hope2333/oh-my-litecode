#!/usr/bin/env bash
# OML Config Conflict Resolver - Automatic and manual conflict resolution
#
# Usage:
#   oml conflict list
#   oml conflict show <id>
#   oml conflict resolve <id> --strategy <local|remote|merge>
#   oml conflict resolve-all --strategy <local|remote>

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Configuration
CONFLICT_DIR="${HOME}/.oml/conflicts"
CONFLICT_LOG="${HOME}/.oml/conflicts.log"

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Initialize conflict resolver
init_conflicts() {
    mkdir -p "$CONFLICT_DIR"
    if [[ ! -f "$CONFLICT_LOG" ]]; then
        echo "# Conflict Log" > "$CONFLICT_LOG"
    fi
}

# List conflicts
cmd_list() {
    init_conflicts
    
    echo -e "${BLUE}Conflict List:${NC}"
    echo ""
    
    local count=0
    for conflict_file in "${CONFLICT_DIR}"/*.conflict 2>/dev/null; do
        [[ -f "$conflict_file" ]] || continue
        count=$((count + 1))
        local name
        name=$(basename "$conflict_file" .conflict)
        local timestamp
        timestamp=$(stat -c %y "$conflict_file" 2>/dev/null | cut -d'.' -f1 || stat -f %Sm "$conflict_file" 2>/dev/null)
        echo -e "  ${GREEN}${count}${NC}. ${name}"
        echo "     Created: ${timestamp}"
        echo "     Status: pending"
        echo ""
    done
    
    if [[ $count -eq 0 ]]; then
        echo "  No conflicts found"
    else
        echo "Total: $count conflicts"
    fi
}

# Show conflict details
cmd_show() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        print_error "Conflict ID required"
        return 1
    fi
    
    local conflict_file="${CONFLICT_DIR}/${id}.conflict"
    if [[ ! -f "$conflict_file" ]]; then
        print_error "Conflict not found: $id"
        return 1
    fi
    
    echo -e "${BLUE}Conflict Details:${NC}"
    echo ""
    echo "ID: $id"
    echo "File: $conflict_file"
    echo ""
    echo -e "${YELLOW}Local version:${NC}"
    echo "---"
    grep -A1000 "^<<<<<<< LOCAL" "$conflict_file" | grep -v "^<<<<<<< LOCAL" | grep -v "^=======" | head -50
    echo ""
    echo -e "${YELLOW}Remote version:${NC}"
    echo "---"
    grep -A1000 "^=======" "$conflict_file" | grep -v "^=======" | grep -v "^>>>>>>> REMOTE" | head -50
}

# Resolve conflict
cmd_resolve() {
    local id="${1:-}"
    local strategy="${2:-ask}"
    
    if [[ -z "$id" ]]; then
        print_error "Conflict ID required"
        return 1
    fi
    
    local conflict_file="${CONFLICT_DIR}/${id}.conflict"
    if [[ ! -f "$conflict_file" ]]; then
        print_error "Conflict not found: $id"
        return 1
    fi
    
    print_step "Resolving conflict: $id"
    
    case "$strategy" in
        local)
            print_step "Using local version..."
            grep -A1000 "^<<<<<<< LOCAL" "$conflict_file" | grep -v "^<<<<<<< LOCAL" | grep -v "^=======" | grep -v "^>>>>>>> REMOTE" > "${id}.resolved"
            ;;
        remote)
            print_step "Using remote version..."
            grep -A1000 "^=======" "$conflict_file" | grep -v "^=======" | grep -v "^>>>>>>> REMOTE" > "${id}.resolved"
            ;;
        merge|ask)
            print_step "Manual resolution required"
            echo "Edit the conflict file and remove conflict markers:"
            echo "  $conflict_file"
            echo ""
            echo "Or use --strategy local|remote for automatic resolution"
            return 0
            ;;
    esac
    
    print_success "Conflict resolved: ${id}.resolved"
    echo "Resolved file: $(pwd)/${id}.resolved"
}

# Resolve all conflicts
cmd_resolve_all() {
    local strategy="${1:-ask}"
    
    init_conflicts
    
    local count=0
    for conflict_file in "${CONFLICT_DIR}"/*.conflict 2>/dev/null; do
        [[ -f "$conflict_file" ]] || continue
        count=$((count + 1))
        local id
        id=$(basename "$conflict_file" .conflict)
        cmd_resolve "$id" "$strategy"
    done
    
    if [[ $count -eq 0 ]]; then
        print_success "No conflicts to resolve"
    else
        print_success "Resolved $count conflicts"
    fi
}

# Show help
show_help() {
    cat <<EOF
OML Config Conflict Resolver

Usage: oml conflict <command>

Commands:
  list                      List all conflicts
  show <id>                 Show conflict details
  resolve <id> --strategy   Resolve conflict (local|remote|merge)
  resolve-all --strategy    Resolve all conflicts
  help                      Show this help

Strategies:
  local    - Use local version
  remote   - Use remote version
  merge    - Manual merge (default)

Examples:
  oml conflict list
  oml conflict show settings.json
  oml conflict resolve settings.json --strategy local
  oml conflict resolve-all --strategy remote

EOF
}

# Main
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        list) cmd_list ;; show) cmd_show "$@" ;; resolve) cmd_resolve "$@" ;;
        resolve-all) cmd_resolve_all "$@" ;; help|--help|-h) show_help ;;
        *) print_error "Unknown: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
