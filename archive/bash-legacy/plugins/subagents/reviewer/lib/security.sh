#!/usr/bin/env bash
# Reviewer Subagent - Security Auditing
# Scans for security vulnerabilities, hardcoded secrets, and insecure patterns
# Integrates Security Auditor functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# Security Patterns
# =============================================================================

# SQL Injection patterns
SQL_INJECTION_PATTERNS=(
    'execute\s*\(\s*["\x27].*%s.*["\x27]'
    'execute\s*\(\s*["\x27].*\+.*["\x27]'
    'query\s*\(\s*["\x27].*\+.*["\x27]'
    'raw\s*\(\s*["\x27].*\+.*["\x27]'
    'executeQuery\s*\([^)]*\+[^)]*\)'
    'createStatement\s*\(\s*\).*execute.*\+'
    '\$\{.*\}.*SELECT|INSERT|UPDATE|DELETE'
    'f["\x27].*SELECT.*\{.*\}'
    '`.*SELECT.*\$\{.*\}'
)

# Command Injection patterns
COMMAND_INJECTION_PATTERNS=(
    'os\.system\s*\([^)]*\+[^)]*\)'
    'os\.popen\s*\([^)]*\+[^)]*\)'
    'subprocess\.call\s*\([^)]*shell\s*=\s*True'
    'subprocess\.run\s*\([^)]*shell\s*=\s*True[^)]*\+'
    'exec\s*\([^)]*\+[^)]*\)'
    'eval\s*\([^)]*\+[^)]*\)'
    '`[^`]*\$[^`]*`'
    '\$\([^)]*\+[^)]*\)'
    'Runtime\.getRuntime.*exec'
)

# XSS patterns
XSS_PATTERNS=(
    'innerHTML\s*='
    'document\.write\s*\('
    '\.html\s*\([^)]*\+[^)]*\)'
    'dangerouslySetInnerHTML'
    'v-html\s*='
    'ng-bind-html\s*='
    '\$\s*\(\s*["\x27]<.*\+.*["\x27]'
)

# Hardcoded secrets patterns
SECRET_PATTERNS=(
    'password\s*[=:]\s*["\x27][^"\x27]+["\x27]'
    'passwd\s*[=:]\s*["\x27][^"\x27]+["\x27]'
    'secret\s*[=:]\s*["\x27][^"\x27]+["\x27]'
    'api_key\s*[=:]\s*["\x27][^"\x27]+["\x27]'
    'apikey\s*[=:]\s*["\x27][^"\x27]+["\x27]'
    'token\s*[=:]\s*["\x27][A-Za-z0-9+/=]{20,}["\x27]'
    'AWS_SECRET_ACCESS_KEY\s*[=:]\s*["\x27]'
    'PRIVATE_KEY\s*[=:]\s*["\x27]'
    '-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----'
    'AKIA[0-9A-Z]{16}'
    'ghp_[A-Za-z0-9]{36}'
    'xox[baprs]-[0-9]{10,13}-[0-9]{10,13}-[a-zA-Z0-9]{24}'
)

# Insecure crypto patterns
INSECURE_CRYPTO_PATTERNS=(
    'MD5\s*\('
    'SHA1\s*\('
    'md5\s*\('
    'sha1\s*\('
    'hashlib\.md5'
    'hashlib\.sha1'
    'Crypto\.MD5'
    'Crypto\.SHA1'
    'DES\s*\.new'
    'RC4'
    'Blowfish'
    'eval\s*\(\s*["\x27]require.*crypto'
)

# Path traversal patterns
PATH_TRAVERSAL_PATTERNS=(
    '\.\./\.\.'
    '\.\.\\'
    'open\s*\([^)]*\+[^)]*\)'
    'file_get_contents\s*\([^)]*\+[^)]*\)'
    'readFile\s*\([^)]*\+[^)]*\)'
    'readFileSync\s*\([^)]*\+[^)]*\)'
    'Path\s*\.join\s*\([^)]*request'
)

# =============================================================================
# SQL Injection Check
# =============================================================================

security_check_sql_injection() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")

    # Only check relevant languages
    case "$lang" in
        python|javascript|typescript|java|php|ruby|go)
            ;;
        *)
            echo "$issues"
            return
            ;;
    esac

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        for pattern in "${SQL_INJECTION_PATTERNS[@]}"; do
            if echo "$line" | grep -qiE "$pattern" 2>/dev/null; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "critical" "security" "sql-injection" \
                    "Potential SQL injection vulnerability detected" \
                    "Use parameterized queries or prepared statements")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                break
            fi
        done
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Command Injection Check
# =============================================================================

security_check_command_injection() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        for pattern in "${COMMAND_INJECTION_PATTERNS[@]}"; do
            if echo "$line" | grep -qiE "$pattern" 2>/dev/null; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "critical" "security" "command-injection" \
                    "Potential command injection vulnerability detected" \
                    "Avoid executing shell commands with user input. Use safe APIs instead.")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                break
            fi
        done
    done < "$file"

    echo "$issues"
}

# =============================================================================
# XSS Check
# =============================================================================

security_check_xss() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local lang
    lang=$(reviewer_detect_language "$file")

    # Only check relevant languages
    case "$lang" in
        javascript|typescript|html|vue)
            ;;
        *)
            echo "$issues"
            return
            ;;
    esac

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        for pattern in "${XSS_PATTERNS[@]}"; do
            if echo "$line" | grep -qiE "$pattern" 2>/dev/null; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "security" "xss" \
                    "Potential XSS vulnerability detected" \
                    "Sanitize user input before rendering. Use safe DOM APIs.")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                break
            fi
        done
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Hardcoded Secrets Check
# =============================================================================

security_check_hardcoded_secrets() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    # Skip sensitive files that are expected to contain secrets
    if reviewer_is_sensitive_file "$file"; then
        reviewer_debug "Skipping sensitive file: $file"
        echo "$issues"
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        for pattern in "${SECRET_PATTERNS[@]}"; do
            if echo "$line" | grep -qiE "$pattern" 2>/dev/null; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "critical" "security" "hardcoded-secrets" \
                    "Potential hardcoded secret detected" \
                    "Use environment variables or secure secret management")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                break
            fi
        done
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Insecure Cryptography Check
# =============================================================================

security_check_insecure_crypto() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        for pattern in "${INSECURE_CRYPTO_PATTERNS[@]}"; do
            if echo "$line" | grep -qiE "$pattern" 2>/dev/null; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "security" "insecure-crypto" \
                    "Use of insecure cryptographic algorithm detected" \
                    "Use modern algorithms like SHA-256, AES-256, or Argon2")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                break
            fi
        done
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Path Traversal Check
# =============================================================================

security_check_path_traversal() {
    local file="$1"
    local issues="[]"

    if [[ ! -f "$file" ]]; then
        echo "$issues"
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))

        for pattern in "${PATH_TRAVERSAL_PATTERNS[@]}"; do
            if echo "$line" | grep -qiE "$pattern" 2>/dev/null; then
                local issue
                issue=$(reviewer_create_issue "$file" "$line_num" "0" "high" "security" "path-traversal" \
                    "Potential path traversal vulnerability detected" \
                    "Validate and sanitize file paths. Use allowlists for permitted paths.")
                issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                break
            fi
        done
    done < "$file"

    echo "$issues"
}

# =============================================================================
# Sensitive File Check
# =============================================================================

security_check_sensitive_files() {
    local root_dir="$1"
    local issues="[]"

    root_dir=$(reviewer_validate_dir "$root_dir")

    # Check for sensitive files that shouldn't be in the repository
    local sensitive_patterns=(
        "*.pem" "*.key" "*.p12" "*.pfx"
        ".env" ".env.*" "*.env"
        "*secret*" "*password*" "*credential*"
        "id_rsa" "id_dsa" "id_ecdsa" "id_ed25519"
        ".aws/credentials" ".ssh/*"
        "*.keystore" "*.jks"
    )

    for pattern in "${sensitive_patterns[@]}"; do
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue

            # Skip if it's in a proper secrets directory
            if [[ "$file" == *"/secrets/"* ]] || [[ "$file" == *"/.vault/"* ]]; then
                continue
            fi

            local issue
            issue=$(reviewer_create_issue "$file" "0" "0" "high" "security" "sensitive-file" \
                "Sensitive file detected in repository: $file" \
                "Remove sensitive files from version control. Use .gitignore and secret management.")
            issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
        done < <(find "$root_dir" -name "$pattern" -type f 2>/dev/null || true)
    done

    echo "$issues"
}

# =============================================================================
# Dependency Security Check (Basic)
# =============================================================================

security_check_dependencies() {
    local root_dir="$1"
    local issues="[]"

    root_dir=$(reviewer_validate_dir "$root_dir")

    # Check package.json for known vulnerable patterns
    if [[ -f "$root_dir/package.json" ]]; then
        local deps
        deps=$(jq -r '.dependencies // {} | keys[]' "$root_dir/package.json" 2>/dev/null || true)

        while IFS= read -r dep; do
            [[ -z "$dep" ]] && continue

            # Check for known problematic packages
            case "$dep" in
                event-stream|flatmap-stream|ua-parser-js|node-ipc)
                    local issue
                    issue=$(reviewer_create_issue "$root_dir/package.json" "0" "0" "critical" "security" "vulnerable-dependency" \
                        "Dependency '$dep' has known security issues" \
                        "Update to a secure version or remove this dependency")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    ;;
            esac
        done <<< "$deps"
    fi

    # Check requirements.txt for known vulnerable patterns
    if [[ -f "$root_dir/requirements.txt" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" == \#* ]] && continue

            local pkg
            pkg=$(echo "$line" | sed 's/[<>=].*//' | tr -d '[:space:]')

            case "$pkg" in
                pyyaml|Pillow|requests|urllib3|django|flask)
                    # Check if version is pinned
                    if ! echo "$line" | grep -qE '[<>=]{1,2}[0-9]'; then
                        local issue
                        issue=$(reviewer_create_issue "$root_dir/requirements.txt" "0" "0" "medium" "security" "unpinned-dependency" \
                            "Dependency '$pkg' version not pinned" \
                            "Pin dependency versions for reproducible builds")
                        issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                    fi
                    ;;
            esac
        done < "$root_dir/requirements.txt"
    fi

    echo "$issues"
}

# =============================================================================
# Security Headers Check (for web projects)
# =============================================================================

security_check_headers() {
    local root_dir="$1"
    local issues="[]"

    root_dir=$(reviewer_validate_dir "$root_dir")

    # Check for security headers in common config files
    local config_files=(
        "nginx.conf"
        ".htaccess"
        "web.config"
        "server.js"
        "app.js"
        "middleware.js"
    )

    local found_config=false
    for config in "${config_files[@]}"; do
        if [[ -f "$root_dir/$config" ]]; then
            found_config=true
            local content
            content=$(cat "$root_dir/$config")

            # Check for missing security headers
            local headers=("X-Frame-Options" "X-Content-Type-Options" "X-XSS-Protection" "Content-Security-Policy" "Strict-Transport-Security")

            for header in "${headers[@]}"; do
                if ! echo "$content" | grep -qi "$header"; then
                    local issue
                    issue=$(reviewer_create_issue "$root_dir/$config" "0" "0" "medium" "security" "missing-security-header" \
                        "Missing security header: $header" \
                        "Add $header to improve security posture")
                    issues=$(echo "$issues" | jq --argjson issue "$issue" '. + [$issue]')
                fi
            done
        fi
    done

    echo "$issues"
}

# =============================================================================
# File-level Security Check
# =============================================================================

security_audit_file() {
    local file="$1"
    local all_issues="[]"

    if [[ ! -f "$file" ]]; then
        reviewer_error "File not found: $file"
        echo "$all_issues"
        return
    fi

    reviewer_debug "Auditing security for: $file"

    local issues

    issues=$(security_check_sql_injection "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(security_check_command_injection "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(security_check_xss "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(security_check_hardcoded_secrets "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(security_check_insecure_crypto "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    issues=$(security_check_path_traversal "$file")
    all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

    echo "$all_issues"
}

# =============================================================================
# Directory-level Security Audit
# =============================================================================

security_audit_directory() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"
    local output_format="${3:-json}"
    local include_sensitive="${4:-true}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    local all_issues="[]"
    local file_count=0

    reviewer_info "Security auditing: $root_dir"

    # Check sensitive files
    if [[ "$include_sensitive" == "true" ]]; then
        local sensitive_issues
        sensitive_issues=$(security_check_sensitive_files "$root_dir")
        all_issues=$(echo "$all_issues" "$sensitive_issues" | jq -s '.[0] + .[1]')
    fi

    # Check dependencies
    local dep_issues
    dep_issues=$(security_check_dependencies "$root_dir")
    all_issues=$(echo "$all_issues" "$dep_issues" | jq -s '.[0] + .[1]')

    # Check security headers
    local header_issues
    header_issues=$(security_check_headers "$root_dir")
    all_issues=$(echo "$all_issues" "$header_issues" | jq -s '.[0] + .[1]')

    # Check each code file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        ((file_count++))

        local issues
        issues=$(security_audit_file "$file")
        all_issues=$(echo "$all_issues" "$issues" | jq -s '.[0] + .[1]')

        reviewer_debug "Audited: $file"
    done < <(reviewer_get_code_files "$root_dir" "$exclude_patterns")

    reviewer_info "Audited $file_count files"

    case "$output_format" in
        json)
            echo "$all_issues"
            ;;
        markdown)
            security_format_report_markdown "$all_issues" "$root_dir"
            ;;
        text)
            security_format_report_text "$all_issues" "$root_dir"
            ;;
        *)
            echo "$all_issues"
            ;;
    esac
}

# =============================================================================
# Report Formatting
# =============================================================================

security_format_report_markdown() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    # Count by severity
    local critical_count high_count medium_count low_count
    critical_count=$(echo "$issues" | jq '[.[] | select(.severity == "critical")] | length')
    high_count=$(echo "$issues" | jq '[.[] | select(.severity == "high")] | length')
    medium_count=$(echo "$issues" | jq '[.[] | select(.severity == "medium")] | length')
    low_count=$(echo "$issues" | jq '[.[] | select(.severity == "low")] | length')

    cat <<EOF
# Security Audit Report

**Directory:** $root_dir
**Generated:** $(reviewer_timestamp_human)
**Total Issues:** $issue_count

## Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | $critical_count |
| 🟠 High | $high_count |
| 🟡 Medium | $medium_count |
| 🔵 Low | $low_count |

EOF

    if [[ $issue_count -eq 0 ]]; then
        echo "✅ No security issues found!"
        return
    fi

    # Group by severity
    for severity in critical high medium low; do
        local sev_issues
        sev_issues=$(echo "$issues" | jq --arg sev "$severity" '[.[] | select(.severity == $sev)]')
        local sev_count
        sev_count=$(echo "$sev_issues" | jq 'length')

        if [[ $sev_count -gt 0 ]]; then
            echo "## $(reviewer_severity_emoji "$severity") ${severity^} ($sev_count)"
            echo ""
            echo "$sev_issues" | jq -r '.[] | "- **\(.file):\(.line)**: \(.message)\n  - Rule: `\(.rule)`\n  - Suggestion: \(.suggestion)"'
            echo ""
        fi
    done

    # Add remediation section
    cat <<EOF
## Remediation Recommendations

1. **Critical Issues**: Address immediately - these represent active security risks
2. **High Issues**: Fix within 24-48 hours
3. **Medium Issues**: Schedule for next sprint
4. **Low Issues**: Address during regular maintenance

## Security Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CWE/SANS Top 25](https://cwe.mitre.org/top25/)
- [GitHub Security Advisories](https://github.com/advisories)
EOF
}

security_format_report_text() {
    local issues="$1"
    local root_dir="${2:-.}"

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    echo "Security Audit Report"
    echo "====================="
    echo "Directory: $root_dir"
    echo "Generated: $(reviewer_timestamp_human)"
    echo "Total Issues: $issue_count"
    echo ""

    if [[ $issue_count -eq 0 ]]; then
        echo "No security issues found!"
        return
    fi

    echo "$issues" | jq -r '.[] | "[\(.severity | ascii_upcase)] \(.file):\(.line) - \(.message)"'
}

# =============================================================================
# Security Score Calculation
# =============================================================================

security_calculate_score() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"

    local issues
    issues=$(security_audit_directory "$root_dir" "$exclude_patterns" "json")

    local total critical high medium low score
    total=$(echo "$issues" | jq 'length')
    critical=$(echo "$issues" | jq '[.[] | select(.severity == "critical")] | length')
    high=$(echo "$issues" | jq '[.[] | select(.severity == "high")] | length')
    medium=$(echo "$issues" | jq '[.[] | select(.severity == "medium")] | length')
    low=$(echo "$issues" | jq '[.[] | select(.severity == "low")] | length')

    # Calculate score (100 - weighted deductions)
    # Critical: -25, High: -10, Medium: -5, Low: -1
    local deductions
    deductions=$((critical * 25 + high * 10 + medium * 5 + low * 1))
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

# =============================================================================
# Security Auditor Integration (Main Entry Point)
# =============================================================================

security_auditor_run() {
    local root_dir="${1:-.}"
    local options="${2:-{}}"

    local exclude_patterns output_format include_sensitive

    exclude_patterns=$(echo "$options" | jq -r '.excludePatterns // "$(reviewer_get_default_excludes)"')
    output_format=$(echo "$options" | jq -r '.outputFormat // "json"')
    include_sensitive=$(echo "$options" | jq -r '.includeSensitive // true')

    security_audit_directory "$root_dir" "$exclude_patterns" "$output_format" "$include_sensitive"
}
