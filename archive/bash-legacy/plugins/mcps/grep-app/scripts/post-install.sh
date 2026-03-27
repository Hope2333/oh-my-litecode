#!/usr/bin/env bash
# Grep-App MCP Plugin - Post Install Hook
# Runs after the plugin is installed
#
# This script:
# 1. Validates dependencies (grep, find, python3)
# 2. Creates necessary directories
# 3. Sets up default configuration
# 4. Provides platform-specific instructions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN_NAME="grep-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if running on Termux
is_termux() {
    [[ -d "/data/data/com.termux/files/usr" ]]
}

# Check if running on GNU/Linux
is_gnu_linux() {
    ! is_termux
}

# Get platform name
get_platform() {
    if is_termux; then
        echo "Termux (Android)"
    else
        echo "GNU/Linux"
    fi
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

# ============================================================================
# Installation Steps
# ============================================================================

step_check_platform() {
    log_info "Detecting platform..."
    local platform
    platform="$(get_platform)"
    log_success "Running on: ${platform}"
}

step_check_dependencies() {
    log_info "Checking dependencies..."

    local missing=()

    # Check grep
    if check_grep; then
        local grep_version
        grep_version="$(grep --version 2>&1 | head -1 | cut -d' ' -f3-4)"
        log_success "grep: ${grep_version}"
    else
        missing+=("grep")
        log_warn "grep: not installed"
    fi

    # Check find
    if check_find; then
        log_success "find: available"
    else
        missing+=("find")
        log_warn "find: not installed"
    fi

    # Check python3
    if check_python3; then
        local python_version
        python_version="$(python3 --version 2>/dev/null)"
        log_success "python3: ${python_version}"
    else
        missing+=("python3")
        log_warn "python3: not installed"
    fi

    # Report missing dependencies
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_warn "Missing dependencies: ${missing[*]}"
        echo ""
        echo "To install dependencies:"
        if is_termux; then
            echo "  pkg install grep find python3"
        elif [[ -f "/etc/debian_version" ]]; then
            echo "  sudo apt install grep find python3"
        elif [[ -f "/etc/arch-release" ]]; then
            echo "  sudo pacman -S grep find python3"
        elif [[ -f "/etc/redhat-release" ]]; then
            echo "  sudo dnf install grep find python3"
        else
            echo "  Please install missing packages for your distribution"
        fi
        echo ""
        log_warn "Grep-App will not work without these dependencies"
    fi
}

step_create_directories() {
    log_info "Creating directories..."

    # Create OML config directory
    local config_dir
    config_dir="$(get_oml_config_dir)"
    mkdir -p "${config_dir}"
    mkdir -p "${config_dir}/logs"
    mkdir -p "${config_dir}/cache"
    mkdir -p "${config_dir}/cache/grep-app"
    mkdir -p "${config_dir}/secrets"
    chmod 700 "${config_dir}/secrets" 2>/dev/null || true

    # Create grep-app config directory
    local grep_app_config_dir="${config_dir}/grep-app"
    mkdir -p "${grep_app_config_dir}"

    log_success "Created: ${config_dir}"
    log_success "Created: ${grep_app_config_dir}"
}

step_init_config() {
    log_info "Initializing configuration..."

    local config_dir
    config_dir="$(get_oml_config_dir)"
    local config_file="${config_dir}/grep-app/config.json"

    if [[ ! -f "$config_file" ]]; then
        # Create default config
        cat > "$config_file" <<'EOF'
{
  "default_path": ".",
  "max_results": 100,
  "exclude_dirs": ["node_modules", ".git", "__pycache__", ".venv", "venv", "dist", "build"],
  "http_port": 8765
}
EOF
        log_success "Created default config: ${config_file}"
    else
        log_info "Config file already exists, skipping creation"
    fi
}

step_init_settings() {
    log_info "Initializing settings..."

    local settings_file
    settings_file="$(get_settings_file)"

    if [[ ! -f "$settings_file" ]]; then
        # Create default settings
        local settings_dir
        settings_dir="$(dirname "$settings_file")"
        mkdir -p "$settings_dir"

        cat > "$settings_file" <<'EOF'
{
  "mcpServers": {},
  "modelProviders": {},
  "model": {}
}
EOF
        log_success "Created default settings: ${settings_file}"
    else
        log_info "Settings file already exists"
    fi
}

step_show_instructions() {
    echo ""
    echo "=============================================="
    echo "  Grep-App MCP Plugin Installation Complete"
    echo "=============================================="
    echo ""
    log_success "Plugin installed successfully!"
    echo ""

    echo "Features:"
    echo "---------"
    echo "  - Natural language code search"
    echo "  - Regular expression search"
    echo "  - Match counting"
    echo "  - File listing"
    echo "  - MCP tools for AI agents"
    echo ""

    echo "Quick Start:"
    echo "------------"
    echo ""

    # Check if dependencies are met
    if check_grep && check_find && check_python3; then
        echo "1. Enable Grep-App MCP (stdio mode - recommended):"
        echo "   oml mcps grep-app enable --mode stdio"
        echo ""
        echo "2. Or enable HTTP mode:"
        echo "   oml mcps grep-app enable --mode http"
        echo ""
    else
        log_warn "Some dependencies are missing. Install them first:"
        if is_termux; then
            echo "   pkg install grep find python3"
        else
            echo "   sudo apt install grep find python3"
        fi
        echo ""
    fi

    echo "3. Verify installation:"
    echo "   oml mcps grep-app status"
    echo ""

    echo "Usage Examples:"
    echo "---------------"
    echo ""
    echo "  # Natural language search"
    echo "  oml mcps grep-app search \"find all Python functions\" --ext py"
    echo ""
    echo "  # Regex search"
    echo "  oml mcps grep-app regex \"def \\w+(\" --ext py"
    echo ""
    echo "  # Count matches"
    echo "  oml mcps grep-app count \"TODO|FIXME\" --ext py,js"
    echo ""
    echo "  # List matching files"
    echo "  oml mcps grep-app files \"import.*from\" --ext py"
    echo ""

    echo "Configuration:"
    echo "--------------"
    echo "  Config:    $(get_oml_config_dir)/grep-app/config.json"
    echo "  Settings:  $(get_settings_file)"
    echo "  Logs:      $(get_oml_config_dir)/logs/"
    echo ""

    echo "MCP Tools (for AI agents):"
    echo "--------------------------"
    echo "  - grep_search_intent: Natural language search"
    echo "  - grep_regex: Regular expression search"
    echo "  - grep_count: Count pattern matches"
    echo "  - grep_files_with_matches: List matching files"
    echo "  - grep_advanced: Advanced search with options"
    echo ""

    echo "Help:"
    echo "-----"
    echo "  oml mcps grep-app help    - Show all commands"
    echo ""
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    echo ""
    log_info "Running post-install hook for Grep-App MCP plugin..."
    echo ""

    step_check_platform
    echo ""

    step_check_dependencies
    echo ""

    step_create_directories
    echo ""

    step_init_config
    step_init_settings
    echo ""

    step_show_instructions
}

main "$@"
