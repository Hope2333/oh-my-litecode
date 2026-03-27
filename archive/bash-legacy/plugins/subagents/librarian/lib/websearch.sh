#!/usr/bin/env bash
# Librarian Subagent - WebSearch MCP Integration
# Handles Exa web search and code context retrieval

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

# Exa configuration
EXA_BASE_URL="${EXA_BASE_URL:-https://api.exa.ai}"
EXA_API_KEY="${EXA_API_KEY:-}"
EXA_TIMEOUT="${EXA_TIMEOUT:-30}"

# Web search using Exa
# Usage: websearch_exa "query" [options]
websearch_exa() {
    local query="$1"
    local limit="${2:-10}"
    local use_autoprompt="${3:-true}"
    local include_domains="${4:-}"
    local exclude_domains="${5:-}"
    
    librarian_info "Searching web: $query"
    
    # Check API key
    if [[ -z "$EXA_API_KEY" ]]; then
        librarian_warn "EXA_API_KEY not set, using mock response"
        echo '{"results": [], "error": "API key not configured"}'
        return 0
    fi
    
    # Build request
    local request_data
    request_data=$(cat <<EOF
{
    "query": "$(librarian_json_escape "$query")",
    "numResults": $limit,
    "useAutoprompt": $use_autoprompt,
    "type": "auto",
    "includeDomains": [],
    "excludeDomains": []
}
EOF
)
    
    # Add domain filters if provided
    if [[ -n "$include_domains" ]]; then
        request_data=$(echo "$request_data" | jq --argjson domains "$(echo "$include_domains" | jq -R 'split(",")' )" '.includeDomains = $domains')
    fi
    
    if [[ -n "$exclude_domains" ]]; then
        request_data=$(echo "$request_data" | jq --argjson domains "$(echo "$exclude_domains" | jq -R 'split(",")' )" '.excludeDomains = $domains')
    fi
    
    # Call Exa API
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $EXA_API_KEY" \
        -d "$request_data" \
        "${EXA_BASE_URL}/search" \
        --max-time "$EXA_TIMEOUT" \
        2>/dev/null) || {
        librarian_error "Exa API call failed"
        echo '{"results": [], "error": "Connection failed"}'
        return 1
    }
    
    # Parse and enrich results
    local results
    results=$(echo "$response" | jq -r '.results // []' 2>/dev/null)
    
    # Add source metadata
    local enriched_results
    enriched_results=$(echo "$results" | jq '
        map(. + {
            source: "exa",
            timestamp: (now | todate)
        })
    ')
    
    echo "$enriched_results"
}

# Get code context using Exa
# Usage: get_code_context_exa "query" [repo_filter]
get_code_context_exa() {
    local query="$1"
    local repo_filter="${2:-}"
    local limit="${3:-5}"
    
    librarian_info "Getting code context: $query"
    
    if [[ -z "$EXA_API_KEY" ]]; then
        librarian_warn "EXA_API_KEY not set"
        echo '{"results": [], "error": "API key not configured"}'
        return 0
    fi
    
    # Build request for code search
    local request_data
    request_data=$(cat <<EOF
{
    "query": "$(librarian_json_escape "$query")",
    "numResults": $limit,
    "type": "code",
    "includeDomains": [],
    "excludeDomains": []
}
EOF
)
    
    # Add GitHub filter if repo specified
    if [[ -n "$repo_filter" ]]; then
        request_data=$(echo "$request_data" | jq --arg repo "$repo_filter" '
            .includeDomains = ["github.com"] |
            .query = (.query + " repo:" + $repo)
        ')
    fi
    
    # Call Exa API
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $EXA_API_KEY" \
        -d "$request_data" \
        "${EXA_BASE_URL}/search" \
        --max-time "$EXA_TIMEOUT" \
        2>/dev/null) || {
        librarian_error "Exa code search failed"
        echo '{"results": [], "error": "Connection failed"}'
        return 1
    }
    
    # Parse results
    local results
    results=$(echo "$response" | jq -r '.results // []' 2>/dev/null)
    
    # Enrich with code-specific metadata
    local enriched_results
    enriched_results=$(echo "$results" | jq '
        map(. + {
            source: "exa_code",
            timestamp: (now | todate),
            isCode: true
        })
    ')
    
    echo "$enriched_results"
}

# Call Exa MCP tool (alternative to direct API)
# Usage: exa_mcp_call "tool_name" "arguments_json"
exa_mcp_call() {
    local tool_name="$1"
    local arguments="$2"
    
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
    
    # Call MCP server
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $EXA_API_KEY" \
        -d "$mcp_request" \
        "${EXA_BASE_URL}/mcp" \
        --max-time "$EXA_TIMEOUT" \
        2>/dev/null) || {
        librarian_error "Exa MCP call failed"
        echo '{"results": [], "error": "Connection failed"}'
        return 1
    }
    
    # Parse response
    local result
    result=$(echo "$response" | jq -r '.result // empty' 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        librarian_error "Exa error: $error_msg"
        echo "{\"results\": [], \"error\": \"$error_msg\"}"
        return 1
    fi
    
    echo "$result"
}

# Format web search results for display
websearch_format_results() {
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
                "**Source**: \(.source // "web") | **Domain**: \(.url | split("/")[2] // "Unknown")\n\n" +
                "**Relevance**: \(.score // "N/A")\n\n" +
                "\(.text // .snippet // "No content")\n\n" +
                "**URL**: [\(.url)](\(.url // "#"))\n\n" +
                "---\n"
            ' 2>/dev/null || echo "$results"
            ;;
        text)
            echo "$results" | jq -r '
                .[] | 
                "[\(.source // "web")] \(.title // "Untitled")\n" +
                "  Domain: \(.url | split("/")[2] // "Unknown") | Score: \(.score // "N/A")\n" +
                "  \(.text // .snippet // "No content" | .[0:200])...\n" +
                "  URL: \(.url // "N/A")\n"
            ' 2>/dev/null || echo "$results"
            ;;
        *)
            echo "$results"
            ;;
    esac
}

# Generate citation for web search result
websearch_generate_citation() {
    local result="$1"
    
    echo "$result" | jq -r '
        {
            type: "web",
            title: .title // "Untitled",
            url: .url // "Unknown",
            domain: (.url | split("/")[2] // "Unknown"),
            timestamp: .timestamp // (now | todate),
            citation: "[" + (.title // "Untitled") + "](" + (.url // "#") + ")"
        }
    '
}

# Combined web search with automatic fallback
# Usage: websearch_auto "query" [limit]
websearch_auto() {
    local query="$1"
    local limit="${2:-10}"
    
    librarian_info "Auto web search: $query"
    
    # Try Exa API first
    local results
    results=$(websearch_exa "$query" "$limit")
    
    # Check if we got results
    local result_count
    result_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")
    
    if [[ "$result_count" -eq 0 ]]; then
        librarian_warn "No results from Exa, trying fallback..."
        # Fallback: return empty with warning
        echo '{"results": [], "warning": "No results available"}'
        return 0
    fi
    
    echo "$results"
}

# Search with content extraction
# Usage: websearch_with_content "query" [limit]
websearch_with_content() {
    local query="$1"
    local limit="${2:-5}"
    
    librarian_info "Searching with content: $query"
    
    # First get search results
    local search_results
    search_results=$(websearch_exa "$query" "$limit")
    
    # Extract IDs for content fetch
    local ids
    ids=$(echo "$search_results" | jq -r '.[].id' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    if [[ -z "$ids" ]]; then
        echo "$search_results"
        return 0
    fi
    
    # Fetch full content
    local content_request
    content_request=$(cat <<EOF
{
    "ids": ["$(echo "$ids" | sed 's/,/", "/g')"],
    "text": true
}
EOF
)
    
    local content_response
    content_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $EXA_API_KEY" \
        -d "$content_request" \
        "${EXA_BASE_URL}/getContents" \
        --max-time "$EXA_TIMEOUT" \
        2>/dev/null) || {
        librarian_warn "Failed to fetch full content"
        echo "$search_results"
        return 0
    }
    
    # Merge content into results
    local contents
    contents=$(echo "$content_response" | jq -r '.contents // []' 2>/dev/null)
    
    # Enrich search results with full content
    echo "$search_results" | jq --argjson contents "$contents" '
        map(. as $result |
            ($contents | map(select(.id == $result.id)) | .[0]) as $content |
            $result + {
                fullText: ($content.text // null),
                extractedAt: ($content.extractedAt // null)
            }
        )
    '
}
