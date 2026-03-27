#!/usr/bin/env bash
# Pre-uninstall script for Scout Subagent Plugin

set -euo pipefail

echo "Uninstalling Scout Subagent Plugin..."

# Detect platform
if [[ -d "/data/data/com.termux/files/usr" ]]; then
    PLATFORM="termux"
    PREFIX="/data/data/com.termux/files/usr"
elif [[ "$(uname)" == "Darwin" ]]; then
    PLATFORM="macos"
    PREFIX="/usr/local"
else
    PLATFORM="gnu-linux"
    PREFIX="/usr/local"
fi

echo "Platform: ${PLATFORM}"

# Check for generated output files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOUT_CONFIG_DIR="${HOME}/.local/share/oml/scout"

echo ""
echo "Checking for generated files..."

OUTPUT_COUNT=0
if [[ -d "${SCOUT_CONFIG_DIR}/output" ]]; then
    OUTPUT_COUNT=$(find "${SCOUT_CONFIG_DIR}/output" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

if [[ "$OUTPUT_COUNT" -gt 0 ]]; then
    echo ""
    echo "Found ${OUTPUT_COUNT} generated output file(s) in:"
    echo "  ${SCOUT_CONFIG_DIR}/output/"
    echo ""
    echo "These files will NOT be automatically deleted."
    echo "To remove them manually after uninstall:"
    echo "  rm -rf ${SCOUT_CONFIG_DIR}/output/*"
fi

# Check for configuration
if [[ -f "${SCOUT_CONFIG_DIR}/config.json" ]]; then
    echo ""
    echo "Configuration file found:"
    echo "  ${SCOUT_CONFIG_DIR}/config.json"
    echo ""
    echo "Do you want to preserve the configuration? (Y/n)"
    read -r preserve_config
    if [[ "$preserve_config" == "n" || "$preserve_config" == "N" ]]; then
        echo "Configuration will be removed."
        rm -f "${SCOUT_CONFIG_DIR}/config.json"
        echo "  ✓ Configuration removed"
    else
        echo "Configuration will be preserved."
    fi
fi

# Check for running processes
echo ""
echo "Checking for running scout processes..."
SCOUT_PIDS=$(pgrep -f "oml scout" 2>/dev/null || true)
if [[ -n "$SCOUT_PIDS" ]]; then
    echo ""
    echo "Warning: Found running scout processes:"
    echo "$SCOUT_PIDS" | while read -r pid; do
        echo "  PID: $pid"
    done
    echo ""
    echo "These processes may fail after uninstall."
fi

# Cleanup temporary files
echo ""
echo "Cleaning up temporary files..."
if [[ -d "${SCOUT_CONFIG_DIR}" ]]; then
    # Remove temporary files only
    find "${SCOUT_CONFIG_DIR}" -name "*.tmp" -delete 2>/dev/null || true
    find "${SCOUT_CONFIG_DIR}" -name "*.bak" -delete 2>/dev/null || true
    echo "  ✓ Temporary files cleaned"
fi

# Verify plugin files
echo ""
echo "Plugin files that will be removed:"
echo "  ${SCRIPT_DIR}/main.sh"
echo "  ${SCRIPT_DIR}/plugin.json"
echo "  ${SCRIPT_DIR}/lib/*.sh"
echo "  ${SCRIPT_DIR}/scripts/*.sh"

# Final confirmation
echo ""
echo "============================================"
echo "Scout Subagent Plugin uninstall complete."
echo "============================================"
echo ""
echo "To remove configuration and output files:"
echo "  rm -rf ${SCOUT_CONFIG_DIR}"
echo ""
echo "To reinstall:"
echo "  oml plugin install scout"
echo ""
