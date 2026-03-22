#!/usr/bin/env bash
# Post-install script for Build Agent Plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

echo "Installing Build Agent Plugin..."

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
for dep in bash make python3; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  ✓ $dep found: $(command -v "$dep")"
    else
        echo "  ✗ $dep not found"
    fi
done

# Create logs directory
LOGS_DIR="${HOME}/.oml/logs/build"
echo "Creating logs directory: ${LOGS_DIR}"
mkdir -p "${LOGS_DIR}"
chmod 755 "${LOGS_DIR}"

# Create cache directory
CACHE_DIR="${HOME}/.oml/cache/build"
echo "Creating cache directory: ${CACHE_DIR}"
mkdir -p "${CACHE_DIR}"
chmod 755 "${CACHE_DIR}"

# Create compatibility symlink
echo "Creating compatibility symlink..."
BIN_DIR="${PREFIX}/bin"

if [[ -w "$BIN_DIR" ]] || command -v sudo >/dev/null 2>&1; then
    # Create oml-build wrapper
    cat > "${BIN_DIR}/oml-build" <<'OML_BUILD_WRAPPER'
#!/usr/bin/env bash
# OML Build Agent wrapper
# Redirects to: oml build
exec oml build "$@"
OML_BUILD_WRAPPER
    chmod +x "${BIN_DIR}/oml-build"
    echo "Created: ${BIN_DIR}/oml-build"
    
    # Create build alias (short form)
    cat > "${BIN_DIR}/build-oml" <<'BUILD_OML_WRAPPER'
#!/usr/bin/env bash
# OML Build Agent short wrapper
# Redirects to: oml build
exec oml build "$@"
BUILD_OML_WRAPPER
    chmod +x "${BIN_DIR}/build-oml"
    echo "Created: ${BIN_DIR}/build-oml"
else
    echo "Cannot create system symlinks. Run manually or use sudo:"
    echo "  sudo ln -sf ${PLUGIN_DIR}/main.sh ${BIN_DIR}/oml-build"
fi

# Verify Makefile integration
echo ""
echo "Verifying Makefile integration..."
OML_ROOT="$(cd "${PLUGIN_DIR}" && cd ../../ && pwd)"

if [[ -f "${OML_ROOT}/Makefile" ]]; then
    echo "  ✓ Top-level Makefile found"
else
    echo "  ✗ Top-level Makefile not found"
fi

if [[ -f "${OML_ROOT}/solve-android/opencode/Makefile" ]]; then
    echo "  ✓ opencode Makefile found"
else
    echo "  ✗ opencode Makefile not found"
fi

if [[ -f "${OML_ROOT}/solve-android/bun/Makefile" ]]; then
    echo "  ✓ bun Makefile found"
else
    echo "  ✗ bun Makefile not found"
fi

# Create default configuration
CONFIG_DIR="${HOME}/.oml"
CONFIG_FILE="${CONFIG_DIR}/build-config.json"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Creating default configuration..."
    cat > "${CONFIG_FILE}" <<'EOF'
{
  "verbose": false,
  "parallel": "auto",
  "log_dir": "~/.oml/logs/build",
  "default_pkgmgr": "auto",
  "default_debug": false,
  "output_format": "text"
}
EOF
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  oml build --help           Show help"
echo "  oml build project          Build all projects"
echo "  oml build project opencode Build opencode only"
echo "  oml build clean            Clean build artifacts"
echo "  oml build status           Show build status"
echo "  oml build logs             Show recent logs"
echo ""
echo "Environment Variables:"
echo "  OML_BUILD_VERBOSE=true     Enable verbose output"
echo "  OML_BUILD_PARALLEL=4       Set parallel jobs"
echo "  OML_OUTPUT_FORMAT=json     Output JSON format"
echo ""
echo "Configuration:"
echo "  Config: ${CONFIG_FILE}"
echo "  Logs:   ${LOGS_DIR}"
