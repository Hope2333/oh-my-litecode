#!/usr/bin/env bash
# Reviewer Subagent - Code Style Checking
# Checks for code style issues, formatting, and naming conventions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# Configuration
# =============================================================================

DEFAULT_MAX_LINE_LENGTH="${OML_REVIEWER_MAX_LINE_LENGTH:-120}"
DEFAULT_INDENT_SIZE="${OML_REVIEWER_INDENT_SIZE:-4}"
DEFAULT_USE_TABS="${OML_REVIEWER_USE_TABS:-false}"

# =============================================================================
# Line Length Check
# =============================================================================

style_check_line_length() {
    local file="$1"
    local max_length="${2:-$DEFAULT_MAX_LINE_LENGTH}"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local len=${#line}

        if [[ $len -gt $max_length ]]; then
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "style" "max-line-length" \
                "Line exceeds maximum length ($len > $max_length)" \
                "Consider breaking this line into multiple lines")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Indentation Check
# =============================================================================

style_check_indentation() {
    local file="$1"
    local indent_size="${2:-$DEFAULT_INDENT_SIZE}"
    local use_tabs="${3:-$DEFAULT_USE_TABS}"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Get leading whitespace
        local leading="${line%%[![:space:]]*}"
        [[ -z "$leading" ]] && continue

        if [[ "$use_tabs" == "true" ]]; then
            # Check for spaces used instead of tabs
            if [[ "$leading" =~ ^[[:space:]]+$ ]] && [[ "$leading" != *$'\t'* ]]; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "style" "indentation" \
                    "Spaces used instead of tabs" \
                    "Use tabs for indentation")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi
        else
            # Check for tabs used instead of spaces
            if [[ "$leading" == *$'\t'* ]]; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "style" "indentation" \
                    "Tabs used instead of spaces" \
                    "Use $indent_size spaces for indentation")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi

            # Check for inconsistent indentation
            local space_count=${#leading}
            if [[ $space_count -gt 0 ]] && [[ $((space_count % indent_size)) -ne 0 ]]; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "indentation" \
                    "Inconsistent indentation ($space_count spaces, expected multiple of $indent_size)" \
                    "Use consistent $indent_size-space indentation")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Trailing Whitespace Check
# =============================================================================

style_check_trailing_whitespace() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for trailing whitespace (excluding empty lines)
        if [[ "$line" =~ [[:space:]]$ ]] && [[ -n "${line// /}" ]]; then
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "trailing-whitespace" \
                "Trailing whitespace detected" \
                "Remove trailing whitespace")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Naming Convention Check
# =============================================================================

style_check_naming_conventions() {
    local file="$1"
    local lang="$2"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang_lower
    lang_lower=$(echo "$lang" | tr '[:upper:]' '[:lower:]')

    case "$lang_lower" in
        javascript|typescript)
            issues=$(style_check_js_naming "$file" "$issues")
            ;;
        python)
            issues=$(style_check_python_naming "$file" "$issues")
            ;;
        bash|shell)
            issues=$(style_check_bash_naming "$file" "$issues")
            ;;
        go)
            issues=$(style_check_go_naming "$file" "$issues")
            ;;
        java)
            issues=$(style_check_java_naming "$file" "$issues")
            ;;
    esac

    echo "$issues"
}

style_check_js_naming() {
    local file="$1"
    local issues="$2"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for snake_case variables (should be camelCase)
        if echo "$line" | grep -qE 'var\s+[a-z]+_[a-z]+|let\s+[a-z]+_[a-z]+|const\s+[a-z]+_[a-z]+'; then
            local var_name
            var_name=$(echo "$line" | grep -oE '(var|let|const)\s+[a-z]+_[a-z]+' | head -1 | awk '{print $2}')
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "naming-convention" \
                "Variable '$var_name' uses snake_case, consider camelCase" \
                "Use camelCase for JavaScript variables")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi

        # Check for PascalCase functions (should be camelCase for non-constructors)
        if echo "$line" | grep -qE 'function\s+[A-Z][a-z]+[A-Z]|[a-z]+\s*=\s*function\s*\([^)]*\)\s*\{' 2>/dev/null; then
            :  # Additional checks could be added here
        fi
    done < "$file"

    echo "$issues"
}

style_check_python_naming() {
    local file="$1"
    local issues="$2"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for camelCase variables (should be snake_case)
        if echo "$line" | grep -qE '^[a-z]+[A-Z][a-z]+\s*=' 2>/dev/null; then
            local var_name
            var_name=$(echo "$line" | grep -oE '^[a-z]+[A-Z][a-z]+' | head -1)
            if [[ -n "$var_name" ]]; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "naming-convention" \
                    "Variable '$var_name' uses camelCase, consider snake_case" \
                    "Use snake_case for Python variables")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi
        fi

        # Check for snake_case class names (should be PascalCase)
        if echo "$line" | grep -qE '^class\s+[a-z]+_[a-z]+'; then
            local class_name
            class_name=$(echo "$line" | grep -oE 'class\s+[a-z]+_[a-z]+' | awk '{print $2}')
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "style" "naming-convention" \
                "Class '$class_name' uses snake_case, should be PascalCase" \
                "Use PascalCase for Python class names")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    done < "$file"

    echo "$issues"
}

style_check_bash_naming() {
    local file="$1"
    local issues="$2"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for camelCase variables (should be snake_case or UPPER_CASE for constants)
        if echo "$line" | grep -qE '^[[:space:]]*[a-z]+[A-Z][a-z]+=' 2>/dev/null; then
            local var_name
            var_name=$(echo "$line" | grep -oE '[a-z]+[A-Z][a-z]+' | head -1)
            if [[ -n "$var_name" ]]; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "naming-convention" \
                    "Variable '$var_name' uses camelCase, consider snake_case" \
                    "Use snake_case or UPPER_CASE for shell variables")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi
        fi
    done < "$file"

    echo "$issues"
}

style_check_go_naming() {
    local file="$1"
    local issues="$2"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for snake_case variables (should be camelCase)
        if echo "$line" | grep -qE '(var|const)\s+[a-z]+_[a-z]+'; then
            local var_name
            var_name=$(echo "$line" | grep -oE '(var|const)\s+[a-z]+_[a-z]+' | awk '{print $2}')
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "naming-convention" \
                "Variable '$var_name' uses snake_case, consider camelCase" \
                "Use camelCase for Go variables")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    done < "$file"

    echo "$issues"
}

style_check_java_naming() {
    local file="$1"
    local issues="$2"
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        # Check for snake_case variables (should be camelCase)
        if echo "$line" | grep -qE '(int|String|boolean|double|float|long|var)\s+[a-z]+_[a-z]+'; then
            local var_name
            var_name=$(echo "$line" | grep -oE '(int|String|boolean|double|float|long|var)\s+[a-z]+_[a-z]+' | awk '{print $2}')
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "naming-convention" \
                "Variable '$var_name' uses snake_case, consider camelCase" \
                "Use camelCase for Java variables")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Brace Style Check
# =============================================================================

style_check_braces() {
    local file="$1"
    local lang="$2"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang_lower
    lang_lower=$(echo "$lang" | tr '[:upper:]' '[:lower:]')

    case "$lang_lower" in
        javascript|typescript|java|cpp|c|go|rust)
            # Check for K&R vs Allman style (simplified check)
            local line_num=0
            local prev_line=""
            while IFS= read -r line || [[ -n "$line" ]]; do
                ((line_num++))

                # Check for opening brace on new line (Allman style)
                if [[ "$line" =~ ^[[:space:]]*\{[[:space:]]*$ ]]; then
                    if [[ "$prev_line" =~ (if|else|for|while|function|switch|try|catch|class)[[:space:]]*[\(\)]?[[:space:]]*$ ]]; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$((line_num - 1))" "0" "info" "style" "brace-style" \
                            "Opening brace on separate line (Allman style)" \
                            "Consider K&R style: place opening brace on same line")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi

                prev_line="$line"
            done < "$file"
            ;;
    esac

    echo "$issues"
}

# =============================================================================
# Comment Style Check
# =============================================================================

style_check_comments() {
    local file="$1"
    local lang="$2"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang_lower
    lang_lower=$(echo "$lang" | tr '[:upper:]' '[:lower:]')
    local total_lines
    total_lines=$(reviewer_count_lines "$file")
    local comment_lines
    comment_lines=$(reviewer_count_comment_lines "$file" "$lang_lower")

    # Check comment ratio
    if [[ $total_lines -gt 10 ]]; then
        local ratio
        ratio=$(awk "BEGIN {printf \"%.2f\", $comment_lines / $total_lines}")

        # Too few comments
        if (( $(echo "$ratio < 0.1" | bc -l 2>/dev/null || echo "0") )); then
            local issue
            issue=$(reviewer_create_issue "$file" "0" "0" "low" "style" "comments" \
                "Low comment ratio (${ratio}), consider adding more documentation" \
                "Aim for at least 10% comment ratio")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    fi

    # Check for TODO/FIXME comments
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        if echo "$line" | grep -qiE '(TODO|FIXME|XXX|HACK|BUG)'; then
            local tag
            tag=$(echo "$line" | grep -oiE '(TODO|FIXME|XXX|HACK|BUG)' | head -1)
            local issue
            issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "style" "comments" \
                "$tag comment found - technical debt indicator" \
                "Address or remove $tag comments")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# File-level Style Check
# =============================================================================

style_check_file() {
    local file="$1"
    local lang="${2:-auto}"
    local all_issues="[]"

    if [[ ! -f "$file" ]]; then
        reviewer_error "File not found: $file"
        echo "$all_issues"
        return
    fi

    # Auto-detect language if needed
    if [[ "$lang" == "auto" ]]; then
        lang=$(reviewer_detect_language "$file")
    fi

    reviewer_debug "Checking style for: $file (language: $lang)"

    # Run all style checks
    local issues

    issues=$(style_check_line_length "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(style_check_trailing_whitespace "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(style_check_naming_conventions "$file" "$lang")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(style_check_braces "$file" "$lang")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(style_check_comments "$file" "$lang")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    echo "$all_issues"
}

# =============================================================================
# Directory-level Style Check
# =============================================================================

style_check_directory() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"
    local output_format="${3:-json}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    local all_issues="[]"
    local file_count=0

    reviewer_info "Checking style in: $root_dir"

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        ((file_count++))

        local issues
        issues=$(style_check_file "$file")
        all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

        reviewer_debug "Processed: $file"
    done < <(reviewer_get_code_files "$root_dir" "$exclude_patterns")

    reviewer_info "Checked $file_count files"

    case "$output_format" in
        json)
            echo "$all_issues"
            ;;
        markdown)
            style_format_report_markdown "$all_issues" "$root_dir"
            ;;
        text)
            style_format_report_text "$all_issues" "$root_dir"
            ;;
        *)
            echo "$all_issues"
            ;;
    esac
}

# =============================================================================
# Report Formatting
# =============================================================================

style_format_report_markdown() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    cat <<EOF
# Style Check Report

**Directory:** $root_dir
**Generated:** $(reviewer_timestamp_human)
**Total Issues:** $issue_count

EOF

    if [[ $issue_count -eq 0 ]]; then
        echo "✅ No style issues found!"
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

style_format_report_text() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    echo "Style Check Report"
    echo "=================="
    echo "Directory: $root_dir"
    echo "Generated: $(reviewer_timestamp_human)"
    echo "Total Issues: $issue_count"
    echo ""

    if [[ $issue_count -eq 0 ]]; then
        echo "No style issues found!"
        return
    fi

    echo "$issues" | jq -r '.[] | "[\(.severity | ascii_upcase)] \(.file):\(.line) - \(.message)"'
}

# =============================================================================
# Quick Stats
# =============================================================================

style_quick_stats() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    local total_files=0
    local total_issues=0
    local files_with_issues=0

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        ((total_files++))

        local issues
        issues=$(style_check_file "$file")
        local issue_count
        issue_count=$(echo "$issues" | jq 'length')

        if [[ $issue_count -gt 0 ]]; then
            ((files_with_issues++))
            total_issues=$((total_issues + issue_count))
        fi
    done < <(reviewer_get_code_files "$root_dir" "$exclude_patterns")

    cat <<EOF
{
  "total_files": $total_files,
  "files_with_issues": $files_with_issues,
  "total_issues": $total_issues,
  "clean_files": $((total_files - files_with_issues)),
  "health_score": $(awk "BEGIN {printf \"%.1f\", ($total_files - $files_with_issues) / $total_files * 100}")
}
EOF
}
