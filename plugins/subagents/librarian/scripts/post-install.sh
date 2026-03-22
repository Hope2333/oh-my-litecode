#!/usr/bin/env bash
# Post-install script for Librarian Subagent Plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "Installing Librarian Subagent Plugin..."
echo "============================================"
echo ""

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
echo "Plugin directory: ${PLUGIN_DIR}"
echo ""

# Check dependencies
echo "Checking dependencies..."
DEPS_OK=true

for dep in bash python3 curl jq; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  ✓ $dep found ($(command -v "$dep"))"
    else
        echo "  ✗ $dep not found"
        DEPS_OK=false
    fi
done

# Check optional dependencies
echo ""
echo "Checking optional dependencies..."
for dep in git npm node; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  ✓ $dep found"
    else
        echo "  ⚠ $dep not found (some features may be limited)"
    fi
done

if [[ "$DEPS_OK" != true ]]; then
    echo ""
    echo "Warning: Some required dependencies are missing!"
    echo "The plugin may not function correctly."
    echo ""
fi

# Create configuration directory
CONFIG_DIR="${HOME}/.local/share/oml/librarian"
CACHE_DIR="${HOME}/.local/cache/oml/librarian"

echo ""
echo "Creating directories..."
mkdir -p "${CONFIG_DIR}"
mkdir -p "${CACHE_DIR}/search"
mkdir -p "${CACHE_DIR}/query"
mkdir -p "${CACHE_DIR}/websearch"
mkdir -p "${CACHE_DIR}/compile"
mkdir -p "${CONFIG_DIR}/knowledge"
echo "  ✓ Config directory: ${CONFIG_DIR}"
echo "  ✓ Cache directory: ${CACHE_DIR}"

# Create default configuration
echo ""
echo "Creating default configuration..."
cat > "${CONFIG_DIR}/config.json" <<'EOF'
{
  "maxResults": 10,
  "outputFormat": "markdown",
  "context7Enabled": true,
  "websearchEnabled": true,
  "dedupMethod": "hybrid",
  "minScore": 0.3,
  "cache": {
    "enabled": true,
    "ttl": 3600,
    "maxSize": 1000
  },
  "sources": {
    "context7": {
      "enabled": true,
      "weight": 1.0
    },
    "websearch": {
      "enabled": true,
      "weight": 0.8
    }
  }
}
EOF
echo "  ✓ Default config created"

# Create .gitkeep files for cache directories
touch "${CACHE_DIR}/search/.gitkeep"
touch "${CACHE_DIR}/query/.gitkeep"
touch "${CACHE_DIR}/websearch/.gitkeep"
touch "${CACHE_DIR}/compile/.gitkeep"
touch "${CONFIG_DIR}/knowledge/.gitkeep"
echo "  ✓ Cache directories initialized"

# Verify installation
echo ""
echo "Verifying installation..."

MAIN_SH="${PLUGIN_DIR}/main.sh"
if [[ -x "$MAIN_SH" ]]; then
    echo "  ✓ main.sh is executable"
else
    echo "  ⚠ main.sh is not executable, fixing..."
    chmod +x "$MAIN_SH"
    echo "  ✓ Fixed"
fi

# Check library files
echo ""
echo "Checking library modules..."
for lib in utils context7 websearch results compile; do
    if [[ -f "${PLUGIN_DIR}/lib/${lib}.sh" ]]; then
        echo "  ✓ lib/${lib}.sh found"
    else
        echo "  ✗ lib/${lib}.sh missing"
    fi
done

# Test basic functionality
echo ""
echo "Running basic functionality test..."
if bash "$MAIN_SH" help >/dev/null 2>&1; then
    echo "  ✓ Help command works"
else
    echo "  ✗ Help command failed"
fi

# Create sample knowledge entry
echo ""
echo "Creating sample knowledge entry..."
SAMPLE_ENTRY="${CONFIG_DIR}/knowledge/sample-entry.json"
cat > "$SAMPLE_ENTRY" <<'EOF'
{
  "id": "sample-001",
  "topic": "Getting Started with Librarian",
  "content": {
    "summary": "The Librarian subagent provides documentation search, web search, and knowledge compilation capabilities.",
    "features": [
      "Context7 MCP integration for library documentation",
      "Exa web search integration",
      "Result deduplication and ranking",
      "Knowledge compilation with citations"
    ]
  },
  "tags": ["librarian", "documentation", "search"],
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "version": 1,
  "sources": [],
  "metadata": {
    "compiler": "librarian",
    "platform": "auto"
  }
}
EOF
echo "  ✓ Sample entry created"

# Print API key configuration info
echo ""
echo "============================================"
echo "API Key Configuration (Optional)"
echo "============================================"
echo ""
echo "To enable full functionality, configure API keys:"
echo ""
echo "1. Context7 API Key (for library documentation):"
echo "   export CONTEXT7_API_KEY='your-key-here'"
echo "   # Or add to ~/.local/share/oml/librarian/config.json"
echo ""
echo "2. Exa API Key (for web search):"
echo "   export EXA_API_KEY='your-key-here'"
echo "   # Or add to ~/.local/share/oml/librarian/config.json"
echo ""
echo "Without API keys, the plugin will operate in limited mode."
echo ""

# Print usage information
echo "============================================"
echo "Librarian Subagent Plugin installed successfully!"
echo "============================================"
echo ""
echo "Quick Start:"
echo "  oml librarian help              # Show help"
echo "  oml librarian search 'query'    # Search documentation"
echo "  oml librarian query react 'hooks'  # Query Context7"
echo "  oml librarian websearch 'rust'  # Web search"
echo "  oml librarian compile 'Topic'   # Compile knowledge"
echo ""
echo "Examples:"
echo "  # Search React documentation"
echo "  oml librarian search 'useState hook' --package react"
echo ""
echo "  # Query PyPI package"
echo "  oml librarian query pypi:requests 'authentication'"
echo ""
echo "  # Web search with domain filter"
echo "  oml librarian websearch 'kubernetes deployment' --include-domains kubernetes.io"
echo ""
echo "  # Compile knowledge guide"
echo "  oml librarian compile 'React Hooks Guide' --query 'react hooks tutorial' --web"
echo ""
echo "Configuration:"
echo "  Config: ${CONFIG_DIR}/config.json"
echo "  Cache:  ${CACHE_DIR}"
echo "  Knowledge: ${CONFIG_DIR}/knowledge/"
echo ""
echo "Environment Variables:"
echo "  OML_LIBRARIAN_MAX_RESULTS       Default: 10"
echo "  OML_LIBRARIAN_OUTPUT_FORMAT     Default: markdown"
echo "  OML_LIBRARIAN_CONTEXT7_ENABLED  Default: true"
echo "  OML_LIBRARIAN_WEBSEARCH_ENABLED Default: true"
echo "  CONTEXT7_API_KEY                Context7 API key"
echo "  EXA_API_KEY                     Exa API key"
echo ""
