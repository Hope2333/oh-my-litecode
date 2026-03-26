#!/usr/bin/env bash
# Qwen Session Manager - CLI Wrapper
# Provides session management commands with TUI support

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_MANAGER="${SCRIPT_DIR}/session_manager.py"

# Get sessions directory
get_sessions_dir() {
    local fake_home="${HOME}"
    if [[ -n "${_FAKEHOME:-}" ]]; then
        fake_home="${_FAKEHOME}"
    elif [[ "${HOME}" == *"/.local/home/qwen" ]]; then
        fake_home="${HOME}"
    else
        fake_home="${HOME}/.local/home/qwen"
    fi
    echo "${fake_home}/.qwen/sessions"
}

# Show help
show_help() {
    cat <<HELP
Qwen Session Manager

Usage: session <command> [options]

Commands:
  tui             Launch interactive TUI interface
  list [limit]    List sessions (text format)
  json            List sessions (JSON format)
  delete <id>     Delete a session
  clear           Clear all sessions (with confirmation)
  info <id>       Show session details
  help            Show this help

TUI Controls:
  ↑/k, ↓/j        Navigate sessions
  Enter           View session details
  d               Delete selected session
  m               Toggle multi-select mode
  x               Mark/unmark session (in multi-select)
  D               Delete marked sessions
  r               Refresh list
  C               Clear all sessions
  ?               Toggle help
  q               Quit

Examples:
  session tui                 # Launch TUI
  session list 20             # List 20 sessions
  session delete abc123       # Delete session by ID
  session json | jq '.sessions'  # Parse JSON output

HELP
}

# Main
main() {
    local cmd="${1:-help}"
    shift || true
    
    local sessions_dir
    sessions_dir="$(get_sessions_dir)"
    
    # Ensure sessions directory exists
    mkdir -p "$sessions_dir"
    
    case "$cmd" in
        tui|T)
            python3 "$SESSION_MANAGER" -d "$sessions_dir"
            ;;
        
        list|ls|l)
            local limit="${1:-10}"
            python3 "$SESSION_MANAGER" -d "$sessions_dir" --list
            ;;
        
        json|j)
            python3 "$SESSION_MANAGER" -d "$sessions_dir" --list --json
            ;;
        
        delete|del|rm|d)
            local session_id="${1:-}"
            if [[ -z "$session_id" ]]; then
                echo "Error: Session ID required" >&2
                echo "Usage: session delete <session_id>" >&2
                exit 1
            fi
            python3 "$SESSION_MANAGER" -d "$sessions_dir" --delete "$session_id"
            ;;
        
        clear|clean|c)
            echo -n "Are you sure you want to delete ALL sessions? [y/N] "
            read -r confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                python3 "$SESSION_MANAGER" -d "$sessions_dir" --clear-all
            else
                echo "Cancelled"
            fi
            ;;
        
        info|i)
            local session_id="${1:-}"
            if [[ -z "$session_id" ]]; then
                echo "Error: Session ID required" >&2
                exit 1
            fi
            python3 "$SESSION_MANAGER" -d "$sessions_dir" --list --json | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data['sessions']:
    if s['session_id'] == '$session_id' or s['session_id'].startswith('$session_id'):
        print(json.dumps(s, indent=2))
        sys.exit(0)
print('Session not found: $session_id', file=sys.stderr)
sys.exit(1)
"
            ;;
        
        help|--help|-h)
            show_help
            ;;
        
        *)
            echo "Unknown command: $cmd" >&2
            show_help
            exit 1
            ;;
    esac
}

main "$@"
