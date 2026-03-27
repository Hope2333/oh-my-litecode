#!/usr/bin/env bash
# Qwen Hook: PostToolUse
# 工具结果缓存 Hook - 缓存工具执行结果以供复用

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_NAME="result-cache"
HOOK_EVENT="qwen:post_tool_use"

# ============================================================================
# Configuration
# ============================================================================
RESULT_CACHE_ENABLED="${RESULT_CACHE_ENABLED:-true}"
RESULT_CACHE_DIR="${RESULT_CACHE_DIR:-}"
RESULT_CACHE_MAX_SIZE="${RESULT_CACHE_MAX_SIZE:-1048576}"  # 1MB default
RESULT_CACHE_TTL="${RESULT_CACHE_TTL:-3600}"  # 1 hour default
RESULT_CACHE_COMPRESS="${RESULT_CACHE_COMPRESS:-false}"

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
    local tool_result="${3:-}"
    local session_id="${4:-}"
    local metadata="${5:-}"

    if [[ "${RESULT_CACHE_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Validate required fields
    if [[ -z "$tool_name" ]]; then
        echo "Tool name is required for caching" >&2
        return 0  # Don't fail, just skip caching
    fi

    # Initialize cache directory if needed
    if [[ -n "$RESULT_CACHE_DIR" ]]; then
        mkdir -p "$RESULT_CACHE_DIR"
    fi

    # Generate cache key
    local cache_key
    cache_key="$(generate_cache_key "$tool_name" "$tool_args")"

    # Check if result should be cached
    if should_cache_result "$tool_name" "$tool_result"; then
        cache_result "$cache_key" "$tool_name" "$tool_args" "$tool_result" "$session_id" "$metadata"
    fi

    # Log cache operation
    log_cache_operation "$cache_key" "$tool_name" "write" "$session_id"

    return 0
}

# ============================================================================
# Cache Functions
# ============================================================================

# Generate cache key from tool name and args
generate_cache_key() {
    local tool_name="$1"
    local tool_args="${2:-}"

    # Create a hash of tool name + args
    local key_string="${tool_name}:${tool_args}"
    echo -n "$key_string" | sha256sum | cut -d' ' -f1
}

# Check if result should be cached
should_cache_result() {
    local tool_name="$1"
    local tool_result="${2:-}"

    # Don't cache empty results
    if [[ -z "$tool_result" ]]; then
        return 1
    fi

    # Don't cache results that are too large
    local result_size="${#tool_result}"
    if [[ "$result_size" -gt "$RESULT_CACHE_MAX_SIZE" ]]; then
        echo "Result too large for cache: ${result_size} bytes" >&2
        return 1
    fi

    # Check for cacheable tool patterns
    local cacheable_patterns=(
        "read_file"
        "grep"
        "search"
        "list"
        "get"
        "fetch"
        "query"
    )

    for pattern in "${cacheable_patterns[@]}"; do
        if echo "$tool_name" | grep -qi "$pattern" 2>/dev/null; then
            return 0  # Should cache
        fi
    done

    # Don't cache by default for write operations
    local non_cacheable_patterns=(
        "write"
        "create"
        "delete"
        "remove"
        "update"
        "exec"
        "run"
    )

    for pattern in "${non_cacheable_patterns[@]}"; do
        if echo "$tool_name" | grep -qi "$pattern" 2>/dev/null; then
            return 1  # Should not cache
        fi
    done

    return 0  # Default to caching
}

# Cache the result
cache_result() {
    local cache_key="$1"
    local tool_name="$2"
    local tool_args="$3"
    local tool_result="$4"
    local session_id="${5:-}"
    local metadata="${6:-}"

    if [[ -z "$RESULT_CACHE_DIR" ]]; then
        return 0
    fi

    local cache_file="${RESULT_CACHE_DIR}/${cache_key}.cache"
    local timestamp
    timestamp="$(date +%s)"
    local expires_at=$((timestamp + RESULT_CACHE_TTL))

    # Create cache entry
    python3 - "${cache_file}" "${tool_name}" "${tool_args}" "${tool_result}" "${timestamp}" "${expires_at}" "${session_id}" "${metadata}" <<'PY'
import json
import sys
import os

cache_file = sys.argv[1]
tool_name = sys.argv[2]
tool_args = sys.argv[3]
tool_result = sys.argv[4]
timestamp = sys.argv[5]
expires_at = sys.argv[6]
session_id = sys.argv[7] if len(sys.argv) > 7 else ""
metadata = sys.argv[8] if len(sys.argv) > 8 else "{}"

# Try to parse metadata as JSON
try:
    metadata = json.loads(metadata)
except:
    metadata = {}

# Try to parse tool_result as JSON
try:
    result_data = json.loads(tool_result)
    is_json = True
except:
    result_data = tool_result
    is_json = False

cache_entry = {
    "cache_key": os.path.basename(cache_file).replace(".cache", ""),
    "tool_name": tool_name,
    "tool_args": tool_args,
    "result": result_data,
    "is_json": is_json,
    "created_at": int(timestamp),
    "expires_at": int(expires_at),
    "session_id": session_id,
    "metadata": metadata,
    "hit_count": 0
}

# Write cache file
with open(cache_file, 'w') as f:
    json.dump(cache_entry, f, indent=2)

print(f"Cached result for {tool_name}")
PY
}

# Get cached result (utility function)
get_cached_result() {
    local cache_key="$1"

    if [[ -z "$RESULT_CACHE_DIR" ]]; then
        return 1
    fi

    local cache_file="${RESULT_CACHE_DIR}/${cache_key}.cache"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    # Check if expired
    python3 -c "
import json
import time

with open('${cache_file}', 'r') as f:
    entry = json.load(f)

if time.time() > entry.get('expires_at', 0):
    exit(1)  # Expired

# Increment hit count
entry['hit_count'] = entry.get('hit_count', 0) + 1
with open('${cache_file}', 'w') as f:
    json.dump(entry, f, indent=2)

# Output result
if entry.get('is_json'):
    print(json.dumps(entry['result']))
else:
    print(entry['result'])
" 2>/dev/null
}

# Clear expired cache entries
clear_expired_cache() {
    if [[ -z "$RESULT_CACHE_DIR" ]]; then
        return 0
    fi

    if [[ ! -d "$RESULT_CACHE_DIR" ]]; then
        return 0
    fi

    local count=0
    for cache_file in "${RESULT_CACHE_DIR}"/*.cache; do
        [[ -f "$cache_file" ]] || continue

        python3 -c "
import json
import time
import sys

with open('${cache_file}', 'r') as f:
    entry = json.load(f)

if time.time() > entry.get('expires_at', 0):
    import os
    os.remove('${cache_file}')
    print('removed', file=sys.stderr)
    sys.exit(0)
sys.exit(1)
" 2>/dev/null && ((count++)) || true
    done

    echo "Cleared ${count} expired cache entries"
}

# Clear all cache
clear_all_cache() {
    if [[ -z "$RESULT_CACHE_DIR" ]]; then
        return 0
    fi

    if [[ ! -d "$RESULT_CACHE_DIR" ]]; then
        return 0
    fi

    local count=0
    for cache_file in "${RESULT_CACHE_DIR}"/*.cache; do
        [[ -f "$cache_file" ]] && rm -f "$cache_file" && ((count++)) || true
    done

    echo "Cleared ${count} cache entries"
}

# ============================================================================
# Logging Functions
# ============================================================================

# Log cache operation
log_cache_operation() {
    local cache_key="$1"
    local tool_name="$2"
    local operation="$3"
    local session_id="${4:-}"

    if [[ -z "$RESULT_CACHE_DIR" ]]; then
        return 0
    fi

    local log_file="${RESULT_CACHE_DIR}/cache-operations.log"
    local timestamp
    timestamp="$(date -Iseconds)"

    {
        echo "=== CACHE OPERATION ==="
        echo "Timestamp: $timestamp"
        echo "Cache Key: $cache_key"
        echo "Tool: $tool_name"
        echo "Operation: $operation"
        echo "Session: ${session_id:-none}"
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
        --get)
            # Get cached result by key
            get_cached_result "${2:-}"
            ;;
        --clear-expired)
            clear_expired_cache
            ;;
        --clear-all)
            clear_all_cache
            ;;
        --help|-h)
            cat <<EOF
PostToolUse Hook - Result Cache

Usage: $(basename "$0") [OPTIONS] [ARGS]

Options:
  --check-event <event>    Check if this hook handles the event
  --get <cache_key>        Get cached result by key
  --clear-expired          Clear expired cache entries
  --clear-all              Clear all cache entries
  --help, -h               Show this help message

Environment Variables:
  RESULT_CACHE_ENABLED     Enable/disable caching (default: true)
  RESULT_CACHE_DIR         Directory to store cache files
  RESULT_CACHE_MAX_SIZE    Maximum result size in bytes (default: 1MB)
  RESULT_CACHE_TTL         Cache TTL in seconds (default: 3600)
  RESULT_CACHE_COMPRESS    Compress cached results (default: false)

Event: $HOOK_EVENT

This hook:
  - Caches tool execution results
  - Automatically expires old entries
  - Skips caching for write operations
  - Tracks cache hit counts

Examples:
  # Set cache directory
  export RESULT_CACHE_DIR=~/.qwen/cache

  # Set cache TTL to 5 minutes
  export RESULT_CACHE_TTL=300

  # Get cached result
  $(basename "$0") --get <cache_key>
EOF
            ;;
        "")
            # Called as hook: event tool_name [tool_args] [tool_result] [session_id] [metadata]
            run_hook "$@"
            ;;
        *)
            # Direct execution with event as first argument
            run_hook "$@"
            ;;
    esac
}

main "$@"
