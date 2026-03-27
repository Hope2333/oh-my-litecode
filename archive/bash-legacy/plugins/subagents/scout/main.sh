#!/usr/bin/env bash
# OML Scout Subagent Plugin
# Code analysis, dependency mapping, and repository statistics

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi

# Source library modules
for lib in utils tree complexity deps stats; do
    if [[ -f "${LIB_DIR}/${lib}.sh" ]]; then
        source "${LIB_DIR}/${lib}.sh"
    fi
done

PLUGIN_NAME="scout"

# Default configuration
DEFAULT_MAX_DEPTH="${OML_SCOUT_MAX_DEPTH:-10}"
DEFAULT_EXCLUDE="${OML_SCOUT_EXCLUDE_PATTERNS:-$(scout_get_default_excludes)}"
DEFAULT_FORMAT="${OML_SCOUT_OUTPUT_FORMAT:-markdown}"

# Analyze codebase structure and complexity
oml_scout_analyze() {
    local target_dir="."
    local exclude="$DEFAULT_EXCLUDE"
    local max_depth="$DEFAULT_MAX_DEPTH"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir|-d)
                target_dir="$2"
                shift 2
                ;;
            --exclude|-e)
                exclude="$2"
                shift 2
                ;;
            --max-depth)
                max_depth="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    target_dir=$(scout_validate_dir "$target_dir")

    # Only show info messages for non-JSON output
    if [[ "$format" != "json" ]]; then
        scout_info "Analyzing codebase: $target_dir"
        scout_info "Exclude patterns: $exclude"
        scout_info "Output format: $format"
    fi

    local result
    result=$(scout_analyze_directory "$target_dir" "$exclude" "$format")

    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        scout_success "Analysis saved to: $output_file"
    else
        echo "$result"
    fi
}

# Generate file tree visualization
oml_scout_tree() {
    local target_dir="."
    local exclude="$DEFAULT_EXCLUDE"
    local max_depth="3"
    local format="text"
    local output_file=""
    local show_files=true
    local show_dirs=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir|-d)
                target_dir="$2"
                shift 2
                ;;
            --exclude|-e)
                exclude="$2"
                shift 2
                ;;
            --max-depth|-m)
                max_depth="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            --dirs-only)
                show_files=false
                shift
                ;;
            --files-only)
                show_dirs=false
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    target_dir=$(scout_validate_dir "$target_dir")

    # Only show info messages for non-JSON output
    if [[ "$format" != "json" ]]; then
        scout_info "Generating tree for: $target_dir"
        scout_info "Max depth: $max_depth"
    fi
    
    local result
    result=$(scout_generate_tree "$target_dir" "$max_depth" "$exclude" "$format")
    
    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        scout_success "Tree saved to: $output_file"
    else
        echo "$result"
    fi
}

# Analyze dependencies and imports
oml_scout_deps() {
    local target_dir="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local graph=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir|-d)
                target_dir="$2"
                shift 2
                ;;
            --exclude|-e)
                exclude="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            --graph|-g)
                graph=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    target_dir=$(scout_validate_dir "$target_dir")

    if [[ "$graph" == true ]]; then
        if [[ "$format" != "json" ]]; then
            scout_info "Building dependency graph..."
        fi
        local result
        result=$(scout_build_dep_graph "$target_dir" "$exclude")

        if [[ -n "$output_file" ]]; then
            echo "$result" > "$output_file"
            scout_success "Dependency graph saved to: $output_file"
        else
            echo "$result"
        fi
    else
        if [[ "$format" != "json" ]]; then
            scout_info "Analyzing dependencies: $target_dir"
        fi

        local result
        result=$(scout_analyze_deps "$target_dir" "$exclude" "$format")
        
        if [[ -n "$output_file" ]]; then
            echo "$result" > "$output_file"
            scout_success "Dependency analysis saved to: $output_file"
        else
            echo "$result"
        fi
    fi
}

# Generate comprehensive analysis report
oml_scout_report() {
    local target_dir="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="markdown"
    local output_file=""
    local sections="all"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir|-d)
                target_dir="$2"
                shift 2
                ;;
            --exclude|-e)
                exclude="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            --sections|-s)
                sections="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    target_dir=$(scout_validate_dir "$target_dir")
    
    scout_info "Generating comprehensive report for: $target_dir"
    
    local timestamp
    timestamp=$(scout_timestamp)
    
    # Generate report based on format
    if [[ "$format" == "json" ]]; then
        _scout_report_json "$target_dir" "$exclude" "$output_file"
    else
        _scout_report_markdown "$target_dir" "$exclude" "$sections" "$output_file"
    fi
}

# Internal: Generate JSON report
_scout_report_json() {
    local target_dir="$1"
    local exclude="$2"
    local output_file="$3"
    
    local stats_json tree_json complexity_json deps_json
    
    stats_json=$(_scout_stats_json "$target_dir" "$(scout_parse_excludes "$exclude")")
    tree_json=$(scout_generate_tree "$target_dir" 3 "$exclude" "json")
    complexity_json=$(scout_complexity_summary "$target_dir" "$exclude" 2>/dev/null || echo '{}')
    
    local report
    report=$(python3 - "$target_dir" "$stats_json" "$tree_json" "$complexity_json" <<'PYTHON'
import sys
import json

target_dir = sys.argv[1]
stats = json.loads(sys.argv[2])
tree = json.loads(sys.argv[3])
complexity = json.loads(sys.argv[4]) if sys.argv[4] else {}

report = {
    "report_type": "scout_comprehensive",
    "generated_at": target_dir,  # Will be replaced
    "directory": target_dir,
    "statistics": stats,
    "file_tree": tree,
    "complexity_summary": complexity
}

print(json.dumps(report, indent=2))
PYTHON
)
    
    # Fix the generated_at field
    report=$(echo "$report" | python3 -c "
import sys, json
data = json.load(sys.stdin)
data['generated_at'] = '$(scout_timestamp)'
data['directory'] = '$target_dir'
print(json.dumps(data, indent=2))
")
    
    if [[ -n "$output_file" ]]; then
        echo "$report" > "$output_file"
        scout_success "Report saved to: $output_file"
    else
        echo "$report"
    fi
}

# Internal: Generate Markdown report
_scout_report_markdown() {
    local target_dir="$1"
    local exclude="$2"
    local sections="$3"
    local output_file="$4"
    
    local report=""
    
    report+="# Scout Analysis Report\n\n"
    report+="**Directory:** $target_dir\n"
    report+="**Generated:** $(scout_timestamp)\n\n"
    report+="---\n\n"
    
    # Section: Overview
    if [[ "$sections" == "all" || "$sections" == *"overview"* ]]; then
        report+="## Overview\n\n"
        local quick_stats
        quick_stats=$(scout_quick_stats "$target_dir")
        report+="\`\`\`\n$quick_stats\n\`\`\`\n\n"
    fi
    
    # Section: File Tree
    if [[ "$sections" == "all" || "$sections" == *"tree"* ]]; then
        report+="## File Structure\n\n"
        local tree_output
        tree_output=$(scout_generate_tree "$target_dir" 3 "$exclude" "markdown")
        report+="$tree_output\n\n"
    fi
    
    # Section: Statistics
    if [[ "$sections" == "all" || "$sections" == *"stats"* || "$sections" == *"statistics"* ]]; then
        report+="## File Statistics\n\n"
        local stats_output
        stats_output=$(scout_file_stats "$target_dir" "$exclude" "markdown")
        report+="$stats_output\n\n"
    fi
    
    # Section: Complexity
    if [[ "$sections" == "all" || "$sections" == *"complexity"* ]]; then
        report+="## Code Complexity\n\n"
        local complexity_output
        complexity_output=$(scout_complexity_summary "$target_dir" "$exclude" 2>/dev/null || echo "Complexity analysis not available")
        if [[ "$complexity_output" != "Complexity analysis not available" ]]; then
            report+="\`\`\`json\n$complexity_output\n\`\`\`\n\n"
        else
            report+="$complexity_output\n\n"
        fi
    fi
    
    # Section: Dependencies
    if [[ "$sections" == "all" || "$sections" == *"deps"* || "$sections" == *"dependencies"* ]]; then
        report+="## Dependencies Summary\n\n"
        report+="See \`oml scout deps\` command for detailed dependency analysis.\n\n"
    fi
    
    # Output report
    if [[ -n "$output_file" ]]; then
        echo -e "$report" > "$output_file"
        scout_success "Report saved to: $output_file"
    else
        echo -e "$report"
    fi
}

# Show file type statistics
oml_scout_stats() {
    local target_dir="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="text"
    local output_file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir|-d)
                target_dir="$2"
                shift 2
                ;;
            --exclude|-e)
                exclude="$2"
                shift 2
                ;;
            --format|-f)
                format="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            --quick|-q)
                scout_quick_stats "$target_dir"
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    target_dir=$(scout_validate_dir "$target_dir")

    # Only show info messages for non-JSON output
    if [[ "$format" != "json" ]]; then
        scout_info "Generating statistics for: $target_dir"
    fi

    local result
    result=$(scout_file_stats "$target_dir" "$exclude" "$format")

    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        scout_success "Statistics saved to: $output_file"
    else
        echo "$result"
    fi
}

# Main entry point
main() {
    local action="${1:-help}"
    shift || true
    
    case "$action" in
        analyze)
            oml_scout_analyze "$@"
            ;;
        tree)
            oml_scout_tree "$@"
            ;;
        deps)
            oml_scout_deps "$@"
            ;;
        report)
            oml_scout_report "$@"
            ;;
        stats)
            oml_scout_stats "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Scout Subagent - Code Analysis Tool

Usage: oml scout <action> [options]

Actions:
  analyze    Analyze codebase structure and complexity
  tree       Generate file tree visualization
  deps       Analyze dependencies and imports
  report     Generate comprehensive analysis report
  stats      Show file type statistics

Options:
  --dir|-d <path>       Target directory (default: current)
  --exclude|-e <pattern> Comma-separated exclude patterns
  --format|-f <format>  Output format: json, markdown, text
  --output|-o <file>    Save output to file
  --max-depth|-m <num>  Maximum tree depth (default: 3 for tree, 10 for analyze)
  --sections|-s <list>  Report sections: all, overview, tree, stats, complexity, deps
  --graph|-g            Generate dependency graph (DOT format)
  --quick|-q            Quick stats summary
  --dirs-only           Show directories only (tree)
  --files-only          Show files only (tree)

Examples:
  # Generate file tree
  oml scout tree --dir ./src --max-depth 2

  # Analyze code complexity
  oml scout analyze --dir ./src --format markdown

  # Analyze dependencies
  oml scout deps --dir ./src --format json --output deps.json

  # Generate comprehensive report
  oml scout report --dir . --format markdown --output report.md

  # Quick statistics
  oml scout stats --quick

  # Detailed statistics
  oml scout stats --dir . --format markdown --output stats.md

Exclude Patterns:
  Default: node_modules,.git,__pycache__,.venv,dist,build,.cache,target,coverage

Output Formats:
  - json: Machine-readable JSON output
  - markdown: Human-readable Markdown report
  - text: Plain text summary

Environment Variables:
  OML_SCOUT_OUTPUT_FORMAT     Default output format (default: markdown)
  OML_SCOUT_MAX_DEPTH         Default max depth (default: 10)
  OML_SCOUT_EXCLUDE_PATTERNS  Default exclude patterns
EOF
            ;;
        *)
            scout_error "Unknown action: $action"
            echo "Use 'oml scout help' for usage"
            return 1
            ;;
    esac
}

main "$@"
