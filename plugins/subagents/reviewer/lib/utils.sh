#!/usr/bin/env bash
# Reviewer Subagent - Utility Functions
# Common utilities for code review operations

set -euo pipefail

# =============================================================================
# Platform Detection
# =============================================================================

reviewer_detect_platform() {
    if [[ -d "/data/data/com.termux/files/usr" ]]; then
        echo "termux"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "gnu-linux"
    fi
}

# =============================================================================
# Default Configuration
# =============================================================================

reviewer_get_default_excludes() {
    echo "node_modules,.git,__pycache__,.venv,dist,build,.cache,target,coverage,.idea,.vscode"
}

reviewer_get_default_max_issues() {
    echo "${OML_REVIEWER_MAX_ISSUES:-100}"
}

reviewer_get_default_format() {
    echo "${OML_REVIEWER_OUTPUT_FORMAT:-markdown}"
}

# =============================================================================
# Directory and File Utilities
# =============================================================================

reviewer_validate_path() {
    local path="${1:-.}"
    if [[ ! -e "$path" ]]; then
        reviewer_error "Path not found: $path"
        return 1
    fi
    # Return absolute path
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    else
        # For files, return the directory and filename
        local dir file
        dir="$(cd "$(dirname "$path")" && pwd)"
        file="$(basename "$path")"
        echo "${dir}/${file}"
    fi
}

reviewer_validate_dir() {
    local dir="${1:-.}"
    if [[ ! -d "$dir" ]]; then
        reviewer_error "Directory not found: $dir"
        return 1
    fi
    # Convert to absolute path
    (cd "$dir" && pwd)
}

reviewer_get_code_files() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"
    local extensions="${3:-js,mjs,cjs,ts,tsx,py,sh,bash,go,rs,java,c,cpp,h,hpp,rb,php,sql,yaml,yml,json,md}"

    root_dir=$(reviewer_validate_dir "$root_dir")

    local find_args=""
    IFS=',' read -ra EXCLUDE_ARR <<< "$exclude_patterns"
    for pattern in "${EXCLUDE_ARR[@]}"; do
        pattern=$(echo "$pattern" | xargs)
        if [[ -n "$pattern" ]]; then
            find_args="${find_args} -name '${pattern}' -prune -o"
        fi
    done

    # Build extension filter
    local ext_filter=""
    IFS=',' read -ra EXT_ARR <<< "$extensions"
    for ext in "${EXT_ARR[@]}"; do
        ext=$(echo "$ext" | xargs)
        if [[ -n "$ext" ]]; then
            ext_filter="${ext_filter} -o -name '*.${ext}'"
        fi
    done
    ext_filter="${ext_filter:3}"  # Remove leading " -o"

    # Find files
    eval "find \"$root_dir\" $find_args -type f $ext_filter 2>/dev/null" || true
}

reviewer_count_files() {
    local root_dir="$1"
    local exclude_patterns="${2:-$(reviewer_get_default_excludes)}"

    reviewer_get_code_files "$root_dir" "$exclude_patterns" | wc -l | tr -d ' '
}

# =============================================================================
# String Utilities
# =============================================================================

reviewer_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

reviewer_xml_escape() {
    local str="$1"
    str="${str//&/&amp;}"
    str="${str//</&lt;}"
    str="${str//>/&gt;}"
    str="${str//\"/&quot;}"
    str="${str//\'/&apos;}"
    echo "$str"
}

reviewer_markdown_escape() {
    local str="$1"
    str="${str//_/\\_}"
    str="${str//\*/\\*}"
    str="${str//\`/\\\`}"
    echo "$str"
}

reviewer_truncate() {
    local str="$1"
    local max_len="${2:-100}"
    if [[ ${#str} -gt $max_len ]]; then
        echo "${str:0:$((max_len - 3))}..."
    else
        echo "$str"
    fi
}

# =============================================================================
# File Analysis Utilities
# =============================================================================

reviewer_get_extension() {
    local file="$1"
    local ext="${file##*.}"
    if [[ "$ext" == "$file" ]]; then
        echo ""
    else
        echo "$ext"
    fi
}

reviewer_detect_language() {
    local file="$1"
    local ext
    ext=$(reviewer_get_extension "$file")

    case "$ext" in
        js|mjs|cjs) echo "javascript" ;;
        ts|tsx) echo "typescript" ;;
        py|pyw) echo "python" ;;
        sh|bash) echo "bash" ;;
        go) echo "go" ;;
        rs) echo "rust" ;;
        java) echo "java" ;;
        c|h) echo "c" ;;
        cpp|cc|cxx|hpp|hxx) echo "cpp" ;;
        rb) echo "ruby" ;;
        php) echo "php" ;;
        pl|pm) echo "perl" ;;
        sql) echo "sql" ;;
        yaml|yml) echo "yaml" ;;
        json) echo "json" ;;
        md|markdown) echo "markdown" ;;
        *) echo "unknown" ;;
    esac
}

reviewer_count_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l < "$file" | tr -d ' '
    else
        echo "0"
    fi
}

reviewer_count_code_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        grep -cv '^\s*$' "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

reviewer_count_blank_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        grep -c '^\s*$' "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

reviewer_count_comment_lines() {
    local file="$1"
    local lang="${2:-unknown}"
    local count=0

    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi

    case "$lang" in
        javascript|typescript|java|cpp|c|go|rust|swift|kotlin|scala)
            count=$(grep -c '^\s*//' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            local block
            block=$(grep -c '^\s*/\*\|^\s*\*\|^\s*\*/' "$file" 2>/dev/null || echo "0")
            block=$(echo "$block" | tr -d '[:space:]')
            count=$((count + block))
            ;;
        python|ruby|bash|perl|yaml|shell)
            count=$(grep -c '^\s*#' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            ;;
        lua)
            count=$(grep -c '^\s*--' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            ;;
        html)
            count=$(grep -c '<!--' "$file" 2>/dev/null || echo "0")
            count=$(echo "$count" | tr -d '[:space:]')
            ;;
        *)
            count=0
            ;;
    esac

    echo "$count"
}

# =============================================================================
# Issue/Finding Creation
# =============================================================================

reviewer_create_issue() {
    local file="$1"
    local line="${2:-0}"
    local column="${3:-0}"
    local severity="$4"  # critical, high, medium, low, info
    local category="$5"  # security, style, performance, best-practices
    local rule="$6"
    local message="$7"
    local suggestion="${8:-}"

    cat <<EOF
{
  "file": "$(reviewer_json_escape "$file")",
  "line": $line,
  "column": $column,
  "severity": "$severity",
  "category": "$category",
  "rule": "$rule",
  "message": "$(reviewer_json_escape "$message")",
  "suggestion": "$(reviewer_json_escape "$suggestion")"
}
EOF
}

reviewer_create_finding() {
    local type="$1"  # issue, warning, info
    local category="$2"
    local message="$3"
    local details="${4:-}"

    cat <<EOF
{
  "type": "$type",
  "category": "$category",
  "message": "$(reviewer_json_escape "$message")",
  "details": "$(reviewer_json_escape "$details")",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# =============================================================================
# Severity Utilities
# =============================================================================

reviewer_severity_to_number() {
    local severity="$1"
    case "$severity" in
        critical) echo "5" ;;
        high) echo "4" ;;
        medium) echo "3" ;;
        low) echo "2" ;;
        info) echo "1" ;;
        *) echo "0" ;;
    esac
}

reviewer_severity_color() {
    local severity="$1"
    case "$severity" in
        critical) echo "\033[31;1m" ;;  # Bold Red
        high) echo "\033[31m" ;;         # Red
        medium) echo "\033[33m" ;;       # Yellow
        low) echo "\033[36m" ;;          # Cyan
        info) echo "\033[32m" ;;         # Green
        *) echo "\033[0m" ;;             # Default
    esac
}

reviewer_severity_emoji() {
    local severity="$1"
    case "$severity" in
        critical) echo "🔴" ;;
        high) echo "🟠" ;;
        medium) echo "🟡" ;;
        low) echo "🔵" ;;
        info) echo "🟢" ;;
        *) echo "⚪" ;;
    esac
}

# =============================================================================
# Logging Utilities
# =============================================================================

reviewer_error() {
    echo "[ERROR] $*" >&2
}

reviewer_warn() {
    echo "[WARN] $*" >&2
}

reviewer_info() {
    if [[ "${OML_REVIEWER_QUIET:-false}" != "true" ]]; then
        echo "[INFO] $*"
    fi
}

reviewer_success() {
    echo "[OK] $*"
}

reviewer_debug() {
    if [[ "${OML_REVIEWER_VERBOSE:-false}" == "true" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# =============================================================================
# Timestamp Utilities
# =============================================================================

reviewer_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

reviewer_timestamp_human() {
    date '+%Y-%m-%d %H:%M:%S'
}

# =============================================================================
# JSON Utilities
# =============================================================================

reviewer_json_array_start() {
    echo "["
}

reviewer_json_array_end() {
    echo "]"
}

reviewer_json_object_start() {
    echo "{"
}

reviewer_json_object_end() {
    echo "}"
}

reviewer_json_join_objects() {
    local first=true
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo "$line"
        fi
    done
}

# =============================================================================
# Pattern Matching Utilities
# =============================================================================

reviewer_match_pattern() {
    local text="$1"
    local pattern="$2"

    echo "$text" | grep -qE "$pattern"
}

reviewer_extract_matches() {
    local text="$1"
    local pattern="$2"

    echo "$text" | grep -oE "$pattern" || true
}

reviewer_count_matches() {
    local text="$1"
    local pattern="$2"

    echo "$text" | grep -oE "$pattern" 2>/dev/null | wc -l | tr -d ' '
}

# =============================================================================
# Security Utilities
# =============================================================================

reviewer_is_sensitive_file() {
    local file="$1"
    local basename
    basename=$(basename "$file")

    case "$basename" in
        *.pem|*.key|*.crt|*.cer|*.p12|*.pfx) return 0 ;;
        id_rsa|id_dsa|id_ecdsa|id_ed25519) return 0 ;;
        .env|.env.*|*.env) return 0 ;;
        *secret*|*password*|*credential*|*token*) return 0 ;;
        config.*.json|config.*.yaml|config.*.yml) return 0 ;;
        *) return 1 ;;
    esac
}

reviewer_is_binary_file() {
    local file="$1"
    if file "$file" 2>/dev/null | grep -qE 'executable|binary|data'; then
        return 0
    fi
    return 1
}

# =============================================================================
# Cache Utilities
# =============================================================================

reviewer_get_cache_dir() {
    local cache_dir="${HOME}/.local/cache/oml/reviewer"
    mkdir -p "$cache_dir"
    echo "$cache_dir"
}

reviewer_get_config_dir() {
    local config_dir="${HOME}/.local/share/oml/reviewer"
    mkdir -p "$config_dir"
    echo "$config_dir"
}

reviewer_cache_get() {
    local key="$1"
    local cache_file="$(reviewer_get_cache_dir)/${key}.cache"

    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    else
        echo ""
    fi
}

reviewer_cache_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-3600}"

    local cache_file="$(reviewer_get_cache_dir)/${key}.cache"
    local meta_file="${cache_file}.meta"

    echo "$value" > "$cache_file"
    echo "$(date +%s) $ttl" > "$meta_file"
}

reviewer_cache_valid() {
    local key="$1"
    local cache_file="$(reviewer_get_cache_dir)/${key}.cache"
    local meta_file="${cache_file}.meta"

    if [[ ! -f "$cache_file" ]] || [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    local created ttl now age
    read -r created ttl < "$meta_file"
    now=$(date +%s)
    age=$((now - created))

    [[ $age -lt $ttl ]]
}

reviewer_cache_clear() {
    local cache_dir
    cache_dir="$(reviewer_get_cache_dir)"

    if [[ -d "$cache_dir" ]]; then
        rm -rf "${cache_dir}"/*
        reviewer_info "Cache cleared"
    fi
}

# =============================================================================
# Configuration Loading
# =============================================================================

reviewer_load_config() {
    local config_file="$(reviewer_get_config_dir)/config.json"

    if [[ -f "$config_file" ]]; then
        cat "$config_file"
    else
        echo '{}'
    fi
}

reviewer_save_config() {
    local config="$1"
    local config_file="$(reviewer_get_config_dir)/config.json"

    echo "$config" | jq '.' > "$config_file"
}

# =============================================================================
# Helper for Issue Collection
# =============================================================================

REVIEWER_ISSUES_FILE=""
REVIEWER_ISSUES_COUNT=0

reviewer_issues_init() {
    REVIEWER_ISSUES_FILE=$(mktemp)
    REVIEWER_ISSUES_COUNT=0
    echo "[]" > "$REVIEWER_ISSUES_FILE"
}

reviewer_issues_add() {
    local issue="$1"
    local max_issues="${2:-$(reviewer_get_default_max_issues)}"

    if [[ $REVIEWER_ISSUES_COUNT -ge $max_issues ]]; then
        reviewer_warn "Maximum issues limit reached ($max_issues)"
        return 0
    fi

    # Add issue to file
    local current
    current=$(cat "$REVIEWER_ISSUES_FILE")
    echo "$current" | jq --argjson issue "$issue" '. + [$issue]' > "$REVIEWER_ISSUES_FILE"
    ((REVIEWER_ISSUES_COUNT++))
}

reviewer_issues_get() {
    if [[ -f "$REVIEWER_ISSUES_FILE" ]]; then
        cat "$REVIEWER_ISSUES_FILE"
    else
        echo "[]"
    fi
}

reviewer_issues_count() {
    echo "$REVIEWER_ISSUES_COUNT"
}

reviewer_issues_cleanup() {
    if [[ -n "$REVIEWER_ISSUES_FILE" ]] && [[ -f "$REVIEWER_ISSUES_FILE" ]]; then
        rm -f "$REVIEWER_ISSUES_FILE"
    fi
}

reviewer_issues_by_severity() {
    local severity="$1"
    local issues
    issues=$(reviewer_issues_get)
    echo "$issues" | jq --arg sev "$severity" '[.[] | select(.severity == $sev)]'
}

reviewer_issues_by_category() {
    local category="$1"
    local issues
    issues=$(reviewer_issues_get)
    echo "$issues" | jq --arg cat "$category" '[.[] | select(.category == $cat)]'
}

reviewer_issues_summary() {
    local issues
    issues=$(reviewer_issues_get)

    python3 - "$issues" <<'PYTHON'
import sys
import json

issues = json.loads(sys.argv[1])

summary = {
    "total": len(issues),
    "by_severity": {},
    "by_category": {}
}

for issue in issues:
    sev = issue.get("severity", "unknown")
    cat = issue.get("category", "unknown")

    summary["by_severity"][sev] = summary["by_severity"].get(sev, 0) + 1
    summary["by_category"][cat] = summary["by_category"].get(cat, 0) + 1

print(json.dumps(summary, indent=2))
PYTHON
}
