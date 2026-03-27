#!/usr/bin/env bash
# OML System Detection Library
# Detects system type, package manager, and environment

set -euo pipefail

# System information
SYSTEM=""
PKG_MANAGER=""
SHELL_TYPE=""
ARCH=""
OS_VERSION=""

# Detect system type
detect_system() {
    if [[ -d "/data/data/com.termux/files/usr" ]]; then
        SYSTEM="termux"
        PKG_MANAGER="pkg"
    elif [[ -f "/etc/arch-release" ]]; then
        SYSTEM="arch"
        PKG_MANAGER="pacman"
    elif [[ -f "/etc/debian_version" ]]; then
        SYSTEM="debian"
        PKG_MANAGER="apt"
    elif [[ -f "/etc/redhat-release" ]]; then
        SYSTEM="rhel"
        PKG_MANAGER="dnf"
    elif [[ "$(uname)" == "Darwin" ]]; then
        SYSTEM="macos"
        PKG_MANAGER="brew"
    else
        SYSTEM="unknown"
        PKG_MANAGER=""
    fi
}

# Detect architecture
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l) ARCH="arm" ;;
        *) ARCH="unknown" ;;
    esac
}

# Detect shell type
detect_shell() {
    SHELL_TYPE=$(basename "$SHELL")
}

# Get OS version
get_os_version() {
    if [[ -f "/etc/os-release" ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_VERSION="${PRETTY_NAME:-Unknown}"
    elif [[ -f "/etc/arch-release" ]]; then
        OS_VERSION="Arch Linux"
    elif [[ -f "/etc/debian_version" ]]; then
        OS_VERSION="Debian $(cat /etc/debian_version)"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_VERSION=$(sw_vers -productVersion)
    else
        OS_VERSION="Unknown"
    fi
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get command version
get_version() {
    local cmd="$1"
    if command_exists "$cmd"; then
        "$cmd" --version 2>&1 | head -1 || "$cmd" -v 2>&1 | head -1 || echo "Unknown"
    else
        echo "Not installed"
    fi
}

# Detect all system information
detect_all() {
    detect_system
    detect_arch
    detect_shell
    get_os_version
}

# Print system information
print_system_info() {
    detect_all
    
    echo "System Information:"
    echo "  System:     $SYSTEM"
    echo "  Package:    $PKG_MANAGER"
    echo "  Arch:       $ARCH"
    echo "  Shell:      $SHELL_TYPE"
    echo "  OS:         $OS_VERSION"
    echo "  Root:       $(is_root && echo 'Yes' || echo 'No')"
    echo ""
    echo "Installed Tools:"
    echo "  Git:        $(get_version git)"
    echo "  Bash:       $(get_version bash)"
    echo "  Python3:    $(get_version python3)"
    echo "  Node.js:    $(get_version node)"
    echo "  Curl:       $(get_version curl)"
    echo "  Wget:       $(get_version wget)"
}

# Main entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_system_info
fi
