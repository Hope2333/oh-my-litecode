#!/usr/bin/env bash
# Librarian Subagent - Utility Functions
# Common utilities for logging, validation, and formatting

set -euo pipefail

# Color codes for output
LIBRARIAN_COLOR_RESET="\033[0m"
LIBRARIAN_COLOR_GREEN="\033[32m"
LIBRARIAN_COLOR_YELLOW="\033[33m"
LIBRARIAN_COLOR_RED="\033[31m"
LIBRARIAN_COLOR_BLUE="\033[34m"
LIBRARIAN_COLOR_CYAN="\033[36m"

# Logging functions
librarian_log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${msg}" >> "${LIBRARIAN_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

librarian_info() {
    echo -e "${LIBRARIAN_COLOR_BLUE}[INFO]${LIBRARIAN_COLOR_RESET} $*" >&2
    librarian_log "INFO" "$*"
}

librarian_success() {
    echo -e "${LIBRARIAN_COLOR_GREEN}[SUCCESS]${LIBRARIAN_COLOR_RESET} $*" >&2
    librarian_log "SUCCESS" "$*"
}

librarian_warn() {
    echo -e "${LIBRARIAN_COLOR_YELLOW}[WARN]${LIBRARIAN_COLOR_RESET} $*" >&2
    librarian_log "WARN" "$*"
}

librarian_error() {
    echo -e "${LIBRARIAN_COLOR_RED}[ERROR]${LIBRARIAN_COLOR_RESET} $*" >&2
    librarian_log "ERROR" "$*"
}

# Validate directory exists
librarian_validate_dir() {
    local dir="${1:-.}"
    if [[ ! -d "$dir" ]]; then
        librarian_error "Directory not found: $dir"
        return 1
    fi
    # Resolve to absolute path
    cd "$dir" && pwd
}

# Validate file exists
librarian_validate_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        librarian_error "File not found: $file"
        return 1
    fi
    echo "$file"
}

# Check if command exists
librarian_check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        librarian_error "Required command not found: $cmd"
        return 1
    fi
    return 0
}

# Check required dependencies
librarian_check_deps() {
    local deps=("bash" "python3" "curl" "jq")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        librarian_error "Missing dependencies: ${missing[*]}"
        return 1
    fi
    return 0
}

# URL encode
librarian_url_encode() {
    local string="$1"
    python3 -c "
import urllib.parse
print(urllib.parse.quote('''${string}'''))
"
}

# JSON escape
librarian_json_escape() {
    local string="$1"
    printf '%s' "$string" | python3 -c "
import json, sys
print(json.dumps(sys.stdin.read()))
"
}

# Generate unique ID
librarian_generate_id() {
    python3 -c "import uuid; print(str(uuid.uuid4())[:8])"
}

# Get current timestamp
librarian_timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

# Calculate hash for deduplication
librarian_hash() {
    local content="$1"
    printf '%s' "$content" | md5sum | cut -d' ' -f1
}

# Format timestamp for display
librarian_format_timestamp() {
    local ts="$1"
    python3 -c "
from datetime import datetime
try:
    dt = datetime.fromisoformat('${ts}'.replace('Z', '+00:00'))
    print(dt.strftime('%Y-%m-%d %H:%M'))
except:
    print('${ts}')
"
}

# Truncate text
librarian_truncate() {
    local text="$1"
    local max_length="${2:-100}"
    if [[ ${#text} -gt $max_length ]]; then
        echo "${text:0:$((max_length-3))}..."
    else
        echo "$text"
    fi
}

# Parse JSON field safely
librarian_json_get() {
    local json="$1"
    local field="$2"
    echo "$json" | jq -r ".${field} // empty" 2>/dev/null || echo ""
}

# Parse nested JSON field
librarian_json_get_nested() {
    local json="$1"
    local path="$2"
    echo "$json" | jq -r "${path} // empty" 2>/dev/null || echo ""
}

# Check if running in Termux
librarian_is_termux() {
    [[ -d "/data/data/com.termux/files/usr" ]]
}

# Get platform name
librarian_get_platform() {
    if librarian_is_termux; then
        echo "termux"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "gnu-linux"
    fi
}

# Get config directory
librarian_get_config_dir() {
    local platform
    platform=$(librarian_get_platform)
    echo "${HOME}/.local/share/oml/librarian"
}

# Get cache directory
librarian_get_cache_dir() {
    echo "${HOME}/.local/cache/oml/librarian"
}

# Initialize directories
librarian_init_dirs() {
    local config_dir
    local cache_dir
    
    config_dir=$(librarian_get_config_dir)
    cache_dir=$(librarian_get_cache_dir)
    
    mkdir -p "$config_dir"
    mkdir -p "$cache_dir"
    mkdir -p "${cache_dir}/search"
    mkdir -p "${cache_dir}/query"
    mkdir -p "${cache_dir}/websearch"
    mkdir -p "${cache_dir}/compile"
    
    echo "$config_dir"
}

# Load configuration
librarian_load_config() {
    local config_file
    config_file="$(librarian_get_config_dir)/config.json"
    
    if [[ -f "$config_file" ]]; then
        cat "$config_file"
    else
        echo "{}"
    fi
}

# Save configuration
librarian_save_config() {
    local config="$1"
    local config_file
    config_file="$(librarian_get_config_dir)/config.json"
    
    echo "$config" | jq '.' > "$config_file"
}

# Get configuration value
librarian_config_get() {
    local key="$1"
    local default="${2:-}"
    local config
    config=$(librarian_load_config)
    local value
    value=$(echo "$config" | jq -r ".${key} // empty" 2>/dev/null || echo "")
    
    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Set configuration value
librarian_config_set() {
    local key="$1"
    local value="$2"
    local config
    config=$(librarian_load_config)
    
    config=$(echo "$config" | jq ".${key} = ${value}")
    librarian_save_config "$config"
}
