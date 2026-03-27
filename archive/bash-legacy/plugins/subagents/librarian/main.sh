#!/usr/bin/env bash
# OML Librarian Subagent Plugin
# Documentation search, Context7 queries, web search, and knowledge compilation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
PLUGIN_NAME="librarian"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi
if [[ -f "${OML_CORE_DIR}/plugin-loader.sh" ]]; then
    source "${OML_CORE_DIR}/plugin-loader.sh"
fi

# Source library modules
for lib in utils context7 websearch results compile; do
    if [[ -f "${LIB_DIR}/${lib}.sh" ]]; then
        source "${LIB_DIR}/${lib}.sh"
    fi
done

# Default configuration
DEFAULT_MAX_RESULTS="${OML_LIBRARIAN_MAX_RESULTS:-10}"
DEFAULT_FORMAT="${OML_LIBRARIAN_OUTPUT_FORMAT:-markdown}"
CONTEXT7_ENABLED="${OML_LIBRARIAN_CONTEXT7_ENABLED:-true}"
WEBSEARCH_ENABLED="${OML_LIBRARIAN_WEBSEARCH_ENABLED:-true}"

# Initialize librarian environment
librarian_init() {
    # Setup directories
    librarian_init_dirs >/dev/null
    
    # Setup log file
    export LIBRARIAN_LOG_FILE="$(librarian_get_cache_dir)/librarian.log"
    
    # Load configuration
    local config
    config=$(librarian_load_config)
    
    # Override defaults with config
    if echo "$config" | jq -e '.maxResults' >/dev/null 2>&1; then
        DEFAULT_MAX_RESULTS=$(echo "$config" | jq -r '.maxResults')
    fi
    if echo "$config" | jq -e '.outputFormat' >/dev/null 2>&1; then
        DEFAULT_FORMAT=$(echo "$config" | jq -r '.outputFormat')
    fi
}

# Show help
show_help() {
    cat <<'EOF'
OML Librarian Subagent - Documentation Search & Knowledge Management

USAGE:
    oml librarian <command> [options]

COMMANDS:
    search      Search documentation (Context7 + local)
    query       Query Context7 MCP for library documentation
    websearch   Web search using Exa MCP
    compile     Compile knowledge from multiple sources
    sources     List and manage citation sources
    cache       Manage search cache
    help        Show this help message

SEARCH COMMAND:
    oml librarian search <query> [options]
    
    Options:
        --package, -p     Package to search (e.g., "react", "npm:lodash")
        --limit, -l       Maximum results (default: 10)
        --format, -f      Output format: json, markdown, text (default: markdown)
        --sources         Comma-separated sources: context7,websearch (default: all)
        --dedup           Deduplication method: url, content, hybrid (default: hybrid)
        --output, -o      Save results to file

    Examples:
        oml librarian search "react hooks" --package react
        oml librarian search "python async" --sources context7 --format json
        oml librarian search "typescript generics" -l 5 -f markdown

QUERY COMMAND:
    oml librarian query <package> <query> [options]
    
    Options:
        --limit, -l       Maximum results (default: 10)
        --format, -f      Output format: json, markdown, text
        --registry        Package registry: npm, pypi, github (default: auto)

    Examples:
        oml librarian query react "how to use useEffect"
        oml librarian query pypi:requests "authentication"
        oml librarian query npm:@types/node "fs module" --format json

WEBSEARCH COMMAND:
    oml librarian websearch <query> [options]
    
    Options:
        --limit, -l       Maximum results (default: 10)
        --format, -f      Output format: json, markdown, text
        --include-domains Comma-separated domains to include
        --exclude-domains Comma-separated domains to exclude
        --with-content    Fetch full page content

    Examples:
        oml librarian websearch "rust async best practices"
        oml librarian websearch "kubernetes deployment" --include-domains kubernetes.io
        oml librarian websearch "docker compose" --with-content

COMPILE COMMAND:
    oml librarian compile <topic> [options]
    
    Options:
        --query, -q       Search query to gather content
        --package, -p     Package to search documentation
        --web             Also search web
        --format, -f      Output format: json, markdown, text
        --output, -o      Save compiled knowledge to file
        --no-citations    Exclude citations
        --no-summary      Exclude summary section

    Examples:
        oml librarian compile "React Hooks Guide" --query "react hooks tutorial"
        oml librarian compile "Python Async" --package asyncio --web
        oml librarian compile "Docker Best Practices" -f json -o docker-guide.json

SOURCES COMMAND:
    oml librarian sources <action> [options]
    
    Actions:
        list              List all citation sources
        export <file>     Export sources to file
        stats             Show source statistics

CACHE COMMAND:
    oml librarian cache <action> [options]
    
    Actions:
        clear             Clear all cache
        stats             Show cache statistics
        list              List cached items

GLOBAL OPTIONS:
    --verbose, -v         Enable verbose output
    --quiet, -q           Suppress non-essential output
    --help, -h            Show help for command

CONFIGURATION:
    Config file: ~/.local/share/oml/librarian/config.json
    Cache dir:   ~/.local/cache/oml/librarian
    Log file:    ~/.local/cache/oml/librarian/librarian.log

ENVIRONMENT VARIABLES:
    OML_LIBRARIAN_MAX_RESULTS       Default result limit
    OML_LIBRARIAN_OUTPUT_FORMAT     Default output format
    OML_LIBRARIAN_CONTEXT7_ENABLED  Enable Context7 integration
    OML_LIBRARIAN_WEBSEARCH_ENABLED Enable WebSearch integration
    CONTEXT7_API_KEY                Context7 API key
    EXA_API_KEY                     Exa API key

EOF
}

# Search command
cmd_search() {
    local query=""
    local package=""
    local limit="$DEFAULT_MAX_RESULTS"
    local format="$DEFAULT_FORMAT"
    local sources="all"
    local dedup="hybrid"
    local output_file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --package|-p)
                package="$2"
                shift 2
                ;;
            --limit|-l)
                limit="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --sources)
                sources="$2"
                shift 2
                ;;
            --dedup)
                dedup="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            --verbose|-v)
                set -x
                shift
                ;;
            -*)
                if [[ -z "$query" ]]; then
                    query="$1"
                fi
                shift
                ;;
            *)
                if [[ -z "$query" ]]; then
                    query="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$query" ]]; then
        librarian_error "Search query is required"
        echo "Usage: oml librarian search <query> [options]"
        return 1
    fi
    
    librarian_info "Searching: $query"
    
    local context7_results="[]"
    local websearch_results="[]"
    
    # Search Context7 if enabled and package specified
    if [[ "$CONTEXT7_ENABLED" == "true" ]] && [[ -n "$package" ]] && [[ "$sources" == "all" || "$sources" == *"context7"* ]]; then
        librarian_info "Searching Context7 for $package..."
        context7_results=$(context7_search "$package" "$query" "$limit" 2>/dev/null || echo "[]")
    fi
    
    # Search web if enabled
    if [[ "$WEBSEARCH_ENABLED" == "true" ]] && [[ "$sources" == "all" || "$sources" == *"websearch"* ]]; then
        librarian_info "Searching web..."
        websearch_results=$(websearch_auto "$query" "$limit" 2>/dev/null || echo "[]")
    fi
    
    # Combine results
    local combined
    combined=$(results_combine_sources "$context7_results" "$websearch_results")

    # Format output (combined already processed through pipeline)
    local formatted="$combined"
    
    local output
    case "$format" in
        json)
            output=$(echo "$formatted" | jq '.')
            ;;
        markdown)
            output=$(echo "$formatted" | jq -r '
                "# Search Results: '"$(librarian_json_escape "$query")"'

" +
                "**Total**: \(. | length) results\n\n" +
                (. | to_entries | map(
                    "## \(.key + 1). \(.value.title // "Untitled")\n\n" +
                    "**Source**: \(.value.source // "Unknown")" +
                    (if .value.package then " | **Package**: \(.value.package)" else "" end) +
                    "\n\n" +
                    "**Score**: \(.value.score // "N/A")\n\n" +
                    "\(.value.content // .value.text // .value.snippet // "No content")\n\n" +
                    (if .value.url then "**URL**: [\(.value.url)](\(.value.url))\n\n" else "" end) +
                    "---\n"
                ) | join("\n"))
            ' 2>/dev/null || echo "$formatted")
            ;;
        text)
            output=$(echo "$formatted" | jq -r '
                "Search Results: '"$(librarian_json_escape "$query")"'
" +
                "=" * 50 + "\n" +
                (. | to_entries | map(
                    "\(.key + 1). [\(.value.source // "?")] \(.value.title // "Untitled")\n" +
                    "   Score: \(.value.score // "N/A")\n" +
                    "   \(.value.content // .value.text // .value.snippet // "No content" | .[0:200])...\n" +
                    (if .value.url then "   URL: \(.value.url)\n" else "" end)
                ) | join("\n"))
            ' 2>/dev/null || echo "$formatted")
            ;;
        *)
            output="$formatted"
            ;;
    esac
    
    # Output
    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        librarian_success "Results saved to: $output_file"
    else
        echo "$output"
    fi
}

# Query command (Context7 specific)
cmd_query() {
    local package=""
    local query=""
    local limit="$DEFAULT_MAX_RESULTS"
    local format="$DEFAULT_FORMAT"
    local registry="auto"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit|-l)
                limit="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --registry)
                registry="$2"
                shift 2
                ;;
            -*)
                if [[ -z "$query" && -n "$package" ]]; then
                    query="$1"
                elif [[ -z "$package" ]]; then
                    package="$1"
                fi
                shift
                ;;
            *)
                if [[ -z "$package" ]]; then
                    package="$1"
                elif [[ -z "$query" ]]; then
                    query="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$package" ]] || [[ -z "$query" ]]; then
        librarian_error "Package and query are required"
        echo "Usage: oml librarian query <package> <query> [options]"
        return 1
    fi
    
    librarian_info "Querying $package: $query"
    
    # Search Context7
    local results
    results=$(context7_search "$package" "$query" "$limit" 2>/dev/null || echo "[]")
    
    # Format output
    local output
    case "$format" in
        json)
            output="$results"
            ;;
        markdown)
            output=$(context7_format_results "$results" "markdown")
            ;;
        text)
            output=$(context7_format_results "$results" "text")
            ;;
        *)
            output="$results"
            ;;
    esac
    
    echo "$output"
}

# WebSearch command
cmd_websearch() {
    local query=""
    local limit="$DEFAULT_MAX_RESULTS"
    local format="$DEFAULT_FORMAT"
    local include_domains=""
    local exclude_domains=""
    local with_content=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit|-l)
                limit="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --include-domains)
                include_domains="$2"
                shift 2
                ;;
            --exclude-domains)
                exclude_domains="$2"
                shift 2
                ;;
            --with-content)
                with_content=true
                shift
                ;;
            --verbose|-v)
                set -x
                shift
                ;;
            -*)
                if [[ -z "$query" ]]; then
                    query="$1"
                fi
                shift
                ;;
            *)
                if [[ -z "$query" ]]; then
                    query="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$query" ]]; then
        librarian_error "Search query is required"
        echo "Usage: oml librarian websearch <query> [options]"
        return 1
    fi
    
    librarian_info "Web searching: $query"
    
    local results
    if [[ "$with_content" == true ]]; then
        results=$(websearch_with_content "$query" "$limit" 2>/dev/null || echo "[]")
    else
        results=$(websearch_auto "$query" "$limit" 2>/dev/null || echo "[]")
    fi
    
    # Format output
    local output
    case "$format" in
        json)
            output="$results"
            ;;
        markdown)
            output=$(websearch_format_results "$results" "markdown")
            ;;
        text)
            output=$(websearch_format_results "$results" "text")
            ;;
        *)
            output="$results"
            ;;
    esac
    
    echo "$output"
}

# Compile command
cmd_compile() {
    local topic=""
    local search_query=""
    local package=""
    local do_web=false
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local include_citations=true
    local include_summary=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query|-q)
                search_query="$2"
                shift 2
                ;;
            --package|-p)
                package="$2"
                shift 2
                ;;
            --web)
                do_web=true
                shift
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            --no-citations)
                include_citations=false
                shift
                ;;
            --no-summary)
                include_summary=false
                shift
                ;;
            --verbose|-v)
                set -x
                shift
                ;;
            -*)
                if [[ -z "$topic" ]]; then
                    topic="$1"
                fi
                shift
                ;;
            *)
                if [[ -z "$topic" ]]; then
                    topic="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$topic" ]]; then
        librarian_error "Topic is required"
        echo "Usage: oml librarian compile <topic> [options]"
        return 1
    fi
    
    # Remove leading dashes from topic
    topic="${topic#--}"
    topic="${topic#-}"
    
    librarian_info "Compiling knowledge: $topic"
    
    # Gather content
    local all_results="[]"
    
    # Search with query
    if [[ -n "$search_query" ]]; then
        librarian_info "Gathering content: $search_query"
        
        local search_results
        search_results=$(cmd_search "$search_query" --limit 20 --format json 2>/dev/null || echo "[]")
        all_results=$(results_merge "$all_results" "$search_results")
    fi
    
    # Query Context7 if package specified
    if [[ -n "$package" ]]; then
        librarian_info "Querying Context7: $package"
        
        local ctx7_results
        ctx7_results=$(context7_search "$package" "$topic" 10 2>/dev/null || echo "[]")
        all_results=$(results_merge "$all_results" "$ctx7_results")
    fi
    
    # Web search if requested
    if [[ "$do_web" == true ]]; then
        librarian_info "Web searching..."
        
        local web_results
        web_results=$(websearch_auto "$topic" 10 2>/dev/null || echo "[]")
        all_results=$(results_merge "$all_results" "$web_results")
    fi
    
    # Deduplicate
    local deduped
    deduped=$(results_deduplicate "$all_results" "hybrid")
    
    # Compile knowledge
    local options
    options=$(cat <<EOF
{
    "format": "$format",
    "includeCitations": $include_citations,
    "includeSummary": $include_summary
}
EOF
)
    
    local compiled
    compiled=$(compile_knowledge "$deduped" "$topic" "$options")
    
    # Output
    if [[ -n "$output_file" ]]; then
        echo "$compiled" > "$output_file"
        librarian_success "Knowledge compiled to: $output_file"
    else
        echo "$compiled"
    fi
}

# Sources command
cmd_sources() {
    local action="${1:-list}"
    shift || true
    
    case "$action" in
        list)
            librarian_info "Listing sources..."
            # This would list from cache or config
            echo "[]"
            ;;
        export)
            local output_file="${1:-sources.json}"
            librarian_info "Exporting sources to: $output_file"
            echo "[]" > "$output_file"
            librarian_success "Sources exported"
            ;;
        stats)
            librarian_info "Source statistics"
            echo '{"total": 0, "bySource": {}}'
            ;;
        *)
            librarian_error "Unknown action: $action"
            echo "Usage: oml librarian sources <list|export|stats>"
            return 1
            ;;
    esac
}

# Cache command
cmd_cache() {
    local action="${1:-stats}"
    shift || true
    
    case "$action" in
        clear)
            results_cache_clear
            ;;
        stats)
            local cache_dir
            cache_dir="$(librarian_get_cache_dir)"
            
            local file_count=0
            local total_size=0
            
            if [[ -d "$cache_dir" ]]; then
                file_count=$(find "$cache_dir" -type f | wc -l)
                total_size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1 || echo "0")
            fi
            
            echo "{\"files\": $file_count, \"size\": \"$total_size\", \"directory\": \"$cache_dir\"}"
            ;;
        list)
            local cache_dir
            cache_dir="$(librarian_get_cache_dir)/search"
            
            if [[ -d "$cache_dir" ]]; then
                ls -la "$cache_dir" 2>/dev/null || echo "[]"
            else
                echo "[]"
            fi
            ;;
        *)
            librarian_error "Unknown action: $action"
            echo "Usage: oml librarian cache <clear|stats|list>"
            return 1
            ;;
    esac
}

# Main entry point
main() {
    # Initialize
    librarian_init
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        search)
            cmd_search "$@"
            ;;
        query)
            cmd_query "$@"
            ;;
        websearch)
            cmd_websearch "$@"
            ;;
        compile)
            cmd_compile "$@"
            ;;
        sources)
            cmd_sources "$@"
            ;;
        cache)
            cmd_cache "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            librarian_error "Unknown command: $command"
            echo "Usage: oml librarian <command> [options]"
            echo "Run 'oml librarian help' for more information."
            return 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
