#!/usr/bin/env bash
# Qwen Hook: Stop
# 会话停止 Hook - 生成会话摘要和清理

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="session-summary"
HOOK_EVENT="qwen:stop"

# ============================================================================
# Configuration
# ============================================================================
SESSION_SUMMARY_ENABLED="${SESSION_SUMMARY_ENABLED:-true}"
SESSION_SUMMARY_DIR="${SESSION_SUMMARY_DIR:-}"
SESSION_SUMMARY_FORMAT="${SESSION_SUMMARY_FORMAT:-text}"
SESSION_SUMMARY_INCLUDE_MESSAGES="${SESSION_SUMMARY_INCLUDE_MESSAGES:-false}"
SESSION_SUMMARY_MAX_MESSAGES="${SESSION_SUMMARY_MAX_MESSAGES:-50}"

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
    local reason="${1:-unknown}"
    local session_id="${2:-}"
    local metadata="${3:-}"

    if [[ "${SESSION_SUMMARY_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Generate session summary
    if [[ -n "$session_id" ]]; then
        generate_summary "$session_id" "$reason" "$metadata"
    fi

    # Cleanup temporary files
    cleanup_session_temp "$session_id"

    # Log session end
    log_session_end "$session_id" "$reason" "$metadata"

    return 0
}

# ============================================================================
# Summary Functions
# ============================================================================

# Generate session summary
generate_summary() {
    local session_id="$1"
    local reason="${2:-unknown}"
    local metadata="${3:-}"

    # Try to find session file
    local session_file=""
    local possible_locations=(
        "${HOME}/.qwen/sessions/${session_id}.json"
        "${HOME}/.local/home/qwen/.qwen/sessions/${session_id}.json"
        "${SESSION_SUMMARY_DIR}/sessions/${session_id}.json"
    )

    for loc in "${possible_locations[@]}"; do
        if [[ -f "$loc" ]]; then
            session_file="$loc"
            break
        fi
    done

    if [[ -z "$session_file" ]]; then
        echo "Session file not found for: $session_id" >&2
        return 0
    fi

    # Generate summary
    local summary
    summary="$(python3 - "${session_file}" "${reason}" "${SESSION_SUMMARY_FORMAT}" "${SESSION_SUMMARY_INCLUDE_MESSAGES}" "${SESSION_SUMMARY_MAX_MESSAGES}" <<'PY'
import json
import sys
from datetime import datetime

session_file = sys.argv[1]
reason = sys.argv[2]
output_format = sys.argv[3] if len(sys.argv) > 3 else 'text'
include_messages = sys.argv[4].lower() == 'true' if len(sys.argv) > 4 else False
max_messages = int(sys.argv[5]) if len(sys.argv) > 5 else 50

with open(session_file, 'r') as f:
    data = json.load(f)

# Extract session info
session_id = data.get('session_id', 'unknown')
name = data.get('name', 'unnamed')
created_at = data.get('created_at', 'unknown')
updated_at = data.get('updated_at', 'unknown')
status = data.get('status', 'unknown')
messages = data.get('messages', [])
context = data.get('context', {})
metadata = data.get('metadata', {})

# Calculate statistics
total_messages = len(messages)
user_messages = sum(1 for m in messages if m.get('role') == 'user')
assistant_messages = sum(1 for m in messages if m.get('role') == 'assistant')
system_messages = sum(1 for m in messages if m.get('role') == 'system')

# Calculate token estimate (rough)
total_chars = sum(len(m.get('content', '')) for m in messages)
estimated_tokens = total_chars // 4  # Rough estimate

# Generate summary
if output_format == 'json':
    summary = {
        'session_id': session_id,
        'name': name,
        'status': status,
        'end_reason': reason,
        'created_at': created_at,
        'ended_at': datetime.utcnow().isoformat() + 'Z',
        'statistics': {
            'total_messages': total_messages,
            'user_messages': user_messages,
            'assistant_messages': assistant_messages,
            'system_messages': system_messages,
            'estimated_tokens': estimated_tokens,
            'total_characters': total_chars
        },
        'context_keys': list(context.keys()) if context else [],
        'metadata': metadata
    }

    if include_messages:
        summary['messages'] = messages[:max_messages]

    print(json.dumps(summary, indent=2, ensure_ascii=False))
else:
    print("=" * 60)
    print("SESSION SUMMARY")
    print("=" * 60)
    print(f"Session ID: {session_id}")
    print(f"Name: {name}")
    print(f"Status: {status}")
    print(f"End Reason: {reason}")
    print(f"Created: {created_at}")
    print(f"Ended: {datetime.utcnow().isoformat()}Z")
    print("-" * 60)
    print("STATISTICS:")
    print(f"  Total Messages: {total_messages}")
    print(f"  User Messages: {user_messages}")
    print(f"  Assistant Messages: {assistant_messages}")
    print(f"  System Messages: {system_messages}")
    print(f"  Estimated Tokens: {estimated_tokens}")
    print(f"  Total Characters: {total_chars}")

    if context:
        print("-" * 60)
        print("CONTEXT:")
        for key, value in context.items():
            print(f"  {key}: {value}")

    if include_messages and messages:
        print("-" * 60)
        print(f"MESSAGES (last {min(len(messages), max_messages)}):")
        for msg in messages[-max_messages:]:
            role = msg.get('role', 'unknown')
            content = msg.get('content', '')[:100]
            timestamp = msg.get('timestamp', '')[:19]
            print(f"  [{timestamp}] {role}: {content}...")

    print("=" * 60)
PY
)"

    # Save summary to file
    if [[ -n "$SESSION_SUMMARY_DIR" ]]; then
        mkdir -p "${SESSION_SUMMARY_DIR}/summaries"
        local summary_file="${SESSION_SUMMARY_DIR}/summaries/${session_id}-summary.json"
        echo "$summary" > "$summary_file" 2>/dev/null || true
    fi

    # Output summary
    echo "$summary"

    return 0
}

# Cleanup session temporary files
cleanup_session_temp() {
    local session_id="$1"

    if [[ -z "$session_id" ]]; then
        return 0
    fi

    # Clean up temp files related to this session
    local temp_patterns=(
        "/tmp/qwen-${session_id}-*"
        "/tmp/oml-session-${session_id}-*"
        "${HOME}/.qwen/tmp/${session_id}-*"
    )

    for pattern in "${temp_patterns[@]}"; do
        for file in $pattern; do
            [[ -e "$file" ]] && rm -f "$file" 2>/dev/null || true
        done
    done
}

# ============================================================================
# Logging Functions
# ============================================================================

# Log session end
log_session_end() {
    local session_id="$1"
    local reason="${2:-unknown}"
    local metadata="${3:-}"

    if [[ -z "$SESSION_SUMMARY_DIR" ]]; then
        return 0
    fi

    local log_file="${SESSION_SUMMARY_DIR}/session-endings.log"
    local timestamp
    timestamp="$(date -Iseconds)"

    {
        echo "=== SESSION END ==="
        echo "Timestamp: $timestamp"
        echo "Session ID: $session_id"
        echo "End Reason: $reason"
        echo "Metadata: ${metadata:-none}"
        echo ""
    } >> "$log_file" 2>/dev/null || true
}

# ============================================================================
# Utility Functions
# ============================================================================

# List session summaries
list_summaries() {
    local limit="${1:-10}"

    if [[ -z "$SESSION_SUMMARY_DIR" ]]; then
        echo "SESSION_SUMMARY_DIR not configured" >&2
        return 1
    fi

    local summaries_dir="${SESSION_SUMMARY_DIR}/summaries"

    if [[ ! -d "$summaries_dir" ]]; then
        echo "No summaries found"
        return 0
    fi

    python3 - "${summaries_dir}" "${limit}" <<'PY'
import json
import sys
import os
import glob

summaries_dir = sys.argv[1]
limit = int(sys.argv[2])

summaries = []
for summary_file in glob.glob(os.path.join(summaries_dir, '*.json')):
    try:
        with open(summary_file, 'r') as f:
            data = json.load(f)
        summaries.append({
            'session_id': data.get('session_id', ''),
            'name': data.get('name', ''),
            'status': data.get('status', ''),
            'ended_at': data.get('ended_at', ''),
            'end_reason': data.get('end_reason', ''),
            'total_messages': data.get('statistics', {}).get('total_messages', 0)
        })
    except:
        pass

# Sort by ended_at descending
summaries.sort(key=lambda x: x.get('ended_at', ''), reverse=True)
summaries = summaries[:limit]

if not summaries:
    print("No summaries found")
else:
    print(f"{'SESSION_ID':<40} {'NAME':<20} {'STATUS':<10} {'MESSAGES':<10} {'ENDED'}")
    print("=" * 95)
    for s in summaries:
        name = (s['name'] or 'unnamed')[:18]
        print(f"{s['session_id']:<40} {name:<20} {s['status']:<10} {s['total_messages']:<10} {s['ended_at'][:19] if s['ended_at'] else 'N/A'}")
    print(f"\nTotal: {len(summaries)} summaries")
PY
}

# Get summary by session ID
get_summary() {
    local session_id="$1"

    if [[ -z "$SESSION_SUMMARY_DIR" ]]; then
        echo "SESSION_SUMMARY_DIR not configured" >&2
        return 1
    fi

    local summary_file="${SESSION_SUMMARY_DIR}/summaries/${session_id}-summary.json"

    if [[ ! -f "$summary_file" ]]; then
        echo "Summary not found for session: $session_id" >&2
        return 1
    fi

    cat "$summary_file"
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
        --list)
            list_summaries "${2:-10}"
            ;;
        --get)
            get_summary "${2:-}"
            ;;
        --help|-h)
            cat <<EOF
Stop Hook - Session Summary Generator

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --list [limit]           List session summaries
  --get <session_id>       Get summary for specific session
  --help, -h               Show this help message

Environment Variables:
  SESSION_SUMMARY_ENABLED      Enable/disable summaries (default: true)
  SESSION_SUMMARY_DIR          Directory to store summaries
  SESSION_SUMMARY_FORMAT       Output format: text|json (default: text)
  SESSION_SUMMARY_INCLUDE_MESSAGES  Include messages in summary (default: false)
  SESSION_SUMMARY_MAX_MESSAGES    Max messages to include (default: 50)

Event: $HOOK_EVENT

This hook:
  - Generates session summary on stop
  - Calculates session statistics
  - Cleans up temporary files
  - Logs session end events

Examples:
  # Set summary directory
  export SESSION_SUMMARY_DIR=~/.qwen/summaries

  # List recent summaries
  $(basename "$0") --list 20

  # Get specific summary
  $(basename "$0") --get <session_id>
EOF
            ;;
        "")
            # Called as hook: event reason [session_id] [metadata]
            run_hook "$@"
            ;;
        *)
            # Direct execution with event as first argument
            run_hook "$@"
            ;;
    esac
}

main "$@"
