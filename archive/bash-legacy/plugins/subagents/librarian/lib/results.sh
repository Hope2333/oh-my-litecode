#!/usr/bin/env bash
# Librarian Subagent - Result Deduplication and Ranking
# Handles merging, deduplication, and relevance scoring of search results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "${SCRIPT_DIR}/utils.sh"

# Merge multiple result arrays
# Usage: results_merge "json_array1" "json_array2" ...
results_merge() {
    local merged="[]"
    
    for results in "$@"; do
        if [[ -n "$results" && "$results" != "[]" && "$results" != "null" ]]; then
            merged=$(echo "$merged" "$results" | jq -s 'add')
        fi
    done
    
    echo "$merged"
}

# Deduplicate results by URL or content hash
# Usage: results_deduplicate "json_array" [method]
results_deduplicate() {
    local results="$1"
    local method="${2:-url}"  # url, content, or hybrid

    librarian_info "Deduplicating ${method}..."

    # Handle empty or invalid input
    if [[ -z "$results" ]] || [[ "$results" == "null" ]]; then
        echo "[]"
        return 0
    fi
    
    local is_array
    is_array=$(echo "$results" | jq 'type == "array"' 2>/dev/null || echo "false")
    if [[ "$is_array" != "true" ]]; then
        echo "[]"
        return 0
    fi

    case "$method" in
        url)
            # Deduplicate by URL
            echo "$results" | jq '
                if length == 0 then [] else unique_by(.url // .link // "") end
            '
            ;;
        content)
            # Deduplicate by content hash
            echo "$results" | jq '
                if length == 0 then [] else
                map(. + {_hash: (.content // .text // .snippet // "") | gsub("[\\s\\n]+"; " ") | hash}) |
                unique_by(._hash) |
                map(del(._hash))
                end
            '
            ;;
        hybrid)
            # Deduplicate by URL first, then by similar content
            echo "$results" | jq '
                if length == 0 then [] else
                # First pass: unique by URL
                unique_by(.url // .link // "") |
                # Second pass: group by similar title
                if length == 0 then [] else
                group_by(.title // "" | gsub("[^a-zA-Z0-9]"; "") | ascii_downcase | .[0:20]) |
                map(
                    # Keep highest scored from each group
                    sort_by(-(.score // 0)) | .[0]
                )
                end
                end
            '
            ;;
        *)
            echo "$results"
            ;;
    esac
}

# Sort results by relevance score
# Usage: results_sort "json_array" [field]
results_sort() {
    local results="$1"
    local field="${2:-score}"
    
    echo "$results" | jq --arg field "$field" '
        sort_by(-(.[$field] // 0))
    '
}

# Filter results by minimum score
# Usage: results_filter_by_score "json_array" min_score
results_filter_by_score() {
    local results="$1"
    local min_score="${2:-0.5}"
    
    echo "$results" | jq --argjson min "$min_score" '
        map(select((.score // 0) >= $min))
    '
}

# Limit results count
# Usage: results_limit "json_array" max_count
results_limit() {
    local results="$1"
    local max_count="${2:-10}"
    
    echo "$results" | jq --argjson max "$max_count" '
        .[0:$max]
    '
}

# Complete pipeline: merge, dedupe, sort, filter, limit
# Usage: results_pipeline "merged_json" [options_json]
results_pipeline() {
    local results="$1"
    local options="${2:-{}}"
    
    local dedup_method
    dedup_method=$(echo "$options" | jq -r '.dedupMethod // "hybrid"')
    
    local min_score
    min_score=$(echo "$options" | jq -r '.minScore // 0.3')
    
    local max_results
    max_results=$(echo "$options" | jq -r '.maxResults // 10')
    
    local sort_field
    sort_field=$(echo "$options" | jq -r '.sortField // "score"')
    
    librarian_info "Running results pipeline..."
    
    # Step 1: Deduplicate
    local deduped
    deduped=$(results_deduplicate "$results" "$dedup_method")
    
    # Step 2: Filter by score
    local filtered
    filtered=$(results_filter_by_score "$deduped" "$min_score")
    
    # Step 3: Sort
    local sorted
    sorted=$(results_sort "$filtered" "$sort_field")
    
    # Step 4: Limit
    local limited
    limited=$(results_limit "$sorted" "$max_results")
    
    # Add metadata (only if limited is an array)
    local is_array
    is_array=$(echo "$limited" | jq 'type == "array"' 2>/dev/null || echo "false")
    
    # Safely get lengths
    local total_len=0
    local final_len=0
    
    if echo "$results" | jq -e 'type == "array"' >/dev/null 2>&1; then
        total_len=$(echo "$results" | jq 'length' 2>/dev/null || echo 0)
    fi
    
    if [[ "$is_array" == "true" ]]; then
        final_len=$(echo "$limited" | jq 'length' 2>/dev/null || echo 0)
        
        # Wrap array in object with metadata (can't add object to array directly)
        echo "$limited" | jq --argjson total "$total_len" --argjson final "$final_len" '
            {
                results: .,
                _metadata: {
                    totalBefore: $total,
                    totalAfter: $final,
                    deduped: (if $total > $final then ($total - $final) else 0 end),
                    pipeline: ["deduplicate", "filter", "sort", "limit"]
                }
            }
        '
    else
        echo "$limited"
    fi
}

# Combine results from multiple sources
# Usage: results_combine_sources "context7_results" "websearch_results" [weights_json]
results_combine_sources() {
    local context7_results="${1:-[]}"
    local websearch_results="${2:-[]}"
    local weights="${3:-{}}"
    
    local context7_weight
    context7_weight=$(echo "$weights" | jq -r '.context7 // 1.0')
    
    local websearch_weight
    websearch_weight=$(echo "$weights" | jq -r '.websearch // 0.8')
    
    librarian_info "Combining sources (c7:$context7_weight, web:$websearch_weight)..."
    
    # Normalize and weight scores
    local weighted_context7
    weighted_context7=$(echo "$context7_results" | jq --argjson w "$context7_weight" '
        map(.score = ((.score // 0.5) * $w))
    ' 2>/dev/null || echo "[]")
    
    local weighted_websearch
    weighted_websearch=$(echo "$websearch_results" | jq --argjson w "$websearch_weight" '
        map(.score = ((.score // 0.5) * $w))
    ' 2>/dev/null || echo "[]")
    
    # Merge and process
    local merged
    merged=$(results_merge "$weighted_context7" "$weighted_websearch")

    # Run through pipeline and extract results array
    local piped
    piped=$(results_pipeline "$merged")
    
    # Extract results array if wrapped with metadata
    if echo "$piped" | jq -e 'type == "object" and has("_metadata")' >/dev/null 2>&1; then
        echo "$piped" | jq '._metadata.items // .'
    else
        echo "$piped"
    fi
}

# Group results by source
# Usage: results_group_by_source "json_array"
results_group_by_source() {
    local results="$1"
    
    echo "$results" | jq '
        group_by(.source // "unknown") |
        map({
            source: .[0].source // "unknown",
            count: length,
            results: .
        })
    '
}

# Extract unique sources/citations
# Usage: results_extract_sources "json_array"
results_extract_sources() {
    local results="$1"
    
    echo "$results" | jq '
        map({
            source: .source // "unknown",
            title: .title // "Untitled",
            url: .url // .link // null,
            package: .package // null,
            domain: ((.url // .link // "") | split("/")[2] // null),
            timestamp: .timestamp // null
        }) |
        unique_by(.url // .title)
    '
}

# Generate bibliography/citations list
# Usage: results_generate_citations "json_array" [format]
results_generate_citations() {
    local results="$1"
    local format="${2:-markdown}"
    
    local citations
    citations=$(results_extract_sources "$results")
    
    case "$format" in
        json)
            echo "$citations"
            ;;
        markdown)
            echo "$citations" | jq -r '
                "## References\n\n" +
                (. | to_entries | map(
                    "\(.key + 1). **\(.value.title // "Untitled")**\n" +
                    "   - Source: \(.value.source // "Unknown")\n" +
                    (if .value.package then "   - Package: \(.value.package)\n" else "" end) +
                    (if .value.url then "   - URL: [\(.value.url)](\(.value.url))\n" else "" end) +
                    (if .value.timestamp then "   - Retrieved: \(.value.timestamp)\n" else "" end)
                ) | join("\n"))
            '
            ;;
        text)
            echo "$citations" | jq -r '
                "References:\n" +
                (. | to_entries | map(
                    "\(.key + 1). \(.value.title // "Untitled")\n" +
                    "   Source: \(.value.source // "Unknown")\n" +
                    (if .value.url then "   URL: \(.value.url)\n" else "" end)
                ) | join("\n"))
            '
            ;;
        bibtex)
            echo "$citations" | jq -r '
                .[] |
                "@misc{lib" + (. | @base64 | .[0:8]) + ",\n" +
                "  title = {\(.title // "Untitled")},\n" +
                (if .value.package then "  package = {\(.value.package)},\n" else "" end) +
                (if .value.url then "  url = {\(.value.url)},\n" else "" end) +
                (if .value.timestamp then "  note = {Accessed: \(.value.timestamp)}" else "" end) +
                "}\n"
            '
            ;;
        *)
            echo "$citations"
            ;;
    esac
}

# Calculate result statistics
# Usage: results_stats "json_array"
results_stats() {
    local results="$1"
    
    echo "$results" | jq '
        {
            total: length,
            bySource: (group_by(.source // "unknown") | map({key: .[0].source, value: length}) | from_entries),
            avgScore: (map(.score // 0) | add / length),
            maxScore: (map(.score // 0) | max),
            minScore: (map(.score // 0) | min),
            withUrl: (map(select(.url != null)) | length),
            withContent: (map(select(.content != null or .text != null or .snippet != null)) | length)
        }
    '
}

# Cache results
# Usage: results_cache_save "cache_key" "json_array" [ttl_seconds]
results_cache_save() {
    local cache_key="$1"
    local results="$2"
    local ttl="${3:-3600}"
    
    local cache_dir
    cache_dir="$(librarian_get_cache_dir)/search"
    
    local cache_file="${cache_dir}/${cache_key}.json"
    local meta_file="${cache_dir}/${cache_key}.meta"
    
    # Save results
    echo "$results" > "$cache_file"
    
    # Save metadata
    cat > "$meta_file" <<EOF
{
    "cached_at": "$(librarian_timestamp)",
    "ttl": $ttl,
    "expires_at": $(($(date +%s) + ttl)),
    "key": "$(librarian_json_escape "$cache_key")",
    "count": $(echo "$results" | jq 'length')
}
EOF
    
    librarian_success "Cached: $cache_key"
}

# Load cached results
# Usage: results_cache_load "cache_key"
results_cache_load() {
    local cache_key="$1"
    
    local cache_dir
    cache_dir="$(librarian_get_cache_dir)/search"
    
    local cache_file="${cache_dir}/${cache_key}.json"
    local meta_file="${cache_dir}/${cache_key}.meta"
    
    # Check if cache exists
    if [[ ! -f "$cache_file" ]] || [[ ! -f "$meta_file" ]]; then
        echo "null"
        return 1
    fi
    
    # Check if expired
    local expires_at
    expires_at=$(jq -r '.expires_at // 0' "$meta_file" 2>/dev/null || echo "0")
    
    if [[ $(date +%s) -gt "$expires_at" ]]; then
        librarian_info "Cache expired: $cache_key"
        rm -f "$cache_file" "$meta_file"
        echo "null"
        return 1
    fi
    
    cat "$cache_file"
}

# Clear cache
# Usage: results_cache_clear [pattern]
results_cache_clear() {
    local pattern="${1:-*}"
    
    local cache_dir
    cache_dir="$(librarian_get_cache_dir)/search"
    
    local count=0
    for file in "$cache_dir"/${pattern}.json; do
        if [[ -f "$file" ]]; then
            rm -f "$file" "${file%.json}.meta"
            ((count++))
        fi
    done
    
    librarian_success "Cleared $count cache entries"
    echo "$count"
}
