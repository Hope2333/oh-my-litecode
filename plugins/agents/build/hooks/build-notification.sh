#!/usr/bin/env bash
# Build Hook: Build Notification
# 构建完成/失败通知 Hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="build-notification"

# ============================================================================
# Configuration
# ============================================================================
BUILD_NOTIFY_ENABLED="${BUILD_NOTIFY_ENABLED:-true}"
BUILD_NOTIFY_ON_SUCCESS="${BUILD_NOTIFY_ON_SUCCESS:-false}"
BUILD_NOTIFY_ON_FAILURE="${BUILD_NOTIFY_ON_FAILURE:-true}"
BUILD_NOTIFY_METHOD="${BUILD_NOTIFY_METHOD:-log}"  # log, webhook, file
BUILD_NOTIFY_WEBHOOK_URL="${BUILD_NOTIFY_WEBHOOK_URL:-}"
BUILD_NOTIFY_FILE="${BUILD_NOTIFY_FILE:-}"

# Supported events
SUPPORTED_EVENTS=(
    "build:complete"
    "build:failed"
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

    if [[ "${BUILD_NOTIFY_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Check notification preferences
    case "$event" in
        build:complete)
            if [[ "${BUILD_NOTIFY_ON_SUCCESS}" != "true" ]]; then
                return 0
            fi
            ;;
        build:failed)
            if [[ "${BUILD_NOTIFY_ON_FAILURE}" != "true" ]]; then
                return 0
            fi
            ;;
    esac

    # Send notification based on method
    case "${BUILD_NOTIFY_METHOD}" in
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
    if [[ "$event" == "build:failed" ]]; then
        status_icon="✗"
    fi

    echo "[BUILD-NOTIFY] ${timestamp} ${status_icon} ${event}: ${payload[*]}"
}

# Send file notification
send_file_notification() {
    local event="$1"
    shift
    local payload=("$@")

    local notify_file="${BUILD_NOTIFY_FILE:-${HOME}/.oml/build-notifications.log}"
    local timestamp
    timestamp="$(date -Iseconds)"

    mkdir -p "$(dirname "$notify_file")" 2>/dev/null || true

    {
        echo "=== BUILD NOTIFICATION ==="
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

    if [[ -z "$BUILD_NOTIFY_WEBHOOK_URL" ]]; then
        echo "[BUILD-NOTIFY] Webhook URL not configured, skipping notification" >&2
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
    'source': 'build-agent',
    'payload': payload
}

print(json.dumps(data))
" "$event" "$timestamp" "${payload[@]}")

    # Send webhook (if curl is available)
    if command -v curl >/dev/null 2>&1; then
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$json_data" \
            "$BUILD_NOTIFY_WEBHOOK_URL" >/dev/null 2>&1 || true
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
Build Notification Hook - 构建通知处理器

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --help, -h               Show this help message

Environment Variables:
  BUILD_NOTIFY_ENABLED     Enable/disable notifications (default: true)
  BUILD_NOTIFY_ON_SUCCESS  Notify on successful builds (default: false)
  BUILD_NOTIFY_ON_FAILURE  Notify on failed builds (default: true)
  BUILD_NOTIFY_METHOD      Notification method: log|file|webhook (default: log)
  BUILD_NOTIFY_WEBHOOK_URL Webhook URL for notifications
  BUILD_NOTIFY_FILE        File path for file notifications

Supported Events:
  - build:complete         Build completed successfully
  - build:failed           Build failed

Examples:
  # Check if hook handles event
  $(basename "$0") --check-event build:complete

  # Enable failure notifications
  export BUILD_NOTIFY_ENABLED=true
  export BUILD_NOTIFY_ON_FAILURE=true

  # Configure webhook notifications
  export BUILD_NOTIFY_METHOD=webhook
  export BUILD_NOTIFY_WEBHOOK_URL=https://hooks.example.com/build

  # Configure file notifications
  export BUILD_NOTIFY_METHOD=file
  export BUILD_NOTIFY_FILE=~/.oml/build-notifications.log
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
