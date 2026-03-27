#!/usr/bin/env bash
# WebSearch MCP Plugin - Pre Uninstall Hook

set -euo pipefail

echo "Uninstalling WebSearch MCP Plugin..."

# Ask about keeping cache
echo ""
echo "Cache directory: ${HOME}/.oml/cache/websearch"
echo "Configuration: ${HOME}/.oml/websearch-config.json"
echo ""
echo "Remove cache and configuration? (y/N)"
read -r confirm

if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    echo "Removing cache..."
    rm -rf "${HOME}/.oml/cache/websearch"
    
    echo "Removing configuration..."
    rm -f "${HOME}/.oml/websearch-config.json"
    
    echo "Cleanup complete."
else
    echo "Keeping cache and configuration."
fi

echo ""
echo "Uninstall complete."
