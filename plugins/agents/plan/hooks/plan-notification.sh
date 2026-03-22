#!/usr/bin/env bash
# Plan Hook: Plan Notification
# 计划完成/里程碑通知 Hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="plan-notification"

# ============================================================================
# Configuration
# ============================================================================
PLAN_NOTIFY_ENABLED="${PLAN_NOTIFY_ENABLED:-true}"
PLAN_NOTIFY_ON_COMPLETE="${PLAN_NOTIFY_ON_COMPLETE:-true}"
PLAN_NOTIFY_ON_TASK_COMPLETE="${PLAN_NOTIFY_ON_TASK_COMPLETE:-false}"
PLAN_NOTIFY_METHOD="${PLAN_NOTIFY_METHOD:-log}"  # log, webhook, file
PLAN_NOTIFY_WEBHOOK_URL="${PLAN_NOTIFY_WEBHOOK_URL:-}"
PLAN_NOTIFY_FILE="${PLAN_NOTIFY_FILE:-}"

# Supported events
SUPPORTED_EVENTS=(
    "plan:complete"
    "plan:task:complete"
)

# ============================================================================
# Hook Interface
# ============================================================================

# Check if this hook handles the given event
check_event() {
    local event="$1"
    
    for supported in "${SUPPORTED_EVENTS[@]}"; do
        if [[ "$event" == "$supported" ]]; then
            echo "true"
            return 0
        fi
    done
    
    echo "false"
}

# Main hook execution
run_hook() {
    local event="$1"
    shift
    local payload=("$@")

    if [[ "${PLAN_NOTIFY_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Check notification preferences
    case "$event" in
        plan:complete)
            if [[ "${PLAN_NOTIFY_ON_COMPLETE}" != "true" ]]; then
                return 0
            fi
            ;;
        plan:task:complete)
            if [[ "${PLAN_NOTIFY_ON_TASK_COMPLETE}" != "true" ]]; then
                return 0
            fi
            ;;
    esac

    # Send notification based on method
    case "${PLAN_NOTIFY_METHOD}" in
        log)
            send_log_notification "$event" "${payload[@]}"
            ;;
        file)
            send_file_notification "$event" "${payload[@]}"
            ;;
        webhook)
            send_webhook_notification "$event" "${payload[@]}"
            ;;
        *)
            send_log_notification "$event" "${payload[@]}"
            ;;
    esac

    return 0
}

# ============================================================================
# Notification Functions
# ============================================================================

# Send log notification
send_log_notification() {
    local event="$1"
    shift
    local payload=("$@")

    local timestamp
    timestamp="$(date -Iseconds)"
    
    local status_icon="✓"
    case "$event" in
        plan:complete)
            echo "[PLAN-NOTIFY] ${timestamp} ${status_icon} Plan completed: ${payload[*]}"
            ;;
        plan:task:complete)
            echo "[PLAN-NOTIFY] ${timestamp} ${status_icon} Task completed: ${payload[*]}"
            ;;
    esac
}

# Send file notification
send_file_notification() {
    local event="$1"
    shift
    local payload=("$@")

    local notify_file="${PLAN_NOTIFY_FILE:-${HOME}/.oml/plan-notifications.log}"
    local timestamp
    timestamp="$(date -Iseconds)"

    mkdir -p "$(dirname "$notify_file")" 2>/dev/null || true

    {
        echo "=== PLAN NOTIFICATION ==="
        echo "Timestamp: $timestamp"
        echo "Event: $event"
        echo "Details: ${payload[*]}"
        echo ""
    } >> "$notify_file" 2>/dev/null || true
}

# Send webhook notification
send_webhook_notification() {
    local event="$1"
    shift
    local payload=("$@")

    if [[ -z "$PLAN_NOTIFY_WEBHOOK_URL" ]]; then
        echo "[PLAN-NOTIFY] Webhook URL not configured, skipping notification" >&2
        return 0
    fi

    local timestamp
    timestamp="$(date -Iseconds)"

    # Build JSON payload
    local json_data
    json_data=$(python3 -c "
import json
import sys

event = sys.argv[1]
timestamp = sys.argv[2]
payload = sys.argv[3:]

data = {
    'event': event,
    'timestamp': timestamp,
    'source': 'plan-agent',
    'payload': payload
}

print(json.dumps(data))
" "$event" "$timestamp" "${payload[@]}")

    # Send webhook (if curl is available)
    if command -v curl >/dev/null 2>&1; then
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$json_data" \
            "$PLAN_NOTIFY_WEBHOOK_URL" >/dev/null 2>&1 || true
    fi
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
Plan Notification Hook - 计划通知处理器

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --help, -h               Show this help message

Environment Variables:
  PLAN_NOTIFY_ENABLED         Enable/disable notifications (default: true)
  PLAN_NOTIFY_ON_COMPLETE     Notify on plan completion (default: true)
  PLAN_NOTIFY_ON_TASK_COMPLETE Notify on task completion (default: false)
  PLAN_NOTIFY_METHOD          Notification method: log|file|webhook (default: log)
  PLAN_NOTIFY_WEBHOOK_URL     Webhook URL for notifications
  PLAN_NOTIFY_FILE            File path for file notifications

Supported Events:
  - plan:complete         Plan completed
  - plan:task:complete    Task completed

Examples:
  # Check if hook handles event
  $(basename "$0") --check-event plan:complete

  # Enable task completion notifications
  export PLAN_NOTIFY_ENABLED=true
  export PLAN_NOTIFY_ON_TASK_COMPLETE=true

  # Configure webhook notifications
  export PLAN_NOTIFY_METHOD=webhook
  export PLAN_NOTIFY_WEBHOOK_URL=https://hooks.example.com/plan

  # Configure file notifications
  export PLAN_NOTIFY_METHOD=file
  export PLAN_NOTIFY_FILE=~/.oml/plan-notifications.log
EOF
            ;;
        "")
            # Called as hook: event [args...]
            run_hook "$@"
            ;;
        *)
            # Direct execution with event as first argument
            run_hook "$@"
            ;;
    esac
}

main "$@"
