#!/usr/bin/env bash
# OML Version Consistency Checker
# Verifies that all version markers are consistent at 0.2.0
#
# Usage: ./scripts/verify-version.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OML_ROOT="${SCRIPT_DIR}/.."
EXPECTED_VERSION="0.2.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "╔═══════════════════════════════════════╗"
echo "║  OML Version Consistency Checker      ║"
echo "╚═══════════════════════════════════════╝"
echo ""

ERRORS=0

# Check core version
echo "Checking core version..."
core_version=$(grep 'OML_VERSION=' "${OML_ROOT}/oml" | cut -d'"' -f2 || echo "not found")

if [[ "$core_version" == "$EXPECTED_VERSION" ]]; then
    echo -e "  Core: ${GREEN}✓ $core_version${NC}"
else
    echo -e "  Core: ${RED}✗ $core_version (expected $EXPECTED_VERSION)${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check plugin versions
echo ""
echo "Checking plugin versions..."

plugin_files=$(find "${OML_ROOT}/plugins/" -name "plugin.json" -type f 2>/dev/null || true)
plugin_count=0
error_plugins=0

for plugin_file in $plugin_files; do
    plugin_count=$((plugin_count + 1))
    plugin_version=$(grep '"version"' "$plugin_file" | cut -d'"' -f4 || echo "not found")
    plugin_name=$(basename "$(dirname "$plugin_file")")
    
    if [[ "$plugin_version" == "$EXPECTED_VERSION" ]]; then
        echo -e "  $plugin_name: ${GREEN}✓${NC}"
    else
        echo -e "  $plugin_name: ${RED}✗ $plugin_version${NC}"
        error_plugins=$((error_plugins + 1))
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "Total plugins: $plugin_count"
echo -e "Error plugins: ${RED}$error_plugins${NC}"

# Check README versions
echo ""
echo "Checking README versions..."

for readme in "${OML_ROOT}/README.md" "${OML_ROOT}/README-OML.md" "${OML_ROOT}/QUICKSTART.md"; do
    if [[ -f "$readme" ]]; then
        readme_version=$(grep -o "0\.[0-9]\+\.[0-9]\+" "$readme" | head -1 || echo "not found")
        readme_name=$(basename "$readme")
        
        if [[ "$readme_version" == "$EXPECTED_VERSION" ]]; then
            echo -e "  $readme_name: ${GREEN}✓${NC}"
        else
            echo -e "  $readme_name: ${YELLOW}! $readme_version${NC}"
        fi
    fi
done

# Summary
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║  Summary                              ║"
echo "╚═══════════════════════════════════════╝"

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ Version consistency check passed${NC}"
    echo "Expected version: $EXPECTED_VERSION"
    echo "Total plugins checked: $plugin_count"
    echo "Error plugins: 0"
    exit 0
else
    echo -e "${RED}✗ Version inconsistency detected${NC}"
    echo "Expected version: $EXPECTED_VERSION"
    echo "Total errors: $ERRORS"
    echo ""
    echo "To fix:"
    echo "  1. Update oml: sed -i 's/OML_VERSION=\"[^\"]*\"/OML_VERSION=\"$EXPECTED_VERSION\"/g' oml"
    echo "  2. Update plugins: for f in plugins/*/plugin.json; do sed -i 's/\"version\": \"[^\"]*\"/\"version\": \"$EXPECTED_VERSION\"/g' \$f; done"
    exit 1
fi
