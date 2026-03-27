#!/usr/bin/env bash
# Qwen Hook: PreToolUse
# 工具使用权限检查 Hook - 在执行工具前验证权限

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="tool-permission"
HOOK_EVENT="qwen:pre_tool_use"

# ============================================================================
# Configuration
# ============================================================================
TOOL_PERMISSION_ENABLED="${TOOL_PERMISSION_ENABLED:-true}"
TOOL_PERMISSION_LOG_DIR="${TOOL_PERMISSION_LOG_DIR:-}"
TOOL_PERMISSION_DENY_LIST="${TOOL_PERMISSION_DENY_LIST:-}"
TOOL_PERMISSION_ALLOW_LIST="${TOOL_PERMISSION_ALLOW_LIST:-}"
TOOL_PERMISSION_REQUIRE_CONFIRM="${TOOL_PERMISSION_REQUIRE_CONFIRM:-false}"

# ============================================================================
# Hook Interface
# ============================================================================

# Check if this hook handles the given event
check_event() {
    local event="$1"
    [[ "$event" == "$HOOK_EVENT" ]] && echo "true" || echo "false"
}

# Main hook execution
run_hook() {
    local event="$1"
    shift
    local tool_name="${1:-}"
    local tool_args="${2:-}"
    local session_id="${3:-}"
    local metadata="${4:-}"

    if [[ "${TOOL_PERMISSION_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Validate tool name
    if [[ -z "$tool_name" ]]; then
        echo "Tool name is required" >&2
        return 1
    fi

    # Check deny list
    if is_tool_denied "$tool_name"; then
        echo "Tool '${tool_name}' is denied by policy" >&2
        log_tool_use "$tool_name" "$tool_args" "$session_id" "denied"
        return 1
    fi

    # Check allow list (if configured)
    if [[ -n "$TOOL_PERMISSION_ALLOW_LIST" ]] && ! is_tool_allowed "$tool_name"; then
        echo "Tool '${tool_name}' is not in allow list" >&2
        log_tool_use "$tool_name" "$tool_args" "$session_id" "denied"
        return 1
    fi

    # Require confirmation for dangerous tools
    if [[ "${TOOL_PERMISSION_REQUIRE_CONFIRM}" == "true" ]] && is_tool_dangerous "$tool_name"; then
        echo "[CONFIRM] Tool '${tool_name}' requires confirmation" >&2
        # In non-interactive mode, we just log the warning
        log_tool_use "$tool_name" "$tool_args" "$session_id" "warning"
    fi

    # Log the tool use
    log_tool_use "$tool_name" "$tool_args" "$session_id" "allowed"

    return 0
}

# ============================================================================
# Permission Functions
# ============================================================================

# Check if tool is in deny list
is_tool_denied() {
    local tool_name="$1"

    if [[ -z "$TOOL_PERMISSION_DENY_LIST" ]]; then
        return 1  # Not denied
    fi

    IFS=',' read -ra denied_tools <<< "$TOOL_PERMISSION_DENY_LIST"
    for denied in "${denied_tools[@]}"; do
        denied="$(echo "$denied" | xargs)"  # Trim whitespace
        if [[ "$tool_name" == "$denied" ]]; then
            return 0  # Denied
        fi
        # Support wildcard patterns
        if [[ "$denied" == *"*"* ]]; then
            local pattern="${denied//\*/.*}"
            if echo "$tool_name" | grep -qE "^${pattern}$" 2>/dev/null; then
                return 0  # Denied
            fi
        fi
    done

    return 1  # Not denied
}

# Check if tool is in allow list
is_tool_allowed() {
    local tool_name="$1"

    if [[ -z "$TOOL_PERMISSION_ALLOW_LIST" ]]; then
        return 0  # Allow all if no allow list
    fi

    IFS=',' read -ra allowed_tools <<< "$TOOL_PERMISSION_ALLOW_LIST"
    for allowed in "${allowed_tools[@]}"; do
        allowed="$(echo "$allowed" | xargs)"  # Trim whitespace
        if [[ "$tool_name" == "$allowed" ]]; then
            return 0  # Allowed
        fi
        # Support wildcard patterns
        if [[ "$allowed" == *"*"* ]]; then
            local pattern="${allowed//\*/.*}"
            if echo "$tool_name" | grep -qE "^${pattern}$" 2>/dev/null; then
                return 0  # Allowed
            fi
        fi
    done

    return 1  # Not allowed
}

# Check if tool is considered dangerous
is_tool_dangerous() {
    local tool_name="$1"

    # List of potentially dangerous tool patterns
    local dangerous_patterns=(
        "exec"
        "shell"
        "bash"
        "run"
        "delete"
        "remove"
        "rm"
        "chmod"
        "chown"
        "sudo"
        "curl.*post"
        "wget.*post"
        "database.*drop"
        "database.*delete"
    )

    local tool_lower
    tool_lower="$(echo "$tool_name" | tr '[:upper:]' '[:lower:]')"

    for pattern in "${dangerous_patterns[@]}"; do
        if echo "$tool_lower" | grep -qE "$pattern" 2>/dev/null; then
            return 0  # Dangerous
        fi
    done

    return 1  # Not dangerous
}

# ============================================================================
# Logging Functions
# ============================================================================

# Log tool use attempt
log_tool_use() {
    local tool_name="$1"
    local tool_args="${2:-}"
    local session_id="${3:-}"
    local status="${4:-unknown}"

    if [[ -z "$TOOL_PERMISSION_LOG_DIR" ]]; then
        return 0
    fi

    mkdir -p "$TOOL_PERMISSION_LOG_DIR"

    local log_file="${TOOL_PERMISSION_LOG_DIR}/tool-use-$(date +%Y%m%d).log"
    local timestamp
    timestamp="$(date -Iseconds)"

    {
        echo "=== TOOL USE LOG ==="
        echo "Timestamp: $timestamp"
        echo "Tool: $tool_name"
        echo "Args: ${tool_args:0:200}"
        echo "Session: ${session_id:-none}"
        echo "Status: $status"
        echo ""
    } >> "$log_file" 2>/dev/null || true
}

# ============================================================================
# CLI Entry Point
# ============================================================================

main() {
    local action="${1:-}"

    case "$action" in
        --check-event)
            check_event "${2:-}"
            ;;
        --help|-h)
            cat <<EOF
PreToolUse Hook - Tool Permission Checker

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --help, -h               Show this help message

Environment Variables:
  TOOL_PERMISSION_ENABLED      Enable/disable checking (default: true)
  TOOL_PERMISSION_LOG_DIR      Directory to log tool usage
  TOOL_PERMISSION_DENY_LIST    Comma-separated denied tools
  TOOL_PERMISSION_ALLOW_LIST   Comma-separated allowed tools (optional)
  TOOL_PERMISSION_REQUIRE_CONFIRM  Require confirmation for dangerous tools

Event: $HOOK_EVENT

This hook:
  - Validates tool name is provided
  - Checks tool against deny list
  - Checks tool against allow list (if configured)
  - Warns about dangerous tools
  - Logs all tool use attempts

Examples:
  # Deny specific tools
  export TOOL_PERMISSION_DENY_LIST="rm,chmod,sudo"

  # Allow only specific tools
  export TOOL_PERMISSION_ALLOW_LIST="read_file,grep_search,list_dir"

  # Require confirmation for dangerous operations
  export TOOL_PERMISSION_REQUIRE_CONFIRM=true
EOF
            ;;
        "")
            # Called as hook: event tool_name [tool_args] [session_id] [metadata]
            run_hook "$@"
            ;;
        *)
            # Direct execution with event as first argument
            run_hook "$@"
            ;;
    esac
}

main "$@"
