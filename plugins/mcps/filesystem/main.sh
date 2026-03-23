#!/usr/bin/env bash
# Filesystem MCP - Safe file and directory operations
#
# Usage:
#   oml mcp filesystem read <file>
#   oml mcp filesystem write <file> <content>
#   oml mcp filesystem list <dir>
#   oml mcp filesystem mkdir <dir>
#   oml mcp filesystem delete <path>
#   oml mcp filesystem search <pattern> [dir]
#   oml mcp filesystem info <path>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="filesystem"

# Security configuration
ALLOWED_ROOTS=("${HOME}" "$PWD")
BLOCKED_PATHS=("/etc" "/usr" "/bin" "/sbin" "/data/data/com.termux/files/usr")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if path is safe
is_path_safe() {
    local path="$1"
    
    # Resolve to absolute path
    local abs_path
    abs_path=$(realpath -m "$path" 2>/dev/null || echo "$path")
    
    # Check blocked paths
    for blocked in "${BLOCKED_PATHS[@]}"; do
        if [[ "$abs_path" == "$blocked"* ]]; then
            return 1
        fi
    done
    
    # Check allowed roots
    for root in "${ALLOWED_ROOTS[@]}"; do
        if [[ "$abs_path" == "$root"* ]]; then
            return 0
        fi
    done
    
    return 1
}

# Validate path
validate_path() {
    local path="$1"
    local operation="$2"
    
    if ! is_path_safe "$path"; then
        echo -e "${RED}Error: Access denied to path: $path${NC}" >&2
        echo "Blocked paths: ${BLOCKED_PATHS[*]}" >&2
        echo "Allowed roots: ${ALLOWED_ROOTS[*]}" >&2
        return 1
    fi
    
    return 0
}

# Read file
cmd_read() {
    local file="${1:-}"
    
    if [[ -z "$file" ]]; then
        echo -e "${RED}Error: File path required${NC}"
        return 1
    fi
    
    if ! validate_path "$file" "read"; then
        return 1
    fi
    
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: $file${NC}" >&2
        return 1
    fi
    
    cat "$file"
}

# Write file
cmd_write() {
    local file="${1:-}"
    local content="${2:-}"
    
    if [[ -z "$file" ]]; then
        echo -e "${RED}Error: File path required${NC}"
        return 1
    fi
    
    if ! validate_path "$file" "write"; then
        return 1
    fi
    
    # Confirm if file exists
    if [[ -f "$file" ]]; then
        echo -e "${YELLOW}Warning: File exists, overwrite? (y/N)${NC}"
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Cancelled"
            return 0
        fi
    fi
    
    # Create directory if needed
    local dir
    dir=$(dirname "$file")
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
    
    # Write content
    if [[ -n "$content" ]]; then
        echo "$content" > "$file"
    else
        # Read from stdin
        cat > "$file"
    fi
    
    echo -e "${GREEN}✓ File written: $file${NC}"
}

# List directory
cmd_list() {
    local dir="${1:-.}"
    
    if ! validate_path "$dir" "list"; then
        return 1
    fi
    
    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}Error: Directory not found: $dir${NC}" >&2
        return 1
    fi
    
    echo "Directory: $dir"
    echo ""
    
    # List with details
    ls -la "$dir"
}

# Create directory
cmd_mkdir() {
    local dir="${1:-}"
    
    if [[ -z "$dir" ]]; then
        echo -e "${RED}Error: Directory path required${NC}"
        return 1
    fi
    
    if ! validate_path "$dir" "mkdir"; then
        return 1
    fi
    
    if [[ -d "$dir" ]]; then
        echo -e "${YELLOW}Warning: Directory already exists${NC}"
        return 0
    fi
    
    mkdir -p "$dir"
    echo -e "${GREEN}✓ Directory created: $dir${NC}"
}

# Delete file or directory
cmd_delete() {
    local path="${1:-}"
    
    if [[ -z "$path" ]]; then
        echo -e "${RED}Error: Path required${NC}"
        return 1
    fi
    
    if ! validate_path "$path" "delete"; then
        return 1
    fi
    
    if [[ ! -e "$path" ]]; then
        echo -e "${RED}Error: Path not found: $path${NC}" >&2
        return 1
    fi
    
    # Confirm deletion
    echo -e "${YELLOW}Warning: Delete $path? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    if [[ -d "$path" ]]; then
        rm -rf "$path"
    else
        rm -f "$path"
    fi
    
    echo -e "${GREEN}✓ Deleted: $path${NC}"
}

# Search files
cmd_search() {
    local pattern="${1:-}"
    local dir="${2:-.}"
    
    if [[ -z "$pattern" ]]; then
        echo -e "${RED}Error: Search pattern required${NC}"
        return 1
    fi
    
    if ! validate_path "$dir" "search"; then
        return 1
    fi
    
    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}Error: Directory not found: $dir${NC}" >&2
        return 1
    fi
    
    echo "Searching for: $pattern"
    echo "In directory: $dir"
    echo ""
    
    find "$dir" -name "*$pattern*" 2>/dev/null | head -20
}

# Get file/directory info
cmd_info() {
    local path="${1:-}"
    
    if [[ -z "$path" ]]; then
        echo -e "${RED}Error: Path required${NC}"
        return 1
    fi
    
    if ! validate_path "$path" "info"; then
        return 1
    fi
    
    if [[ ! -e "$path" ]]; then
        echo -e "${RED}Error: Path not found: $path${NC}" >&2
        return 1
    fi
    
    echo "Path: $path"
    echo "Type: $([ -d "$path" ] && echo "Directory" || echo "File")"
    echo "Size: $([ -f "$path" ] && du -h "$path" | cut -f1 || echo "-")"
    echo "Permissions: $(stat -c %a "$path" 2>/dev/null || stat -f %Lp "$path" 2>/dev/null || echo "unknown")"
    echo "Modified: $(stat -c %y "$path" 2>/dev/null || stat -f %Sm "$path" 2>/dev/null || echo "unknown")"
}

# Show help
show_help() {
    cat <<EOF
Filesystem MCP - Safe file and directory operations

Usage: oml mcp filesystem <command> [args]

Commands:
  read <file>              Read file content
  write <file> [content]   Write content to file
  list [dir]               List directory contents
  mkdir <dir>              Create directory
  delete <path>            Delete file or directory
  search <pattern> [dir]   Search for files
  info <path>              Get file/directory info
  help                     Show this help

Security:
  - Operations restricted to user directories
  - Blocked paths: /etc, /usr, /bin, /sbin
  - Dangerous operations require confirmation

Examples:
  oml mcp filesystem read ~/test.txt
  oml mcp filesystem write ~/test.txt "Hello"
  oml mcp filesystem list ~/
  oml mcp filesystem mkdir ~/newdir
  oml mcp filesystem search ".py" ~/projects
  oml mcp filesystem info ~/test.txt

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        read)
            cmd_read "$@"
            ;;
        write)
            cmd_write "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        mkdir)
            cmd_mkdir "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        search)
            cmd_search "$@"
            ;;
        info)
            cmd_info "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
