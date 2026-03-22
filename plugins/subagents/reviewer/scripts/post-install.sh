#!/usr/bin/env bash
# Post-install script for Reviewer Subagent Plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "Installing Reviewer Subagent Plugin..."
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

for dep in bash python3 jq find grep; do
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
for dep in git npm node shellcheck; do
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
CONFIG_DIR="${HOME}/.local/share/oml/reviewer"
CACHE_DIR="${HOME}/.local/cache/oml/reviewer"

echo ""
echo "Creating directories..."
mkdir -p "${CONFIG_DIR}"
mkdir -p "${CACHE_DIR}/reports"
mkdir -p "${CACHE_DIR}/cache"
mkdir -p "${CONFIG_DIR}/rules"
echo "  ✓ Config directory: ${CONFIG_DIR}"
echo "  ✓ Cache directory: ${CACHE_DIR}"

# Create default configuration
echo ""
echo "Creating default configuration..."
cat > "${CONFIG_DIR}/config.json" <<'EOF'
{
  "outputFormat": "markdown",
  "maxIssues": 100,
  "excludePatterns": "node_modules,.git,__pycache__,.venv,dist,build,.cache,target,coverage,.idea,.vscode",
  "security": {
    "enabled": true,
    "includeSensitiveFiles": true,
    "checkDependencies": true,
    "checkHeaders": true
  },
  "style": {
    "enabled": true,
    "maxLineLength": 120,
    "indentSize": 4,
    "useTabs": false
  },
  "performance": {
    "enabled": true,
    "checkLoops": true,
    "checkMemory": true,
    "checkBlocking": true
  },
  "bestPractices": {
    "enabled": true,
    "checkErrorHandling": true,
    "checkLogging": true,
    "checkDocumentation": true,
    "checkDuplication": true,
    "maxFunctionLines": 50
  },
  "strictMode": false,
  "verbose": false,
  "quiet": false
}
EOF
echo "  ✓ Default config created"

# Create default custom rules
echo ""
echo "Creating default custom rules..."
cat > "${CONFIG_DIR}/rules/custom-rules.json" <<'EOF'
{
  "version": "1.0",
  "rules": [],
  "ignorePatterns": [],
  "severityOverrides": {}
}
EOF
echo "  ✓ Custom rules file created"

# Create .gitkeep files for cache directories
touch "${CACHE_DIR}/reports/.gitkeep"
touch "${CACHE_DIR}/cache/.gitkeep"
touch "${CONFIG_DIR}/rules/.gitkeep"
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
for lib in utils style security performance best-practices report; do
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

# Create sample report template
echo ""
echo "Creating sample report template..."
cat > "${CONFIG_DIR}/report-template.md" <<'EOF'
# Code Review Report

**Project:** {{project_name}}
**Date:** {{generated_at}}
**Reviewer:** {{reviewer_name}}

## Executive Summary

{{summary}}

## Findings

{{findings}}

## Recommendations

{{recommendations}}

## Appendix

{{appendix}}
EOF
echo "  ✓ Report template created"

# Print usage information
echo ""
echo "============================================"
echo "Reviewer Subagent Plugin installed successfully!"
echo "============================================"
echo ""
echo "Quick Start:"
echo "  oml reviewer help              # Show help"
echo "  oml reviewer code ./src        # Run full code review"
echo "  oml reviewer security ./src    # Security audit"
echo "  oml reviewer style ./src       # Style check"
echo "  oml reviewer report .          # Generate report"
echo ""
echo "Examples:"
echo "  # Full code review with JSON output"
echo "  oml reviewer code ./src --format json --output review.json"
echo ""
echo "  # Security audit only"
echo "  oml reviewer security . --format markdown"
echo ""
echo "  # Style check with custom line length"
echo "  oml reviewer style . --max-line-length 100"
echo ""
echo "  # Generate HTML report"
echo "  oml reviewer report . --format html --output report.html"
echo ""
echo "  # Quick summary"
echo "  oml reviewer report . --quick"
echo ""
echo "Configuration:"
echo "  Config: ${CONFIG_DIR}/config.json"
echo "  Cache:  ${CACHE_DIR}"
echo "  Rules:  ${CONFIG_DIR}/rules/"
echo ""
echo "Environment Variables:"
echo "  OML_REVIEWER_OUTPUT_FORMAT       Default: markdown"
echo "  OML_REVIEWER_MAX_ISSUES          Default: 100"
echo "  OML_REVIEWER_EXCLUDE_PATTERNS    Default: node_modules,.git,..."
echo "  OML_REVIEWER_SECURITY_ENABLED    Default: true"
echo "  OML_REVIEWER_STYLE_ENABLED       Default: true"
echo "  OML_REVIEWER_PERFORMANCE_ENABLED Default: true"
echo "  OML_REVIEWER_BEST_PRACTICES_ENABLED Default: true"
echo "  OML_REVIEWER_STRICT_MODE         Default: false"
echo ""
echo "Supported Checks:"
echo "  • Security: SQL injection, XSS, command injection, hardcoded secrets"
echo "  • Style: Line length, indentation, naming conventions, trailing whitespace"
echo "  • Performance: Inefficient loops, memory leaks, blocking operations"
echo "  • Best Practices: Error handling, logging, documentation, code duplication"
echo ""
