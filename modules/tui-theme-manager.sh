#!/usr/bin/env bash
# OML TUI Theme Manager - Customizable themes for SuperTUI
#
# Usage:
#   oml tui theme list
#   oml tui theme use <name>
#   oml tui theme create <name>
#   oml tui theme export

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Configuration
THEME_DIR="${HOME}/.oml/themes"
CURRENT_THEME="${THEME_DIR}/current"

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Initialize themes
init_themes() {
    mkdir -p "$THEME_DIR"
    
    # Default theme
    if [[ ! -f "${THEME_DIR}/default.json" ]]; then
        cat > "${THEME_DIR}/default.json" <<EOF
{
  "name": "default",
  "colors": {
    "primary": "\\033[0;34m",
    "success": "\\033[0;32m",
    "warning": "\\033[0;33m",
    "error": "\\033[0;31m",
    "text": "\\033[0;37m"
  }
}
EOF
    fi
    
    # Dark theme
    if [[ ! -f "${THEME_DIR}/dark.json" ]]; then
        cat > "${THEME_DIR}/dark.json" <<EOF
{
  "name": "dark",
  "colors": {
    "primary": "\\033[1;34m",
    "success": "\\033[1;32m",
    "warning": "\\033[1;33m",
    "error": "\\033[1;31m",
    "text": "\\033[1;37m"
  }
}
EOF
    fi
}

# List themes
cmd_list() {
    init_themes
    echo -e "${BLUE}Available Themes:${NC}"
    echo ""
    
    local current=""
    if [[ -f "$CURRENT_THEME" ]]; then
        current=$(cat "$CURRENT_THEME")
    fi
    
    for theme_file in "${THEME_DIR}"/*.json; do
        [[ -f "$theme_file" ]] || continue
        local name
        name=$(basename "$theme_file" .json)
        local marker="  "
        if [[ "$name" == "$current" ]]; then
            marker="* "
        fi
        echo -e "${marker}${GREEN}${name}${NC}"
    done
    
    echo ""
    echo "Use 'oml tui theme use <name>' to switch theme"
}

# Use theme
cmd_use() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        print_error "Theme name required"
        return 1
    fi
    
    init_themes
    local theme_file="${THEME_DIR}/${name}.json"
    
    if [[ ! -f "$theme_file" ]]; then
        print_error "Theme not found: $name"
        return 1
    fi
    
    echo "$name" > "$CURRENT_THEME"
    print_success "Theme switched to: $name"
}

# Create theme
cmd_create() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        print_error "Theme name required"
        return 1
    fi
    
    init_themes
    local theme_file="${THEME_DIR}/${name}.json"
    
    if [[ -f "$theme_file" ]]; then
        print_error "Theme already exists: $name"
        return 1
    fi
    
    echo "Creating theme: $name"
    echo ""
    
    read -p "Primary color code (default: \033[0;34m): " primary
    read -p "Success color code (default: \033[0;32m): " success
    read -p "Warning color code (default: \033[0;33m): " warning
    read -p "Error color code (default: \033[0;31m): " error
    read -p "Text color code (default: \033[0;37m): " text
    
    cat > "$theme_file" <<EOF
{
  "name": "$name",
  "colors": {
    "primary": "${primary:-\\033[0;34m}",
    "success": "${success:-\\033[0;32m}",
    "warning": "${warning:-\\033[0;33m}",
    "error": "${error:-\\033[0;31m}",
    "text": "${text:-\\033[0;37m}"
  }
}
EOF
    
    print_success "Theme created: $name"
}

# Export theme
cmd_export() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        if [[ -f "$CURRENT_THEME" ]]; then
            name=$(cat "$CURRENT_THEME")
        else
            print_error "No active theme"
            return 1
        fi
    fi
    
    local theme_file="${THEME_DIR}/${name}.json"
    if [[ ! -f "$theme_file" ]]; then
        print_error "Theme not found: $name"
        return 1
    fi
    
    echo "Theme: $name"
    cat "$theme_file"
}

# Show help
show_help() {
    cat <<EOF
OML TUI Theme Manager

Usage: oml tui theme <command>

Commands:
  list              List available themes
  use <name>        Switch to theme
  create <name>     Create new theme
  export [name]     Export theme config
  help              Show this help

Built-in Themes:
  default           Default theme
  dark              Dark theme

Examples:
  oml tui theme list
  oml tui theme use dark
  oml tui theme create mytheme
  oml tui theme export

EOF
}

# Main
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        list) cmd_list ;; use) cmd_use "$@" ;; create) cmd_create "$@" ;;
        export) cmd_export "$@" ;; help|--help|-h) show_help ;;
        *) print_error "Unknown: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
