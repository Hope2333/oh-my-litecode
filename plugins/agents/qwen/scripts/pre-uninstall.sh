#!/usr/bin/env bash
# Pre-uninstall script for Qwen Agent Plugin

set -euo pipefail

echo "Uninstalling Qwen Agent Plugin..."

# Detect platform
if [[ -d "/data/data/com.termux/files/usr" ]]; then
    PLATFORM="termux"
    PREFIX="/data/data/com.termux/files/usr"
else
    PLATFORM="gnu-linux"
    PREFIX="/usr/local"
fi

# Remove compatibility symlink
BIN_DIR="${PREFIX}/bin"
if [[ -L "${BIN_DIR}/qwenx" ]]; then
    echo "Removing symlink: ${BIN_DIR}/qwenx"
    rm "${BIN_DIR}/qwenx"
fi

# Ask about keeping configuration
echo ""
echo "Configuration files are preserved in:"
echo "  ~/.local/home/qwen/"
echo ""
echo "To remove configuration, run:"
echo "  rm -rf ~/.local/home/qwen"

echo ""
echo "Uninstall complete."
