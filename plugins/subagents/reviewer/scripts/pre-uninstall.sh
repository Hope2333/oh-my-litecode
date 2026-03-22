#!/usr/bin/env bash
# Pre-uninstall script for Reviewer Subagent Plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "Uninstalling Reviewer Subagent Plugin..."
echo "============================================"
echo ""

# Configuration directories
CONFIG_DIR="${HOME}/.local/share/oml/reviewer"
CACHE_DIR="${HOME}/.local/cache/oml/reviewer"

# Ask user about data preservation
echo "Data Preservation Options:"
echo ""
echo "  The following user data will be affected:"
echo "  - Configuration: ${CONFIG_DIR}/config.json"
echo "  - Custom rules: ${CONFIG_DIR}/rules/"
echo "  - Report templates: ${CONFIG_DIR}/report-template.md"
echo "  - Generated reports: ${CACHE_DIR}/reports/"
echo "  - Cache files: ${CACHE_DIR}/cache/"
echo ""
echo "  Choose an option:"
echo "  1. Keep all user data (recommended)"
echo "  2. Keep configuration and rules, remove cache"
echo "  3. Remove everything"
echo ""

# Non-interactive mode: default to keeping data
if [[ "${OML_UNINSTALL_MODE:-interactive}" != "interactive" ]]; then
    echo "Non-interactive mode: Keeping user data (option 1)"
    UNINSTALL_OPTION=1
else
    read -p "Enter option (1/2/3) [default: 1]: " UNINSTALL_OPTION
    UNINSTALL_OPTION="${UNINSTALL_OPTION:-1}"
fi

case "$UNINSTALL_OPTION" in
    1)
        echo ""
        echo "Keeping all user data..."
        # Only remove cache
        if [[ -d "$CACHE_DIR" ]]; then
            echo "  Removing cache directory..."
            rm -rf "$CACHE_DIR"
            echo "  ✓ Cache removed"
        fi
        echo "  ✓ Configuration preserved: ${CONFIG_DIR}"
        echo "  ✓ Custom rules preserved: ${CONFIG_DIR}/rules/"
        echo "  ✓ Report templates preserved: ${CONFIG_DIR}/"
        ;;
    2)
        echo ""
        echo "Removing cache, keeping configuration and rules..."
        if [[ -d "$CACHE_DIR" ]]; then
            rm -rf "$CACHE_DIR"
            echo "  ✓ Cache removed"
        fi
        echo "  ✓ Configuration preserved: ${CONFIG_DIR}"
        echo "  ✓ Custom rules preserved: ${CONFIG_DIR}/rules/"
        echo "  ✓ Report templates preserved: ${CONFIG_DIR}/"
        ;;
    3)
        echo ""
        echo "Removing all user data..."
        if [[ -d "$CONFIG_DIR" ]]; then
            rm -rf "$CONFIG_DIR"
            echo "  ✓ Configuration removed"
        fi
        if [[ -d "$CACHE_DIR" ]]; then
            rm -rf "$CACHE_DIR"
            echo "  ✓ Cache removed"
        fi
        echo "  ⚠ All user data has been removed"
        ;;
    *)
        echo ""
        echo "Invalid option. Keeping all user data..."
        ;;
esac

# Remove plugin symlink if exists
echo ""
echo "Checking for plugin symlinks..."
for prefix in "/usr/local/bin" "/data/data/com.termux/files/usr/bin" "$HOME/.local/bin"; do
    if [[ -L "${prefix}/oml-reviewer" ]]; then
        rm -f "${prefix}/oml-reviewer"
        echo "  ✓ Removed symlink: ${prefix}/oml-reviewer"
    fi
done

# Verify plugin removal
echo ""
echo "Plugin files remaining in ${PLUGIN_DIR}:"
if [[ -d "$PLUGIN_DIR" ]]; then
    file_count=$(find "$PLUGIN_DIR" -type f 2>/dev/null | wc -l)
    echo "  $file_count files (plugin directory not removed)"
    echo "  Note: Plugin directory should be removed by package manager"
fi

echo ""
echo "============================================"
echo "Reviewer Subagent Plugin uninstalled"
echo "============================================"
echo ""

if [[ "$UNINSTALL_OPTION" != "3" ]]; then
    echo "Your data has been preserved at:"
    echo "  ${CONFIG_DIR}"
    echo ""
    echo "To completely remove all data, run:"
    echo "  rm -rf ${CONFIG_DIR} ${CACHE_DIR}"
    echo ""
fi

echo "Done."
