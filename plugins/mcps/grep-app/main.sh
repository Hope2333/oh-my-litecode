#!/usr/bin/env bash
# Grep-App MCP Plugin for OML
# Provides MCP (Model Context Protocol) service for code search and analysis
#
# Usage:
#   oml mcps grep-app search <query> [options]    # Natural language search
#   oml mcps grep-app regex <pattern> [options]   # Regex search
#   oml mcps grep-app count <pattern> [options]   # Count matches
#   oml mcps grep-app files <pattern> [options]   # List matching files
#   oml mcps grep-app config <key> [value]        # Configuration management
#   oml mcps grep-app enable                      # Enable Grep-App MCP
#   oml mcps grep-app disable                     # Disable Grep-App MCP
#   oml mcps grep-app status                      # Check service status
#   oml mcps grep-app mcp-stdio                   # MCP stdio server mode
#   oml mcps grep-app mcp-http                    # MCP HTTP server mode
#
# Examples:
#   # Natural language search
#   oml mcps grep-app search "find all Python functions"
#   oml mcps grep-app search "TODO comments in JavaScript" --ext py,js
#
#   # Regex search
#   oml mcps grep-app regex "def \w+\(" --ext py
#   oml mcps grep-app regex "console\.log" --ext js,ts
#
#   # Count matches
#   oml mcps grep-app count "TODO|FIXME" --ext py,js
#
#   # List matching files
#   oml mcps grep-app files "import.*from" --ext py
#
#   # Advanced search with multiple options
#   oml mcps grep-app regex "class \w+" --ext py --exclude-dir tests --context 3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"
PLUGIN_NAME="grep-app"
PLUGIN_TYPE="mcps"

# OML core paths
OML_CORE_DIR="${OML_CORE_DIR:-}"
if [[ -z "$OML_CORE_DIR" ]]; then
    if [[ -d "${SCRIPT_DIR}/../../core" ]]; then
        OML_CORE_DIR="$(cd "${SCRIPT_DIR}/../../core" && pwd)"
    fi
fi

# Source OML core modules
if [[ -n "$OML_CORE_DIR" && -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi

# ============================================================================
# Configuration
# ============================================================================

# Default configuration
GREP_APP_DEFAULT_PATH="${GREP_APP_DEFAULT_PATH:-.}"
GREP_APP_MAX_RESULTS="${GREP_APP_MAX_RESULTS:-100}"
GREP_APP_EXCLUDE_DIRS="${GREP_APP_EXCLUDE_DIRS:-node_modules,.git,__pycache__,.venv,venv,dist,build}"
GREP_APP_HTTP_PORT="${GREP_APP_HTTP_PORT:-8765}"

# Get OML config directory
get_oml_config_dir() {
    if [[ -n "${_FAKEHOME:-}" ]]; then
        echo "${_FAKEHOME}/.oml"
    else
        echo "${HOME}/.oml"
    fi
}

# Get settings file path
get_settings_file() {
    local fake_home="${_FAKEHOME:-$HOME}"
    echo "${fake_home}/.qwen/settings.json"
}

# Get grep-app config file
get_grep_app_config() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/grep-app/config.json"
}

# Get enabled plugins directory
get_enabled_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/enabled/${PLUGIN_TYPE}"
}

# Get cache directory
get_cache_dir() {
    local config_dir
    config_dir="$(get_oml_config_dir)"
    echo "${config_dir}/cache/grep-app"
}

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_success() {
    echo "[OK] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Check if running on Termux
is_termux() {
    [[ -d "/data/data/com.termux/files/usr" ]]
}

# Check if running on GNU/Linux
is_gnu_linux() {
    ! is_termux
}

# Check if grep is available
check_grep() {
    if command -v grep >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if find is available
check_find() {
    if command -v find >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if python3 is available
check_python3() {
    if command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Get grep options for extended regex
get_grep_extended() {
    if grep -E "" >/dev/null 2>&1; then
        echo "-E"
    else
        echo ""
    fi
}

# Build exclude arguments for grep
build_grep_exclude() {
    local exclude_dirs="${1:-$GREP_APP_EXCLUDE_DIRS}"
    local args=()

    IFS=',' read -ra DIRS <<< "$exclude_dirs"
    for dir in "${DIRS[@]}"; do
        dir=$(echo "$dir" | xargs)  # trim whitespace
        if [[ -n "$dir" ]]; then
            args+=("--exclude-dir=$dir")
        fi
    done

    echo "${args[@]}"
}

# Build find exclude arguments
build_find_exclude() {
    local exclude_dirs="${1:-$GREP_APP_EXCLUDE_DIRS}"
    local args=()

    IFS=',' read -ra DIRS <<< "$exclude_dirs"
    for dir in "${DIRS[@]}"; do
        dir=$(echo "$dir" | xargs)
        if [[ -n "$dir" ]]; then
            args+=("-name" "$dir" "-prune" "-o")
        fi
    done

    echo "${args[@]}"
}

# Detect file extensions for search
detect_extensions() {
    local query="$1"
    local exts=()

    # Simple keyword-based extension detection
    if echo "$query" | grep -qi "python\|\.py\|def \|import \|class "; then
        exts+=("py")
    fi
    if echo "$query" | grep -qi "javascript\|\.js\|function \|const \|let \|var \|=>"; then
        exts+=("js")
    fi
    if echo "$query" | grep -qi "typescript\|\.ts\|interface \|type \|enum "; then
        exts+=("ts" "tsx")
    fi
    if echo "$query" | grep -qi "java\|\.java\|public class \|private \|void "; then
        exts+=("java")
    fi
    if echo "$query" | grep -qi "rust\|\.rs\|fn \|let mut \|impl "; then
        exts+=("rs")
    fi
    if echo "$query" | grep -qi "go\|\.go\|func \|package \|import \""; then
        exts+=("go")
    fi
    if echo "$query" | grep -qi "c\+\+\|\.cpp\|\.cc\|#include \|std::"; then
        exts+=("cpp" "cc" "cxx" "h" "hpp")
    fi
    if echo "$query" | grep -qi "shell\|bash\|\.sh\|#!/"; then
        exts+=("sh" "bash" "zsh")
    fi
    if echo "$query" | grep -qi "html\|\.html\|<div\|<span\|<!DOCTYPE"; then
        exts+=("html" "htm")
    fi
    if echo "$query" | grep -qi "css\|\.css\|{.*:.*;"; then
        exts+=("css" "scss" "less")
    fi
    if echo "$query" | grep -qi "json\|\.json"; then
        exts+=("json")
    fi
    if echo "$query" | grep -qi "yaml\|yml\|\.ya?ml"; then
        exts+=("yaml" "yml")
    fi
    if echo "$query" | grep -qi "markdown\|\.md\|# \|## "; then
        exts+=("md")
    fi
    if echo "$query" | grep -qi "sql\|\.sql\|SELECT \|INSERT \|UPDATE \|DELETE "; then
        exts+=("sql")
    fi
    if echo "$query" | grep -qi "docker\|Dockerfile"; then
        exts+=("Dockerfile")
    fi
    if echo "$query" | grep -qi "make\|Makefile"; then
        exts+=("mk" "Makefile")
    fi

    if [[ ${#exts[@]} -eq 0 ]]; then
        # Default to common source code extensions
        exts=("py" "js" "ts" "java" "go" "rs" "cpp" "c" "h" "sh" "bash" "rb" "php")
    fi

    # Remove duplicates and output
    printf '%s\n' "${exts[@]}" | sort -u | tr '\n' ',' | sed 's/,$//'
}

# Convert natural language to grep pattern
nl_to_pattern() {
    local query="$1"
    local pattern=""

    # Common patterns
    if echo "$query" | grep -qi "function"; then
        pattern="function|def |fn |func "
    elif echo "$query" | grep -qi "class"; then
        pattern="class |interface |type |struct "
    elif echo "$query" | grep -qi "import"; then
        pattern="import |require\(|from "
    elif echo "$query" | grep -qi "variable\|const\|let\|var"; then
        pattern="const |let |var "
    elif echo "$query" | grep -qi "todo\|fixme"; then
        pattern="TODO|FIXME|XXX|HACK|BUG"
    elif echo "$query" | grep -qi "comment"; then
        pattern="//|#|/\*|\*"
    elif echo "$query" | grep -qi "error\|exception"; then
        pattern="error|Error|ERROR|exception|Exception|raise |throw "
    elif echo "$query" | grep -qi "log\|print"; then
        pattern="console\.log|print\(|log\.|logger\."
    elif echo "$query" | grep -qi "test"; then
        pattern="test_|_test|describe\(|it\(|@Test|func Test"
    else
        # Use query words as pattern
        pattern=$(echo "$query" | sed 's/[^a-zA-Z0-9_ ]//g' | tr ' ' '|')
    fi

    echo "$pattern"
}

# ============================================================================
# Search Command - Natural Language Search
# ============================================================================

cmd_search() {
    local query=""
    local path="$GREP_APP_DEFAULT_PATH"
    local extensions=""
    local max_results="$GREP_APP_MAX_RESULTS"
    local exclude_dirs="$GREP_APP_EXCLUDE_DIRS"
    local context=0
    local ignore_case=true
    local json_output=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path|-p)
                path="$2"
                shift 2
                ;;
            --ext|-e)
                extensions="$2"
                shift 2
                ;;
            --max|-n)
                max_results="$2"
                shift 2
                ;;
            --exclude-dir)
                exclude_dirs="$2"
                shift 2
                ;;
            --context|-C)
                context="$2"
                shift 2
                ;;
            --no-ignore-case)
                ignore_case=false
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Usage: grep-app search <query> [options]"
                return 1
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
        log_error "Query is required"
        echo "Usage: grep-app search <query> [options]"
        echo ""
        echo "Options:"
        echo "  --path, -p <path>       Search path (default: .)"
        echo "  --ext, -e <exts>        File extensions (auto-detected if not specified)"
        echo "  --max, -n <num>         Max results (default: 100)"
        echo "  --exclude-dir <dirs>    Directories to exclude"
        echo "  --context, -C <num>     Context lines (default: 0)"
        echo "  --no-ignore-case        Case sensitive search"
        echo "  --json                  Output in JSON format"
        return 1
    fi

    # Auto-detect extensions if not specified
    if [[ -z "$extensions" ]]; then
        extensions=$(detect_extensions "$query")
        log_info "Auto-detected extensions: $extensions"
    fi

    # Convert natural language to pattern
    local pattern
    pattern=$(nl_to_pattern "$query")
    log_info "Converted query to pattern: $pattern"

    # Build grep arguments
    local grep_args=()
    grep_args+=("-E")
    if [[ "$ignore_case" == "true" ]]; then
        grep_args+=("-i")
    fi
    if [[ $context -gt 0 ]]; then
        grep_args+=("-C" "$context")
    fi
    grep_args+=("-n")  # line numbers
    grep_args+=("-H")  # file names

    # Add exclude directories
    local exclude_args
    exclude_args=$(build_grep_exclude "$exclude_dirs")
    if [[ -n "$exclude_args" ]]; then
        grep_args+=($exclude_args)
    fi

    # Build find pattern for extensions
    local find_pattern=""
    IFS=',' read -ra EXTS <<< "$extensions"
    for ext in "${EXTS[@]}"; do
        ext=$(echo "$ext" | xargs)
        if [[ -n "$ext" ]]; then
            if [[ -n "$find_pattern" ]]; then
                find_pattern+=" -o "
            fi
            find_pattern+="-name '*.$ext'"
        fi
    done

    # Execute search
    log_info "Searching for '$query' in path: $path"

    local results
    if [[ -n "$find_pattern" ]]; then
        results=$(find "$path" -type f \( $find_pattern \) ! \( $(build_find_exclude "$exclude_dirs") \) -print0 2>/dev/null | \
            xargs -0 grep "${grep_args[@]}" -- "$pattern" 2>/dev/null | head -n "$max_results" || true)
    else
        results=$(grep "${grep_args[@]}" -r -- "$pattern" "$path" 2>/dev/null | head -n "$max_results" || true)
    fi

    if [[ -z "$results" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"query": "'"$query"'", "pattern": "'"$pattern"'", "matches": [], "count": 0}'
        else
            echo "No matches found for: $query"
        fi
        return 0
    fi

    # Output results
    if [[ "$json_output" == "true" ]]; then
        output_json "$query" "$pattern" "$results"
    else
        echo "Search results for: $query"
        echo "Pattern: $pattern"
        echo "Extensions: $extensions"
        echo "========================================"
        echo "$results"
        echo ""
        local count
        count=$(echo "$results" | wc -l)
        echo "Total matches: $count"
    fi
}

# ============================================================================
# Regex Command - Regular Expression Search
# ============================================================================

cmd_regex() {
    local pattern=""
    local path="$GREP_APP_DEFAULT_PATH"
    local extensions=""
    local max_results="$GREP_APP_MAX_RESULTS"
    local exclude_dirs="$GREP_APP_EXCLUDE_DIRS"
    local context=0
    local ignore_case=false
    local json_output=false
    local extended=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path|-p)
                path="$2"
                shift 2
                ;;
            --ext|-e)
                extensions="$2"
                shift 2
                ;;
            --max|-n)
                max_results="$2"
                shift 2
                ;;
            --exclude-dir)
                exclude_dirs="$2"
                shift 2
                ;;
            --context|-C)
                context="$2"
                shift 2
                ;;
            --ignore-case|-i)
                ignore_case=true
                shift
                ;;
            --basic-regex)
                extended=false
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Usage: grep-app regex <pattern> [options]"
                return 1
                ;;
            *)
                if [[ -z "$pattern" ]]; then
                    pattern="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        log_error "Pattern is required"
        echo "Usage: grep-app regex <pattern> [options]"
        echo ""
        echo "Options:"
        echo "  --path, -p <path>       Search path (default: .)"
        echo "  --ext, -e <exts>        File extensions (comma-separated)"
        echo "  --max, -n <num>         Max results (default: 100)"
        echo "  --exclude-dir <dirs>    Directories to exclude"
        echo "  --context, -C <num>     Context lines (default: 0)"
        echo "  --ignore-case, -i       Case insensitive search"
        echo "  --basic-regex           Use basic regex (default: extended)"
        echo "  --json                  Output in JSON format"
        return 1
    fi

    # Build grep arguments
    local grep_args=()
    if [[ "$extended" == "true" ]]; then
        grep_args+=("-E")
    fi
    if [[ "$ignore_case" == "true" ]]; then
        grep_args+=("-i")
    fi
    if [[ $context -gt 0 ]]; then
        grep_args+=("-C" "$context")
    fi
    grep_args+=("-n")
    grep_args+=("-H")

    # Add exclude directories
    local exclude_args
    exclude_args=$(build_grep_exclude "$exclude_dirs")
    if [[ -n "$exclude_args" ]]; then
        grep_args+=($exclude_args)
    fi

    # Build find pattern for extensions
    local find_pattern=""
    if [[ -n "$extensions" ]]; then
        IFS=',' read -ra EXTS <<< "$extensions"
        for ext in "${EXTS[@]}"; do
            ext=$(echo "$ext" | xargs)
            if [[ -n "$ext" ]]; then
                if [[ -n "$find_pattern" ]]; then
                    find_pattern+=" -o "
                fi
                find_pattern+="-name '*.$ext'"
            fi
        done
    fi

    # Execute search
    log_info "Searching with regex pattern: $pattern"

    local results
    if [[ -n "$find_pattern" ]]; then
        results=$(find "$path" -type f \( $find_pattern \) ! \( $(build_find_exclude "$exclude_dirs") \) -print0 2>/dev/null | \
            xargs -0 grep "${grep_args[@]}" -- "$pattern" 2>/dev/null | head -n "$max_results" || true)
    else
        results=$(grep "${grep_args[@]}" -r -- "$pattern" "$path" 2>/dev/null | head -n "$max_results" || true)
    fi

    if [[ -z "$results" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"pattern": "'"$pattern"'", "matches": [], "count": 0}'
        else
            echo "No matches found for pattern: $pattern"
        fi
        return 0
    fi

    # Output results
    if [[ "$json_output" == "true" ]]; then
        output_json "" "$pattern" "$results"
    else
        echo "Regex search results for: $pattern"
        echo "========================================"
        echo "$results"
        echo ""
        local count
        count=$(echo "$results" | wc -l)
        echo "Total matches: $count"
    fi
}

# ============================================================================
# Count Command - Count Matches
# ============================================================================

cmd_count() {
    local pattern=""
    local path="$GREP_APP_DEFAULT_PATH"
    local extensions=""
    local exclude_dirs="$GREP_APP_EXCLUDE_DIRS"
    local ignore_case=false
    local json_output=false
    local extended=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path|-p)
                path="$2"
                shift 2
                ;;
            --ext|-e)
                extensions="$2"
                shift 2
                ;;
            --exclude-dir)
                exclude_dirs="$2"
                shift 2
                ;;
            --ignore-case|-i)
                ignore_case=true
                shift
                ;;
            --basic-regex)
                extended=false
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Usage: grep-app count <pattern> [options]"
                return 1
                ;;
            *)
                if [[ -z "$pattern" ]]; then
                    pattern="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        log_error "Pattern is required"
        echo "Usage: grep-app count <pattern> [options]"
        return 1
    fi

    # Build grep arguments
    local grep_args=()
    if [[ "$extended" == "true" ]]; then
        grep_args+=("-E")
    fi
    if [[ "$ignore_case" == "true" ]]; then
        grep_args+=("-i")
    fi
    grep_args+=("-c")  # count only

    # Add exclude directories
    local exclude_args
    exclude_args=$(build_grep_exclude "$exclude_dirs")
    if [[ -n "$exclude_args" ]]; then
        grep_args+=($exclude_args)
    fi

    # Build find pattern for extensions
    local find_pattern=""
    if [[ -n "$extensions" ]]; then
        IFS=',' read -ra EXTS <<< "$extensions"
        for ext in "${EXTS[@]}"; do
            ext=$(echo "$ext" | xargs)
            if [[ -n "$ext" ]]; then
                if [[ -n "$find_pattern" ]]; then
                    find_pattern+=" -o "
                fi
                find_pattern+="-name '*.$ext'"
            fi
        done
    fi

    # Execute count
    log_info "Counting matches for pattern: $pattern"

    local total_count=0
    local file_count=0
    local results=""

    if [[ -n "$find_pattern" ]]; then
        while IFS= read -r -d '' file; do
            local count
            count=$(grep "${grep_args[@]}" -- "$pattern" "$file" 2>/dev/null || echo "0")
            if [[ "$count" -gt 0 ]]; then
                total_count=$((total_count + count))
                file_count=$((file_count + 1))
                results+="$file: $count"$'\n'
            fi
        done < <(find "$path" -type f \( $find_pattern \) ! \( $(build_find_exclude "$exclude_dirs") \) -print0 2>/dev/null)
    else
        while IFS= read -r line; do
            local file
            local count
            file=$(echo "$line" | cut -d: -f1)
            count=$(echo "$line" | cut -d: -f2)
            if [[ "$count" -gt 0 ]]; then
                total_count=$((total_count + count))
                file_count=$((file_count + 1))
                results+="$line"$'\n'
            fi
        done < <(grep "${grep_args[@]}" -r -- "$pattern" "$path" 2>/dev/null)
    fi

    # Output results
    if [[ "$json_output" == "true" ]]; then
        cat <<EOF
{
  "pattern": "$pattern",
  "total_matches": $total_count,
  "files_with_matches": $file_count,
  "by_file": $(echo "$results" | python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
result = {}
for line in lines:
    if ':' in line:
        parts = line.rsplit(':', 1)
        if len(parts) == 2:
            result[parts[0]] = int(parts[1])
print(json.dumps(result))
" 2>/dev/null || echo "{}")
}
EOF
    else
        echo "Count results for: $pattern"
        echo "========================================"
        if [[ -n "$results" ]]; then
            echo "$results"
        fi
        echo ""
        echo "Total matches: $total_count"
        echo "Files with matches: $file_count"
    fi
}

# ============================================================================
# Files Command - List Matching Files
# ============================================================================

cmd_files() {
    local pattern=""
    local path="$GREP_APP_DEFAULT_PATH"
    local extensions=""
    local max_results="$GREP_APP_MAX_RESULTS"
    local exclude_dirs="$GREP_APP_EXCLUDE_DIRS"
    local ignore_case=false
    local json_output=false
    local extended=true
    local names_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path|-p)
                path="$2"
                shift 2
                ;;
            --ext|-e)
                extensions="$2"
                shift 2
                ;;
            --max|-n)
                max_results="$2"
                shift 2
                ;;
            --exclude-dir)
                exclude_dirs="$2"
                shift 2
                ;;
            --ignore-case|-i)
                ignore_case=true
                shift
                ;;
            --basic-regex)
                extended=false
                shift
                ;;
            --names-only|-l)
                names_only=true
                shift
                ;;
            --json)
                json_output=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Usage: grep-app files <pattern> [options]"
                return 1
                ;;
            *)
                if [[ -z "$pattern" ]]; then
                    pattern="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        log_error "Pattern is required"
        echo "Usage: grep-app files <pattern> [options]"
        return 1
    fi

    # Build grep arguments
    local grep_args=()
    if [[ "$extended" == "true" ]]; then
        grep_args+=("-E")
    fi
    if [[ "$ignore_case" == "true" ]]; then
        grep_args+=("-i")
    fi
    if [[ "$names_only" == "true" ]]; then
        grep_args+=("-l")  # files with matches only
    else
        grep_args+=("-L")  # files without matches (we'll invert)
    fi
    grep_args+=("-r")

    # Add exclude directories
    local exclude_args
    exclude_args=$(build_grep_exclude "$exclude_dirs")
    if [[ -n "$exclude_args" ]]; then
        grep_args+=($exclude_args)
    fi

    # Build find pattern for extensions
    local find_pattern=""
    if [[ -n "$extensions" ]]; then
        IFS=',' read -ra EXTS <<< "$extensions"
        for ext in "${EXTS[@]}"; do
            ext=$(echo "$ext" | xargs)
            if [[ -n "$ext" ]]; then
                if [[ -n "$find_pattern" ]]; then
                    find_pattern+=" -o "
                fi
                find_pattern+="-name '*.$ext'"
            fi
        done
    fi

    # Execute search
    log_info "Finding files matching pattern: $pattern"

    local files=()
    if [[ -n "$find_pattern" ]]; then
        while IFS= read -r -d '' file; do
            if grep "${grep_args[@]}" -- "$pattern" "$file" >/dev/null 2>&1; then
                files+=("$file")
            fi
        done < <(find "$path" -type f \( $find_pattern \) ! \( $(build_find_exclude "$exclude_dirs") \) -print0 2>/dev/null)
    else
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                files+=("$file")
            fi
        done < <(grep "${grep_args[@]}" -- "$pattern" "$path" 2>/dev/null | head -n "$max_results")
    fi

    # Limit results
    if [[ ${#files[@]} -gt $max_results ]]; then
        files=("${files[@]:0:$max_results}")
    fi

    # Output results
    if [[ "$json_output" == "true" ]]; then
        cat <<EOF
{
  "pattern": "$pattern",
  "files": $(printf '%s\n' "${files[@]}" | python3 -c "
import sys, json
files = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(files))
" 2>/dev/null || echo "[]"),
  "count": ${#files[@]}
}
EOF
    else
        echo "Files matching pattern: $pattern"
        echo "========================================"
        if [[ ${#files[@]} -eq 0 ]]; then
            echo "No files found"
        else
            for file in "${files[@]}"; do
                echo "$file"
            done
        fi
        echo ""
        echo "Total files: ${#files[@]}"
    fi
}

# ============================================================================
# Config Command - Configuration Management
# ============================================================================

cmd_config() {
    local key="${1:-}"
    local value="${2:-}"

    if [[ -z "$key" ]]; then
        show_config
        return 0
    fi

    case "$key" in
        default_path)
            set_config_value "default_path" "$value"
            ;;
        max_results)
            set_config_value "max_results" "$value"
            ;;
        exclude_dirs)
            set_config_value "exclude_dirs" "$value"
            ;;
        http_port)
            set_config_value "http_port" "$value"
            ;;
        reset)
            reset_config
            ;;
        *)
            log_error "Unknown config key: $key"
            echo "Available keys: default_path, max_results, exclude_dirs, http_port, reset"
            return 1
            ;;
    esac
}

show_config() {
    local config_file
    config_file="$(get_grep_app_config)"

    echo "Grep-App Configuration"
    echo "======================"
    echo ""

    if [[ ! -f "$config_file" ]]; then
        echo "Using default configuration:"
        echo "  default_path:    $GREP_APP_DEFAULT_PATH"
        echo "  max_results:     $GREP_APP_MAX_RESULTS"
        echo "  exclude_dirs:    $GREP_APP_EXCLUDE_DIRS"
        echo "  http_port:       $GREP_APP_HTTP_PORT"
        echo ""
        echo "No custom config file found: $config_file"
        return 0
    fi

    python3 - "${config_file}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])

try:
    data = json.loads(config_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading config: {e}")
    sys.exit(1)

print(f"default_path:    {data.get('default_path', '.')}")
print(f"max_results:     {data.get('max_results', 100)}")
print(f"exclude_dirs:    {data.get('exclude_dirs', 'node_modules,.git,__pycache__')}")
print(f"http_port:       {data.get('http_port', 8765)}")
PY
}

set_config_value() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        log_error "Value is required for key: $key"
        return 1
    fi

    local config_file
    config_file="$(get_grep_app_config)"
    local config_dir
    config_dir="$(dirname "$config_file")"

    mkdir -p "$config_dir"

    # Create or update config
    if [[ -f "$config_file" ]]; then
        python3 - "${config_file}" "${key}" "${value}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]

try:
    data = json.loads(config_path.read_text(encoding='utf-8'))
except:
    data = {}

# Convert value type
if value.isdigit():
    value = int(value)
elif value.lower() in ('true', 'false'):
    value = value.lower() == 'true'

data[key] = value
config_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f"Set {key} = {value}")
PY
    else
        # Create new config
        cat > "$config_file" <<EOF
{
  "$key": $(
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    elif [[ "$value" == "true" || "$value" == "false" ]]; then
        echo "$value"
    else
        echo "\"$value\""
    fi
  )
}
EOF
        log_success "Created config file: $config_file"
    fi

    log_success "Configuration updated"
}

reset_config() {
    local config_file
    config_file="$(get_grep_app_config)"

    if [[ -f "$config_file" ]]; then
        rm "$config_file"
        log_success "Configuration reset to defaults"
    else
        log_info "No custom configuration to reset"
    fi
}

# ============================================================================
# Enable/Disable/Status Commands
# ============================================================================

cmd_enable() {
    local mode="${1:-stdio}"
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode|-m)
                mode="$2"
                shift 2
                ;;
            --force|-f)
                force=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    case "$mode" in
        stdio|http)
            ;;
        *)
            log_error "Invalid mode: $mode (must be 'stdio' or 'http')"
            return 1
            ;;
    esac

    log_info "Enabling Grep-App MCP in ${mode} mode..."

    local settings_file
    settings_file="$(get_settings_file)"

    # Ensure settings file exists
    if [[ ! -f "$settings_file" ]]; then
        log_warn "settings.json not found, creating default configuration..."
        local fake_home
        fake_home="$(dirname "$settings_file")"
        mkdir -p "$fake_home"

        cat > "$settings_file" <<'EOF'
{
  "mcpServers": {},
  "modelProviders": {},
  "model": {}
}
EOF
    fi

    # Update settings
    if [[ "$mode" == "stdio" ]]; then
        enable_stdio_mode "$settings_file"
    else
        enable_http_mode "$settings_file"
    fi

    # Create enabled symlink
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    mkdir -p "$enabled_dir"

    if [[ ! -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        ln -sf "$PLUGIN_DIR" "${enabled_dir}/${PLUGIN_NAME}"
        log_success "Created enabled symlink: ${enabled_dir}/${PLUGIN_NAME}"
    fi

    log_success "Grep-App MCP enabled successfully!"
}

enable_stdio_mode() {
    local settings_file="$1"

    log_info "Configuring stdio mode..."

    python3 - "${settings_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

mcp_servers = data.setdefault('mcpServers', {})

# Configure grep-app for stdio mode
mcp_servers['grep-app'] = {
    'command': 'bash',
    'args': ['-c', 'grep-app main.sh mcp-stdio'],
    'protocol': 'mcp',
    'enabled': True,
    'trust': False,
    'excludeTools': []
}

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print("Updated settings.json for stdio mode")
PY
}

enable_http_mode() {
    local settings_file="$1"

    log_info "Configuring HTTP mode..."

    local port="${GREP_APP_HTTP_PORT:-8765}"

    python3 - "${settings_file}" "${port}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
port = sys.argv[2] if len(sys.argv) > 2 else "8765"

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

mcp_servers = data.setdefault('mcpServers', {})

# Configure grep-app for HTTP mode
mcp_servers['grep-app'] = {
    'url': f'http://localhost:{port}/mcp',
    'protocol': 'mcp',
    'enabled': True,
    'trust': False,
    'excludeTools': []
}

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f"Updated settings.json for HTTP mode (port {port})")
PY
}

cmd_disable() {
    log_info "Disabling Grep-App MCP..."

    local settings_file
    settings_file="$(get_settings_file)"

    if [[ ! -f "$settings_file" ]]; then
        log_warn "settings.json not found, nothing to disable"
        return 0
    fi

    python3 - "${settings_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except Exception as e:
    print(f"Error reading settings: {e}")
    sys.exit(1)

# Disable in mcpServers
mcp_servers = data.get('mcpServers', {})
if 'grep-app' in mcp_servers:
    mcp_servers['grep-app']['enabled'] = False
    print("Disabled grep-app in mcpServers")
else:
    print("grep-app not found in mcpServers")

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print("Settings updated")
PY

    # Remove enabled symlink
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    if [[ -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        rm "${enabled_dir}/${PLUGIN_NAME}"
        log_info "Removed enabled symlink"
    fi

    log_success "Grep-App MCP disabled"
}

cmd_status() {
    log_info "Checking Grep-App MCP status..."
    echo ""

    local settings_file
    settings_file="$(get_settings_file)"

    # Check if enabled
    local enabled=false
    local mode="unknown"

    if [[ -f "$settings_file" ]]; then
        local status_info
        status_info=$(python3 - "${settings_file}" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except:
    print("disabled|unknown")
    sys.exit(0)

mcp_servers = data.get('mcpServers', {})
grep_app = mcp_servers.get('grep-app', {})

enabled = grep_app.get('enabled', False)

# Determine mode
if 'command' in grep_app:
    mode = "stdio"
elif 'url' in grep_app:
    url = grep_app.get('url', '')
    if url.startswith('http://') or url.startswith('https://'):
        mode = "http"
    else:
        mode = "custom"
else:
    mode = "unknown"

print(f"{'enabled' if enabled else 'disabled'}|{mode}")
PY
)
        enabled=$(echo "$status_info" | cut -d'|' -f1)
        mode=$(echo "$status_info" | cut -d'|' -f2)
    fi

    # Check if plugin is enabled
    local plugin_enabled=false
    local enabled_dir
    enabled_dir="$(get_enabled_dir)"
    if [[ -L "${enabled_dir}/${PLUGIN_NAME}" ]]; then
        plugin_enabled=true
    fi

    # Display status
    echo "Grep-App MCP Status"
    echo "==================="
    echo ""

    if [[ "$plugin_enabled" == "true" ]]; then
        echo "Plugin:      ✓ Enabled"
    else
        echo "Plugin:      ✗ Disabled"
    fi

    if [[ "$enabled" == "enabled" ]]; then
        echo "Service:     ✓ Enabled"
    else
        echo "Service:     ✗ Disabled"
    fi

    echo "Mode:        ${mode}"

    # Platform info
    echo ""
    echo "Platform:"
    if is_termux; then
        echo "  - Running on: Termux (Android)"
    else
        echo "  - Running on: GNU/Linux"
    fi

    # Dependency check
    echo ""
    echo "Dependencies:"
    if check_grep; then
        echo "  - grep:      ✓ Installed ($(grep --version 2>&1 | head -1))"
    else
        echo "  - grep:      ✗ Not installed"
    fi

    if check_find; then
        echo "  - find:      ✓ Installed"
    else
        echo "  - find:      ✗ Not installed"
    fi

    if check_python3; then
        echo "  - python3:   ✓ Installed ($(python3 --version 2>/dev/null))"
    else
        echo "  - python3:   ✗ Not installed"
    fi

    echo ""

    # Recommendations
    if [[ "$enabled" == "disabled" ]]; then
        echo "Recommendation: Run 'oml mcps grep-app enable' to enable"
    fi
}

# ============================================================================
# MCP Tools - JSON-RPC Interface
# ============================================================================

# Output JSON result
output_json() {
    local query="$1"
    local pattern="$2"
    local results="$3"

    python3 - "${query}" "${pattern}" <<PY
import json
import sys
from pathlib import Path

query = sys.argv[1] if len(sys.argv) > 1 else ""
pattern = sys.argv[2] if len(sys.argv) > 2 else ""

# Read stdin for results
import sys
results = sys.stdin.read().strip()

matches = []
for line in results.split('\n'):
    if not line:
        continue
    # Parse grep output: file:line_num:content
    parts = line.split(':', 2)
    if len(parts) >= 3:
        matches.append({
            'file': parts[0],
            'line': int(parts[1]) if parts[1].isdigit() else 0,
            'content': parts[2]
        })
    elif len(parts) == 2:
        matches.append({
            'file': parts[0],
            'line': 0,
            'content': parts[1]
        })

result = {
    'query': query,
    'pattern': pattern,
    'matches': matches[:100],  # Limit to 100
    'count': len(matches)
}

print(json.dumps(result, ensure_ascii=False))
PY
}

# MCP stdio server mode
mcp_stdio() {
    # MCP JSON-RPC over stdio
    # Reads JSON-RPC requests from stdin, writes responses to stdout

    while IFS= read -r line; do
        process_mcp_request "$line"
    done
}

# Process MCP JSON-RPC request
process_mcp_request() {
    local request="$1"

    python3 - "$request" <<'PY'
import json
import sys
import subprocess
import os

def run_grep_command(cmd, args):
    """Run grep command and return output"""
    try:
        result = subprocess.run(
            ['grep'] + args,
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout, result.returncode
    except subprocess.TimeoutExpired:
        return "", -1
    except Exception as e:
        return str(e), -1

def grep_search_intent(query, path=".", extensions=None, max_results=100):
    """Natural language search - converts intent to grep pattern"""
    # Simple keyword extraction
    keywords = []
    if 'function' in query.lower():
        keywords.extend(['function', 'def ', 'fn ', 'func '])
    if 'class' in query.lower():
        keywords.extend(['class ', 'interface ', 'type '])
    if 'import' in query.lower():
        keywords.extend(['import ', 'require(', 'from '])
    if 'todo' in query.lower() or 'fixme' in query.lower():
        keywords.extend(['TODO', 'FIXME', 'XXX'])
    if 'error' in query.lower() or 'exception' in query.lower():
        keywords.extend(['error', 'Error', 'exception', 'Exception'])
    if 'log' in query.lower() or 'print' in query.lower():
        keywords.extend(['console.log', 'print(', 'log.'])

    if not keywords:
        keywords = query.split()

    pattern = '|'.join(keywords)

    grep_args = ['-E', '-i', '-n', '-H', '-r', '--max-count', str(max_results)]
    if extensions:
        grep_args.extend(['--include', f'*.{extensions[0]}'])

    stdout, rc = run_grep_command('grep', grep_args + [pattern, path])

    matches = []
    for line in stdout.strip().split('\n'):
        if line:
            parts = line.split(':', 2)
            if len(parts) >= 3:
                matches.append({
                    'file': parts[0],
                    'line': int(parts[1]) if parts[1].isdigit() else 0,
                    'content': parts[2]
                })

    return {
        'query': query,
        'pattern': pattern,
        'matches': matches,
        'count': len(matches)
    }

def grep_regex(pattern, path=".", extensions=None, max_results=100, ignore_case=False):
    """Regular expression search"""
    grep_args = ['-E', '-n', '-H', '-r', '--max-count', str(max_results)]
    if ignore_case:
        grep_args.append('-i')
    if extensions:
        for ext in extensions:
            grep_args.extend(['--include', f'*.{ext}'])

    stdout, rc = run_grep_command('grep', grep_args + [pattern, path])

    matches = []
    for line in stdout.strip().split('\n'):
        if line:
            parts = line.split(':', 2)
            if len(parts) >= 3:
                matches.append({
                    'file': parts[0],
                    'line': int(parts[1]) if parts[1].isdigit() else 0,
                    'content': parts[2]
                })

    return {
        'pattern': pattern,
        'matches': matches,
        'count': len(matches)
    }

def grep_count(pattern, path=".", extensions=None, ignore_case=False):
    """Count matches"""
    grep_args = ['-E', '-c', '-r']
    if ignore_case:
        grep_args.append('-i')
    if extensions:
        for ext in extensions:
            grep_args.extend(['--include', f'*.{ext}'])

    stdout, rc = run_grep_command('grep', grep_args + [pattern, path])

    total = 0
    by_file = {}
    for line in stdout.strip().split('\n'):
        if ':' in line:
            parts = line.rsplit(':', 1)
            if len(parts) == 2 and parts[1].isdigit():
                by_file[parts[0]] = int(parts[1])
                total += int(parts[1])

    return {
        'pattern': pattern,
        'total_matches': total,
        'files_with_matches': len(by_file),
        'by_file': by_file
    }

def grep_files_with_matches(pattern, path=".", extensions=None, max_results=100, ignore_case=False):
    """List files with matches"""
    grep_args = ['-E', '-l', '-r']
    if ignore_case:
        grep_args.append('-i')
    if extensions:
        for ext in extensions:
            grep_args.extend(['--include', f'*.{ext}'])

    stdout, rc = run_grep_command('grep', grep_args + [pattern, path])

    files = [f for f in stdout.strip().split('\n') if f]
    return {
        'pattern': pattern,
        'files': files[:max_results],
        'count': min(len(files), max_results)
    }

def grep_advanced(pattern, path=".", options=None):
    """Advanced search with full options"""
    if options is None:
        options = {}

    grep_args = ['-E', '-n', '-H', '-r']

    if options.get('ignore_case'):
        grep_args.append('-i')
    if options.get('max_results'):
        grep_args.extend(['--max-count', str(options['max_results'])])
    if options.get('context'):
        grep_args.extend(['-C', str(options['context'])])
    if options.get('extensions'):
        for ext in options['extensions']:
            grep_args.extend(['--include', f'*.{ext}'])
    if options.get('exclude_dirs'):
        for d in options['exclude_dirs']:
            grep_args.extend(['--exclude-dir', d])

    stdout, rc = run_grep_command('grep', grep_args + [pattern, path])

    matches = []
    for line in stdout.strip().split('\n'):
        if line:
            parts = line.split(':', 2)
            if len(parts) >= 3:
                matches.append({
                    'file': parts[0],
                    'line': int(parts[1]) if parts[1].isdigit() else 0,
                    'content': parts[2]
                })

    return {
        'pattern': pattern,
        'matches': matches,
        'count': len(matches),
        'options_used': options
    }

# Tool definitions
TOOLS = {
    'grep_search_intent': {
        'description': 'Search code using natural language intent',
        'inputSchema': {
            'type': 'object',
            'properties': {
                'query': {'type': 'string', 'description': 'Natural language search query'},
                'path': {'type': 'string', 'description': 'Search path', 'default': '.'},
                'extensions': {'type': 'array', 'items': {'type': 'string'}, 'description': 'File extensions'},
                'max_results': {'type': 'integer', 'description': 'Max results', 'default': 100}
            },
            'required': ['query']
        }
    },
    'grep_regex': {
        'description': 'Search code using regular expression',
        'inputSchema': {
            'type': 'object',
            'properties': {
                'pattern': {'type': 'string', 'description': 'Regex pattern'},
                'path': {'type': 'string', 'description': 'Search path', 'default': '.'},
                'extensions': {'type': 'array', 'items': {'type': 'string'}, 'description': 'File extensions'},
                'max_results': {'type': 'integer', 'description': 'Max results', 'default': 100},
                'ignore_case': {'type': 'boolean', 'description': 'Case insensitive', 'default': False}
            },
            'required': ['pattern']
        }
    },
    'grep_count': {
        'description': 'Count pattern matches in code',
        'inputSchema': {
            'type': 'object',
            'properties': {
                'pattern': {'type': 'string', 'description': 'Regex pattern'},
                'path': {'type': 'string', 'description': 'Search path', 'default': '.'},
                'extensions': {'type': 'array', 'items': {'type': 'string'}, 'description': 'File extensions'},
                'ignore_case': {'type': 'boolean', 'description': 'Case insensitive', 'default': False}
            },
            'required': ['pattern']
        }
    },
    'grep_files_with_matches': {
        'description': 'List files containing pattern matches',
        'inputSchema': {
            'type': 'object',
            'properties': {
                'pattern': {'type': 'string', 'description': 'Regex pattern'},
                'path': {'type': 'string', 'description': 'Search path', 'default': '.'},
                'extensions': {'type': 'array', 'items': {'type': 'string'}, 'description': 'File extensions'},
                'max_results': {'type': 'integer', 'description': 'Max results', 'default': 100},
                'ignore_case': {'type': 'boolean', 'description': 'Case insensitive', 'default': False}
            },
            'required': ['pattern']
        }
    },
    'grep_advanced': {
        'description': 'Advanced search with full options',
        'inputSchema': {
            'type': 'object',
            'properties': {
                'pattern': {'type': 'string', 'description': 'Regex pattern'},
                'path': {'type': 'string', 'description': 'Search path', 'default': '.'},
                'options': {
                    'type': 'object',
                    'description': 'Search options',
                    'properties': {
                        'ignore_case': {'type': 'boolean'},
                        'max_results': {'type': 'integer'},
                        'context': {'type': 'integer'},
                        'extensions': {'type': 'array', 'items': {'type': 'string'}},
                        'exclude_dirs': {'type': 'array', 'items': {'type': 'string'}}
                    }
                }
            },
            'required': ['pattern']
        }
    }
}

def handle_request(request):
    """Handle JSON-RPC request"""
    try:
        req = json.loads(request)
    except json.JSONDecodeError as e:
        return {
            'jsonrpc': '2.0',
            'id': None,
            'error': {'code': -32700, 'message': f'Parse error: {e}'}
        }

    method = req.get('method', '')
    params = req.get('params', {})
    req_id = req.get('id')

    # Handle initialize
    if method == 'initialize':
        return {
            'jsonrpc': '2.0',
            'id': req_id,
            'result': {
                'protocolVersion': '2024-11-05',
                'capabilities': {
                    'tools': {}
                },
                'serverInfo': {
                    'name': 'grep-app',
                    'version': '1.0.0'
                }
            }
        }

    # Handle tools/list
    if method == 'tools/list':
        tools = []
        for name, info in TOOLS.items():
            tools.append({
                'name': name,
                'description': info['description'],
                'inputSchema': info['inputSchema']
            })
        return {
            'jsonrpc': '2.0',
            'id': req_id,
            'result': {'tools': tools}
        }

    # Handle tools/call
    if method == 'tools/call':
        tool_name = params.get('name', '')
        tool_args = params.get('arguments', {})

        try:
            if tool_name == 'grep_search_intent':
                result = grep_search_intent(
                    tool_args.get('query', ''),
                    tool_args.get('path', '.'),
                    tool_args.get('extensions'),
                    tool_args.get('max_results', 100)
                )
            elif tool_name == 'grep_regex':
                result = grep_regex(
                    tool_args.get('pattern', ''),
                    tool_args.get('path', '.'),
                    tool_args.get('extensions'),
                    tool_args.get('max_results', 100),
                    tool_args.get('ignore_case', False)
                )
            elif tool_name == 'grep_count':
                result = grep_count(
                    tool_args.get('pattern', ''),
                    tool_args.get('path', '.'),
                    tool_args.get('extensions'),
                    tool_args.get('ignore_case', False)
                )
            elif tool_name == 'grep_files_with_matches':
                result = grep_files_with_matches(
                    tool_args.get('pattern', ''),
                    tool_args.get('path', '.'),
                    tool_args.get('extensions'),
                    tool_args.get('max_results', 100),
                    tool_args.get('ignore_case', False)
                )
            elif tool_name == 'grep_advanced':
                result = grep_advanced(
                    tool_args.get('pattern', ''),
                    tool_args.get('path', '.'),
                    tool_args.get('options')
                )
            else:
                return {
                    'jsonrpc': '2.0',
                    'id': req_id,
                    'error': {'code': -32601, 'message': f'Tool not found: {tool_name}'}
                }

            return {
                'jsonrpc': '2.0',
                'id': req_id,
                'result': {
                    'content': [{'type': 'text', 'text': json.dumps(result, ensure_ascii=False)}]
                }
            }
        except Exception as e:
            return {
                'jsonrpc': '2.0',
                'id': req_id,
                'error': {'code': -32603, 'message': f'Internal error: {e}'}
            }

    # Handle notifications
    if req_id is None:
        return None

    # Unknown method
    return {
        'jsonrpc': '2.0',
        'id': req_id,
        'error': {'code': -32601, 'message': f'Method not found: {method}'}
    }

# Main
request = sys.argv[1]
response = handle_request(request)
if response:
    print(json.dumps(response))
PY
}

# MCP HTTP server mode
mcp_http() {
    local port="${GREP_APP_HTTP_PORT:-8765}"

    log_info "Starting Grep-App MCP HTTP server on port ${port}..."

    python3 - "${port}" <<'PY'
import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765

# Import grep functions from stdio handler
exec(open(__file__).read().split('# Main')[0].split('# MCP HTTP')[1] if False else '''
def run_grep_command(cmd, args):
    import subprocess
    try:
        result = subprocess.run(['grep'] + args, capture_output=True, text=True, timeout=30)
        return result.stdout, result.returncode
    except:
        return "", -1

def grep_search_intent(query, path=".", extensions=None, max_results=100):
    keywords = []
    for kw in ['function', 'class', 'import', 'todo', 'error', 'log']:
        if kw in query.lower():
            keywords.append(kw)
    if not keywords:
        keywords = query.split()
    pattern = '|'.join(keywords)
    grep_args = ['-E', '-i', '-n', '-H', '-r', '--max-count', str(max_results)]
    stdout, _ = run_grep_command('grep', grep_args + [pattern, path])
    matches = []
    for line in stdout.strip().split('\\n'):
        if line:
            parts = line.split(':', 2)
            if len(parts) >= 3:
                matches.append({'file': parts[0], 'line': int(parts[1]) if parts[1].isdigit() else 0, 'content': parts[2]})
    return {'query': query, 'pattern': pattern, 'matches': matches, 'count': len(matches)}

def grep_regex(pattern, path=".", extensions=None, max_results=100, ignore_case=False):
    grep_args = ['-E', '-n', '-H', '-r', '--max-count', str(max_results)]
    if ignore_case: grep_args.append('-i')
    stdout, _ = run_grep_command('grep', grep_args + [pattern, path])
    matches = []
    for line in stdout.strip().split('\\n'):
        if line:
            parts = line.split(':', 2)
            if len(parts) >= 3:
                matches.append({'file': parts[0], 'line': int(parts[1]) if parts[1].isdigit() else 0, 'content': parts[2]})
    return {'pattern': pattern, 'matches': matches, 'count': len(matches)}

def grep_count(pattern, path=".", extensions=None, ignore_case=False):
    grep_args = ['-E', '-c', '-r']
    if ignore_case: grep_args.append('-i')
    stdout, _ = run_grep_command('grep', grep_args + [pattern, path])
    total, by_file = 0, {}
    for line in stdout.strip().split('\\n'):
        if ':' in line:
            parts = line.rsplit(':', 1)
            if len(parts) == 2 and parts[1].isdigit():
                by_file[parts[0]] = int(parts[1])
                total += int(parts[1])
    return {'pattern': pattern, 'total_matches': total, 'files_with_matches': len(by_file), 'by_file': by_file}

def grep_files_with_matches(pattern, path=".", extensions=None, max_results=100, ignore_case=False):
    grep_args = ['-E', '-l', '-r']
    if ignore_case: grep_args.append('-i')
    stdout, _ = run_grep_command('grep', grep_args + [pattern, path])
    files = [f for f in stdout.strip().split('\\n') if f]
    return {'pattern': pattern, 'files': files[:max_results], 'count': min(len(files), max_results)}

def grep_advanced(pattern, path=".", options=None):
    if options is None: options = {}
    grep_args = ['-E', '-n', '-H', '-r']
    if options.get('ignore_case'): grep_args.append('-i')
    if options.get('max_results'): grep_args.extend(['--max-count', str(options['max_results'])])
    if options.get('context'): grep_args.extend(['-C', str(options['context'])])
    stdout, _ = run_grep_command('grep', grep_args + [pattern, path])
    matches = []
    for line in stdout.strip().split('\\n'):
        if line:
            parts = line.split(':', 2)
            if len(parts) >= 3:
                matches.append({'file': parts[0], 'line': int(parts[1]) if parts[1].isdigit() else 0, 'content': parts[2]})
    return {'pattern': pattern, 'matches': matches, 'count': len(matches), 'options_used': options}
''')

TOOLS = {
    'grep_search_intent': {'description': 'Search code using natural language intent'},
    'grep_regex': {'description': 'Search code using regular expression'},
    'grep_count': {'description': 'Count pattern matches in code'},
    'grep_files_with_matches': {'description': 'List files containing pattern matches'},
    'grep_advanced': {'description': 'Advanced search with full options'}
}

class MCPHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        try:
            req = json.loads(body)
        except json.JSONDecodeError as e:
            self.send_error(400, f'Invalid JSON: {e}')
            return

        method = req.get('method', '')
        params = req.get('params', {})
        req_id = req.get('id')

        result = None

        if method == 'initialize':
            result = {
                'protocolVersion': '2024-11-05',
                'capabilities': {'tools': {}},
                'serverInfo': {'name': 'grep-app', 'version': '1.0.0'}
            }
        elif method == 'tools/list':
            result = {'tools': [{'name': n, 'description': i['description']} for n, i in TOOLS.items()]}
        elif method == 'tools/call':
            tool_name = params.get('name', '')
            tool_args = params.get('arguments', {})
            if tool_name == 'grep_search_intent':
                result = grep_search_intent(tool_args.get('query', ''), tool_args.get('path', '.'))
            elif tool_name == 'grep_regex':
                result = grep_regex(tool_args.get('pattern', ''), tool_args.get('path', '.'))
            elif tool_name == 'grep_count':
                result = grep_count(tool_args.get('pattern', ''), tool_args.get('path', '.'))
            elif tool_name == 'grep_files_with_matches':
                result = grep_files_with_matches(tool_args.get('pattern', ''), tool_args.get('path', '.'))
            elif tool_name == 'grep_advanced':
                result = grep_advanced(tool_args.get('pattern', ''), tool_args.get('path', '.'), tool_args.get('options'))
            else:
                self.send_error(404, f'Tool not found: {tool_name}')
                return
        else:
            self.send_error(404, f'Method not found: {method}')
            return

        response = {'jsonrpc': '2.0', 'id': req_id, 'result': result}
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode('utf-8'))

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok'}).encode('utf-8'))
        elif self.path == '/tools':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'tools': list(TOOLS.keys())}).encode('utf-8'))
        else:
            self.send_error(404, 'Not found')

    def log_message(self, format, *args):
        print(f"[HTTP] {args[0]}")

print(f"Grep-App MCP HTTP server running on http://localhost:{port}")
print("Endpoints:")
print("  POST /          - JSON-RPC endpoint")
print("  GET  /health    - Health check")
print("  GET  /tools     - List available tools")
print("Press Ctrl+C to stop")

server = HTTPServer(('localhost', port), MCPHandler)
try:
    server.serve_forever()
except KeyboardInterrupt:
    print("\\nShutting down...")
    server.shutdown()
PY
}

# ============================================================================
# Help Command
# ============================================================================

show_help() {
    cat <<'EOF'
Grep-App MCP Plugin for OML

Usage: oml mcps grep-app <command> [options]

Commands:
  search <query> [opts]     Natural language code search
  regex <pattern> [opts]    Regular expression search
  count <pattern> [opts]    Count pattern matches
  files <pattern> [opts]    List files with matches
  config <key> [value]      Configuration management
  enable                    Enable Grep-App MCP service
  disable                   Disable Grep-App MCP service
  status                    Show service status

Search Options:
  --path, -p <path>         Search path (default: .)
  --ext, -e <exts>          File extensions (comma-separated)
  --max, -n <num>           Max results (default: 100)
  --exclude-dir <dirs>      Directories to exclude
  --context, -C <num>       Context lines around match
  --ignore-case, -i         Case insensitive search
  --json                    Output in JSON format

Config Keys:
  default_path              Default search path
  max_results               Default max results
  exclude_dirs              Default excluded directories
  http_port                 HTTP server port
  reset                     Reset to defaults

MCP Modes:
  stdio                     Standard I/O mode (default)
  http                      HTTP server mode

Examples:
  # Natural language search
  oml mcps grep-app search "find all Python functions" --ext py
  oml mcps grep-app search "TODO comments" --json

  # Regex search
  oml mcps grep-app regex "def \w+\(" --ext py
  oml mcps grep-app regex "console\.log" --ext js,ts -i

  # Count matches
  oml mcps grep-app count "TODO|FIXME" --ext py,js

  # List matching files
  oml mcps grep-app files "import.*from" --ext py

  # Enable MCP service
  oml mcps grep-app enable --mode stdio
  oml mcps grep-app enable --mode http

  # Configure
  oml mcps grep-app config max_results 200
  oml mcps grep-app config exclude_dirs "node_modules,.git,venv"

MCP Tools (for AI agents):
  - grep_search_intent: Natural language search
  - grep_regex: Regular expression search
  - grep_count: Count matches
  - grep_files_with_matches: List matching files
  - grep_advanced: Advanced search with options

Platform Support:
  - Termux (Android): Full support
  - GNU/Linux: Full support

See also:
  oml mcps list           - List all MCP services
  oml mcps status         - Show MCP status
EOF
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        # Search commands
        search)
            cmd_search "$@"
            ;;
        regex)
            cmd_regex "$@"
            ;;
        count)
            cmd_count "$@"
            ;;
        files)
            cmd_files "$@"
            ;;

        # Config command
        config)
            cmd_config "$@"
            ;;

        # MCP management
        enable)
            cmd_enable "$@"
            ;;
        disable)
            cmd_disable "$@"
            ;;
        status)
            cmd_status "$@"
            ;;

        # MCP server modes
        mcp-stdio)
            mcp_stdio
            ;;
        mcp-http)
            mcp_http "$@"
            ;;

        # Help
        help|--help|-h|"")
            show_help
            ;;

        # Unknown command
        *)
            log_error "Unknown command: $action"
            echo ""
            show_help
            return 1
            ;;
    esac
}

main "$@"
