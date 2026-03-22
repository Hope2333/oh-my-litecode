#!/usr/bin/env bash
# Librarian Subagent - Context7 MCP Integration
# Handles Context7 library resolution and documentation queries

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

# Context7 configuration
CONTEXT7_BASE_URL="${CONTEXT7_BASE_URL:-https://api.context7.com}"
CONTEXT7_API_KEY="${CONTEXT7_API_KEY:-}"
CONTEXT7_TIMEOUT="${CONTEXT7_TIMEOUT:-30}"

# Resolve library ID from package name
# Usage: context7_resolve_library "react" or "npm:react" or "pypi:requests"
context7_resolve_library() {
    local package="$1"
    local registry="${2:-auto}"
    
    librarian_info "Resolving library: $package"
    
    # Auto-detect registry from package prefix
    if [[ "$package" == npm:* ]]; then
        registry="npm"
        package="${package#npm:}"
    elif [[ "$package" == pypi:* ]]; then
        registry="pypi"
        package="${package#pypi:}"
    elif [[ "$package" == gh:* ]]; then
        registry="github"
        package="${package#gh:}"
    elif [[ "$registry" == "auto" ]]; then
        # Try to detect from package name patterns
        if [[ "$package" == @*/* ]] || [[ "$package" == @* ]]; then
            registry="npm"
        else
            registry="npm"  # Default to npm
        fi
    fi
    
    # Build API request
    local request_data
    request_data=$(cat <<EOF
{
    "package": "$(librarian_json_escape "$package")",
    "registry": "$registry"
}
EOF
)
    
    # Call Context7 MCP resolve-library-id tool
    local result
    result=$(context7_mcp_call "resolve-library-id" "$request_data")
    
    if [[ -z "$result" ]]; then
        librarian_error "Failed to resolve library: $package"
        return 1
    fi
    
    # Parse result
    local library_id
    library_id=$(echo "$result" | jq -r '.libraryId // empty' 2>/dev/null)
    
    if [[ -z "$library_id" ]]; then
        librarian_error "No library ID returned for: $package"
        return 1
    fi
    
    librarian_success "Resolved: $package -> $library_id"
    echo "$library_id"
}

# Query documentation for a library
# Usage: context7_query_docs "library-id" "query string"
context7_query_docs() {
    local library_id="$1"
    local query="$2"
    local limit="${3:-10}"
    
    librarian_info "Querying docs for $library_id: $query"
    
    # Build API request
    local request_data
    request_data=$(cat <<EOF
{
    "libraryId": "$(librarian_json_escape "$library_id")",
    "query": "$(librarian_json_escape "$query")",
    "limit": $limit
}
EOF
)
    
    # Call Context7 MCP query-docs tool
    local result
    result=$(context7_mcp_call "query-docs" "$request_data")
    
    if [[ -z "$result" ]]; then
        librarian_error "Failed to query docs for: $library_id"
        return 1
    fi
    
    echo "$result"
}

# Combined search: resolve + query
# Usage: context7_search "package" "query" [limit]
context7_search() {
    local package="$1"
    local query="$2"
    local limit="${3:-10}"
    
    # Resolve library ID
    local library_id
    library_id=$(context7_resolve_library "$package") || return 1
    
    # Query documentation
    local result
    result=$(context7_query_docs "$library_id" "$query" "$limit")
    
    # Add source metadata
    local enriched_result
    enriched_result=$(echo "$result" | jq --arg pkg "$package" --arg lid "$library_id" '
        .results // [] | map(. + {
            source: "context7",
            package: $pkg,
            libraryId: $lid,
            timestamp: (now | todate)
        })
    ')
    
    echo "$enriched_result"
}

# Call Context7 MCP tool
# Internal function - uses MCP protocol
context7_mcp_call() {
    local tool_name="$1"
    local arguments="$2"
    
    # Check if API key is set
    if [[ -z "$CONTEXT7_API_KEY" ]]; then
        # Try to load from settings
        local fake_home="${_FAKEHOME:-${HOME}/.local/home/qwen}"
        local settings_file="${fake_home}/.qwen/settings.json"
        
        if [[ -f "$settings_file" ]]; then
            CONTEXT7_API_KEY=$(jq -r '.context7ApiKey // empty' "$settings_file" 2>/dev/null || echo "")
        fi
        
        if [[ -z "$CONTEXT7_API_KEY" ]]; then
            librarian_warn "CONTEXT7_API_KEY not set, using mock response"
            echo '{"results": [], "error": "API key not configured"}'
            return 0
        fi
    fi
    
    # Build MCP request
    local mcp_request
    mcp_request=$(cat <<EOF
{
    "jsonrpc": "2.0",
    "id": $(date +%s),
    "method": "tools/call",
    "params": {
        "name": "$tool_name",
        "arguments": $arguments
    }
}
EOF
)
    
    # Call MCP server (via npx or direct API)
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $CONTEXT7_API_KEY" \
        -d "$mcp_request" \
        "${CONTEXT7_BASE_URL}/mcp" \
        --max-time "$CONTEXT7_TIMEOUT" \
        2>/dev/null) || {
        librarian_error "Context7 MCP call failed"
        echo '{"results": [], "error": "Connection failed"}'
        return 1
    }
    
    # Parse response
    local result
    result=$(echo "$response" | jq -r '.result // empty' 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        librarian_error "Context7 error: $error_msg"
        echo "{\"results\": [], \"error\": \"$error_msg\"}"
        return 1
    fi
    
    echo "$result"
}

# List available libraries (cached)
context7_list_libraries() {
    local cache_file
    cache_file="$(librarian_get_cache_dir)/query/libraries.cache"
    
    # Check cache (1 hour TTL)
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)))
        
        if [[ $cache_age -lt 3600 ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    librarian_info "Fetching library list..."
    
    # This would call a list-libraries endpoint if available
    # For now, return empty array
    echo "[]"
}

# Get library metadata
context7_get_library_info() {
    local library_id="$1"
    
    librarian_info "Getting info for: $library_id"
    
    local request_data
    request_data=$(cat <<EOF
{
    "libraryId": "$(librarian_json_escape "$library_id")"
}
EOF
)
    
    local result
    result=$(context7_mcp_call "get-library-info" "$request_data")
    
    echo "$result"
}

# Format Context7 results for display
context7_format_results() {
    local results="$1"
    local format="${2:-markdown}"
    
    case "$format" in
        json)
            echo "$results"
            ;;
        markdown)
            echo "$results" | jq -r '
                .[] | 
                "## \(.title // "Untitled")\n\n" +
                "**Source**: \(.source // "Unknown") | **Package**: \(.package // "N/A")\n\n" +
                "**Relevance**: \(.score // "N/A")\n\n" +
                "```\n\(.content // .snippet // "No content")\n```\n\n" +
                "**URL**: \(.url // "N/A")\n\n" +
                "---\n"
            ' 2>/dev/null || echo "$results"
            ;;
        text)
            echo "$results" | jq -r '
                .[] | 
                "[\(.source // "?")] \(.title // "Untitled")\n" +
                "  Package: \(.package // "N/A") | Score: \(.score // "N/A")\n" +
                "  \(.content // .snippet // "No content" | .[0:200])...\n" +
                "  URL: \(.url // "N/A")\n"
            ' 2>/dev/null || echo "$results"
            ;;
        *)
            echo "$results"
            ;;
    esac
}

# Generate citation for Context7 result
context7_generate_citation() {
    local result="$1"
    
    echo "$result" | jq -r '
        {
            type: "context7",
            title: .title // "Untitled",
            package: .package // "Unknown",
            libraryId: .libraryId // "Unknown",
            url: .url // null,
            timestamp: .timestamp // (now | todate),
            citation: "[" + (.package // "?") + " - " + (.title // "Untitled") + "](" + (.url // "#") + ")"
        }
    '
}
