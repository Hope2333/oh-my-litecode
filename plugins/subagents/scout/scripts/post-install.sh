#!/usr/bin/env bash
# Post-install script for Scout Subagent Plugin

set -euo pipefail

echo "Installing Scout Subagent Plugin..."

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

# Check dependencies
echo ""
echo "Checking dependencies..."
DEPS_OK=true

for dep in bash python3 git find; do
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
for dep in bc du wc grep awk; do
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
fi

# Create configuration directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOUT_CONFIG_DIR="${HOME}/.local/share/oml/scout"

echo ""
echo "Creating configuration directory: ${SCOUT_CONFIG_DIR}"
mkdir -p "${SCOUT_CONFIG_DIR}"

# Create default configuration
cat > "${SCOUT_CONFIG_DIR}/config.json" <<EOF
{
  "defaultFormat": "markdown",
  "defaultMaxDepth": 10,
  "excludePatterns": [
    "node_modules",
    ".git",
    "__pycache__",
    ".venv",
    "dist",
    "build",
    ".cache",
    "target",
    "coverage",
    ".idea",
    ".vscode"
  ],
  "maxFileSize": 1048576,
  "timeout": 60
}
EOF

echo "✓ Default configuration created"

# Create output directory
mkdir -p "${SCOUT_CONFIG_DIR}/output"
echo "✓ Output directory created"

# Verify installation
echo ""
echo "Verifying installation..."

MAIN_SH="${SCRIPT_DIR}/main.sh"
if [[ -x "$MAIN_SH" ]]; then
    echo "  ✓ main.sh is executable"
else
    echo "  ⚠ main.sh is not executable, fixing..."
    chmod +x "$MAIN_SH"
    echo "  ✓ Fixed"
fi

# Check library files
for lib in utils tree complexity deps stats; do
    if [[ -f "${SCRIPT_DIR}/lib/${lib}.sh" ]]; then
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

# Create sample output for verification
echo ""
echo "Generating sample output..."
SAMPLE_OUTPUT="${SCOUT_CONFIG_DIR}/output/sample-tree.txt"
if bash "$MAIN_SH" tree --dir "${SCRIPT_DIR}/.." --max-depth 2 --format text > "$SAMPLE_OUTPUT" 2>/dev/null; then
    echo "  ✓ Sample tree generated: ${SAMPLE_OUTPUT}"
else
    echo "  ⚠ Could not generate sample output"
fi

echo ""
echo "============================================"
echo "Scout Subagent Plugin installed successfully!"
echo "============================================"
echo ""
echo "Quick Start:"
echo "  oml scout help              # Show help"
echo "  oml scout tree              # Generate file tree"
echo "  oml scout stats --quick     # Quick statistics"
echo "  oml scout analyze           # Analyze codebase"
echo "  oml scout report            # Generate report"
echo ""
echo "Examples:"
echo "  # Generate tree with custom depth"
echo "  oml scout tree --dir ./src --max-depth 3"
echo ""
echo "  # Analyze with JSON output"
echo "  oml scout analyze --format json --output analysis.json"
echo ""
echo "  # Generate comprehensive report"
echo "  oml scout report --format markdown --output report.md"
echo ""
echo "  # Dependency analysis"
echo "  oml scout deps --dir ./src --format markdown"
echo ""
echo "Configuration:"
echo "  Config: ${SCOUT_CONFIG_DIR}/config.json"
echo "  Output: ${SCOUT_CONFIG_DIR}/output/"
echo ""
echo "Environment Variables:"
echo "  OML_SCOUT_OUTPUT_FORMAT     Default: markdown"
echo "  OML_SCOUT_MAX_DEPTH         Default: 10"
echo "  OML_SCOUT_EXCLUDE_PATTERNS  Default: node_modules,.git,__pycache__,..."
echo ""
