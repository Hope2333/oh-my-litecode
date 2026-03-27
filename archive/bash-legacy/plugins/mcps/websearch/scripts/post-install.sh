#!/usr/bin/env bash
# WebSearch MCP Plugin - Post Install Hook

set -euo pipefail

echo "Installing WebSearch MCP Plugin..."

# Detect platform
if [[ -d "/data/data/com.termux/files/usr" ]]; then
    PLATFORM="termux"
    PREFIX="/data/data/com.termux/files/usr"
else
    PLATFORM="gnu-linux"
    PREFIX="/usr/local"
fi

echo "Platform: ${PLATFORM}"

# Check dependencies
echo "Checking dependencies..."
for dep in bash python3 curl jq nodejs; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  ✓ $dep found"
    else
        echo "  ✗ $dep not found"
    fi
done

# Create cache directory
CACHE_DIR="${HOME}/.oml/cache/websearch"
echo "Creating cache directory: $CACHE_DIR"
mkdir -p "$CACHE_DIR"

# Create configuration template
CONFIG_FILE="${HOME}/.oml/websearch-config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<EOF
{
  "exa": {
    "baseUrl": "https://api.exa.ai",
    "timeout": 30,
    "cache": {
      "enabled": true,
      "ttl": 3600,
      "maxSize": 1000
    }
  }
}
EOF
    echo "Created configuration template: $CONFIG_FILE"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  oml mcps websearch search \"query\""
echo "  oml mcps websearch code-context \"query\""
echo "  oml mcps websearch config show"
echo ""
echo "Configuration:"
echo "  Set EXA_API_KEY environment variable:"
echo "    export EXA_API_KEY=\"your-api-key\""
echo "  Or edit: $CONFIG_FILE"
