#!/usr/bin/env bash
# OML Reviewer Subagent Plugin
# Code review, security auditing, style checking, and best practices validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
PLUGIN_NAME="reviewer"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi
if [[ -f "${OML_CORE_DIR}/plugin-loader.sh" ]]; then
    source "${OML_CORE_DIR}/plugin-loader.sh"
fi

# Source library modules
for lib in utils style security performance best-practices report; do
    if [[ -f "${LIB_DIR}/${lib}.sh" ]]; then
        source "${LIB_DIR}/${lib}.sh"
    fi
done

# Default configuration
DEFAULT_EXCLUDE="${OML_REVIEWER_EXCLUDE_PATTERNS:-$(reviewer_get_default_excludes)}"
DEFAULT_FORMAT="${OML_REVIEWER_OUTPUT_FORMAT:-markdown}"
DEFAULT_MAX_ISSUES="${OML_REVIEWER_MAX_ISSUES:-100}"
SECURITY_ENABLED="${OML_REVIEWER_SECURITY_ENABLED:-true}"
STYLE_ENABLED="${OML_REVIEWER_STYLE_ENABLED:-true}"
PERFORMANCE_ENABLED="${OML_REVIEWER_PERFORMANCE_ENABLED:-true}"
BEST_PRACTICES_ENABLED="${OML_REVIEWER_BEST_PRACTICES_ENABLED:-true}"
STRICT_MODE="${OML_REVIEWER_STRICT_MODE:-false}"

# =============================================================================
# Help Message
# =============================================================================

show_help() {
    cat <<'EOF'
OML Reviewer Subagent - Code Quality Review & Security Auditing

USAGE:
    oml reviewer <command> [options]

COMMANDS:
    code            Comprehensive code review (all checks)
    security        Security vulnerability audit
    style           Code style and formatting check
    performance     Performance issue analysis
    best-practices  Best practices compliance check
    report          Generate structured review report
    help            Show this help message

CODE COMMAND:
    oml reviewer code [directory] [options]

    Options:
        --exclude, -e     Comma-separated exclude patterns
        --format, -f      Output format: json, markdown, text (default: markdown)
        --output, -o      Save report to file
        --no-security     Skip security checks
        --no-style        Skip style checks
        --no-performance  Skip performance checks
        --no-best-practices  Skip best practices checks
        --strict          Enable strict mode (more issues reported)

    Examples:
        oml reviewer code ./src
        oml reviewer code . --format json --output report.json
        oml reviewer code ./app --exclude "node_modules,vendor"

SECURITY COMMAND:
    oml reviewer security [directory] [options]

    Options:
        --exclude, -e     Comma-separated exclude patterns
        --format, -f      Output format: json, markdown, text
        --output, -o      Save report to file
        --no-sensitive    Skip sensitive file detection
        --score           Show security score only

    Examples:
        oml reviewer security ./src
        oml reviewer security . --format json
        oml reviewer security . --score

STYLE COMMAND:
    oml reviewer style [directory] [options]

    Options:
        --exclude, -e     Comma-separated exclude patterns
        --format, -f      Output format: json, markdown, text
        --output, -o      Save report to file
        --max-line-length Maximum line length (default: 120)
        --indent-size     Indent size (default: 4)
        --stats           Show style statistics only

    Examples:
        oml reviewer style ./src
        oml reviewer style . --max-line-length 100
        oml reviewer style . --stats

PERFORMANCE COMMAND:
    oml reviewer performance [directory] [options]

    Options:
        --exclude, -e     Comma-separated exclude patterns
        --format, -f      Output format: json, markdown, text
        --output, -o      Save report to file
        --score           Show performance score only

    Examples:
        oml reviewer performance ./src
        oml reviewer performance . --score

BEST-PRACTICES COMMAND:
    oml reviewer best-practices [directory] [options]

    Options:
        --exclude, -e     Comma-separated exclude patterns
        --format, -f      Output format: json, markdown, text
        --output, -o      Save report to file
        --score           Show best practices score only

    Examples:
        oml reviewer best-practices ./src
        oml reviewer best-practices . --score

REPORT COMMAND:
    oml reviewer report [directory] [options]

    Options:
        --exclude, -e     Comma-separated exclude patterns
        --format, -f      Output format: json, markdown, text, html
        --output, -o      Save report to file (required for html)
        --quick           Generate quick summary only
        --comprehensive   Generate full comprehensive report (default)

    Examples:
        oml reviewer report . --format markdown --output report.md
        oml reviewer report . --format html --output report.html
        oml reviewer report . --quick

GLOBAL OPTIONS:
    --verbose, -v         Enable verbose output
    --quiet, -q           Suppress non-essential output
    --help, -h            Show help for command

CONFIGURATION:
    Config file: ~/.local/share/oml/reviewer/config.json
    Cache dir:   ~/.local/cache/oml/reviewer
    Log file:    ~/.local/cache/oml/reviewer/reviewer.log

ENVIRONMENT VARIABLES:
    OML_REVIEWER_OUTPUT_FORMAT        Default: markdown
    OML_REVIEWER_MAX_ISSUES           Default: 100
    OML_REVIEWER_EXCLUDE_PATTERNS     Default: node_modules,.git,__pycache__,...
    OML_REVIEWER_SECURITY_ENABLED     Default: true
    OML_REVIEWER_STYLE_ENABLED        Default: true
    OML_REVIEWER_PERFORMANCE_ENABLED  Default: true
    OML_REVIEWER_BEST_PRACTICES_ENABLED Default: true
    OML_REVIEWER_STRICT_MODE          Default: false

EXIT CODES:
    0 - Success, no critical issues
    1 - Success, issues found
    2 - Error (invalid arguments, missing files, etc.)
    3 - Critical security issues found (in strict mode)

EOF
}

# =============================================================================
# Code Review Command
# =============================================================================

cmd_code() {
    local target="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local do_security="$SECURITY_ENABLED"
    local do_style="$STYLE_ENABLED"
    local do_performance="$PERFORMANCE_ENABLED"
    local do_best_practices="$BEST_PRACTICES_ENABLED"
    local strict="$STRICT_MODE"

    # Parse positional argument for directory
    if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
        target="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --no-security)
                do_security="false"
                shift
                ;;
            --no-style)
                do_style="false"
                shift
                ;;
            --no-performance)
                do_performance="false"
                shift
                ;;
            --no-best-practices)
                do_best_practices="false"
                shift
                ;;
            --strict)
                strict="true"
                shift
                ;;
            --verbose|-v)
                export OML_REVIEWER_VERBOSE="true"
                shift
                ;;
            --quiet|-q)
                export OML_REVIEWER_QUIET="true"
                shift
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Source modules
    source "${LIB_DIR}/style.sh"
    source "${LIB_DIR}/security.sh"
    source "${LIB_DIR}/performance.sh"
    source "${LIB_DIR}/best-practices.sh"

    local all_issues="[]"
    local issues

    # Check if target is a file or directory
    if [[ -f "$target" ]]; then
        # Single file review
        reviewer_info "Reviewing file: $target"

        if [[ "$do_style" == "true" ]]; then
            issues=$(style_check_file "$target")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi

        if [[ "$do_security" == "true" ]]; then
            issues=$(security_audit_file "$target")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi

        if [[ "$do_performance" == "true" ]]; then
            issues=$(performance_analyze_file "$target")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi

        if [[ "$do_best_practices" == "true" ]]; then
            issues=$(best_practices_check_file "$target")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi
    elif [[ -d "$target" ]]; then
        target=$(reviewer_validate_dir "$target")
        reviewer_info "Starting code review: $target"

        # Run enabled checks
        if [[ "$do_style" == "true" ]]; then
            reviewer_info "Running style checks..."
            issues=$(style_check_directory "$target" "$exclude" "json" 2>/dev/null || echo "[]")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi

        if [[ "$do_security" == "true" ]]; then
            reviewer_info "Running security audit..."
            issues=$(security_audit_directory "$target" "$exclude" "json" "true" 2>/dev/null || echo "[]")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi

        if [[ "$do_performance" == "true" ]]; then
            reviewer_info "Running performance analysis..."
            issues=$(performance_analyze_directory "$target" "$exclude" "json" 2>/dev/null || echo "[]")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi

        if [[ "$do_best_practices" == "true" ]]; then
            reviewer_info "Running best practices check..."
            issues=$(best_practices_check_directory "$target" "$exclude" "json" 2>/dev/null || echo "[]")
            all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')
        fi
    else
        reviewer_error "Path not found: $target"
        return 1
    fi

    # Format output
    local output
    case "$format" in
        json)
            output=$(echo "$all_issues" | jq '.')
            ;;
        markdown)
            output=$(format_issues_markdown "$all_issues" "$target" "Code Review")
            ;;
        text)
            output=$(format_issues_text "$all_issues" "$target" "Code Review")
            ;;
        *)
            output="$all_issues"
            ;;
    esac

    # Output
    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        reviewer_success "Report saved to: $output_file"
    else
        echo "$output"
    fi

    # Check for critical issues in strict mode
    if [[ "$strict" == "true" ]]; then
        local critical_count
        critical_count=$(echo "$all_issues" | jq '[.[] | select(.severity == "critical")] | length')
        if [[ $critical_count -gt 0 ]]; then
            reviewer_error "Found $critical_count critical issues in strict mode"
            return 3
        fi
    fi

    return 0
}

# =============================================================================
# Security Command
# =============================================================================

cmd_security() {
    local target="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local include_sensitive="true"
    local score_only="false"

    if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
        target="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --no-sensitive)
                include_sensitive="false"
                shift
                ;;
            --score)
                score_only="true"
                shift
                ;;
            --verbose|-v)
                export OML_REVIEWER_VERBOSE="true"
                shift
                ;;
            --quiet|-q)
                export OML_REVIEWER_QUIET="true"
                shift
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    source "${LIB_DIR}/security.sh"

    local output
    # Check if target is a file or directory
    if [[ -f "$target" ]]; then
        output=$(security_audit_file "$target")
    elif [[ -d "$target" ]]; then
        if [[ "$score_only" == "true" ]]; then
            output=$(security_calculate_score "$target" "$exclude")
        else
            output=$(security_audit_directory "$target" "$exclude" "$format" "$include_sensitive")
        fi
    else
        reviewer_error "Path not found: $target"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        reviewer_success "Security report saved to: $output_file"
    else
        echo "$output"
    fi
}

# =============================================================================
# Style Command
# =============================================================================

cmd_style() {
    local target="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local stats_only="false"
    local max_line_length="$DEFAULT_MAX_LINE_LENGTH"
    local indent_size="$DEFAULT_INDENT_SIZE"

    if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
        target="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --max-line-length)
                max_line_length="$2"
                shift 2
                ;;
            --indent-size)
                indent_size="$2"
                shift 2
                ;;
            --stats)
                stats_only="true"
                shift
                ;;
            --verbose|-v)
                export OML_REVIEWER_VERBOSE="true"
                shift
                ;;
            --quiet|-q)
                export OML_REVIEWER_QUIET="true"
                shift
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    source "${LIB_DIR}/style.sh"

    local output
    # Check if target is a file or directory
    if [[ -f "$target" ]]; then
        output=$(style_check_file "$target")
        if [[ "$format" == "markdown" ]]; then
            output=$(style_format_report_markdown "$output" "$target")
        elif [[ "$format" == "text" ]]; then
            output=$(style_format_report_text "$output" "$target")
        fi
    elif [[ -d "$target" ]]; then
        export OML_REVIEWER_MAX_LINE_LENGTH="$max_line_length"
        export OML_REVIEWER_INDENT_SIZE="$indent_size"

        if [[ "$stats_only" == "true" ]]; then
            output=$(style_quick_stats "$target" "$exclude")
        else
            output=$(style_check_directory "$target" "$exclude" "$format")
        fi
    else
        reviewer_error "Path not found: $target"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        reviewer_success "Style report saved to: $output_file"
    else
        echo "$output"
    fi
}

# =============================================================================
# Performance Command
# =============================================================================

cmd_performance() {
    local target="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local score_only="false"

    if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
        target="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --score)
                score_only="true"
                shift
                ;;
            --verbose|-v)
                export OML_REVIEWER_VERBOSE="true"
                shift
                ;;
            --quiet|-q)
                export OML_REVIEWER_QUIET="true"
                shift
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    source "${LIB_DIR}/performance.sh"

    local output
    # Check if target is a file or directory
    if [[ -f "$target" ]]; then
        output=$(performance_analyze_file "$target")
        if [[ "$format" == "markdown" ]]; then
            output=$(performance_format_report_markdown "$output" "$target")
        elif [[ "$format" == "text" ]]; then
            output=$(performance_format_report_text "$output" "$target")
        fi
    elif [[ -d "$target" ]]; then
        if [[ "$score_only" == "true" ]]; then
            output=$(performance_calculate_score "$target" "$exclude")
        else
            output=$(performance_analyze_directory "$target" "$exclude" "$format")
        fi
    else
        reviewer_error "Path not found: $target"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        reviewer_success "Performance report saved to: $output_file"
    else
        echo "$output"
    fi
}

# =============================================================================
# Best Practices Command
# =============================================================================

cmd_best_practices() {
    local target="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local score_only="false"

    if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
        target="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --score)
                score_only="true"
                shift
                ;;
            --verbose|-v)
                export OML_REVIEWER_VERBOSE="true"
                shift
                ;;
            --quiet|-q)
                export OML_REVIEWER_QUIET="true"
                shift
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    source "${LIB_DIR}/best-practices.sh"

    local output
    # Check if target is a file or directory
    if [[ -f "$target" ]]; then
        output=$(best_practices_check_file "$target")
        if [[ "$format" == "markdown" ]]; then
            output=$(best_practices_format_report_markdown "$output" "$target")
        elif [[ "$format" == "text" ]]; then
            output=$(best_practices_format_report_text "$output" "$target")
        fi
    elif [[ -d "$target" ]]; then
        if [[ "$score_only" == "true" ]]; then
            output=$(best_practices_calculate_score "$target" "$exclude")
        else
            output=$(best_practices_check_directory "$target" "$exclude" "$format")
        fi
    else
        reviewer_error "Path not found: $target"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        reviewer_success "Best practices report saved to: $output_file"
    else
        echo "$output"
    fi
}

# =============================================================================
# Report Command
# =============================================================================

cmd_report() {
    local target="."
    local exclude="$DEFAULT_EXCLUDE"
    local format="$DEFAULT_FORMAT"
    local output_file=""
    local quick="false"
    local comprehensive="true"

    if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
        target="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --quick)
                quick="true"
                comprehensive="false"
                shift
                ;;
            --comprehensive)
                comprehensive="true"
                shift
                ;;
            --verbose|-v)
                export OML_REVIEWER_VERBOSE="true"
                shift
                ;;
            --quiet|-q)
                export OML_REVIEWER_QUIET="true"
                shift
                ;;
            --help|-h)
                show_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done

    source "${LIB_DIR}/report.sh"

    local output
    # Check if target is a file or directory
    if [[ -f "$target" ]]; then
        # For single file, just do a quick check
        output=$(report_generate_quick "$(dirname "$target")" "$exclude")
    elif [[ -d "$target" ]]; then
        if [[ "$quick" == "true" ]]; then
            output=$(report_generate_quick "$target" "$exclude")
        else
            output=$(report_generate_comprehensive "$target" "$exclude" "$format" "$output_file")
            # report_generate_comprehensive already handles output_file
            if [[ -z "$output_file" ]]; then
                echo "$output"
            fi
            return 0
        fi
    else
        reviewer_error "Path not found: $target"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        reviewer_success "Report saved to: $output_file"
    else
        echo "$output"
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================

format_issues_markdown() {
    local issues="$1"
    local root_dir="${2:-.}"
    local title="${3:-Review}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    cat <<EOF
# $title Report

**Directory:** $root_dir
**Generated:** $(reviewer_timestamp_human)
**Total Issues:** $issue_count

EOF

    if [[ $issue_count -eq 0 ]]; then
        echo "✅ No issues found!"
        return
    fi

    # Group by severity
    for severity in critical high medium low info; do
        local sev_issues
        sev_issues=$(echo "$issues" | jq --arg sev "$severity" '[.[] | select(.severity == $sev)]')
        local sev_count
        sev_count=$(echo "$sev_issues" | jq 'length')

        if [[ $sev_count -gt 0 ]]; then
            echo "## $(reviewer_severity_emoji "$severity") ${severity^} ($sev_count)"
            echo ""
            echo "$sev_issues" | jq -r '.[] | "- **\(.file):\(.line)**: \(.message)"'
            echo ""
        fi
    done
}

format_issues_text() {
    local issues="$1"
    local root_dir="${2:-.}"
    local title="${3:-Review}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    echo "$title Report"
    echo "=============="
    echo "Directory: $root_dir"
    echo "Generated: $(reviewer_timestamp_human)"
    echo "Total Issues: $issue_count"
    echo ""

    if [[ $issue_count -eq 0 ]]; then
        echo "No issues found!"
        return
    fi

    echo "$issues" | jq -r '.[] | "[\(.severity | ascii_upcase)] \(.file):\(.line) - \(.message)"'
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        code)
            cmd_code "$@"
            ;;
        security)
            cmd_security "$@"
            ;;
        style)
            cmd_style "$@"
            ;;
        performance)
            cmd_performance "$@"
            ;;
        best-practices|best_practices)
            cmd_best_practices "$@"
            ;;
        report)
            cmd_report "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        version|--version|-V)
            echo "OML Reviewer Subagent v0.1.0"
            ;;
        *)
            reviewer_error "Unknown command: $command"
            echo "Usage: oml reviewer <command> [options]"
            echo "Run 'oml reviewer help' for more information."
            return 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
