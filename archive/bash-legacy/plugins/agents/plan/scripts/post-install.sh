#!/usr/bin/env bash
# Post-install script for Plan Agent Plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

echo "Installing Plan Agent Plugin..."

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
for dep in bash python3; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  ✓ $dep found: $(command -v "$dep")"
    else
        echo "  ✗ $dep not found"
    fi
done

# Create data directory
DATA_DIR="${HOME}/.oml/plans"
echo "Creating data directory: ${DATA_DIR}"
mkdir -p "${DATA_DIR}"
chmod 755 "${DATA_DIR}"

# Create logs directory
LOGS_DIR="${HOME}/.oml/logs/plan"
echo "Creating logs directory: ${LOGS_DIR}"
mkdir -p "${LOGS_DIR}"
chmod 755 "${LOGS_DIR}"

# Create compatibility symlink
echo "Creating compatibility symlink..."
BIN_DIR="${PREFIX}/bin"

if [[ -w "$BIN_DIR" ]] || command -v sudo >/dev/null 2>&1; then
    # Create oml-plan wrapper
    cat > "${BIN_DIR}/oml-plan" <<'OML_PLAN_WRAPPER'
#!/usr/bin/env bash
# OML Plan Agent wrapper
# Redirects to: oml plan
exec oml plan "$@"
OML_PLAN_WRAPPER
    chmod +x "${BIN_DIR}/oml-plan"
    echo "Created: ${BIN_DIR}/oml-plan"
else
    echo "Cannot create system symlinks. Run manually or use sudo:"
    echo "  sudo ln -sf ${PLUGIN_DIR}/main.sh ${BIN_DIR}/oml-plan"
fi

# Create default configuration
CONFIG_DIR="${HOME}/.oml"
CONFIG_FILE="${CONFIG_DIR}/plan-config.json"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Creating default configuration..."
    cat > "${CONFIG_FILE}" <<'EOF'
{
  "verbose": false,
  "default_complexity": "medium",
  "default_format": "text",
  "data_dir": "~/.oml/plans",
  "auto_decompose": true,
  "estimate_hours": true
}
EOF
fi

# Initialize task registry integration
echo "Initializing task registry integration..."
if [[ -f "${HOME}/.oml/tasks/registry.json" ]]; then
    echo "  ✓ Task registry found"
else
    echo "  ℹ Task registry will be initialized on first use"
fi

# Create sample template
TEMPLATES_FILE="${DATA_DIR}/templates.json"
if [[ ! -f "${TEMPLATES_FILE}" ]]; then
    echo "Creating sample templates..."
    cat > "${TEMPLATES_FILE}" <<'EOF'
{
  "templates": [
    {
      "name": "feature",
      "description": "新功能开发模板",
      "phases": ["research", "design", "implement", "test", "review", "deploy"],
      "default_complexity": "medium"
    },
    {
      "name": "bugfix",
      "description": "Bug 修复模板",
      "phases": ["research", "implement", "test", "review"],
      "default_complexity": "simple"
    },
    {
      "name": "refactor",
      "description": "代码重构模板",
      "phases": ["research", "design", "implement", "test"],
      "default_complexity": "complex"
    }
  ]
}
EOF
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  oml plan --help              Show help"
echo "  oml plan create \"功能名称\"    创建新计划"
echo "  oml plan list                列出所有计划"
echo "  oml plan status <plan-id>    查看计划状态"
echo "  oml plan update <plan-id>    更新计划"
echo "  oml plan complete <plan-id>  标记完成"
echo ""
echo "Examples:"
echo "  oml plan create \"实现用户登录功能\" --complexity=medium"
echo "  oml plan create \"重构支付模块\" --deadline=2024-12-31"
echo "  oml plan list --status=in_progress"
echo "  oml plan status plan-123456 --format=json"
echo ""
echo "Environment Variables:"
echo "  OML_PLAN_VERBOSE=true      Enable verbose output"
echo "  OML_OUTPUT_FORMAT=json     Output JSON format"
echo ""
echo "Configuration:"
echo "  Config:     ${CONFIG_FILE}"
echo "  Data:       ${DATA_DIR}"
echo "  Logs:       ${LOGS_DIR}"
echo "  Templates:  ${TEMPLATES_FILE}"
