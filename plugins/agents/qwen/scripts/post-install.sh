#!/usr/bin/env bash
# Post-install script for Qwen Agent Plugin

set -euo pipefail

echo "Installing Qwen Agent Plugin..."

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
for dep in nodejs python3 git; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  ✓ $dep found"
    else
        echo "  ✗ $dep not found"
    fi
done

# Setup fake home directory
FAKE_HOME="${HOME}/.local/home/qwen"
echo "Creating fake home directory: ${FAKE_HOME}"
mkdir -p "${FAKE_HOME}/.qwen"
mkdir -p "${FAKE_HOME}/.qwenx/secrets"
chmod 700 "${FAKE_HOME}/.qwenx/secrets"

# Create default settings.json if not exists
SETTINGS_FILE="${FAKE_HOME}/.qwen/settings.json"
if [[ ! -f "${SETTINGS_FILE}" ]]; then
    echo "Creating default settings.json..."
    cat > "${SETTINGS_FILE}" <<'EOF'
{
  "mcp": {
    "allowed": ["context7"],
    "excluded": []
  },
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "protocol": "mcp",
      "enabled": true,
      "trust": false,
      "excludeTools": []
    }
  },
  "modelProviders": {
    "openai": []
  },
  "model": {
    "id": "default",
    "name": "Default Model"
  }
}
EOF
fi

# Create compatibility symlink
echo "Creating compatibility symlink..."
BIN_DIR="${PREFIX}/bin"
mkdir -p "$BIN_DIR"

# Create qwenx wrapper for backward compatibility
if [[ -w "$BIN_DIR" ]] || command -v sudo >/dev/null 2>&1; then
    cat > "${BIN_DIR}/qwenx" <<'QWENX_WRAPPER'
#!/usr/bin/env bash
# qwenx compatibility wrapper
# Redirects to: oml qwen
exec oml qwen "$@"
QWENX_WRAPPER
    chmod +x "${BIN_DIR}/qwenx"
    echo "Created: ${BIN_DIR}/qwenx"
else
    echo "Cannot create system symlink. Run manually or use sudo:"
    echo "  sudo ln -sf $(pwd)/plugins/agents/qwen/main.sh ${BIN_DIR}/qwenx"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  oml qwen --help          Show help"
echo "  oml qwen 'your query'    Start chat"
echo "  oml qwen ctx7 --help     Context7 management"
echo ""
echo "Backward compatibility:"
echo "  qwenx 'your query'       (if symlink created)"
echo ""
echo "Configuration:"
echo "  Settings: ${SETTINGS_FILE}"
echo "  Context7 keys: ${FAKE_HOME}/.qwenx/secrets/context7.keys"
