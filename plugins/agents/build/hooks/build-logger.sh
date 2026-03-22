#!/usr/bin/env bash
# Build Hook: Build Logger
# 记录构建事件到日志文件

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="build-logger"

# ============================================================================
# Configuration
# ============================================================================
BUILD_LOGGER_ENABLED="${BUILD_LOGGER_ENABLED:-true}"
BUILD_LOGGER_LOG_DIR="${BUILD_LOGGER_LOG_DIR:-}"
BUILD_LOGGER_FORMAT="${BUILD_LOGGER_FORMAT:-text}"

# Supported events
SUPPORTED_EVENTS=(
    "build:start"
    "build:complete"
    "build:failed"
    "build:clean:start"
    "build:clean:complete"
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

    if [[ "${BUILD_LOGGER_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Set default log directory if not set
    if [[ -z "$BUILD_LOGGER_LOG_DIR" ]]; then
        BUILD_LOGGER_LOG_DIR="${HOME}/.oml/logs/build-hooks"
    fi

    mkdir -p "$BUILD_LOGGER_LOG_DIR" 2>/dev/null || true

    # Log the event
    log_event "$event" "${payload[@]}"

    return 0
}

# ============================================================================
# Logging Functions
# ============================================================================

# Log event to file
log_event() {
    local event="$1"
    shift
    local payload=("$@")

    local timestamp
    timestamp="$(date -Iseconds)"
    local log_file="${BUILD_LOGGER_LOG_DIR}/build-events.log"

    # Format payload
    local payload_str=""
    for item in "${payload[@]}"; do
        payload_str="${payload_str} ${item}"
    done

    # Write to log file
    {
        echo "=== BUILD EVENT ==="
        echo "Timestamp: $timestamp"
        echo "Event: $event"
        echo "Payload:$payload_str"
        echo ""
    } >> "$log_file" 2>/dev/null || true

    # Also output to stdout if verbose
    if [[ "${BUILD_LOGGER_VERBOSE:-false}" == "true" ]]; then
        echo "[BUILD-LOGGER] $event:$payload_str"
    fi
}

# ============================================================================
# Event Handlers
# ============================================================================

handle_build_start() {
    local project="${1:-unknown}"
    local ver="${2:-current}"
    
    echo "Build started: project=$project, ver=$ver"
}

handle_build_complete() {
    local project="${1:-unknown}"
    local status="${2:-success}"
    local duration="${3:-0}"
    
    echo "Build completed: project=$project, status=$status, duration=${duration}s"
}

handle_build_failed() {
    local project="${1:-unknown}"
    local exit_code="${2:-1}"
    
    echo "Build failed: project=$project, exit_code=$exit_code"
}

handle_clean_start() {
    local project="${1:-all}"
    
    echo "Clean started: project=$project"
}

handle_clean_complete() {
    local project="${1:-all}"
    local status="${2:-success}"
    
    echo "Clean completed: project=$project, status=$status"
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
Build Logger Hook - 构建事件日志记录器

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --help, -h               Show this help message

Environment Variables:
  BUILD_LOGGER_ENABLED     Enable/disable logging (default: true)
  BUILD_LOGGER_LOG_DIR     Directory to store logs
  BUILD_LOGGER_FORMAT      Log format: text|json (default: text)
  BUILD_LOGGER_VERBOSE     Verbose output (default: false)

Supported Events:
  - build:start            Build operation started
  - build:complete         Build completed successfully
  - build:failed           Build failed
  - build:clean:start      Clean operation started
  - build:clean:complete   Clean completed

Examples:
  # Check if hook handles event
  $(basename "$0") --check-event build:start

  # Set log directory
  export BUILD_LOGGER_LOG_DIR=~/.oml/logs/build-hooks

  # Enable verbose output
  export BUILD_LOGGER_VERBOSE=true
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
