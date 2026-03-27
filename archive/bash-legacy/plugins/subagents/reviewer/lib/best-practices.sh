#!/usr/bin/env bash
# Reviewer Subagent - Best Practices Validation
# Checks for coding best practices, error handling, documentation, and code quality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# Error Handling Check
# =============================================================================

best_practices_check_error_handling() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")

    local line_num=0
    local has_try=false
    local has_catch=false
    local try_line=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        case "$lang" in
            javascript|typescript)
                # Check for try-catch blocks
                if echo "$line" | grep -qE 'try\s*\{'; then
                    has_try=true
                    try_line=$line_num
                fi

                if [[ "$has_try" == true ]]; then
                    if echo "$line" | grep -qE 'catch\s*\(|catch\s*\('; then
                        has_catch=true
                    fi

                    # Check for empty catch blocks
                    if echo "$line" | grep -qE 'catch\s*\([^)]*\)\s*\{\s*\}'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "best-practices" "error-handling" \
                            "Empty catch block. Errors should be handled or logged." \
                            "Log the error, rethrow, or handle appropriately")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi

                    # Check for catch without error parameter
                    if echo "$line" | grep -qE 'catch\s*\(\s*\)'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "best-practices" "error-handling" \
                            "Catch block without error parameter. Consider capturing error details." \
                            "Use catch (error) to access error information")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi

                # Check for unhandled promises
                if echo "$line" | grep -qE '\.then\s*\(' && ! echo "$line" | grep -qE '\.catch\s*\('; then
                    # Check next few lines for .catch
                    local next_lines
                    next_lines=$(sed -n "$((line_num + 1)),$((line_num + 5))p" "$file" 2>/dev/null)
                    if ! echo "$next_lines" | grep -qE '\.catch\s*\('; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "best-practices" "error-handling" \
                            "Promise without .catch() handler. Unhandled rejections may occur." \
                            "Add .catch() handler or use try-catch with await")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi

                # Reset at block end (simplified)
                if echo "$line" | grep -qE '^\s*\}\s*$' && [[ "$has_try" == true ]]; then
                    if [[ "$has_catch" == false ]]; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$try_line" "0" "medium" "best-practices" "error-handling" \
                            "Try block without catch. Ensure errors are handled." \
                            "Add catch block or use try-catch-finally")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                    has_try=false
                    has_catch=false
                fi
                ;;

            python)
                # Check for try-except blocks
                if echo "$line" | grep -qE '^\s*try\s*:'; then
                    has_try=true
                    try_line=$line_num
                fi

                if [[ "$has_try" == true ]]; then
                    if echo "$line" | grep -qE '^\s*except'; then
                        has_catch=true
                    fi

                    # Check for bare except
                    if echo "$line" | grep -qE '^\s*except\s*:'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "best-practices" "error-handling" \
                            "Bare except clause. Catch specific exceptions instead." \
                            "Use 'except SpecificError:' to catch specific exceptions")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi

                    # Check for except with pass
                    if echo "$line" | grep -qE '^\s*except[^:]*:\s*pass'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "best-practices" "error-handling" \
                            "Empty except block with pass. Errors should be handled or logged." \
                            "Log the error, rethrow, or handle appropriately")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi

                # Reset at function end (simplified)
                if echo "$line" | grep -qE '^\s*except' && [[ "$has_try" == true ]]; then
                    has_try=false
                    has_catch=false
                fi
                ;;

            java)
                # Check for try-catch blocks
                if echo "$line" | grep -qE 'try\s*\{'; then
                    has_try=true
                    try_line=$line_num
                fi

                if [[ "$has_try" == true ]]; then
                    if echo "$line" | grep -qE 'catch\s*\('; then
                        has_catch=true
                    fi

                    # Check for empty catch
                    if echo "$line" | grep -qE 'catch\s*\([^)]*\)\s*\{\s*\}'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "medium" "best-practices" "error-handling" \
                            "Empty catch block. Errors should be handled or logged." \
                            "Log the error, rethrow, or handle appropriately")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi

                    # Check for catch Exception (too broad)
                    if echo "$line" | grep -qE 'catch\s*\(\s*Exception\s+'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "low" "best-practices" "error-handling" \
                            "Catching generic Exception. Catch specific exceptions instead." \
                            "Catch specific exception types for better error handling")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi
                ;;
        esac
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Logging Check
# =============================================================================

best_practices_check_logging() {
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

    # Check for console.log in production code
    case "$lang" in
        javascript|typescript)
            local console_count
            console_count=$(echo "$content" | grep -c 'console\.log' 2>/dev/null || echo "0")
            console_count=$(echo "$console_count" | tr -d '[:space:]')
            console_count=${console_count:-0}

            if [[ "$console_count" -gt 5 ]]; then
                local first_log_line
                first_log_line=$(grep -n 'console\.log' "$file" 2>/dev/null | head -1 | cut -d: -f1)

                if [[ -n "$first_log_line" ]]; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$first_log_line" "0" "low" "best-practices" "logging" \
                        "Multiple console.log statements ($console_count found). Use proper logging framework." \
                        "Use a logging library like winston, pino, or log4js")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
            fi
            ;;

        python)
            local print_count
            print_count=$(echo "$content" | grep -cE '^\s*print\s*\(' 2>/dev/null || echo "0")
            print_count=$(echo "$print_count" | tr -d '[:space:]')
            print_count=${print_count:-0}

            if [[ "$print_count" -gt 5 ]]; then
                local first_print_line
                first_print_line=$(grep -nE '^\s*print\s*\(' "$file" 2>/dev/null | head -1 | cut -d: -f1)

                if [[ -n "$first_print_line" ]]; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$first_print_line" "0" "low" "best-practices" "logging" \
                        "Multiple print statements ($print_count found). Use logging module instead." \
                        "Use Python's logging module for proper log levels and formatting")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
            fi
            ;;
    esac

    # Check for logging without levels
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        case "$lang" in
            javascript|typescript)
                if echo "$line" | grep -qE 'console\.(log|error|warn|info|debug)'; then
                    # Check if it's in a catch block without error info
                    if echo "$line" | grep -qE 'console\.(log|error)\s*\(\s*["\x27][^"\x27]*["\x27]\s*\)'; then
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "best-practices" "logging" \
                            "Console log without error context. Include error details in logs." \
                            "Log the error object: console.error('Message:', error)")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi
                ;;
        esac
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Documentation Check
# =============================================================================

best_practices_check_documentation() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")
    local total_lines
    total_lines=$(reviewer_count_lines "$file")
    local comment_lines
    comment_lines=$(reviewer_count_comment_lines "$file" "$lang")

    # Check for missing file header documentation
    local first_non_empty_line
    first_non_empty_line=$(grep -n -m1 '[^[:space:]]' "$file" 2>/dev/null | cut -d: -f1)

    if [[ -n "$first_non_empty_line" ]]; then
        local first_content
        first_content=$(sed -n "${first_non_empty_line}p" "$file")

        case "$lang" in
            javascript|typescript)
                if ! echo "$first_content" | grep -qE '^\s*(//|/\*|import|export|from|require)'; then
                    :  # Has comment or import
                elif ! echo "$first_content" | grep -qE '^\s*(//|/\*)'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "1" "0" "info" "best-practices" "documentation" \
                        "Missing file header documentation. Add JSDoc or comment describing module purpose." \
                        "Add a comment block at the top describing the module's purpose")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;

            python)
                if ! echo "$first_content" | grep -qE '^\s*(#|\"\"\"|import|from)'; then
                    :  # Has comment or docstring or import
                elif ! echo "$first_content" | grep -qE '^\s*(#|\"\"\")'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "1" "0" "info" "best-practices" "documentation" \
                        "Missing module docstring. Add documentation describing module purpose." \
                        "Add a docstring at the top describing the module's purpose")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;
        esac
    fi

    # Check for undocumented functions
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        case "$lang" in
            javascript|typescript)
                # Check for function without JSDoc
                if echo "$line" | grep -qE '^(export\s+)?(async\s+)?function\s+\w+|^\s*(const|let|var)\s+\w+\s*=\s*(async\s+)?\([^)]*\)\s*=>'; then
                    # Check previous line for JSDoc
                    local prev_line
                    prev_line=$(sed -n "$((line_num - 1))p" "$file" 2>/dev/null)
                    if ! echo "$prev_line" | grep -qE '\*/'; then
                        local func_name
                        func_name=$(echo "$line" | grep -oE 'function\s+\w+|\w+\s*=' | head -1 | sed 's/function\s*//' | sed 's/\s*=//')
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "best-practices" "documentation" \
                            "Function '$func_name' lacks JSDoc documentation." \
                            "Add JSDoc comment with @param, @returns, and description")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi
                ;;

            python)
                # Check for function without docstring
                if echo "$line" | grep -qE '^\s*def\s+\w+'; then
                    # Check next line for docstring
                    local next_line
                    next_line=$(sed -n "$((line_num + 1))p" "$file" 2>/dev/null)
                    if ! echo "$next_line" | grep -qE '^\s*("""|\x27\x27\x27)'; then
                        local func_name
                        func_name=$(echo "$line" | grep -oE 'def\s+\w+' | awk '{print $2}')
                        local issue
                        issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "best-practices" "documentation" \
                            "Function '$func_name' lacks docstring." \
                            "Add a docstring describing parameters, return value, and purpose")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                fi
                ;;
        esac
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Code Duplication Check
# =============================================================================

best_practices_check_code_duplication() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local content
    content=$(cat "$file")

    # Simple duplication detection: look for repeated code blocks
    # This is a simplified version - real duplication detection is more complex

    local line_count
    line_count=$(reviewer_count_lines "$file")

    if [[ $line_count -lt 20 ]]; then
        echo "$issues"
        return
    fi

    # Check for repeated patterns (simplified)
    local patterns
    patterns=$(echo "$content" | grep -v '^\s*$' | grep -v '^\s*//' | grep -v '^\s*#' | sort | uniq -c | sort -rn | head -10)

    while IFS= read -r pattern_info; do
        [[ -z "$pattern_info" ]] && continue

        local count pattern
        count=$(echo "$pattern_info" | awk '{print $1}')
        pattern=$(echo "$pattern_info" | cut -d' ' -f2-)

        # Skip very short patterns
        [[ ${#pattern} -lt 30 ]] && continue

        if [[ $count -ge 5 ]]; then
            local first_occurrence
            first_occurrence=$(grep -n -F "$pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)

            if [[ -n "$first_occurrence" ]]; then
                local issue
                issue=$(reviewer_create_issue "$file" "$first_occurrence" "0" "medium" "best-practices" "code-duplication" \
                    "Code pattern repeated $count times. Consider extracting to function." \
                    "Extract repeated code into a reusable function or module")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi
        fi
    done <<< "$patterns"

    echo "$issues"
}

# =============================================================================
# Magic Numbers Check
# =============================================================================

best_practices_check_magic_numbers() {
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

        # Skip comments and string literals
        [[ "$line" =~ ^[[:space:]]*(//|#) ]] && continue

        # Look for magic numbers (excluding 0, 1, 2, -1)
        local numbers
        numbers=$(echo "$line" | grep -oE '\b[0-9]+\b' 2>/dev/null || true)

        for num in $numbers; do
            case "$num" in
                0|1|2|-1|100|1000)
                    continue
                    ;;
                *)
                    # Check if it's in a meaningful context
                    if echo "$line" | grep -qE "=\s*$num|==\s*$num|!=\s*$num|>\s*$num|<\s*$num|>=\s*$num|<=\s*$num"; then
                        # Check if it's already in a constant
                        if ! echo "$line" | grep -qiE '(const|CONST|FINAL|readonly|enum)'; then
                            local issue
                            issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "best-practices" "magic-numbers" \
                                "Magic number $num found. Consider using a named constant." \
                                "Extract to a named constant with descriptive name")
                            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                            break  # Only report once per line
                        fi
                    fi
                    ;;
            esac
        done
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Dead Code Check
# =============================================================================

best_practices_check_dead_code() {
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

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        case "$lang" in
            javascript|typescript)
                # Check for commented-out code that looks like imports
                if echo "$line" | grep -qE '^\s*//\s*(import|require|const|let|var|function|class)\s'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "best-practices" "dead-code" \
                        "Commented-out code detected. Remove dead code or document why it's kept." \
                        "Remove unused code or add explanation comment if needed for reference")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi

                # Check for TODO without issue reference
                if echo "$line" | grep -qiE '//\s*TODO\s*:' && ! echo "$line" | grep -qiE '#[0-9]+|JIRA|GH-'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "best-practices" "dead-code" \
                        "TODO without issue reference. Link to tracking system." \
                        "Add issue/ticket reference: TODO (#123): description")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;

            python)
                # Check for commented-out imports
                if echo "$line" | grep -qE '^\s*#\s*(import|from)\s'; then
                    local issue
                    issue=$(reviewer_create_issue "$file" "$line_num" "0" "info" "best-practices" "dead-code" \
                        "Commented-out import detected. Remove dead code." \
                        "Remove unused imports")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
                ;;
        esac

        # Check for unreachable code after return/throw
        if echo "$line" | grep -qE '^\s*(return|throw|break|continue)\s*[;}]?\s*$'; then
            local next_line
            next_line=$(sed -n "$((line_num + 1))p" "$file" 2>/dev/null)

            # Check if next line is code (not closing brace or comment)
            if [[ -n "$next_line" ]] && ! echo "$next_line" | grep -qE '^\s*(\}|//|#|\*|$)'; then
                local issue
                issue=$(reviewer_create_issue "$file" "$((line_num + 1))" "0" "medium" "best-practices" "dead-code" \
                    "Potentially unreachable code after $(echo "$line" | grep -oE '(return|throw|break|continue)' | head -1)." \
                    "Remove or refactor unreachable code")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
            fi
        fi
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Function Length Check
# =============================================================================

best_practices_check_function_length() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")
    local max_function_lines="${OML_REVIEWER_MAX_FUNCTION_LINES:-50}"

    local line_num=0
    local in_function=false
    local function_start=0
    local function_name=""
    local brace_count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        case "$lang" in
            javascript|typescript|java|cpp|c|go)
                # Detect function start
                if echo "$line" | grep -qE 'function\s+\w+|\w+\s*\([^)]*\)\s*\{|async\s+\w+\s*\('; then
                    in_function=true
                    function_start=$line_num
                    function_name=$(echo "$line" | grep -oE 'function\s+\w+|\w+\s*=' | head -1 | sed 's/function\s*//' | sed 's/\s*=//')
                    brace_count=0
                fi

                if [[ "$in_function" == true ]]; then
                    # Count braces
                    local open_braces close_braces
                    open_braces=$(echo "$line" | grep -o '{' | wc -l)
                    close_braces=$(echo "$line" | grep -o '}' | wc -l)
                    brace_count=$((brace_count + open_braces - close_braces))

                    # Function ended
                    if [[ $brace_count -le 0 ]] && [[ $open_braces -gt 0 || $line_num -gt $function_start ]]; then
                        local func_length=$((line_num - function_start))

                        if [[ $func_length -gt $max_function_lines ]]; then
                            local issue
                            issue=$(reviewer_create_issue "$file" "$function_start" "0" "medium" "best-practices" "function-length" \
                                "Function '$function_name' is too long ($func_length lines). Max recommended: $max_function_lines." \
                                "Break into smaller, focused functions")
                            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                        fi

                        in_function=false
                    fi
                fi
                ;;

            python)
                # Detect function start
                if echo "$line" | grep -qE '^\s*def\s+\w+'; then
                    # Check previous function length
                    if [[ "$in_function" == true ]]; then
                        local func_length=$((line_num - function_start))

                        if [[ $func_length -gt $max_function_lines ]]; then
                            local issue
                            issue=$(reviewer_create_issue "$file" "$function_start" "0" "medium" "best-practices" "function-length" \
                                "Function '$function_name' is too long ($func_length lines). Max recommended: $max_function_lines." \
                                "Break into smaller, focused functions")
                            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                        fi
                    fi

                    in_function=true
                    function_start=$line_num
                    function_name=$(echo "$line" | grep -oE 'def\s+\w+' | awk '{print $2}')
                fi
                ;;
        esac
    done < "$file"

    # Check last function
    if [[ "$in_function" == true ]]; then
        local func_length=$((line_num - function_start))

        if [[ $func_length -gt $max_function_lines ]]; then
            local issue
            issue=$(reviewer_create_issue "$file" "$function_start" "0" "medium" "best-practices" "function-length" \
                "Function '$function_name' is too long ($func_length lines). Max recommended: $max_function_lines." \
                "Break into smaller, focused functions")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        fi
    fi

    echo "$issues"
}

# =============================================================================
# File-level Best Practices Check
# =============================================================================

best_practices_check_file() {
    local file="$1"
    local all_issues="[]"

    if [[ ! -f "$file" ]]; then
        reviewer_error "File not found: $file"
        echo "$all_issues"
        return
    fi

    reviewer_debug "Checking best practices for: $file"

    local issues

    issues=$(best_practices_check_error_handling "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(best_practices_check_logging "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(best_practices_check_documentation "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(best_practices_check_code_duplication "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(best_practices_check_magic_numbers "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(best_practices_check_dead_code "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(best_practices_check_function_length "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    echo "$all_issues"
}

# =============================================================================
# Directory-level Best Practices Check
# =============================================================================

best_practices_check_directory() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"
    local output_format="${3:-json}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    local all_issues="[]"
    local file_count=0

    reviewer_info "Checking best practices in: $root_dir"

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        ((file_count++))

        local issues
        issues=$(best_practices_check_file "$file")
        all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

        reviewer_debug "Checked: $file"
    done < <(reviewer_get_code_files "$root_dir" "$exclude_patterns")

    reviewer_info "Checked $file_count files"

    case "$output_format" in
        json)
            echo "$all_issues"
            ;;
        markdown)
            best_practices_format_report_markdown "$all_issues" "$root_dir"
            ;;
        text)
            best_practices_format_report_text "$all_issues" "$root_dir"
            ;;
        *)
            echo "$all_issues"
            ;;
    esac
}

# =============================================================================
# Report Formatting
# =============================================================================

best_practices_format_report_markdown() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    cat <<EOF
# Best Practices Report

**Directory:** $root_dir
**Generated:** $(reviewer_timestamp_human)
**Total Issues:** $issue_count

EOF

    if [[ $issue_count -eq 0 ]]; then
        echo "✅ No best practices violations found!"
        return
    fi

    # Group by category
    for category in error-handling logging documentation code-duplication magic-numbers dead-code function-length; do
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

    # Add best practices tips
    cat <<EOF
## Best Practices Tips

1. **Error Handling**: Always handle errors explicitly, never silently ignore them
2. **Logging**: Use appropriate log levels and include context in log messages
3. **Documentation**: Document public APIs, complex logic, and non-obvious decisions
4. **Code Reuse**: Extract repeated code into reusable functions
5. **Constants**: Use named constants instead of magic numbers
6. **Function Size**: Keep functions small and focused (single responsibility)
7. **Dead Code**: Remove unused code; version control preserves history

## Resources

- [Clean Code by Robert C. Martin](https://www.amazon.com/Clean-Code-Handbook-Software-Craftsmanship/dp/0132350882)
- [The Pragmatic Programmer](https://pragprog.com/titles/tpp20/the-pragmatic-programmer-20th-anniversary-edition/)
- [Google Style Guides](https://google.github.io/styleguide/)
EOF
}

best_practices_format_report_text() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    echo "Best Practices Report"
    echo "====================="
    echo "Directory: $root_dir"
    echo "Generated: $(reviewer_timestamp_human)"
    echo "Total Issues: $issue_count"
    echo ""

    if [[ $issue_count -eq 0 ]]; then
        echo "No best practices violations found!"
        return
    fi

    echo "$issues" | jq -r '.[] | "[\(.severity | ascii_upcase)] \(.file):\(.line) - \(.message)"'
}

# =============================================================================
# Best Practices Score Calculation
# =============================================================================

best_practices_calculate_score() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"

    local issues
    issues=$(best_practices_check_directory "$root_dir" "$exclude_patterns" "json")

    local total critical high medium low score
    total=$(echo "$issues" | jq 'length')
    critical=$(echo "$issues" | jq '[.[] | select(.severity == "critical")] | length')
    high=$(echo "$issues" | jq '[.[] | select(.severity == "high")] | length')
    medium=$(echo "$issues" | jq '[.[] | select(.severity == "medium")] | length')
    low=$(echo "$issues" | jq '[.[] | select(.severity == "low")] | length')

    # Calculate score (100 - weighted deductions)
    local deductions
    deductions=$((critical * 15 + high * 8 + medium * 4 + low * 1))
    score=$((100 - deductions))
    [[ $score -lt 0 ]] && score=0

    cat <<EOF
{
  "score": $score,
  "grade": "$(security_score_to_grade $score)",
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

# Helper function (copy from security.sh)
security_score_to_grade() {
    local score=$1

    if [[ $score -ge 90 ]]; then
        echo "A"
    elif [[ $score -ge 80 ]]; then
        echo "B"
    elif [[ $score -ge 70 ]]; then
        echo "C"
    elif [[ $score -ge 60 ]]; then
        echo "D"
    else
        echo "F"
    fi
}
