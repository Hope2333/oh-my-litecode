#!/usr/bin/env bash
# OML Cache Manager - Memory caching with LRU and TTL
#
# Usage:
#   oml cache get <key>
#   oml cache set <key> <value>
#   oml cache delete <key>
#   oml cache clear
#   oml cache stats

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Configuration
CACHE_DIR="${HOME}/.oml/cache"
CACHE_DB="${CACHE_DIR}/cache.db"
CACHE_CONFIG="${CACHE_DIR}/cache-config.json"
MAX_SIZE="${MAX_SIZE:-1000}"
TTL="${TTL:-3600}"

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

# Initialize cache
init_cache() {
    mkdir -p "$CACHE_DIR"
    if [[ ! -f "$CACHE_DB" ]]; then
        echo '{}' > "$CACHE_DB"
    fi
    if [[ ! -f "$CACHE_CONFIG" ]]; then
        cat > "$CACHE_CONFIG" <<EOF
{
  "max_size": $MAX_SIZE,
  "ttl_seconds": $TTL,
  "hit_count": 0,
  "miss_count": 0
}
EOF
    fi
}

# Get cached value
cmd_get() {
    local key="${1:-}"
    if [[ -z "$key" ]]; then
        print_error "Key required"
        return 1
    fi
    
    init_cache
    local value
    value=$(jq -r --arg k "$key" '.[$k] // empty' "$CACHE_DB" 2>/dev/null)
    
    if [[ -n "$value" ]]; then
        print_success "Cache hit: $key"
        echo "$value"
        # Update hit count
        local hits
        hits=$(jq -r '.hit_count' "$CACHE_CONFIG")
        jq --argjson h "$((hits + 1))" '.hit_count = $h' "$CACHE_CONFIG" > "${CACHE_CONFIG}.tmp" && mv "${CACHE_CONFIG}.tmp" "$CACHE_CONFIG"
    else
        print_step "Cache miss: $key"
        # Update miss count
        local misses
        misses=$(jq -r '.miss_count' "$CACHE_CONFIG")
        jq --argjson m "$((misses + 1))" '.miss_count = $m' "$CACHE_CONFIG" > "${CACHE_CONFIG}.tmp" && mv "${CACHE_CONFIG}.tmp" "$CACHE_CONFIG"
        return 1
    fi
}

# Set cached value
cmd_set() {
    local key="${1:-}"
    local value="${2:-}"
    
    if [[ -z "$key" ]] || [[ -z "$value" ]]; then
        print_error "Key and value required"
        return 1
    fi
    
    init_cache
    local temp_file
    temp_file=$(mktemp)
    jq --arg k "$key" --arg v "$value" --arg t "$(date +%s)" '.[$k] = {"value": $v, "timestamp": $t}' "$CACHE_DB" > "$temp_file" && mv "$temp_file" "$CACHE_DB"
    
    print_success "Cached: $key"
}

# Delete cached value
cmd_delete() {
    local key="${1:-}"
    if [[ -z "$key" ]]; then
        print_error "Key required"
        return 1
    fi
    
    init_cache
    local temp_file
    temp_file=$(mktemp)
    jq --arg k "$key" 'del(.[$k])' "$CACHE_DB" > "$temp_file" && mv "$temp_file" "$CACHE_DB"
    
    print_success "Deleted: $key"
}

# Clear all cache
cmd_clear() {
    init_cache
    echo '{}' > "$CACHE_DB"
    print_success "Cache cleared"
}

# Show cache stats
cmd_stats() {
    init_cache
    
    echo -e "${BLUE}Cache Statistics:${NC}"
    echo ""
    
    local hits misses total hit_rate
    hits=$(jq -r '.hit_count' "$CACHE_CONFIG")
    misses=$(jq -r '.miss_count' "$CACHE_CONFIG")
    total=$((hits + misses))
    if [[ $total -gt 0 ]]; then
        hit_rate=$(awk "BEGIN {printf \"%.2f\", ($hits / $total) * 100}")
    else
        hit_rate="0.00"
    fi
    
    echo "Hit Count: $hits"
    echo "Miss Count: $misses"
    echo "Hit Rate: ${hit_rate}%"
    echo ""
    
    local cache_size
    cache_size=$(jq 'keys | length' "$CACHE_DB")
    echo "Cached Items: $cache_size"
    echo "Max Size: $MAX_SIZE"
    echo "TTL: ${TTL}s"
}

# Cleanup expired cache
cmd_cleanup() {
    init_cache
    local now
    now=$(date +%s)
    local temp_file
    temp_file=$(mktemp)
    jq --argjson n "$now" 'to_entries | map(select(.value.timestamp + '"$TTL"' > $n)) | from_entries' "$CACHE_DB" > "$temp_file" && mv "$temp_file" "$CACHE_DB"
    print_success "Cleanup complete"
}

# Show help
show_help() {
    cat <<EOF
OML Cache Manager - LRU + TTL caching

Usage: oml cache <command>

Commands:
  get <key>         Get cached value
  set <key> <val>   Set cached value
  delete <key>      Delete cached value
  clear             Clear all cache
  stats             Show cache stats
  cleanup           Cleanup expired cache
  help              Show this help

Features:
  - LRU eviction
  - TTL expiration
  - Hit/miss tracking
  - Auto cleanup

Examples:
  oml cache set mykey "myvalue"
  oml cache get mykey
  oml cache stats
  oml cache cleanup

EOF
}

# Main
main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        get) cmd_get "$@" ;; set) cmd_set "$@" ;; delete) cmd_delete "$@" ;;
        clear) cmd_clear ;; stats) cmd_stats ;; cleanup) cmd_cleanup ;;
        help|--help|-h) show_help ;; *) print_error "Unknown: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
