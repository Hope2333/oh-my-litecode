#!/usr/bin/env bash
# Code Review Skill - Review code and suggest improvements
#
# Usage:
#   oml skill code-review review_code <file>
#   oml skill code-review suggest_improvements <file>
#   oml skill code-review check_style <file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Review code
cmd_review_code() {
    local file="${1:-}"
    
    if [[ -z "$file" ]]; then
        echo -e "${RED}Error: File required${NC}" >&2
        return 1
    fi
    
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: $file${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Reviewing code: $file${NC}"
    echo ""
    
    # Get file info
    local ext="${file##*.}"
    local lines=$(wc -l < "$file")
    local size=$(du -h "$file" | cut -f1)
    
    echo "File: $file"
    echo "Type: $ext"
    echo "Lines: $lines"
    echo "Size: $size"
    echo ""
    
    # Check for common issues
    echo "Issues found:"
    
    # Check for TODO comments
    local todos=$(grep -c "TODO\|FIXME\|XXX" "$file" 2>/dev/null || echo "0")
    if [[ "$todos" -gt 0 ]]; then
        echo -e "  ${YELLOW}! $todos TODO/FIXME comments found${NC}"
    fi
    
    # Check for long lines
    local long_lines=$(awk 'length > 120' "$file" | wc -l)
    if [[ "$long_lines" -gt 0 ]]; then
        echo -e "  ${YELLOW}! $long_lines lines > 120 characters${NC}"
    fi
    
    # Check for debug statements
    local debug=$(grep -c "console.log\|print(\|debug" "$file" 2>/dev/null || echo "0")
    if [[ "$debug" -gt 0 ]]; then
        echo -e "  ${YELLOW}! $debug debug statements found${NC}"
    fi
    
    # Check for hardcoded values
    local hardcoded=$(grep -c "localhost\|127.0.0.1\|password\|secret" "$file" 2>/dev/null || echo "0")
    if [[ "$hardcoded" -gt 0 ]]; then
        echo -e "  ${RED}✗ $hardcoded hardcoded values found (security risk)${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Code review complete${NC}"
}

# Suggest improvements
cmd_suggest_improvements() {
    local file="${1:-}"
    
    if [[ -z "$file" ]]; then
        echo -e "${RED}Error: File required${NC}" >&2
        return 1
    fi
    
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: $file${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Analyzing code for improvements: $file${NC}"
    echo ""
    
    local ext="${file##*.}"
    
    echo "Suggested improvements:"
    echo ""
    
    case "$ext" in
        sh|bash)
            echo "  1. Add 'set -euo pipefail' at the top"
            echo "  2. Quote all variables: \"\$var\""
            echo "  3. Use functions for reusability"
            echo "  4. Add error handling"
            echo "  5. Add usage help (-h/--help)"
            ;;
        py)
            echo "  1. Add type hints"
            echo "  2. Add docstrings"
            echo "  3. Use context managers"
            echo "  4. Follow PEP 8 style"
            echo "  5. Add unit tests"
            ;;
        js|ts)
            echo "  1. Use const/let instead of var"
            echo "  2. Add TypeScript types"
            echo "  3. Use async/await"
            echo "  4. Add JSDoc comments"
            echo "  5. Add unit tests"
            ;;
        *)
            echo "  1. Add comments"
            echo "  2. Follow style guide"
            echo "  3. Add error handling"
            echo "  4. Add tests"
            echo "  5. Refactor complex logic"
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}✓ Improvement suggestions complete${NC}"
}

# Check style
cmd_check_style() {
    local file="${1:-}"
    
    if [[ -z "$file" ]]; then
        echo -e "${RED}Error: File required${NC}" >&2
        return 1
    fi
    
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: $file${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}Checking code style: $file${NC}"
    echo ""
    
    local ext="${file##*.}"
    
    # Check for style issues
    echo "Style check results:"
    echo ""
    
    # Check indentation
    local spaces=$(grep -c "^    " "$file" 2>/dev/null || echo "0")
    local tabs=$(grep -c $'^\t' "$file" 2>/dev/null || echo "0")
    
    echo "  Indentation:"
    echo "    Spaces: $spaces"
    echo "    Tabs: $tabs"
    
    if [[ "$tabs" -gt 0 ]] && [[ "$spaces" -gt 0 ]]; then
        echo -e "    ${YELLOW}! Mixed indentation detected${NC}"
    fi
    
    # Check for trailing whitespace
    local trailing=$(grep -c " $" "$file" 2>/dev/null || echo "0")
    if [[ "$trailing" -gt 0 ]]; then
        echo -e "    ${YELLOW}! $trailing lines with trailing whitespace${NC}"
    fi
    
    # Check for missing newline at EOF
    if [[ -n "$(tail -c1 "$file")" ]]; then
        echo -e "    ${YELLOW}! Missing newline at end of file${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Style check complete${NC}"
}

# Show help
show_help() {
    cat <<EOF
Code Review Skill - Review code and suggest improvements

Usage: oml skill code-review <command> [args]

Commands:
  review_code <file>           Review code for issues
  suggest_improvements <file>  Suggest code improvements
  check_style <file>           Check code style
  help                         Show this help

Capabilities:
  - Code review
  - Improvement suggestions
  - Style checking
  - Best practices checking

Examples:
  oml skill code-review review_code src/main.py
  oml skill code-review suggest_improvements script.sh
  oml skill code-review check_style index.js

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        review_code)
            cmd_review_code "$@"
            ;;
        suggest_improvements)
            cmd_suggest_improvements "$@"
            ;;
        check_style)
            cmd_check_style "$@"
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
