#!/usr/bin/env bash
# Reviewer Subagent - Performance Analysis
# Detects performance issues, inefficient patterns, and optimization opportunities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# Performance Patterns
# =============================================================================

# Inefficient loop patterns
INEFFICIENT_LOOP_PATTERNS=(
    # Nested loops with large datasets
    'for\s*\([^)]*\)\s*for\s*\([^)]*\)'
    'while\s*\([^)]*\)\s*for\s*\([^)]*\)'
    # Loop with string concatenation
    '\+\s*=\s*.*inside\s*(for|while)'
    # Loop with DOM manipulation (JS)
    'getElementById|getElementsByClassName.*inside\s*loop'
)

# Memory leak patterns
MEMORY_LEAK_PATTERNS=(
    # Event listeners not removed
    'addEventListener\s*\([^)]*\)'
    # Global variables
    'window\.[a-zA-Z_]+\s*='
    # Closures in loops
    'for\s*\([^)]*\)\s*\{[^}]*function'
    # Timers not cleared
    'setInterval\s*\('
    'setTimeout\s*\('
)

# Unnecessary allocation patterns
UNNECESSARY_ALLOC_PATTERNS=(
    # Creating objects in loops
    'new\s+Object\s*\(\s*\)'
    '\{\s*\}'
    # String concatenation in loops
    '\+\s*='
    # Array push in loops (could use bulk operations)
    '\.push\s*\('
)

# Blocking operation patterns
BLOCKING_OP_PATTERNS=(
    # Synchronous file operations
    'readFileSync|writeFileSync|appendFileSync'
    'fs\.readSync|fs\.writeSync'
    # Synchronous database queries
    'executeSync|querySync'
    # Sleep/blocking calls
    'sleep\s*\(|usleep\s*\(|Thread\.sleep'
    'time\.sleep\(|asyncio\.sleep\s*\(\s*0'
)

# =============================================================================
# Inefficient Loop Detection
# =============================================================================

performance_check_inefficient_loops() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")
    local content
    content=$(cat "$file")

    # Check for nested loops
    local nested_count
    nested_count=$(echo "$content" | grep -cE 'for\s*\(|while\s*\(' 2>/dev/null || echo "0")
    nested_count=$(echo "$nested_count" | tr -d '[:space:]')
    nested_count=${nested_count:-0}

    if [[ "$nested_count" -gt 5 ]]; then
        # Find lines with nested loops
        local line_num=0
        local in_loop=0
        local loop_start=0

        while IFS= read -r line || [[ -n "$line" ]]; do
            ((line_num++))

            if echo "$line" | grep -qE 'for\s*\(|while\s*\('; then
                if [[ $in_loop -gt 0 ]]; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "performance" "inefficient-loops" \
                        "Nested loop detected (depth: $((in_loop + 1))). Consider optimizing algorithm." \
                        "Consider using hash maps, early termination, or algorithmic improvements")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ((in_loop++))
                loop_start=$line_num
            fi

            # Simple brace matching for loop end (approximation)
            if echo "$line" | grep -qE '^\s*\}'; then
                if [[ $in_loop -gt 0 ]]; then
                    ((in_loop--))
                fi
            fi
        done < "$file"
    fi

    # Check for string concatenation in loops
    local line_num=0
    local in_loop=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        if echo "$line" | grep -qE 'for\s*\(|while\s*\('; then
            in_loop=true
        fi

        if [[ "$in_loop" == true ]]; then
            # Check for string concatenation
            if echo "$line" | grep -qE '\+\s*=|\.\s*concat\s*\('; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "performance" "inefficient-loops" \
                    "String concatenation in loop. Use StringBuilder/join instead." \
                    "Use array join, StringBuilder, or template literals for better performance")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi

            # Check for loop end
            if echo "$line" | grep -qE '^\s*\}'; then
                in_loop=false
            fi
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Memory Leak Detection
# =============================================================================

performance_check_memory_leaks() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        case "$lang" in
            javascript|typescript)
                # Check for event listeners without cleanup
                if echo "$line" | grep -qE 'addEventListener\s*\('; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "performance" "memory-leaks" \
                        "Event listener added. Ensure it's removed to prevent memory leaks." \
                        "Store reference and call removeEventListener, or use once option")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi

                # Check for setInterval without clearInterval
                if echo "$line" | grep -qE 'setInterval\s*\('; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "performance" "memory-leaks" \
                        "setInterval used. Ensure clearInterval is called to prevent memory leaks." \
                        "Store interval ID and call clearInterval when component unmounts")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi

                # Check for global variable assignments
                if echo "$line" | grep -qE 'window\.[a-zA-Z_]+\s*='; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "performance" "memory-leaks" \
                        "Global variable assignment detected. Consider using module scope." \
                        "Use module pattern or closures to avoid polluting global scope")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;

            python)
                # Check for unclosed resources
                if echo "$line" | grep -qE 'open\s*\([^)]*\)' && ! echo "$line" | grep -qE 'with\s+open'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "performance" "memory-leaks" \
                        "File opened without context manager. Use 'with' statement." \
                        "Use 'with open(...) as f:' to ensure proper resource cleanup")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;
        esac
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Unnecessary Allocation Detection
# =============================================================================

performance_check_unnecessary_allocations() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")

    local line_num=0
    local in_loop=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Track loop context
        if echo "$line" | grep -qE 'for\s*\(|while\s*\('; then
            in_loop=true
        fi
        if echo "$line" | grep -qE '^\s*\}'; then
            in_loop=false
        fi

        case "$lang" in
            javascript|typescript)
                # Check for object creation in loops
                if [[ "$in_loop" == true ]]; then
                    if echo "$line" | grep -qE 'new\s+Object\s*\(\s*\)|\{\s*\}\s*:'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "performance" "unnecessary-allocations" \
                            "Object creation in loop. Consider hoisting or reusing objects." \
                            "Create object outside loop and reuse, or use Object.create(null)")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi
                ;;

            java)
                # Check for new in loops
                if [[ "$in_loop" == true ]]; then
                    if echo "$line" | grep -qE 'new\s+(ArrayList|HashMap|StringBuilder)\s*\('; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "performance" "unnecessary-allocations" \
                            "Collection creation in loop. Consider hoisting outside loop." \
                            "Create collection outside loop and clear/reuse it")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi
                ;;

            python)
                # Check for list creation in loops
                if [[ "$in_loop" == true ]]; then
                    if echo "$line" | grep -qE '\[\s*\]'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "performance" "unnecessary-allocations" \
                            "Empty list creation in loop. Consider hoisting if possible." \
                            "Create list outside loop if it doesn't need to be recreated")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi
                ;;
        esac
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Blocking Operation Detection
# =============================================================================

performance_check_blocking_operations() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        case "$lang" in
            javascript|typescript)
                # Check for synchronous fs operations
                if echo "$line" | grep -qE 'readFileSync|writeFileSync|appendFileSync|existsSync'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "performance" "blocking-operations" \
                        "Synchronous file operation blocks event loop. Use async version." \
                        "Use readFile, writeFile, or promise-based fs/promises module")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi

                # Check for sync XHR (in browser context)
                if echo "$line" | grep -qE 'open\s*\(\s*["\x27]GET|POST["\x27].*false\s*\)'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "critical" "performance" "blocking-operations" \
                        "Synchronous XMLHttpRequest blocks UI. Use async or fetch API." \
                        "Use fetch() API or async XMLHttpRequest")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;

            python)
                # Check for blocking sleep
                if echo "$line" | grep -qE 'time\.sleep\s*\('; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "performance" "blocking-operations" \
                        "Blocking sleep call. Consider asyncio.sleep in async code." \
                        "Use asyncio.sleep() in async functions for non-blocking delays")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi

                # Check for synchronous requests
                if echo "$line" | grep -qE 'requests\.(get|post|put|delete)\s*\('; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "performance" "blocking-operations" \
                        "Synchronous HTTP request. Consider aiohttp or httpx for async." \
                        "Use aiohttp or httpx.AsyncClient for non-blocking HTTP requests")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;

            java)
                # Check for Thread.sleep
                if echo "$line" | grep -qE 'Thread\.sleep\s*\('; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "performance" "blocking-operations" \
                        "Thread.sleep blocks current thread. Consider async alternatives." \
                        "Use CompletableFuture or reactive programming for non-blocking delays")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;
        esac
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Caching Opportunities Detection
# =============================================================================

performance_check_caching_opportunities() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")
    local content
    content=$(cat "$file")

    # Check for repeated expensive operations
    # Pattern: Same function called multiple times with same arguments

    # Find function calls
    local func_calls
    func_calls=$(echo "$content" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\s*\([^)]*\)' 2>/dev/null | sort | uniq -c | sort -rn | head -20)

    while IFS= read -r call_info; do
        [[ -z "$call_info" ]] && continue

        local count func_name
        count=$(echo "$call_info" | awk '{print $1}')
        func_name=$(echo "$call_info" | awk '{print $2}')

        # Skip common built-ins
        case "$func_name" in
            console.log|print|printf|echo|log|debug|info|warn|error)
                continue
                ;;
        esac

        if [[ $count -ge 5 ]]; then
            # Find first occurrence line
            local first_line
            first_line=$(grep -n "$func_name" "$file" 2>/dev/null | head -1 | cut -d: -f1)

            if [[ -n "$first_line" ]]; then
                local issue
                issue=$(reviewer_create_issue "$file" "$first_line" "0" "low" "performance" "caching-opportunities" \
                    "Function '$func_name' called $count times. Consider memoization or caching." \
                    "Use memoization, caching, or store result in variable if arguments are same")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi
        fi
    done <<< "$func_calls"

    echo "$issues"
}

# =============================================================================
# Large File/Resource Detection
# =============================================================================

performance_check_large_resources() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local file_size
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")

    # Check for very large files (> 1000 lines for source code)
    local line_count
    line_count=$(reviewer_count_lines "$file")

    if [[ $line_count -gt 1000 ]]; then
        local issue
        issue=$(reviewer_create_issue "$file" "0" "0" "info" "performance" "large-file" \
            "Large file detected ($line_count lines). Consider splitting into modules." \
            "Split into smaller, focused modules for better maintainability and performance")
        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
    fi

    # Check for large inline data
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for very long lines that might contain inline data
        if [[ ${#line} -gt 500 ]]; then
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "performance" "large-inline-data" \
                "Very long line (${#line} chars). Consider externalizing data." \
                "Move large data to separate files or use external resources")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# N+1 Query Detection (Database)
# =============================================================================

performance_check_n_plus_one() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")

    # Look for patterns indicating N+1 queries
    local line_num=0
    local in_loop=false
    local loop_start=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        if echo "$line" | grep -qE 'for\s*\(|while\s*\(|\.forEach\s*\(|\.map\s*\('; then
            in_loop=true
            loop_start=$line_num
        fi

        if [[ "$in_loop" == true ]]; then
            # Check for database queries in loops
            case "$lang" in
                javascript|typescript)
                    if echo "$line" | grep -qiE '\.(find|findOne|findById|query|execute)\s*\('; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "performance" "n-plus-one" \
                            "Database query inside loop. Potential N+1 query problem." \
                            "Use bulk queries with IN clause, or use .populate()/.include() for relations")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                    ;;

                python)
                    if echo "$line" | grep -qiE '\.(filter|get|all|execute|query)\s*\('; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "performance" "n-plus-one" \
                            "Database query inside loop. Potential N+1 query problem." \
                            "Use select_related/prefetch_related or bulk queries")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                    ;;

                java)
                    if echo "$line" | grep -qiE '\.(find|query|execute|select)\s*\('; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "performance" "n-plus-one" \
                            "Database query inside loop. Potential N+1 query problem." \
                            "Use JOIN FETCH or EntityGraph for eager loading")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                    ;;
            esac

            if echo "$line" | grep -qE '^\s*\}'; then
                in_loop=false
            fi
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# File-level Performance Check
# =============================================================================

performance_analyze_file() {
    local file="$1"
    local all_issues="[]"

    if [[ ! -f "$file" ]]; then
        reviewer_error "File not found: $file"
        echo "$all_issues"
        return
    fi

    reviewer_debug "Analyzing performance for: $file"

    local issues

    issues=$(performance_check_inefficient_loops "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(performance_check_memory_leaks "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(performance_check_unnecessary_allocations "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(performance_check_blocking_operations "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(performance_check_caching_opportunities "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(performance_check_n_plus_one "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(performance_check_large_resources "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    echo "$all_issues"
}

# =============================================================================
# Directory-level Performance Analysis
# =============================================================================

performance_analyze_directory() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"
    local output_format="${3:-json}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    local all_issues="[]"
    local file_count=0

    reviewer_info "Analyzing performance in: $root_dir"

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        ((file_count++))

        local issues
        issues=$(performance_analyze_file "$file")
        all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

        reviewer_debug "Analyzed: $file"
    done < <(reviewer_get_code_files "$root_dir" "$exclude_patterns")

    reviewer_info "Analyzed $file_count files"

    case "$output_format" in
        json)
            echo "$all_issues"
            ;;
        markdown)
            performance_format_report_markdown "$all_issues" "$root_dir"
            ;;
        text)
            performance_format_report_text "$all_issues" "$root_dir"
            ;;
        *)
            echo "$all_issues"
            ;;
    esac
}

# =============================================================================
# Report Formatting
# =============================================================================

performance_format_report_markdown() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    cat <<EOF
# Performance Analysis Report

**Directory:** $root_dir
**Generated:** $(reviewer_timestamp_human)
**Total Issues:** $issue_count

EOF

    if [[ $issue_count -eq 0 ]]; then
        echo "✅ No performance issues found!"
        return
    fi

    # Group by category
    for category in inefficient-loops memory-leaks unnecessary-allocations blocking-operations caching-opportunities n-plus-one large-file; do
        local cat_issues
        cat_issues=$(echo "$issues" | jq --arg cat "$category" '[.[] | select(.rule == $cat)]')
        local cat_count
        cat_count=$(echo "$cat_issues" | jq 'length')

        if [[ $cat_count -gt 0 ]]; then
            echo "## ${category//-/ } ($(reviewer_severity_emoji "medium") $cat_count)"
            echo ""
            echo "$cat_issues" | jq -r '.[] | "- **\(.file):\(.line)**: \(.message)"'
            echo ""
        fi
    done

    # Add optimization tips
    cat <<EOF
## Optimization Tips

1. **Algorithm Optimization**: Review O(n²) or worse complexity algorithms
2. **Caching**: Implement memoization for expensive computations
3. **Lazy Loading**: Load resources only when needed
4. **Batch Operations**: Combine multiple operations into single calls
5. **Connection Pooling**: Reuse database connections
6. **Async Operations**: Use non-blocking I/O where possible

## Profiling Tools

- **JavaScript**: Chrome DevTools, Node.js --inspect
- **Python**: cProfile, py-spy, memory_profiler
- **Java**: VisualVM, JProfiler, YourKit
- **Go**: pprof, trace
EOF
}

performance_format_report_text() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    echo "Performance Analysis Report"
    echo "==========================="
    echo "Directory: $root_dir"
    echo "Generated: $(reviewer_timestamp_human)"
    echo "Total Issues: $issue_count"
    echo ""

    if [[ $issue_count -eq 0 ]]; then
        echo "No performance issues found!"
        return
    fi

    echo "$issues" | jq -r '.[] | "[\(.severity | ascii_upcase)] \(.file):\(.line) - \(.message)"'
}

# =============================================================================
# Performance Score Calculation
# =============================================================================

performance_calculate_score() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"

    local issues
    issues=$(performance_analyze_directory "$root_dir" "$exclude_patterns" "json")

    local total critical high medium low score
    total=$(echo "$issues" | jq 'length')
    critical=$(echo "$issues" | jq '[.[] | select(.severity == "critical")] | length')
    high=$(echo "$issues" | jq '[.[] | select(.severity == "high")] | length')
    medium=$(echo "$issues" | jq '[.[] | select(.severity == "medium")] | length')
    low=$(echo "$issues" | jq '[.[] | select(.severity == "low")] | length')

    # Calculate score (100 - weighted deductions)
    local deductions
    deductions=$((critical * 20 + high * 10 + medium * 5 + low * 2))
    score=$((100 - deductions))
    [[ $score -lt 0 ]] && score=0

    cat <<EOF
{
  "score": $score,
  "total_issues": $total,
  "by_severity": {
    "critical": $critical,
    "high": $high,
    "medium": $medium,
    "low": $low
  }
}
EOF
}
