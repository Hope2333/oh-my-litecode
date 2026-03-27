#!/usr/bin/env bash
# Context7 MCP Plugin - Post Install Hook
# Runs after the plugin is installed
#
# This script:
# 1. Validates dependencies (nodejs, npx)
# 2. Creates necessary directories
# 3. Sets up default configuration
# 4. Provides platform-specific instructions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN_NAME="context7"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if node is available
check_node() {
    if command -v node >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if npx is available
check_npx() {
    if command -v npx >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Check if npm is available
check_npm() {
    if command -v npm >/dev/null 2>&1; then
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
    local fake_home
    if [[ -n "${_FAKEHOME:-}" ]]; then
        fake_home="${_FAKEHOME}"
    else
        fake_home="${HOME}"
    fi
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
    
    # Check node
    if check_node; then
        local node_version
        node_version="$(node --version 2>/dev/null || echo 'unknown')"
        log_success "Node.js: ${node_version}"
    else
        missing+=("nodejs")
        log_warn "Node.js: not installed"
    fi
    
    # Check npm
    if check_npm; then
        local npm_version
        npm_version="$(npm --version 2>/dev/null || echo 'unknown')"
        log_success "npm: ${npm_version}"
    else
        missing+=("npm")
        log_warn "npm: not installed"
    fi
    
    # Check npx
    if check_npx; then
        log_success "npx: available"
    else
        if ! check_npm; then
            missing+=("npx")
            log_warn "npx: not available (requires npm)"
        fi
    fi
    
    # Report missing dependencies
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_warn "Missing dependencies: ${missing[*]}"
        echo ""
        echo "To install dependencies:"
        if is_termux; then
            echo "  pkg install nodejs npm"
        elif [[ -f "/etc/debian_version" ]]; then
            echo "  sudo apt install nodejs npm"
        elif [[ -f "/etc/arch-release" ]]; then
            echo "  sudo pacman -S nodejs npm"
        elif [[ -f "/etc/redhat-release" ]]; then
            echo "  sudo dnf install nodejs npm"
        else
            echo "  Please install nodejs and npm for your distribution"
        fi
        echo ""
        log_warn "Context7 local mode will not work without nodejs/npm"
        log_warn "Remote mode can still be used with an API key"
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
    mkdir -p "${config_dir}/secrets"
    chmod 700 "${config_dir}/secrets" 2>/dev/null || true
    log_success "Created: ${config_dir}"
    
    # Create qwen settings directory
    local settings_dir
    settings_dir="$(dirname "$(get_settings_file)")"
    mkdir -p "${settings_dir}"
    log_success "Created: ${settings_dir}"
    
    # Create context7 secrets directory
    local fake_home
    if [[ -n "${_FAKEHOME:-}" ]]; then
        fake_home="${_FAKEHOME}"
    else
        fake_home="${HOME}"
    fi
    local ctx7_secrets="${fake_home}/.qwenx/secrets"
    mkdir -p "${ctx7_secrets}"
    chmod 700 "${ctx7_secrets}" 2>/dev/null || true
    log_success "Created: ${ctx7_secrets}"
}

step_init_settings() {
    log_info "Initializing settings..."
    
    local settings_file
    settings_file="$(get_settings_file)"
    
    if [[ ! -f "$settings_file" ]]; then
        # Create default settings
        cat > "$settings_file" <<'EOF'
{
  "mcpServers": {},
  "modelProviders": {
    "openai": []
  },
  "model": {
    "id": "",
    "name": ""
  },
  "context7": {
    "enabled": false,
    "mode": "local"
  }
}
EOF
        log_success "Created default settings.json"
    else
        log_info "settings.json already exists, skipping creation"
        
        # Ensure context7 section exists
        python3 - "${settings_file}" <<'PY'
import json
from pathlib import Path

settings_path = Path(sys.argv[1] if len(sys.argv) > 1 else sys.argv[0])
if len(sys.argv) > 1:
    settings_path = Path(sys.argv[1])
else:
    # Handle case where script is called with stdin
    import sys
    settings_path = Path(sys.argv[1])

try:
    data = json.loads(settings_path.read_text(encoding='utf-8'))
except:
    print("Could not read settings.json")
    sys.exit(0)

# Ensure context7 section exists
if 'context7' not in data:
    data['context7'] = {
        'enabled': False,
        'mode': 'local'
    }
    settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print("Added context7 section to settings.json")
else:
    print("context7 section already exists")
PY
    fi
}

step_show_instructions() {
    echo ""
    echo "=============================================="
    echo "  Context7 MCP Plugin Installation Complete"
    echo "=============================================="
    echo ""
    log_success "Plugin installed successfully!"
    echo ""
    
    echo "Next Steps:"
    echo "-----------"
    echo ""
    
    # Check if dependencies are met
    if check_node && check_npx; then
        echo "1. Enable Context7 (local mode - recommended):"
        echo "   oml mcps context7 enable --mode local"
        echo ""
        echo "   This will run Context7 locally using npx."
        echo "   No API key required."
    else
        echo "1. Install dependencies (required for local mode):"
        if is_termux; then
            echo "   pkg install nodejs npm"
        else
            echo "   sudo apt install nodejs npm  # Debian/Ubuntu"
            echo "   # or"
            echo "   sudo pacman -S nodejs npm    # Arch"
        fi
        echo ""
        echo "2. Or use remote mode (requires API key):"
        echo "   oml mcps context7 enable --mode remote --api-key \"sk-xxx\""
    fi
    
    echo ""
    echo "2. Verify installation:"
    echo "   oml mcps context7 status"
    echo ""
    echo "3. Use Context7 with Qwen:"
    echo "   oml qwen \"查询 Python 文档\""
    echo ""
    echo "4. Manage API keys (remote mode):"
    echo "   oml qwen ctx7 set <your-api-key>"
    echo "   oml qwen ctx7 list"
    echo ""
    
    echo "Configuration Files:"
    echo "--------------------"
    echo "  Settings:  $(get_settings_file)"
    echo "  Secrets:   $(get_oml_config_dir)/secrets/"
    echo "  Logs:      $(get_oml_config_dir)/logs/"
    echo ""
    
    echo "Help:"
    echo "-----"
    echo "  oml mcps context7 help    - Show all commands"
    echo "  oml qwen ctx7 help        - Context7 key management"
    echo ""
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    echo ""
    log_info "Running post-install hook for Context7 MCP plugin..."
    echo ""
    
    step_check_platform
    echo ""
    
    step_check_dependencies
    echo ""
    
    step_create_directories
    echo ""
    
    step_init_settings
    echo ""
    
    step_show_instructions
}

main "$@"
