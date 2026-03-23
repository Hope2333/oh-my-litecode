#!/usr/bin/env bash
# OML Qwenx Deployment Module
# Manages Qwenx installation, configuration, and updates
#
# Usage:
#   oml qwen deploy      # Deploy Qwenx
#   oml qwen update      # Update Qwenx
#   oml qwen config      # Configure Qwenx
#   oml qwen status      # Show Qwenx status

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
QWENX_HOME="${QWENX_HOME:-${HOME}/.local/home/qwenx}"
QWENX_CONFIG="${QWENX_HOME}/.qwen"
OML_ROOT="${OML_ROOT:-${HOME}/develop/oh-my-litecode}"

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

if [[ -f "${LIB_DIR}/system-detect.sh" ]]; then
    source "${LIB_DIR}/system-detect.sh"
    detect_system
fi

if [[ "$SYSTEM" == "termux" ]] && [[ -f "${LIB_DIR}/android-perms.sh" ]]; then
    source "${LIB_DIR}/android-perms.sh"
fi

# Print step
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Print success
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print error
print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Print warning
print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing=()
    
    if ! command -v git >/dev/null 2>&1; then
        missing+=("git")
    fi
    
    if ! command -v node >/dev/null 2>&1; then
        missing+=("node")
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        missing+=("python3")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing: ${missing[*]}"
        return 1
    fi
    
    print_success "Prerequisites satisfied"
}

# Detect Android permissions
detect_android_perms_wrapper() {
    if [[ "$SYSTEM" == "termux" ]]; then
        print_step "Detecting Android permissions..."
        
        if check_root; then
            print_success "Root access available"
            return 0
        elif check_shizuku; then
            print_success "Shizuku available"
            return 0
        elif check_adb_shell; then
            print_warning "ADB Shell (limited permissions)"
            return 0
        else
            print_warning "Normal user (limited permissions)"
            return 0
        fi
    fi
}

# Create Qwenx directories
create_directories() {
    print_step "Creating Qwenx directories..."
    
    mkdir -p "${QWENX_HOME}/.qwen"
    mkdir -p "${QWENX_HOME}/.qwenx/secrets"
    mkdir -p "${QWENX_HOME}/.oml/sessions"
    mkdir -p "${QWENX_HOME}/.oml/cache"
    
    chmod 700 "${QWENX_HOME}"
    chmod 700 "${QWENX_HOME}/.qwenx/secrets"
    
    print_success "Directories created"
}

# Create default configuration
create_config() {
    print_step "Creating default configuration..."
    
    local settings_file="${QWENX_CONFIG}/settings.json"
    
    if [[ ! -f "$settings_file" ]]; then
        cat > "$settings_file" <<EOF
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "protocol": "mcp",
      "enabled": true,
      "trust": false
    }
  },
  "modelProviders": {
    "openai": []
  },
  "model": {
    "id": "default",
    "name": "Default Model"
  }
}
EOF
        print_success "Default config created"
    else
        print_warning "Config already exists"
    fi
}

# Setup skills directory
setup_skills() {
    print_step "Setting up skills..."
    
    local skills_dir="${QWENX_CONFIG}/skills"
    
    if [[ ! -d "$skills_dir" ]]; then
        mkdir -p "$skills_dir"
        
        # Create example skill
        cat > "${skills_dir}/example-skill/SKILL.md" <<'EOF'
---
name: example-skill
description: Example skill for Qwenx
version: 1.0.0
---

# Example Skill

This is an example skill template.

## Usage

```bash
oml qwen "use example-skill"
```

## Features

- Feature 1
- Feature 2

EOF
        
        print_success "Skills directory created"
    fi
}

# Setup agents directory
setup_agents() {
    print_step "Setting up agents..."
    
    local agents_dir="${QWENX_CONFIG}/agents"
    
    if [[ ! -d "$agents_dir" ]]; then
        mkdir -p "$agents_dir"
        
        # Create example agent
        cat > "${agents_dir}/example.md" <<'EOF'
---
name: example-agent
description: Example agent configuration
version: 1.0.0
---

# Example Agent

This is an example agent template.

## Configuration

```json
{
  "model": "qwen-plus",
  "temperature": 0.7,
  "max_tokens": 2000
}
```

## Usage

```bash
oml qwen --agent example-agent
```

EOF
        
        print_success "Agents directory created"
    fi
}

# Link OML plugins
link_oml_plugins() {
    print_step "Linking OML plugins..."
    
    local oml_plugins="${OML_ROOT}/plugins"
    local qwen_plugins="${QWENX_CONFIG}/plugins"
    
    if [[ -d "$oml_plugins" ]]; then
        if [[ ! -L "$qwen_plugins" ]]; then
            ln -sf "$oml_plugins" "$qwen_plugins"
            print_success "OML plugins linked"
        else
            print_warning "Plugins already linked"
        fi
    else
        print_warning "OML plugins not found"
    fi
}

# Deploy Qwenx
cmd_deploy() {
    print_step "Deploying Qwenx..."
    
    detect_android_perms_wrapper
    check_prerequisites
    create_directories
    create_config
    setup_skills
    setup_agents
    link_oml_plugins
    
    print_success "Qwenx deployed successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Configure API key: oml qwen-key add <key>"
    echo "  2. Start using: oml qwen"
    echo "  3. Manage plugins: oml qwen-oauth list"
}

# Update Qwenx
cmd_update() {
    print_step "Updating Qwenx..."
    
    # Update OML plugins
    if [[ -f "${OML_ROOT}/bin/oml-update.sh" ]]; then
        bash "${OML_ROOT}/bin/oml-update.sh" plugins
    fi
    
    # Update Qwenx config
    if [[ -f "${QWENX_CONFIG}/settings.json" ]]; then
        print_warning "Config update not yet implemented"
    fi
    
    print_success "Qwenx updated"
}

# Show Qwenx status
cmd_status() {
    echo "Qwenx Status:"
    echo ""
    
    # Directories
    echo "Directories:"
    echo "  Home: ${QWENX_HOME}"
    echo "  Config: ${QWENX_CONFIG}"
    echo "  Skills: ${QWENX_CONFIG}/skills"
    echo "  Agents: ${QWENX_CONFIG}/agents"
    echo ""
    
    # Android permissions
    if [[ "$SYSTEM" == "termux" ]]; then
        echo "Android Permissions:"
        if check_root; then
            echo "  Root: ✓"
        elif check_shizuku; then
            echo "  Shizuku: ✓"
        elif check_adb_shell; then
            echo "  ADB Shell: ✓"
        else
            echo "  Normal: ✓"
        fi
        echo ""
    fi
    
    # Configuration
    echo "Configuration:"
    if [[ -f "${QWENX_CONFIG}/settings.json" ]]; then
        echo "  Settings: ✓"
    else
        echo "  Settings: ✗"
    fi
    
    if [[ -d "${QWENX_CONFIG}/skills" ]]; then
        echo "  Skills: ✓"
    else
        echo "  Skills: ✗"
    fi
    
    if [[ -d "${QWENX_CONFIG}/agents" ]]; then
        echo "  Agents: ✓"
    else
        echo "  Agents: ✗"
    fi
    echo ""
    
    # Plugins
    echo "Plugins:"
    if [[ -L "${QWENX_CONFIG}/plugins" ]]; then
        echo "  OML Plugins: ✓ (linked)"
    else
        echo "  OML Plugins: ✗"
    fi
}

# Show help
print_help() {
    cat <<EOF
OML Qwenx Deployment

Usage: oml qwen <command>

Commands:
  deploy      Deploy Qwenx with default configuration
  update      Update Qwenx configuration and plugins
  status      Show Qwenx status
  config      Open Qwenx configuration
  help        Show this help

Examples:
  oml qwen deploy           # Deploy Qwenx
  oml qwen update           # Update Qwenx
  oml qwen status           # Show status
  oml qwen config           # Edit configuration

Android Permissions:
  This command automatically detects:
  - Root access
  - Shizuku availability
  - ADB Shell mode
  - Normal user mode

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        deploy)
            cmd_deploy
            ;;
        update)
            cmd_update
            ;;
        status)
            cmd_status
            ;;
        config)
            if [[ -f "${QWENX_CONFIG}/settings.json" ]]; then
                ${EDITOR:-nano} "${QWENX_CONFIG}/settings.json"
            else
                print_error "Config not found. Run 'oml qwen deploy' first."
            fi
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            print_error "Unknown command: $command"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
