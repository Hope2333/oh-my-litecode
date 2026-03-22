#!/usr/bin/env bash
# Pre-uninstall script for Plan Agent Plugin

set -euo pipefail

echo "Uninstalling Plan Agent Plugin..."

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

for symlink in "oml-plan"; do
    if [[ -L "${BIN_DIR}/${symlink}" ]]; then
        echo "Removing symlink: ${BIN_DIR}/${symlink}"
        rm "${BIN_DIR}/${symlink}"
    fi
done

# Ask about configuration and data
DATA_DIR="${HOME}/.oml/plans"
LOGS_DIR="${HOME}/.oml/logs/plan"
CONFIG_FILE="${HOME}/.oml/plan-config.json"
TEMPLATES_FILE="${DATA_DIR}/templates.json"

echo ""
echo "The following files will be preserved:"
echo ""

# Count plans
if [[ -f "${DATA_DIR}/plans.json" ]]; then
    plan_count=$(python3 -c "import json; print(len(json.load(open('${DATA_DIR}/plans.json')).get('plans', [])))" 2>/dev/null || echo "unknown")
    echo "  Plans data: ${DATA_DIR}/plans.json (${plan_count} plans)"
fi

if [[ -f "${TEMPLATES_FILE}" ]]; then
    template_count=$(python3 -c "import json; print(len(json.load(open('${TEMPLATES_FILE}')).get('templates', [])))" 2>/dev/null || echo "unknown")
    echo "  Templates:  ${TEMPLATES_FILE} (${template_count} templates)"
fi

if [[ -d "$LOGS_DIR" ]]; then
    log_count=$(find "$LOGS_DIR" -type f -name "*.log" 2>/dev/null | wc -l)
    echo "  Logs:       ${LOGS_DIR} (${log_count} files)"
fi

if [[ -f "$CONFIG_FILE" ]]; then
    echo "  Config:     ${CONFIG_FILE}"
fi

echo ""
echo "To remove all plan agent data, run:"
echo "  rm -rf ${DATA_DIR}"
echo "  rm -rf ${LOGS_DIR}"
echo "  rm -f ${CONFIG_FILE}"
echo ""
echo "Note: Plans data will be preserved for future re-installation."
echo ""
echo "Uninstall complete."
