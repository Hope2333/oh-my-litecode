#!/usr/bin/env bash
# Post-install script for Worker Subagent Plugin

set -euo pipefail

echo "Installing Worker Subagent Plugin..."

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
for dep in nodejs python3 git bash; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "  ✓ $dep found"
    else
        echo "  ✗ $dep not found"
    fi
done

# Initialize task registry
echo ""
echo "Initializing task registry..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OML_CORE_DIR="${SCRIPT_DIR}/../../../core"

if [[ -f "${OML_CORE_DIR}/task-registry.sh" ]]; then
    source "${OML_CORE_DIR}/task-registry.sh"
    oml_task_registry_init
    echo "✓ Task registry initialized"
else
    echo "Warning: task-registry.sh not found"
fi

# Create worker base directory
WORKER_HOME="${HOME}/.local/home/worker"
echo ""
echo "Creating worker base directory: ${WORKER_HOME}"
mkdir -p "${WORKER_HOME}/.qwen"
mkdir -p "${WORKER_HOME}/.cache"
mkdir -p "${WORKER_HOME}/.local/share"

# Create default worker config
cat > "${WORKER_HOME}/.qwen/worker-config.json" <<EOF
{
  "defaultAgent": "qwen",
  "defaultScope": "**",
  "maxParallelTasks": 3,
  "autoRetry": false,
  "logLevel": "info"
}
EOF

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  oml worker spawn qwen --task \"实现用户认证模块\" --scope \"src/auth/**\""
echo "  oml worker status"
echo "  oml worker logs --task-id <task-id>"
echo ""
echo "Examples:"
echo "  # Single task (wait for completion)"
echo "  oml worker spawn qwen --task \"写一个排序算法\""
echo ""
echo "  # Background task"
echo "  oml worker spawn qwen --task \"实现 API\" --scope \"src/api/**\" --background"
echo ""
echo "  # Multiple parallel tasks"
echo "  oml worker spawn qwen --task \"任务 A\" --scope \"src/a/**\" --background"
echo "  oml worker spawn qwen --task \"任务 B\" --scope \"src/b/**\" --background"
echo "  oml worker wait"
echo ""
echo "Configuration:"
echo "  Task Registry: ~/.oml/tasks/registry.json"
echo "  Task Logs: ~/.oml/tasks/logs/"
echo "  Worker Config: ${WORKER_HOME}/.qwen/worker-config.json"
