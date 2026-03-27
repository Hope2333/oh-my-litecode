#!/usr/bin/env bash
# Migration Tool - Shell to TypeScript
#
# This script helps migrate from shell-based OML to TypeScript-based OML.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }

OML_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing=()
    
    if ! command -v node >/dev/null 2>&1; then
        missing+=("node")
    fi
    
    if ! command -v npm >/dev/null 2>&1; then
        missing+=("npm")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing: ${missing[*]}"
        return 1
    fi
    
    print_success "Prerequisites satisfied"
}

# Install dependencies
install_deps() {
    print_step "Installing dependencies..."
    cd "$OML_ROOT"
    npm install
    print_success "Dependencies installed"
}

# Build TypeScript
build_ts() {
    print_step "Building TypeScript..."
    cd "$OML_ROOT"
    npm run build
    print_success "TypeScript built"
}

# Verify installation
verify() {
    print_step "Verifying installation..."
    
    local oml_cli="$OML_ROOT/packages/cli/dist/bin/oml.js"
    
    if [[ ! -f "$oml_cli" ]]; then
        print_error "OML CLI not found"
        return 1
    fi
    
    if node "$oml_cli" --version >/dev/null 2>&1; then
        print_success "OML CLI verified"
    else
        print_error "OML CLI verification failed"
        return 1
    fi
}

# Show migration summary
show_summary() {
    echo ""
    echo "========================================"
    echo "  Migration Complete!"
    echo "========================================"
    echo ""
    echo "New TypeScript-based OML is ready."
    echo ""
    echo "Usage:"
    echo "  $OML_ROOT/bin/oml.sh --help"
    echo "  node $OML_ROOT/packages/cli/dist/bin/oml.js --help"
    echo ""
    echo "Available commands:"
    echo "  oml qwen          - Qwen controller"
    echo "  oml qwen session  - Session management"
    echo "  oml help          - Show help"
    echo ""
    echo "========================================"
}

# Main
main() {
    echo ""
    echo "========================================"
    echo "  OML Migration Tool"
    echo "  Shell -> TypeScript"
    echo "========================================"
    echo ""
    
    check_prerequisites
    install_deps
    build_ts
    verify
    show_summary
}

main "$@"
