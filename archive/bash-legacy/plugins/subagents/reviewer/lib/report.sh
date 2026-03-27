#!/usr/bin/env bash
# Reviewer Subagent - Report Generation
# Generates structured review reports in multiple formats

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# =============================================================================
# Report Data Structure
# =============================================================================

report_create() {
    local root_dir="$1"
    local report_type="${2:-comprehensive}"

    cat <<EOF
{
  "report_type": "$report_type",
  "generated_at": "$(reviewer_timestamp)",
  "generated_at_human": "$(reviewer_timestamp_human)",
  "directory": "$(reviewer_json_escape "$root_dir")",
  "platform": "$(reviewer_detect_platform)",
  "summary": {
    "total_issues": 0,
    "by_category": {},
    "by_severity": {},
    "files_analyzed": 0,
    "total_lines": 0
  },
  "scores": {
    "overall": 100,
    "security": 100,
    "style": 100,
    "performance": 100,
    "best_practices": 100
  },
  "issues": [],
  "recommendations": [],
  "metadata": {
    "reviewer_version": "0.1.0",
    "execution_time_ms": 0
  }
}
EOF
}

# =============================================================================
# Report Generation - Comprehensive
# =============================================================================

report_generate_comprehensive() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"
    local output_format="${3:-markdown}"
    local output_file="${4:-}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    local start_time
    start_time=$(date +%s%3N 2>/dev/null || date +%s)000

    reviewer_info "Generating comprehensive report for: $root_dir"

    # Source all check modules
    source "${SCRIPT_DIR}/style.sh"
    source "${SCRIPT_DIR}/security.sh"
    source "${SCRIPT_DIR}/performance.sh"
    source "${SCRIPT_DIR}/best-practices.sh"

    # Run all checks
    local style_issues security_issues performance_issues best_practices_issues
    style_issues=$(style_check_directory "$root_dir" "$exclude_patterns" "json" 2>/dev/null || echo "[]")
    security_issues=$(security_audit_directory "$root_dir" "$exclude_patterns" "json" "true" 2>/dev/null || echo "[]")
    performance_issues=$(performance_analyze_directory "$root_dir" "$exclude_patterns" "json" 2>/dev/null || echo "[]")
    best_practices_issues=$(best_practices_check_directory "$root_dir" "$exclude_patterns" "json" 2>/dev/null || echo "[]")

    # Combine all issues
    local all_issues
    all_issues=$(echo "$style_issues" "$security_issues" "$performance_issues" "$best_practices_issues" | jq -s 'add')

    local end_time
    end_time=$(date +%s%3N 2>/dev/null || date +%s)000
    local execution_time=$((end_time - start_time))

    # Count files and lines
    local file_count total_lines
    file_count=$(reviewer_count_files "$root_dir" "$exclude_patterns")
    total_lines=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local lines
        lines=$(reviewer_count_lines "$file")
        total_lines=$((total_lines + lines))
    done < <(reviewer_get_code_files "$root_dir" "$exclude_patterns")

    # Calculate scores
    local security_score style_score performance_score bp_score overall_score
    security_score=$(report_calculate_security_score "$security_issues")
    style_score=$(report_calculate_style_score "$style_issues" "$file_count")
    performance_score=$(report_calculate_performance_score "$performance_issues")
    bp_score=$(report_calculate_bp_score "$best_practices_issues")
    overall_score=$(( (security_score + style_score + performance_score + bp_score) / 4 ))

    # Generate summary
    local summary
    summary=$(report_generate_summary "$all_issues" "$file_count" "$total_lines")

    # Generate recommendations
    local recommendations
    recommendations=$(report_generate_recommendations "$all_issues")

    # Build final report
    local report
    report=$(cat <<EOF
{
  "report_type": "comprehensive",
  "generated_at": "$(reviewer_timestamp)",
  "generated_at_human": "$(reviewer_timestamp_human)",
  "directory": "$(reviewer_json_escape "$root_dir")",
  "platform": "$(reviewer_detect_platform)",
  "summary": $summary,
  "scores": {
    "overall": $overall_score,
    "security": $security_score,
    "style": $style_score,
    "performance": $performance_score,
    "best_practices": $bp_score
  },
  "issues": $all_issues,
  "recommendations": $recommendations,
  "metadata": {
    "reviewer_version": "0.1.0",
    "execution_time_ms": $execution_time,
    "files_analyzed": $file_count,
    "total_lines": $total_lines
  }
}
EOF
)

    # Format output
    local formatted
    case "$output_format" in
        json)
            formatted=$(echo "$report" | jq '.')
            ;;
        markdown)
            formatted=$(report_format_markdown "$report")
            ;;
        text)
            formatted=$(report_format_text "$report")
            ;;
        html)
            formatted=$(report_format_html "$report")
            ;;
        *)
            formatted="$report"
            ;;
    esac

    # Output
    if [[ -n "$output_file" ]]; then
        echo "$formatted" > "$output_file"
        reviewer_success "Report saved to: $output_file"
    else
        echo "$formatted"
    fi
}

# =============================================================================
# Report Generation - Quick Summary
# =============================================================================

report_generate_quick() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    reviewer_info "Generating quick summary for: $root_dir"

    # Source check modules
    source "${SCRIPT_DIR}/style.sh"
    source "${SCRIPT_DIR}/security.sh"

    # Quick counts
    local file_count style_count security_count
    file_count=$(reviewer_count_files "$root_dir" "$exclude_patterns")

    local style_issues security_issues
    style_issues=$(style_check_directory "$root_dir" "$exclude_patterns" "json" 2>/dev/null || echo "[]")
    security_issues=$(security_audit_directory "$root_dir" "$exclude_patterns" "json" "false" 2>/dev/null || echo "[]")

    style_count=$(echo "$style_issues" | jq 'length')
    security_count=$(echo "$security_issues" | jq 'length')

    # Count by severity
    local critical high medium
    critical=$(echo "$security_issues" | jq '[.[] | select(.severity == "critical")] | length')
    high=$(echo "$security_issues" | jq '[.[] | select(.severity == "high")] | length')
    medium=$(echo "$security_issues" | jq '[.[] | select(.severity == "medium")] | length')

    # Calculate health score
    local health_score
    health_score=$((100 - critical * 25 - high * 10 - medium * 5 - style_count))
    [[ $health_score -lt 0 ]] && health_score=0

    cat <<EOF
{
  "directory": "$(reviewer_json_escape "$root_dir")",
  "files_analyzed": $file_count,
  "total_issues": $((style_count + security_count)),
  "style_issues": $style_count,
  "security_issues": $security_count,
  "security_by_severity": {
    "critical": $critical,
    "high": $high,
    "medium": $medium
  },
  "health_score": $health_score,
  "status": "$(report_status_from_score $health_score)"
}
EOF
}

# =============================================================================
# Score Calculations
# =============================================================================

report_calculate_security_score() {
    local issues="$1"

    local total critical high medium low score
    total=$(echo "$issues" | jq 'length')
    critical=$(echo "$issues" | jq '[.[] | select(.severity == "critical")] | length')
    high=$(echo "$issues" | jq '[.[] | select(.severity == "high")] | length')
    medium=$(echo "$issues" | jq '[.[] | select(.severity == "medium")] | length')
    low=$(echo "$issues" | jq '[.[] | select(.severity == "low")] | length')

    score=$((100 - critical * 25 - high * 10 - medium * 5 - low * 1))
    [[ $score -lt 0 ]] && score=0
    [[ $score -gt 100 ]] && score=100

    echo "$score"
}

report_calculate_style_score() {
    local issues="$1"
    local file_count="$2"

    [[ $file_count -eq 0 ]] && echo "100" && return

    local issue_count
    issue_count=$(echo "$issues" | jq 'length')

    # Style score based on issues per file ratio
    local ratio
    ratio=$(awk "BEGIN {printf \"%.2f\", $issue_count / $file_count}")
    local score
    score=$(awk "BEGIN {printf \"%.0f\", 100 - ($ratio * 10)}")

    [[ $score -lt 0 ]] && score=0
    [[ $score -gt 100 ]] && score=100

    echo "$score"
}

report_calculate_performance_score() {
    local issues="$1"

    local total critical high medium low score
    total=$(echo "$issues" | jq 'length')
    critical=$(echo "$issues" | jq '[.[] | select(.severity == "critical")] | length')
    high=$(echo "$issues" | jq '[.[] | select(.severity == "high")] | length')
    medium=$(echo "$issues" | jq '[.[] | select(.severity == "medium")] | length')
    low=$(echo "$issues" | jq '[.[] | select(.severity == "low")] | length')

    score=$((100 - critical * 20 - high * 10 - medium * 5 - low * 2))
    [[ $score -lt 0 ]] && score=0
    [[ $score -gt 100 ]] && score=100

    echo "$score"
}

report_calculate_bp_score() {
    local issues="$1"

    local total critical high medium low score
    total=$(echo "$issues" | jq 'length')
    critical=$(echo "$issues" | jq '[.[] | select(.severity == "critical")] | length')
    high=$(echo "$issues" | jq '[.[] | select(.severity == "high")] | length')
    medium=$(echo "$issues" | jq '[.[] | select(.severity == "medium")] | length')
    low=$(echo "$issues" | jq '[.[] | select(.severity == "low")] | length')

    score=$((100 - critical * 15 - high * 8 - medium * 4 - low * 1))
    [[ $score -lt 0 ]] && score=0
    [[ $score -gt 100 ]] && score=100

    echo "$score"
}

report_status_from_score() {
    local score=$1

    if [[ $score -ge 90 ]]; then
        echo "excellent"
    elif [[ $score -ge 75 ]]; then
        echo "good"
    elif [[ $score -ge 60 ]]; then
        echo "fair"
    elif [[ $score -ge 40 ]]; then
        echo "poor"
    else
        echo "critical"
    fi
}

# =============================================================================
# Summary Generation
# =============================================================================

report_generate_summary() {
    local issues="$1"
    local file_count="${2:-0}"
    local total_lines="${3:-0}"

    local total
    total=$(echo "$issues" | jq 'length')

    local by_severity by_category
    by_severity=$(echo "$issues" | jq 'group_by(.severity) | map({key: .[0].severity, value: length}) | from_entries')
    by_category=$(echo "$issues" | jq 'group_by(.category) | map({key: .[0].category, value: length}) | from_entries')

    cat <<EOF
{
  "total_issues": $total,
  "by_category": $by_category,
  "by_severity": $by_severity,
  "files_analyzed": $file_count,
  "total_lines": $total_lines
}
EOF
}

# =============================================================================
# Recommendations Generation
# =============================================================================

report_generate_recommendations() {
    local issues="$1"

    python3 - "$issues" <<'PYTHON'
import sys
import json

issues = json.loads(sys.argv[1])

recommendations = []

# Analyze issues and generate recommendations
severity_counts = {}
category_counts = {}

for issue in issues:
    sev = issue.get("severity", "unknown")
    cat = issue.get("category", "unknown")

    severity_counts[sev] = severity_counts.get(sev, 0) + 1
    category_counts[cat] = category_counts.get(cat, 0) + 1

# Generate recommendations based on findings
if severity_counts.get("critical", 0) > 0:
    recommendations.append({
        "priority": "critical",
        "title": "Address Critical Security Issues Immediately",
        "description": f"Found {severity_counts['critical']} critical issues that need immediate attention.",
        "actions": [
            "Review and fix all critical security vulnerabilities",
            "Run security audit after fixes",
            "Consider security-focused code review"
        ]
    })

if severity_counts.get("high", 0) > 0:
    recommendations.append({
        "priority": "high",
        "title": "Fix High Priority Issues",
        "description": f"Found {severity_counts['high']} high priority issues.",
        "actions": [
            "Address high severity security issues",
            "Fix performance bottlenecks",
            "Improve error handling"
        ]
    })

if category_counts.get("security", 0) > 5:
    recommendations.append({
        "priority": "high",
        "title": "Improve Security Posture",
        "description": "Multiple security issues detected across the codebase.",
        "actions": [
            "Implement security training for team",
            "Add security linting to CI/CD",
            "Consider security audit by external party"
        ]
    })

if category_counts.get("style", 0) > 10:
    recommendations.append({
        "priority": "medium",
        "title": "Standardize Code Style",
        "description": "Many style inconsistencies found.",
        "actions": [
            "Configure and run automated formatter (Prettier, Black, etc.)",
            "Add linting to pre-commit hooks",
            "Document coding standards"
        ]
    })

if category_counts.get("performance", 0) > 3:
    recommendations.append({
        "priority": "medium",
        "title": "Optimize Performance",
        "description": "Performance issues detected that may impact user experience.",
        "actions": [
            "Profile application to identify bottlenecks",
            "Implement caching where appropriate",
            "Review database queries for optimization"
        ]
    })

if category_counts.get("best-practices", 0) > 5:
    recommendations.append({
        "priority": "medium",
        "title": "Improve Code Quality",
        "description": "Best practices violations detected.",
        "actions": [
            "Add code review checklist",
            "Implement pair programming for complex changes",
            "Schedule refactoring sessions"
        ]
    })

if len(recommendations) == 0:
    recommendations.append({
        "priority": "info",
        "title": "Maintain Good Practices",
        "description": "Code quality looks good! Continue following best practices.",
        "actions": [
            "Keep up regular code reviews",
            "Monitor for regressions",
            "Share knowledge with team"
        ]
    })

print(json.dumps(recommendations, indent=2))
PYTHON
}

# =============================================================================
# Report Formatting - Markdown
# =============================================================================

report_format_markdown() {
    local report="$1"

    python3 - "$report" <<'PYTHON'
import sys
import json

report = json.loads(sys.argv[1])

output = []

# Header
output.append("# Code Review Report")
output.append("")
output.append(f"**Directory:** {report.get('directory', 'Unknown')}")
output.append(f"**Generated:** {report.get('generated_at_human', 'Unknown')}")
output.append(f"**Platform:** {report.get('platform', 'Unknown')}")
output.append("")

# Scores
scores = report.get('scores', {})
output.append("## Overall Scores")
output.append("")
output.append("| Category | Score | Status |")
output.append("|----------|-------|--------|")

for cat in ['overall', 'security', 'style', 'performance', 'best_practices']:
    score = scores.get(cat, 0)
    if score >= 90:
        status = "✅ Excellent"
    elif score >= 75:
        status = "🟢 Good"
    elif score >= 60:
        status = "🟡 Fair"
    elif score >= 40:
        status = "🟠 Poor"
    else:
        status = "🔴 Critical"
    output.append(f"| {cat.replace('_', ' ').title()} | {score} | {status} |")

output.append("")

# Summary
summary = report.get('summary', {})
output.append("## Summary")
output.append("")
output.append(f"- **Files Analyzed:** {summary.get('files_analyzed', 0)}")
output.append(f"- **Total Lines:** {summary.get('total_lines', 0)}")
output.append(f"- **Total Issues:** {summary.get('total_issues', 0)}")
output.append("")

# Issues by Severity
by_severity = summary.get('by_severity', {})
if by_severity:
    output.append("### Issues by Severity")
    output.append("")
    for sev in ['critical', 'high', 'medium', 'low', 'info']:
        count = by_severity.get(sev, 0)
        if count > 0:
            emoji = {'critical': '🔴', 'high': '🟠', 'medium': '🟡', 'low': '🔵', 'info': '🟢'}.get(sev, '⚪')
            output.append(f"- {emoji} **{sev.title()}:** {count}")
    output.append("")

# Issues by Category
by_category = summary.get('by_category', {})
if by_category:
    output.append("### Issues by Category")
    output.append("")
    for cat, count in sorted(by_category.items(), key=lambda x: x[1], reverse=True):
        output.append(f"- **{cat.replace('-', ' ').title()}:** {count}")
    output.append("")

# Top Issues
issues = report.get('issues', [])
if issues:
    output.append("## Top Issues")
    output.append("")

    # Show critical and high severity issues first
    critical_high = [i for i in issues if i.get('severity') in ['critical', 'high']][:20]

    for issue in critical_high:
        sev = issue.get('severity', 'unknown')
        emoji = {'critical': '🔴', 'high': '🟠', 'medium': '🟡', 'low': '🔵', 'info': '🟢'}.get(sev, '⚪')
        output.append(f"### {emoji} [{sev.upper()}] {issue.get('rule', 'Unknown')}")
        output.append("")
        output.append(f"- **File:** `{issue.get('file', 'Unknown')}` (line {issue.get('line', '?')})")
        output.append(f"- **Message:** {issue.get('message', 'No description')}")
        output.append(f"- **Suggestion:** {issue.get('suggestion', 'No suggestion provided')}")
        output.append("")

# Recommendations
recommendations = report.get('recommendations', [])
if recommendations:
    output.append("## Recommendations")
    output.append("")

    for rec in recommendations:
        priority = rec.get('priority', 'info')
        emoji = {'critical': '🔴', 'high': '🟠', 'medium': '🟡', 'low': '🔵', 'info': '🟢'}.get(priority, '⚪')
        output.append(f"### {emoji} {rec.get('title', 'Recommendation')}")
        output.append("")
        output.append(f"{rec.get('description', '')}")
        output.append("")
        output.append("**Actions:**")
        for action in rec.get('actions', []):
            output.append(f"- {action}")
        output.append("")

# Metadata
metadata = report.get('metadata', {})
if metadata:
    output.append("---")
    output.append("")
    output.append(f"*Generated by OML Reviewer v{metadata.get('reviewer_version', 'Unknown')} in {metadata.get('execution_time_ms', 0)}ms*")

print('\n'.join(output))
PYTHON
}

# =============================================================================
# Report Formatting - Text
# =============================================================================

report_format_text() {
    local report="$1"

    python3 - "$report" <<'PYTHON'
import sys
import json

report = json.loads(sys.argv[1])

output = []

output.append("=" * 60)
output.append("CODE REVIEW REPORT")
output.append("=" * 60)
output.append("")
output.append(f"Directory: {report.get('directory', 'Unknown')}")
output.append(f"Generated: {report.get('generated_at_human', 'Unknown')}")
output.append(f"Platform: {report.get('platform', 'Unknown')}")
output.append("")

# Scores
scores = report.get('scores', {})
output.append("SCORES")
output.append("-" * 40)
for cat in ['overall', 'security', 'style', 'performance', 'best_practices']:
    score = scores.get(cat, 0)
    output.append(f"  {cat.replace('_', ' ').title():20} {score}")
output.append("")

# Summary
summary = report.get('summary', {})
output.append("SUMMARY")
output.append("-" * 40)
output.append(f"  Files Analyzed:  {summary.get('files_analyzed', 0)}")
output.append(f"  Total Lines:     {summary.get('total_lines', 0)}")
output.append(f"  Total Issues:    {summary.get('total_issues', 0)}")
output.append("")

# Issues
issues = report.get('issues', [])
if issues:
    output.append("TOP ISSUES")
    output.append("-" * 40)

    critical_high = [i for i in issues if i.get('severity') in ['critical', 'high']][:20]
    for issue in critical_high:
        sev = issue.get('severity', 'unknown').upper()
        output.append(f"  [{sev}] {issue.get('file', '?')}:{issue.get('line', '?')}")
        output.append(f"         {issue.get('message', 'No description')}")
        output.append("")

print('\n'.join(output))
PYTHON
}

# =============================================================================
# Report Formatting - HTML
# =============================================================================

report_format_html() {
    local report="$1"

    python3 - "$report" <<'PYTHON'
import sys
import json

report = json.loads(sys.argv[1])

html = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Code Review Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .score-card { display: inline-block; padding: 20px; margin: 10px; border-radius: 8px; text-align: center; min-width: 120px; }
        .score-excellent { background: #d4edda; color: #155724; }
        .score-good { background: #d1ecf1; color: #0c5460; }
        .score-fair { background: #fff3cd; color: #856404; }
        .score-poor { background: #f8d7da; color: #721c24; }
        .score-value { font-size: 36px; font-weight: bold; }
        .score-label { font-size: 14px; text-transform: uppercase; }
        .issue { border-left: 4px solid #dc3545; padding: 15px; margin: 15px 0; background: #fff; }
        .issue-critical { border-color: #dc3545; }
        .issue-high { border-color: #fd7e14; }
        .issue-medium { border-color: #ffc107; }
        .issue-low { border-color: #17a2b8; }
        .issue-meta { color: #666; font-size: 14px; }
        .recommendation { background: #e7f3ff; padding: 20px; border-radius: 8px; margin: 15px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
        .badge-critical { background: #dc3545; color: white; }
        .badge-high { background: #fd7e14; color: white; }
        .badge-medium { background: #ffc107; color: black; }
        .badge-low { background: #17a2b8; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📋 Code Review Report</h1>
        <p><strong>Directory:</strong> ''' + report.get('directory', 'Unknown') + '''</p>
        <p><strong>Generated:</strong> ''' + report.get('generated_at_human', 'Unknown') + '''</p>

        <h2>Overall Scores</h2>
        <div>
'''

scores = report.get('scores', {})
for cat in ['overall', 'security', 'style', 'performance', 'best_practices']:
    score = scores.get(cat, 0)
    if score >= 90:
        css_class = 'score-excellent'
    elif score >= 75:
        css_class = 'score-good'
    elif score >= 60:
        css_class = 'score-fair'
    else:
        css_class = 'score-poor'

    html += f'''            <div class="score-card {css_class}">
                <div class="score-value">{score}</div>
                <div class="score-label">{cat.replace('_', ' ')}</div>
            </div>
'''

html += '''        </div>

        <h2>Summary</h2>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
'''

summary = report.get('summary', {})
html += f'''            <tr><td>Files Analyzed</td><td>{summary.get('files_analyzed', 0)}</td></tr>
            <tr><td>Total Lines</td><td>{summary.get('total_lines', 0)}</td></tr>
            <tr><td>Total Issues</td><td>{summary.get('total_issues', 0)}</td></tr>
'''

html += '''        </table>

        <h2>Issues by Severity</h2>
        <table>
            <tr><th>Severity</th><th>Count</th></tr>
'''

by_severity = summary.get('by_severity', {})
for sev in ['critical', 'high', 'medium', 'low', 'info']:
    count = by_severity.get(sev, 0)
    if count > 0:
        html += f'''            <tr><td><span class="badge badge-{sev}">{sev.upper()}</span></td><td>{count}</td></tr>
'''

html += '''        </table>

        <h2>Critical & High Issues</h2>
'''

issues = report.get('issues', [])
critical_high = [i for i in issues if i.get('severity') in ['critical', 'high']][:20]

for issue in critical_high:
    sev = issue.get('severity', 'unknown')
    html += f'''
        <div class="issue issue-{sev}">
            <span class="badge badge-{sev}">{sev.upper()}</span>
            <strong>{issue.get('rule', 'Unknown')}</strong>
            <p class="issue-meta">📁 {issue.get('file', 'Unknown')} (line {issue.get('line', '?')})</p>
            <p>{issue.get('message', 'No description')}</p>
            <p><em>💡 {issue.get('suggestion', 'No suggestion')}</em></p>
        </div>
'''

recommendations = report.get('recommendations', [])
if recommendations:
    html += '''
        <h2>Recommendations</h2>
'''
    for rec in recommendations:
        html += f'''
        <div class="recommendation">
            <h3>{rec.get('title', 'Recommendation')}</h3>
            <p>{rec.get('description', '')}</p>
            <ul>
'''
        for action in rec.get('actions', []):
            html += f'                <li>{action}</li>\n'
        html += '''            </ul>
        </div>
'''

html += '''
    </div>
</body>
</html>
'''

print(html)
PYTHON
}

# =============================================================================
# Report Export
# =============================================================================

report_export() {
    local report="$1"
    local format="$2"
    local output_file="$3"

    local formatted
    case "$format" in
        markdown|md)
            formatted=$(report_format_markdown "$report")
            ;;
        text|txt)
            formatted=$(report_format_text "$report")
            ;;
        html)
            formatted=$(report_format_html "$report")
            ;;
        json)
            formatted=$(echo "$report" | jq '.')
            ;;
        *)
            formatted="$report"
            ;;
    esac

    echo "$formatted" > "$output_file"
    reviewer_success "Report exported to: $output_file"
}
