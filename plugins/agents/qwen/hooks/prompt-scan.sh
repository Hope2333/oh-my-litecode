#!/usr/bin/env bash
# Qwen Hook: UserPromptSubmit
# 用户提示提交 Hook - 扫描和验证用户输入

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="prompt-scan"
HOOK_EVENT="qwen:user_prompt_submit"

# ============================================================================
# Configuration
# ============================================================================
PROMPT_SCAN_ENABLED="${PROMPT_SCAN_ENABLED:-true}"
PROMPT_SCAN_LOG_DIR="${PROMPT_SCAN_LOG_DIR:-}"
PROMPT_SCAN_MAX_LENGTH="${PROMPT_SCAN_MAX_LENGTH:-10000}"
PROMPT_SCAN_BLOCK_PATTERNS="${PROMPT_SCAN_BLOCK_PATTERNS:-}"

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
    local prompt="$1"
    local session_id="${2:-}"
    local metadata="${3:-}"

    if [[ "${PROMPT_SCAN_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Validate prompt
    if ! validate_prompt "$prompt"; then
        echo "Prompt validation failed" >&2
        return 1
    fi

    # Scan for sensitive patterns
    if ! scan_for_sensitive_content "$prompt"; then
        echo "Sensitive content detected in prompt" >&2
        return 1
    fi

    # Check prompt length
    if ! check_prompt_length "$prompt"; then
        echo "Prompt too long (max: ${PROMPT_SCAN_MAX_LENGTH} chars)" >&2
        return 1
    fi

    # Log the prompt (if logging enabled)
    log_prompt "$prompt" "$session_id" "$metadata"

    return 0
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate prompt content
validate_prompt() {
    local prompt="$1"

    # Check for empty prompt
    if [[ -z "$prompt" ]]; then
        echo "Empty prompt" >&2
        return 1
    fi

    # Check for only whitespace
    if [[ -z "${prompt// /}" ]]; then
        echo "Prompt contains only whitespace" >&2
        return 1
    fi

    return 0
}

# Scan for sensitive content patterns
scan_for_sensitive_content() {
    local prompt="$1"

    # Define blocked patterns (pipe-separated)
    local blocked_patterns="${PROMPT_SCAN_BLOCK_PATTERNS:-}"

    if [[ -n "$blocked_patterns" ]]; then
        IFS='|' read -ra patterns <<< "$blocked_patterns"
        for pattern in "${patterns[@]}"; do
            if [[ -n "$pattern" && "$prompt" == *"$pattern"* ]]; then
                echo "Blocked pattern detected: $pattern" >&2
                return 1
            fi
        done
    fi

    # Check for potential secret patterns
    local secret_patterns=(
        "password[[:space:]]*[=:]"
        "secret[[:space:]]*[=:]"
        "api_key[[:space:]]*[=:]"
        "apikey[[:space:]]*[=:]"
        "token[[:space:]]*[=:]"
    )

    for pattern in "${secret_patterns[@]}"; do
        if echo "$prompt" | grep -qiE "$pattern" 2>/dev/null; then
            # Log warning but don't block (user might be asking about security)
            echo "[WARN] Potential secret pattern detected: $pattern" >&2
        fi
    done

    return 0
}

# Check prompt length
check_prompt_length() {
    local prompt="$1"
    local length="${#prompt}"

    if [[ "$length" -gt "$PROMPT_SCAN_MAX_LENGTH" ]]; then
        return 1
    fi

    return 0
}

# Log prompt to file
log_prompt() {
    local prompt="$1"
    local session_id="${2:-}"
    local metadata="${3:-}"

    if [[ -z "$PROMPT_SCAN_LOG_DIR" ]]; then
        return 0
    fi

    mkdir -p "$PROMPT_SCAN_LOG_DIR"

    local log_file="${PROMPT_SCAN_LOG_DIR}/prompts-$(date +%Y%m%d).log"
    local timestamp
    timestamp="$(date -Iseconds)"

    {
        echo "=== PROMPT LOG ==="
        echo "Timestamp: $timestamp"
        echo "Session: ${session_id:-none}"
        echo "Metadata: ${metadata:-none}"
        echo "Length: ${#prompt}"
        echo "---"
        echo "$prompt"
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
UserPromptSubmit Hook - Prompt Scanner

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --help, -h               Show this help message

Environment Variables:
  PROMPT_SCAN_ENABLED          Enable/disable scanning (default: true)
  PROMPT_SCAN_LOG_DIR          Directory to log prompts
  PROMPT_SCAN_MAX_LENGTH       Maximum prompt length (default: 10000)
  PROMPT_SCAN_BLOCK_PATTERNS   Pipe-separated blocked patterns

Event: $HOOK_EVENT

This hook:
  - Validates prompt is not empty
  - Scans for sensitive content patterns
  - Checks prompt length limits
  - Optionally logs prompts for audit
EOF
            ;;
        "")
            # Called as hook: event prompt [session_id] [metadata]
            run_hook "$@"
            ;;
        *)
            # Direct execution with event as first argument
            run_hook "$@"
            ;;
    esac
}

main "$@"
