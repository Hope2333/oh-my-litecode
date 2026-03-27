#!/usr/bin/env bash
# OML Unified Installer
# Automatic installation for multiple systems
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/your-org/oh-my-litecode/main/bin/oml-install.sh | bash
#   OR
#   wget -qO- https://raw.githubusercontent.com/your-org/oh-my-litecode/main/bin/oml-install.sh | bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
OML_ROOT="${OML_ROOT:-${HOME}/develop/oh-my-litecode}"
OML_BRANCH="${OML_BRANCH:-main}"
OML_REPO="${OML_REPO:-https://github.com/your-org/oh-my-litecode.git}"

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

if [[ -f "${LIB_DIR}/system-detect.sh" ]]; then
    source "${LIB_DIR}/system-detect.sh"
fi

if [[ -f "${LIB_DIR}/package-manager.sh" ]]; then
    source "${LIB_DIR}/package-manager.sh"
fi

# Print banner
print_banner() {
    echo -e "${BLUE}"
    cat <<'EOF'
╔═══════════════════════════════════════╗
║     OML - Oh My Litecode Installer    ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

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
    
    if ! command -v bash >/dev/null 2>&1; then
        missing+=("bash")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing prerequisites: ${missing[*]}"
        print_step "Installing missing packages..."
        pkg_install "${missing[@]}"
    fi
    
    print_success "Prerequisites satisfied"
}

# Clone repository
clone_repo() {
    print_step "Cloning OML repository..."
    
    if [[ -d "$OML_ROOT" ]]; then
        print_warning "OML already exists at $OML_ROOT"
        echo -n "Do you want to update it? (y/N): "
        read -r confirm
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            cd "$OML_ROOT"
            git pull origin "$OML_BRANCH"
            print_success "OML updated"
        else
            print_warning "Installation cancelled"
            return 1
        fi
    else
        git clone --depth 1 --branch "$OML_BRANCH" "$OML_REPO" "$OML_ROOT"
        print_success "OML cloned to $OML_ROOT"
    fi
}

# Setup PATH
setup_path() {
    print_step "Setting up PATH..."
    
    local shell_rc="${HOME}/.bashrc"
    local path_export="export PATH=\"${OML_ROOT}:\$PATH\""
    
    # Detect shell
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ -f "${HOME}/.zshrc" ]]; then
        shell_rc="${HOME}/.zshrc"
    fi
    
    # Add to shell rc if not already present
    if ! grep -q "$OML_ROOT" "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# OML (Oh My Litecode)" >> "$shell_rc"
        echo "$path_export" >> "$shell_rc"
        print_success "PATH added to $shell_rc"
    else
        print_warning "PATH already configured"
    fi
    
    # Export for current session
    export PATH="${OML_ROOT}:${PATH}"
}

# Install dependencies
install_deps() {
    print_step "Installing dependencies..."
    
    if [[ -f "${LIB_DIR}/package-manager.sh" ]]; then
        source "${LIB_DIR}/package-manager.sh"
        install_oml_deps
    else
        print_warning "Package manager not available, skipping dependency installation"
    fi
}

# Initialize configuration
init_config() {
    print_step "Initializing configuration..."
    
    local config_dir="${HOME}/.oml"
    
    if [[ ! -d "$config_dir" ]]; then
        mkdir -p "$config_dir"
        print_success "Config directory created: $config_dir"
    else
        print_warning "Config directory already exists"
    fi
    
    # Create default config
    local config_file="${config_dir}/config.json"
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" <<EOF
{
  "version": "1.0.0",
  "installed_at": "$(date -Iseconds)",
  "branch": "$OML_BRANCH",
  "system": "${SYSTEM:-unknown}"
}
EOF
        print_success "Default config created"
    fi
}

# Post-installation
post_install() {
    print_step "Running post-installation..."
    
    if [[ -f "${OML_ROOT}/scripts/post-install.sh" ]]; then
        bash "${OML_ROOT}/scripts/post-install.sh"
    fi
    
    print_success "Post-installation complete"
}

# Print completion message
print_completion() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     OML Installation Complete!        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your shell or run: source ${HOME}/.bashrc"
    echo "  2. Verify installation: oml --help"
    echo "  3. Get started: oml qwen"
    echo ""
    echo "Documentation:"
    echo "  - Quick Start: ${OML_ROOT}/QUICKSTART.md"
    echo "  - Full Guide: ${OML_ROOT}/README-OML.md"
    echo ""
}

# Main installation function
main() {
    print_banner
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch)
                OML_BRANCH="$2"
                shift 2
                ;;
            --root)
                OML_ROOT="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--branch <branch>] [--root <path>]"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Detect system
    if type detect_all >/dev/null 2>&1; then
        detect_all
        print_step "Detected system: $SYSTEM ($PKG_MANAGER)"
    fi
    
    # Run installation steps
    check_prerequisites
    clone_repo
    setup_path
    install_deps
    init_config
    post_install
    print_completion
}

main "$@"
