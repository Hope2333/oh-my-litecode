#!/usr/bin/env bash
# OML Android Permission Detection Library
# Detects root, Shizuku, and ADB Shell permissions

set -euo pipefail

# Permission levels
PERM_NORMAL="normal"
PERM_ADB="adb_shell"
PERM_SHIZUKU="shizuku"
PERM_ROOT="root"

# Current permission level
CURRENT_PERM=""

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        CURRENT_PERM="$PERM_ROOT"
        return 0
    fi
    
    # Try su command
    if command -v su >/dev/null 2>&1; then
        if su -c "id" 2>/dev/null | grep -q "uid=0"; then
            CURRENT_PERM="$PERM_ROOT"
            return 0
        fi
    fi
    
    return 1
}

# Check if Shizuku is available
check_shizuku() {
    # Check Shizuku service
    if command -v shizuku >/dev/null 2>&1; then
        if shizuku status 2>/dev/null | grep -q "running"; then
            CURRENT_PERM="$PERM_SHIZUKU"
            return 0
        fi
    fi
    
    # Check Shizuku via app_process
    if ls /data/local/tmp/shizuku* >/dev/null 2>&1; then
        CURRENT_PERM="$PERM_SHIZUKU"
        return 0
    fi
    
    # Check Shizuku binder
    if dumpsys package moe.shizuku.privileged.api >/dev/null 2>&1; then
        CURRENT_PERM="$PERM_SHIZUKU"
        return 0
    fi
    
    return 1
}

# Check if running in ADB shell
check_adb_shell() {
    # Check ADB context
    if [[ "$(getprop service.adb.state 2>/dev/null)" == "started" ]]; then
        CURRENT_PERM="$PERM_ADB"
        return 0
    fi
    
    # Check user ID (ADB shell usually runs as shell@android)
    local user_id
    user_id=$(id -u 2>/dev/null || echo "1")
    if [[ "$user_id" == "2000" ]]; then
        CURRENT_PERM="$PERM_ADB"
        return 0
    fi
    
    # Check ADB authorized keys
    if [[ -f /data/misc/adb/adb_keys ]]; then
        CURRENT_PERM="$PERM_ADB"
        return 0
    fi
    
    return 1
}

# Get Android SDK version
get_android_sdk() {
    getprop ro.build.version.sdk 2>/dev/null || echo "unknown"
}

# Get Android version
get_android_version() {
    getprop ro.build.version.release 2>/dev/null || echo "unknown"
}

# Check Termux
check_termux() {
    [[ -d "/data/data/com.termux/files/usr" ]]
}

# Get package info
get_package_info() {
    local package="$1"
    
    if command -v pm >/dev/null 2>&1; then
        pm list packages | grep -q "$package"
    else
        return 1
    fi
}

# Check Shizuku app installed
check_shizuku_installed() {
    get_package_info "moe.shizuku.privileged.api"
}

# Check ADB over WiFi enabled
check_adb_wifi() {
    local adb_port
    adb_port=$(getprop service.adb.tcp.port 2>/dev/null)
    [[ -n "$adb_port" ]] && [[ "$adb_port" != "5555" ]]
}

# Get all permissions
get_all_permissions() {
    if command -v pm >/dev/null 2>&1; then
        pm list permissions -g 2>/dev/null | head -50
    else
        echo "Permission listing not available"
    fi
}

# Detect all Android permissions
detect_android_perms() {
    echo "Android Permission Detection:"
    echo ""
    
    # Basic info
    echo "Android Version: $(get_android_version)"
    echo "Android SDK: $(get_android_sdk)"
    echo "Termux: $(check_termux && echo 'Yes' || echo 'No')"
    echo ""
    
    # Permission level
    echo "Permission Level:"
    if check_root; then
        echo "  ✓ Root access"
    elif check_shizuku; then
        echo "  ✓ Shizuku available"
    elif check_adb_shell; then
        echo "  ✓ ADB Shell"
    else
        echo "  ✗ Normal user"
    fi
    echo ""
    
    # Shizuku status
    echo "Shizuku Status:"
    if check_shizuku_installed; then
        echo "  ✓ Shizuku app installed"
    else
        echo "  ✗ Shizuku app not installed"
    fi
    
    if check_shizuku; then
        echo "  ✓ Shizuku service running"
    else
        echo "  ✗ Shizuku service not running"
    fi
    echo ""
    
    # ADB status
    echo "ADB Status:"
    if check_adb_wifi; then
        echo "  ✓ ADB over WiFi enabled"
    else
        echo "  ✗ ADB over WiFi disabled"
    fi
    
    if check_adb_shell; then
        echo "  ✓ Running in ADB shell"
    else
        echo "  ✗ Not running in ADB shell"
    fi
    echo ""
    
    # Available commands
    echo "Available Commands:"
    echo "  Root: $(command -v su >/dev/null 2>&1 && echo 'Yes' || echo 'No')"
    echo "  PM: $(command -v pm >/dev/null 2>&1 && echo 'Yes' || echo 'No')"
    echo "  Dumpsys: $(command -v dumpsys >/dev/null 2>&1 && echo 'Yes' || echo 'No')"
}

# Main entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_all_permissions
    echo ""
    detect_android_perms
fi
