#!/usr/bin/env bash
# Pre-uninstall script for Build Agent Plugin

set -euo pipefail

echo "Uninstalling Build Agent Plugin..."

# Detect platform
if [[ -d "/data/data/com.termux/files/usr" ]]; then
    PLATFORM="termux"
    PREFIX="/data/data/com.termux/files/usr"
else
    PLATFORM="gnu-linux"
    PREFIX="/usr/local"
fi

# Remove compatibility symlinks
BIN_DIR="${PREFIX}/bin"

for symlink in "oml-build" "build-oml"; do
    if [[ -L "${BIN_DIR}/${symlink}" ]]; then
        echo "Removing symlink: ${BIN_DIR}/${symlink}"
        rm "${BIN_DIR}/${symlink}"
    fi
done

# Ask about configuration and logs
CONFIG_DIR="${HOME}/.oml"
LOGS_DIR="${CONFIG_DIR}/logs/build"
CACHE_DIR="${CONFIG_DIR}/cache/build"
CONFIG_FILE="${CONFIG_DIR}/build-config.json"

echo ""
echo "The following files will be preserved:"
echo ""

if [[ -d "$LOGS_DIR" ]]; then
    log_count=$(find "$LOGS_DIR" -type f -name "*.log" 2>/dev/null | wc -l)
    echo "  Build logs: ${LOGS_DIR} (${log_count} files)"
fi

if [[ -d "$CACHE_DIR" ]]; then
    cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    echo "  Cache:      ${CACHE_DIR} (${cache_size})"
fi

if [[ -f "$CONFIG_FILE" ]]; then
    echo "  Config:     ${CONFIG_FILE}"
fi

echo ""
echo "To remove all build agent data, run:"
echo "  rm -rf ${LOGS_DIR}"
echo "  rm -rf ${CACHE_DIR}"
echo "  rm -f ${CONFIG_FILE}"
echo ""
echo "Uninstall complete."
