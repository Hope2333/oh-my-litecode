#!/usr/bin/env bash
# WebSearch MCP Plugin for OML
# Provides web search and code context retrieval using Exa AI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_NAME="websearch"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi

# Configuration
EXA_BASE_URL="${EXA_BASE_URL:-https://api.exa.ai}"
EXA_API_KEY="${EXA_API_KEY:-}"
EXA_TIMEOUT="${EXA_TIMEOUT:-30}"
WEBSERACH_CACHE_DIR="${WEBSERACH_CACHE_DIR:-${HOME}/.oml/cache/websearch}"

# Initialize cache directory
init_cache() {
    mkdir -p "$WEBSERACH_CACHE_DIR"
}

# Web search using Exa
# Usage: websearch_search "query" [limit] [use_autoprompt]
websearch_search() {
    local query="$1"
    local limit="${2:-10}"
    local use_autoprompt="${3:-true}"
    
    log_info "Searching web: $query"
    
    # Check API key
    if [[ -z "$EXA_API_KEY" ]]; then
        log_error "EXA_API_KEY not set"
        echo '{"error": "EXA_API_KEY not configured"}'
        return 1
    fi
    
    # Check cache
    local cache_key
    cache_key=$(echo "$query" | md5sum | cut -d' ' -f1)
    local cache_file="$WEBSERACH_CACHE_DIR/${cache_key}.json"
    
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        if [[ $cache_age -lt 3600 ]]; then
            log_info "Using cached result"
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Make API request
    local response
    response=$(curl -s -X POST "${EXA_BASE_URL}/search" \
        -H "Authorization: Bearer ${EXA_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"query\": \"$(echo "$query" | sed 's/"/\\"/g')\",
            \"numResults\": $limit,
            \"useAutoprompt\": $use_autoprompt,
            \"type\": \"auto\"
        }" \
        --max-time "$EXA_TIMEOUT")
    
    # Cache result
    echo "$response" > "$cache_file"
    
    # Output result
    echo "$response"
}

# Get code context from GitHub/StackOverflow
# Usage: websearch_code_context "query" [tokens]
websearch_code_context() {
    local query="$1"
    local tokens="${2:-5000}"
    
    log_info "Getting code context: $query"
    
    if [[ -z "$EXA_API_KEY" ]]; then
        log_error "EXA_API_KEY not set"
        echo '{"error": "EXA_API_KEY not configured"}'
        return 1
    fi
    
    local response
    response=$(curl -s -X POST "${EXA_BASE_URL}/getCodeContext" \
        -H "Authorization: Bearer ${EXA_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"query\": \"$(echo "$query" | sed 's/"/\\"/g')\",
            \"tokensNum\": $tokens
        }" \
        --max-time "$EXA_TIMEOUT")
    
    echo "$response"
}

# List sources
websearch_sources() {
    local cache_dir="$WEBSERACH_CACHE_DIR"
    
    if [[ ! -d "$cache_dir" ]]; then
        echo "No cached sources found"
        return 0
    fi
    
    echo "=== WebSearch Sources ==="
    echo ""
    
    local count=0
    for file in "$cache_dir"/*.json; do
        if [[ -f "$file" ]]; then
            local age
            age=$(( $(date +%s) - $(stat -c %Y "$file") ))
            local hours=$((age / 3600))
            echo "  - $(basename "$file" .json) (${hours}h ago)"
            ((count++))
        fi
    done
    
    echo ""
    echo "Total: $count sources"
}

# Manage configuration
websearch_config() {
    local action="${1:-show}"
    
    case "$action" in
        show)
            echo "=== WebSearch Configuration ==="
            echo ""
            echo "Base URL: $EXA_BASE_URL"
            echo "API Key: ${EXA_API_KEY:0:10}..."
            echo "Timeout: ${EXA_TIMEOUT}s"
            echo "Cache Dir: $WEBSERACH_CACHE_DIR"
            echo ""
            ;;
        set)
            local key="$2"
            local value="$3"
            
            case "$key" in
                EXA_BASE_URL)
                    export EXA_BASE_URL="$value"
                    echo "Set EXA_BASE_URL=$value"
                    ;;
                EXA_API_KEY)
                    export EXA_API_KEY="$value"
                    echo "Set EXA_API_KEY (hidden)"
                    ;;
                EXA_TIMEOUT)
                    export EXA_TIMEOUT="$value"
                    echo "Set EXA_TIMEOUT=$value"
                    ;;
                *)
                    echo "Unknown key: $key"
                    return 1
                    ;;
            esac
            ;;
        clear-cache)
            rm -rf "$WEBSERACH_CACHE_DIR"/*
            echo "Cache cleared"
            ;;
        *)
            echo "Usage: websearch config [show|set <key> <value>|clear-cache]"
            return 1
            ;;
    esac
}

# Show help
websearch_help() {
    cat <<EOF
WebSearch MCP Plugin

Usage: websearch <command> [args]

Commands:
  search <query> [limit] [autoprompt]    Search the web
  code-context <query> [tokens]          Get code context
  sources                                List search sources
  config [action]                        Manage configuration
  help                                   Show this help

Examples:
  websearch search "React hooks tutorial" 10 true
  websearch code-context "Python async await" 5000
  websearch sources
  websearch config show
  websearch config set EXA_TIMEOUT 60
  websearch config clear-cache

Environment Variables:
  EXA_API_KEY      Exa API key (required for search)
  EXA_BASE_URL     Exa API base URL (default: https://api.exa.ai)
  EXA_TIMEOUT      Request timeout in seconds (default: 30)

EOF
}

# Main entry point
main() {
    init_cache
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        search)
            websearch_search "$@"
            ;;
        code-context|code)
            websearch_code_context "$@"
            ;;
        sources)
            websearch_sources
            ;;
        config)
            websearch_config "$@"
            ;;
        help|--help|-h)
            websearch_help
            ;;
        *)
            echo "Unknown command: $command"
            websearch_help
            return 1
            ;;
    esac
}

main "$@"
