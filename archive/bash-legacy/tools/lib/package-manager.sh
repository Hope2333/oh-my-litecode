#!/usr/bin/env bash
# OML Package Manager Abstraction Layer
# Unified interface for different package managers

set -euo pipefail

# Source system detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/system-detect.sh" ]]; then
    source "${SCRIPT_DIR}/system-detect.sh"
    detect_system
fi

# Install packages
pkg_install() {
    local packages=("$@")
    
    case "$PKG_MANAGER" in
        pkg)
            pkg install -y "${packages[@]}"
            ;;
        pacman)
            sudo pacman -S --noconfirm "${packages[@]}"
            ;;
        apt)
            sudo apt update && sudo apt install -y "${packages[@]}"
            ;;
        dnf)
            sudo dnf install -y "${packages[@]}"
            ;;
        brew)
            brew install "${packages[@]}"
            ;;
        *)
            echo "Error: Unsupported package manager: $PKG_MANAGER" >&2
            return 1
            ;;
    esac
}

# Install Python packages
pip_install() {
    local packages=("$@")
    
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install --user "${packages[@]}"
    elif command -v pip >/dev/null 2>&1; then
        pip install --user "${packages[@]}"
    else
        echo "Error: pip not found" >&2
        return 1
    fi
}

# Install Node.js packages
npm_install() {
    local packages=("$@")
    
    if command -v npm >/dev/null 2>&1; then
        npm install -g "${packages[@]}"
    elif command -v yarn >/dev/null 2>&1; then
        yarn global add "${packages[@]}"
    else
        echo "Error: npm/yarn not found" >&2
        return 1
    fi
}

# Check if package is installed
is_installed() {
    local package="$1"
    
    case "$PKG_MANAGER" in
        pkg)
            pkg list-installed 2>/dev/null | grep -q "^$package "
            ;;
        pacman)
            pacman -Q "$package" &>/dev/null
            ;;
        apt)
            dpkg -l "$package" &>/dev/null
            ;;
        dnf)
            dnf list installed "$package" &>/dev/null
            ;;
        brew)
            brew list "$package" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Update package database
pkg_update() {
    case "$PKG_MANAGER" in
        pkg)
            pkg update
            ;;
        pacman)
            sudo pacman -Sy
            ;;
        apt)
            sudo apt update
            ;;
        dnf)
            sudo dnf check-update
            ;;
        brew)
            brew update
            ;;
        *)
            echo "Error: Unsupported package manager: $PKG_MANAGER" >&2
            return 1
            ;;
    esac
}

# Upgrade all packages
pkg_upgrade() {
    case "$PKG_MANAGER" in
        pkg)
            pkg upgrade -y
            ;;
        pacman)
            sudo pacman -Su --noconfirm
            ;;
        apt)
            sudo apt upgrade -y
            ;;
        dnf)
            sudo dnf upgrade -y
            ;;
        brew)
            brew upgrade
            ;;
        *)
            echo "Error: Unsupported package manager: $PKG_MANAGER" >&2
            return 1
            ;;
    esac
}

# Install OML dependencies
install_oml_deps() {
    local deps=(
        "git"
        "bash"
        "python3"
        "curl"
    )
    
    # Add system-specific packages
    case "$SYSTEM" in
        termux)
            deps+=("wget" "proot" "resolve-march-native")
            ;;
        debian|rhel)
            deps+=("wget" "jq")
            ;;
        arch)
            deps+=("wget" "jq")
            ;;
        macos)
            deps+=("wget" "jq")
            ;;
    esac
    
    echo "Installing OML dependencies..."
    pkg_install "${deps[@]}"
    
    # Install Python dependencies
    echo "Installing Python dependencies..."
    pip_install "requests" "pydantic" || true
    
    # Install Node.js dependencies (if needed)
    if command -v node >/dev/null 2>&1; then
        echo "Installing Node.js dependencies..."
        npm_install "jq" || true
    fi
}

# Main entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "deps" ]]; then
        install_oml_deps
    else
        echo "OML Package Manager"
        echo ""
        echo "Usage: $0 [deps]"
        echo ""
        echo "Commands:"
        echo "  deps    Install OML dependencies"
    fi
fi
