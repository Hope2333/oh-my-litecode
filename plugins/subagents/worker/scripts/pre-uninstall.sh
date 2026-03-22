#!/usr/bin/env bash
# Pre-uninstall script for Worker Subagent Plugin

set -euo pipefail

echo "Uninstalling Worker Subagent Plugin..."

# Detect platform
if [[ -d "/data/data/com.termux/files/usr" ]]; then
    PLATFORM="termux"
    PREFIX="/data/data/com.termux/files/usr"
else
    PLATFORM="gnu-linux"
    PREFIX="/usr/local"
fi

# Check for running tasks
echo "Checking for running tasks..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OML_CORE_DIR="${SCRIPT_DIR}/../../../core"

if [[ -f "${OML_CORE_DIR}/task-registry.sh" ]]; then
    source "${OML_CORE_DIR}/task-registry.sh"
    
    # Get running tasks count
    local running_count
    running_count=$(python3 - "${OML_TASKS_REGISTRY:-${HOME}/.oml/tasks/registry.json}" <<'PY'
import json
import sys

registry_path = sys.argv[1]
try:
    with open(registry_path, 'r') as f:
        data = json.load(f)
    running = [t for t in data.get('tasks', []) if t['status'] == 'running']
    print(len(running))
except:
    print(0)
PY
)
    
    if [[ "$running_count" -gt 0 ]]; then
        echo ""
        echo "Warning: ${running_count} task(s) still running!"
        echo ""
        echo "Running tasks will be cancelled. Continue? (y/N)"
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo "Cancelling all running tasks..."
            python3 - "${OML_TASKS_REGISTRY}" <<'PY'
import json
import sys
import os

registry_path = sys.argv[1]
with open(registry_path, 'r') as f:
    data = json.load(f)

for task in data.get('tasks', []):
    if task['status'] == 'running':
        pid = task.get('pid', 0)
        if pid > 0:
            try:
                os.kill(pid, 15)  # SIGTERM
                print(f"  Cancelled: {task['task_id']} (PID: {pid})")
            except:
                print(f"  Failed to cancel: {task['task_id']}")
PY
        else
            echo "Uninstall cancelled."
            exit 1
        fi
    fi
fi

# Ask about keeping configuration
echo ""
echo "Configuration files and task history will be preserved in:"
echo "  ~/.oml/tasks/"
echo "  ~/.local/home/worker/"
echo ""
echo "To remove completely, run:"
echo "  rm -rf ~/.oml/tasks"
echo "  rm -rf ~/.local/home/worker"

echo ""
echo "Uninstall complete."
