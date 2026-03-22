#!/usr/bin/env bash
# Plan Hook: Plan Tracker
# 计划追踪和统计 Hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="plan-tracker"

# ============================================================================
# Configuration
# ============================================================================
PLAN_TRACKER_ENABLED="${PLAN_TRACKER_ENABLED:-true}"
PLAN_TRACKER_LOG_DIR="${PLAN_TRACKER_LOG_DIR:-}"
PLAN_TRACKER_FORMAT="${PLAN_TRACKER_FORMAT:-text}"

# Supported events
SUPPORTED_EVENTS=(
    "plan:create"
    "plan:update"
    "plan:complete"
    "plan:task:complete"
    "plan:delete"
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

    if [[ "${PLAN_TRACKER_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Set default log directory if not set
    if [[ -z "$PLAN_TRACKER_LOG_DIR" ]]; then
        PLAN_TRACKER_LOG_DIR="${HOME}/.oml/logs/plan-hooks"
    fi

    mkdir -p "$PLAN_TRACKER_LOG_DIR" 2>/dev/null || true

    # Log the event
    log_event "$event" "${payload[@]}"

    # Update statistics
    update_statistics "$event" "${payload[@]}"

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
    local log_file="${PLAN_TRACKER_LOG_DIR}/plan-events.log"

    # Format payload
    local payload_str=""
    for item in "${payload[@]}"; do
        payload_str="${payload_str} ${item}"
    done

    # Write to log file
    {
        echo "=== PLAN EVENT ==="
        echo "Timestamp: $timestamp"
        echo "Event: $event"
        echo "Payload:$payload_str"
        echo ""
    } >> "$log_file" 2>/dev/null || true

    # Also output to stdout if verbose
    if [[ "${PLAN_TRACKER_VERBOSE:-false}" == "true" ]]; then
        echo "[PLAN-TRACKER] $event:$payload_str"
    fi
}

# ============================================================================
# Statistics Functions
# ============================================================================

# Update statistics
update_statistics() {
    local event="$1"
    shift
    local payload=("$@")

    local stats_file="${PLAN_TRACKER_LOG_DIR}/plan-stats.json"

    # Initialize stats file if not exists
    if [[ ! -f "$stats_file" ]]; then
        cat > "$stats_file" <<'EOF'
{
  "total_plans_created": 0,
  "total_plans_completed": 0,
  "total_tasks_completed": 0,
  "total_plans_updated": 0,
  "total_plans_deleted": 0,
  "last_updated": ""
}
EOF
    fi

    # Update stats based on event
    python3 - "${stats_file}" "$event" <<'PY'
import json
import sys
from datetime import datetime

stats_file = sys.argv[1]
event = sys.argv[2]

with open(stats_file, 'r') as f:
    stats = json.load(f)

if event == 'plan:create':
    stats['total_plans_created'] = stats.get('total_plans_created', 0) + 1
elif event == 'plan:complete':
    stats['total_plans_completed'] = stats.get('total_plans_completed', 0) + 1
elif event == 'plan:task:complete':
    stats['total_tasks_completed'] = stats.get('total_tasks_completed', 0) + 1
elif event == 'plan:update':
    stats['total_plans_updated'] = stats.get('total_plans_updated', 0) + 1
elif event == 'plan:delete':
    stats['total_plans_deleted'] = stats.get('total_plans_deleted', 0) + 1

stats['last_updated'] = datetime.utcnow().isoformat() + 'Z'

with open(stats_file, 'w') as f:
    json.dump(stats, f, indent=2)
PY
}

# ============================================================================
# Event Handlers
# ============================================================================

handle_plan_create() {
    local plan_id="${1:-unknown}"
    local title="${2:-untitled}"
    
    echo "Plan created: id=$plan_id, title=$title"
}

handle_plan_update() {
    local plan_id="${1:-unknown}"
    local status="${2:-updated}"
    
    echo "Plan updated: id=$plan_id, status=$status"
}

handle_plan_complete() {
    local plan_id="${1:-unknown}"
    
    echo "Plan completed: id=$plan_id"
}

handle_task_complete() {
    local plan_id="${1:-unknown}"
    local task_id="${2:-unknown}"
    
    echo "Task completed: plan=$plan_id, task=$task_id"
}

handle_plan_delete() {
    local plan_id="${1:-unknown}"
    
    echo "Plan deleted: id=$plan_id"
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
        --stats)
            show_statistics
            ;;
        --help|-h)
            cat <<EOF
Plan Tracker Hook - 计划追踪和统计处理器

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --stats                  Show plan statistics
  --help, -h               Show this help message

Environment Variables:
  PLAN_TRACKER_ENABLED     Enable/disable tracking (default: true)
  PLAN_TRACKER_LOG_DIR     Directory to store logs and stats
  PLAN_TRACKER_FORMAT      Log format: text|json (default: text)
  PLAN_TRACKER_VERBOSE     Verbose output (default: false)

Supported Events:
  - plan:create            Plan created
  - plan:update            Plan updated
  - plan:complete          Plan completed
  - plan:task:complete     Task completed
  - plan:delete            Plan deleted

Examples:
  # Check if hook handles event
  $(basename "$0") --check-event plan:create

  # Show statistics
  $(basename "$0") --stats

  # Set log directory
  export PLAN_TRACKER_LOG_DIR=~/.oml/logs/plan-hooks

  # Enable verbose output
  export PLAN_TRACKER_VERBOSE=true
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

# Show statistics
show_statistics() {
    local stats_file="${PLAN_TRACKER_LOG_DIR:-${HOME}/.oml/logs/plan-hooks}/plan-stats.json"

    if [[ ! -f "$stats_file" ]]; then
        echo "No statistics available yet"
        return 0
    fi

    if [[ "${PLAN_TRACKER_FORMAT}" == "json" ]]; then
        cat "$stats_file"
    else
        python3 -c "
import json

with open('${stats_file}', 'r') as f:
    stats = json.load(f)

print('=== Plan Statistics ===')
print(f\"Total Plans Created:  {stats.get('total_plans_created', 0)}\")
print(f\"Total Plans Completed: {stats.get('total_plans_completed', 0)}\")
print(f\"Total Tasks Completed: {stats.get('total_tasks_completed', 0)}\")
print(f\"Total Plans Updated:  {stats.get('total_plans_updated', 0)}\")
print(f\"Total Plans Deleted:  {stats.get('total_plans_deleted', 0)}\")
print(f\"Last Updated: {stats.get('last_updated', 'N/A')}\")
"
    fi
}

main "$@"
