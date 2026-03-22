#!/usr/bin/env bash
# Scout Plugin - Utility Functions

set -euo pipefail

# Detect platform
scout_detect_platform() {
    if [[ -d "/data/data/com.termux/files/usr" ]]; then
        echo "termux"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "gnu-linux"
    fi
}

# Get default exclude patterns
scout_get_default_excludes() {
    echo "node_modules,.git,__pycache__,.venv,dist,build,.cache,target,coverage,.idea,.vscode"
}

# Parse exclude patterns to find arguments
scout_parse_excludes() {
    local patterns="${1:-$(scout_get_default_excludes)}"
    local find_args=""
    
    IFS=',' read -ra EXCLUDE_ARR <<< "$patterns"
    for pattern in "${EXCLUDE_ARR[@]}"; do
        pattern=$(echo "$pattern" | xargs)  # trim whitespace
        if [[ -n "$pattern" ]]; then
            find_args="${find_args} -name '${pattern}' -prune -o"
        fi
    done
    
    echo "$find_args"
}

# JSON escape string
scout_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# Get file extension
scout_get_extension() {
    local file="$1"
    local ext="${file##*.}"
    if [[ "$ext" == "$file" ]]; then
        echo ""
    else
        echo "$ext"
    fi
}

# Detect language from file extension
scout_detect_language() {
    local file="$1"
    local ext
    ext=$(scout_get_extension "$file")
    
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
        hs) echo "haskell" ;;
        ex|exs) echo "elixir" ;;
        clj|cljs|cljc) echo "clojure" ;;
        erl|hrl) echo "erlang" ;;
        ml|mli) echo "ocaml" ;;
        swift) echo "swift" ;;
        kt|kts) echo "kotlin" ;;
        scala) echo "scala" ;;
        r|R) echo "r" ;;
        lua) echo "lua" ;;
        sql) echo "sql" ;;
        html|htm) echo "html" ;;
        css|scss|sass|less) echo "css" ;;
        json) echo "json" ;;
        xml) echo "xml" ;;
        yaml|yml) echo "yaml" ;;
        md|markdown) echo "markdown" ;;
        txt) echo "text" ;;
        *) echo "unknown" ;;
    esac
}

# Check if file is a code file
scout_is_code_file() {
    local file="$1"
    local lang
    lang=$(scout_detect_language "$file")
    [[ "$lang" != "unknown" && "$lang" != "text" ]]
}

# Get human readable file size
scout_human_size() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Get current timestamp in ISO format
scout_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# Print error message
scout_error() {
    echo "[ERROR] $*" >&2
}

# Print warning message
scout_warn() {
    echo "[WARN] $*" >&2
}

# Print info message
scout_info() {
    echo "[INFO] $*"
}

# Print success message
scout_success() {
    echo "[OK] $*"
}

# Validate directory exists
scout_validate_dir() {
    local dir="${1:-.}"
    if [[ ! -d "$dir" ]]; then
        scout_error "Directory not found: $dir"
        return 1
    fi
    echo "$dir"
}

# Count lines in file
scout_count_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l < "$file" | tr -d ' '
    else
        echo "0"
    fi
}

# Count non-empty lines
scout_count_code_lines() {
    local file="$1"
    if [[ -f "$file" ]]; then
        grep -cv '^\s*$' "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
