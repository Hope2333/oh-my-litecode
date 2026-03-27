#!/usr/bin/env bash
# Git MCP - Safe git repository operations
#
# Usage:
#   oml mcp git status
#   oml mcp git diff
#   oml mcp git add <files>
#   oml mcp git commit -m "message"
#   oml mcp git log
#   oml mcp git branch [name]
#   oml mcp git checkout <branch>
#   oml mcp git push [remote] [branch]
#   oml mcp git pull [remote] [branch]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if in git repository
check_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}" >&2
        return 1
    fi
}

# Show status
cmd_status() {
    check_git_repo || return 1
    
    echo -e "${BLUE}Git Status:${NC}"
    echo ""
    git status
}

# Show diff
cmd_diff() {
    check_git_repo || return 1
    
    echo -e "${BLUE}Git Diff:${NC}"
    echo ""
    git diff
}

# Stage files
cmd_add() {
    check_git_repo || return 1
    
    local files=("$@")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Staging all changes${NC}"
        git add .
    else
        git add "${files[@]}"
    fi
    
    echo -e "${GREEN}✓ Files staged${NC}"
}

# Commit changes
cmd_commit() {
    check_git_repo || return 1
    
    local message=""
    local all=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--message)
                message="$2"
                shift 2
                ;;
            -a|--all)
                all=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$message" ]]; then
        echo -e "${RED}Error: Commit message required (-m \"message\")${NC}"
        return 1
    fi
    
    # Confirm
    echo -e "${YELLOW}Commit with message: $message? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    if [[ "$all" == true ]]; then
        git commit -a -m "$message"
    else
        git commit -m "$message"
    fi
    
    echo -e "${GREEN}✓ Committed${NC}"
}

# Show log
cmd_log() {
    check_git_repo || return 1
    
    local count="${1:-10}"
    
    echo -e "${BLUE}Git Log (last $count commits):${NC}"
    echo ""
    git log --oneline -n "$count"
}

# Branch operations
cmd_branch() {
    check_git_repo || return 1
    
    local branch_name="${1:-}"
    
    if [[ -z "$branch_name" ]]; then
        # List branches
        echo -e "${BLUE}Branches:${NC}"
        echo ""
        git branch
    else
        # Create new branch
        echo -e "${YELLOW}Create branch: $branch_name? (y/N)${NC}"
        read -r confirm
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            git checkout -b "$branch_name"
            echo -e "${GREEN}✓ Branch created: $branch_name${NC}"
        else
            echo "Cancelled"
        fi
    fi
}

# Checkout branch
cmd_checkout() {
    check_git_repo || return 1
    
    local branch="${1:-}"
    
    if [[ -z "$branch" ]]; then
        echo -e "${RED}Error: Branch name required${NC}"
        return 1
    fi
    
    # Confirm
    echo -e "${YELLOW}Switch to branch: $branch? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    git checkout "$branch"
    echo -e "${GREEN}✓ Switched to branch: $branch${NC}"
}

# Push to remote
cmd_push() {
    check_git_repo || return 1
    
    local remote="${1:-origin}"
    local branch="${2:-}"
    
    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD)
    fi
    
    # Confirm
    echo -e "${YELLOW}Push to $remote/$branch? (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        return 0
    fi
    
    git push "$remote" "$branch"
    echo -e "${GREEN}✓ Pushed to $remote/$branch${NC}"
}

# Pull from remote
cmd_pull() {
    check_git_repo || return 1
    
    local remote="${1:-origin}"
    local branch="${2:-}"
    
    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD)
    fi
    
    echo -e "${BLUE}Pulling from $remote/$branch...${NC}"
    git pull "$remote" "$branch"
    echo -e "${GREEN}✓ Pulled${NC}"
}

# Show help
show_help() {
    cat <<EOF
Git MCP - Safe git repository operations

Usage: oml mcp git <command> [args]

Commands:
  status                  Show repository status
  diff                    Show changes
  add [files]             Stage files (all if none specified)
  commit -m "msg" [-a]    Commit changes
  log [count]             Show commit log
  branch [name]           List or create branches
  checkout <branch>       Switch branches
  push [remote] [branch]  Push to remote
  pull [remote] [branch]  Pull from remote
  help                    Show this help

Security:
  - Only works in git repositories
  - Dangerous operations require confirmation

Examples:
  oml mcp git status
  oml mcp git diff
  oml mcp git add src/main.py
  oml mcp git commit -m "Add feature"
  oml mcp git log 5
  oml mcp git branch feature-1
  oml mcp git checkout feature-1
  oml mcp git push origin feature-1
  oml mcp git pull

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        status)
            cmd_status
            ;;
        diff)
            cmd_diff
            ;;
        add)
            cmd_add "$@"
            ;;
        commit)
            cmd_commit "$@"
            ;;
        log)
            cmd_log "$@"
            ;;
        branch)
            cmd_branch "$@"
            ;;
        checkout)
            cmd_checkout "$@"
            ;;
        push)
            cmd_push "$@"
            ;;
        pull)
            cmd_pull "$@"
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
