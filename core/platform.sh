#!/usr/bin/env bash
# OML Platform Detection and Adaptation Layer
# Supports: Termux (Android) and GNU/Linux

set -euo pipefail

OML_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Platform detection
oml_platform_detect() {
    if [[ -d "/data/data/com.termux/files/usr" ]]; then
        echo "termux"
    elif [[ -f "/etc/debian_version" ]]; then
        echo "debian"
    elif [[ -f "/etc/arch-release" ]]; then
        echo "arch"
    elif [[ -f "/etc/redhat-release" ]]; then
        echo "rhel"
    else
        echo "gnu-linux"
    fi
}

# Get platform label (short)
oml_platform_label() {
    local platform
    platform="$(oml_platform_detect)"
    case "$platform" in
        termux) echo "termux" ;;
        *) echo "gnu-linux" ;;
    esac
}

# Get platform family (for config selection)
oml_platform_family() {
    local platform
    platform="$(oml_platform_detect)"
    case "$platform" in
        termux) echo "termux" ;;
        debian|ubuntu|mint) echo "debian" ;;
        arch|manjaro) echo "arch" ;;
        rhel|centos|fedora) echo "rhel" ;;
        *) echo "gnu-linux" ;;
    esac
}

# Get package manager for current platform
oml_pkgmgr_detect() {
    local platform
    platform="$(oml_platform_detect)"
    
    case "$platform" in
        termux)
            if command -v pacman >/dev/null 2>&1; then
                echo "pacman"
            else
                echo "dpkg"
            fi
            ;;
        debian|ubuntu|mint)
            echo "apt"
            ;;
        arch|manjaro)
            echo "pacman"
            ;;
        rhel|centos|fedora)
            if command -v dnf >/dev/null 2>&1; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get prefix path for current platform
oml_prefix_path() {
    local platform
    platform="$(oml_platform_detect)"
    
    case "$platform" in
        termux)
            echo "/data/data/com.termux/files/usr"
            ;;
        *)
            echo "/usr/local"
            ;;
    esac
}

# Get home directory (respecting fake home if set)
oml_home_path() {
    if [[ -n "${_FAKEHOME:-}" ]]; then
        echo "${_FAKEHOME}"
    else
        echo "${HOME}"
    fi
}

# Get OML config directory
oml_config_dir() {
    local home
    home="$(oml_home_path)"
    
    if [[ "$home" == *"/.local/home/"* ]]; then
        # Fake home environment
        echo "${home}/.oml"
    else
        echo "${HOME}/.oml"
    fi
}

# Ensure config directory exists
oml_ensure_config_dir() {
    local config_dir
    config_dir="$(oml_config_dir)"
    mkdir -p "${config_dir}"
    mkdir -p "${config_dir}/logs"
    mkdir -p "${config_dir}/cache"
    mkdir -p "${config_dir}/secrets"
    chmod 700 "${config_dir}/secrets" 2>/dev/null || true
}

# Get platform-specific config path
oml_platform_config() {
    local platform
    platform="$(oml_platform_label)"
    echo "$(oml_config_dir)/${platform}"
}

# Check if running in fake home isolation
oml_is_fake_home() {
    [[ -n "${_FAKEHOME:-}" && "${HOME}" == "${_FAKEHOME}" ]]
}

# Get fake home path for a specific agent
oml_get_fake_home() {
    local agent_name="${1:-}"
    if [[ -z "$agent_name" ]]; then
        echo "${HOME}/.local/home/default"
    else
        echo "${HOME}/.local/home/${agent_name}"
    fi
}

# Setup fake home environment for an agent
oml_setup_fake_home() {
    local agent_name="${1:-agent}"
    local fake_home
    fake_home="$(oml_get_fake_home "$agent_name")"
    
    export _REALHOME="${HOME}"
    export _FAKEHOME="${fake_home}"
    export HOME="${fake_home}"
    
    mkdir -p "${fake_home}"
    mkdir -p "${fake_home}/.config"
    mkdir -p "${fake_home}/.cache"
    mkdir -p "${fake_home}/.local/share"
}

# Restore original home
oml_restore_home() {
    if [[ -n "${_REALHOME:-}" ]]; then
        export HOME="${_REALHOME}"
        unset _REALHOME
        unset _FAKEHOME
    fi
}

# Get Python path (prefer python3)
oml_python_path() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        echo "python"
    else
        echo ""
    fi
}

# Get Node.js path
oml_node_path() {
    if command -v node >/dev/null 2>&1; then
        echo "node"
    else
        echo ""
    fi
}

# Check required dependencies
oml_check_deps() {
    local deps=("$@")
    local missing=()
    
    for dep in "${deps[@]}"; do
        case "$dep" in
            python|python3)
                if [[ -z "$(oml_python_path)" ]]; then
                    missing+=("python3")
                fi
                ;;
            node|nodejs)
                if [[ -z "$(oml_node_path)" ]]; then
                    missing+=("nodejs")
                fi
                ;;
            git)
                if ! command -v git >/dev/null 2>&1; then
                    missing+=("git")
                fi
                ;;
            bash)
                if [[ -z "${BASH_VERSION:-}" ]]; then
                    missing+=("bash")
                fi
                ;;
            *)
                if ! command -v "$dep" >/dev/null 2>&1; then
                    missing+=("$dep")
                fi
                ;;
        esac
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "missing:${missing[*]}"
        return 1
    fi
    
    echo "ok"
    return 0
}

# Install dependencies using platform package manager
oml_install_deps() {
    local deps=("$@")
    local pkgmgr
    pkgmgr="$(oml_pkgmgr_detect)"
    
    case "$pkgmgr" in
        apt)
            sudo apt install -y "${deps[@]}"
            ;;
        pacman)
            sudo pacman -S --noconfirm "${deps[@]}"
            ;;
        dnf)
            sudo dnf install -y "${deps[@]}"
            ;;
        yum)
            sudo yum install -y "${deps[@]}"
            ;;
        dpkg)
            pkg install -y "${deps[@]}"
            ;;
        *)
            echo "Error: Unsupported package manager: $pkgmgr" >&2
            return 1
            ;;
    esac
}

# Get architecture
oml_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armhf)
            echo "arm"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Main entry for CLI usage
main() {
    local action="${1:-detect}"
    shift || true
    
    case "$action" in
        detect)
            oml_platform_detect
            ;;
        label)
            oml_platform_label
            ;;
        family)
            oml_platform_family
            ;;
        pkgmgr)
            oml_pkgmgr_detect
            ;;
        prefix)
            oml_prefix_path
            ;;
        home)
            oml_home_path
            ;;
        config-dir)
            oml_config_dir
            ;;
        ensure-config)
            oml_ensure_config_dir
            ;;
        check-deps)
            oml_check_deps "$@"
            ;;
        install-deps)
            oml_install_deps "$@"
            ;;
        arch)
            oml_arch
            ;;
        fake-home-setup)
            oml_setup_fake_home "$@"
            ;;
        fake-home-restore)
            oml_restore_home
            ;;
        *)
            echo "Unknown action: $action"
            echo "Available actions: detect, label, family, pkgmgr, prefix, home, config-dir, ensure-config, check-deps, install-deps, arch, fake-home-setup, fake-home-restore"
            return 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
