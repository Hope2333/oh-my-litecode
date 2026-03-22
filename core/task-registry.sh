#!/usr/bin/env bash
# OML Task Registry
# Manages subagent task lifecycle and status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to find OML root
if [[ -z "${OML_ROOT:-}" ]]; then
    if [[ "$(basename "$SCRIPT_DIR")" == "core" ]]; then
        export OML_ROOT="$(dirname "$SCRIPT_DIR")"
    fi
fi

# Source platform if available
if [[ -f "${SCRIPT_DIR}/platform.sh" ]]; then
    source "${SCRIPT_DIR}/platform.sh"
fi

# Directories
OML_TASKS_DIR="${OML_TASKS_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/tasks}"
OML_TASKS_REGISTRY="${OML_TASKS_DIR}/registry.json"
OML_TASKS_LOGS_DIR="${OML_TASKS_DIR}/logs"

# Initialize registry
oml_task_registry_init() {
    mkdir -p "${OML_TASKS_DIR}"
    mkdir -p "${OML_TASKS_LOGS_DIR}"
    if [[ ! -f "${OML_TASKS_REGISTRY}" ]]; then
        cat > "${OML_TASKS_REGISTRY}" <<'EOF'
{
  "tasks": [],
  "completed": []
}
EOF
    fi
}

# Generate unique task ID
oml_task_generate_id() {
    echo "task-$(date +%s)-$$-${RANDOM}"
}

# Register new task
oml_task_register() {
    local task_id="$1"
    local agent="$2"
    local task_desc="$3"
    local scope="${4:-**}"
    local fake_home="$5"
    local pid="${6:-0}"
    
    python3 - "${OML_TASKS_REGISTRY}" "${task_id}" "${agent}" "${task_desc}" "${scope}" "${fake_home}" "${pid}" "${OML_TASKS_LOGS_DIR}" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
task_id = sys.argv[2]
agent = sys.argv[3]
task_desc = sys.argv[4]
scope = sys.argv[5]
fake_home = sys.argv[6]
pid = int(sys.argv[7]) if sys.argv[7] else 0
logs_dir = sys.argv[8]

with open(registry_path, 'r') as f:
    data = json.load(f)

task = {
    'task_id': task_id,
    'agent': agent,
    'task': task_desc,
    'scope': scope,
    'status': 'running' if pid > 0 else 'pending',
    'created_at': datetime.utcnow().isoformat() + 'Z',
    'updated_at': datetime.utcnow().isoformat() + 'Z',
    'fake_home': fake_home,
    'pid': pid,
    'log_file': f"{logs_dir}/{task_id}.log"
}

data['tasks'].append(task)

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Registered task: {task_id}")
PY
}

# Update task status
oml_task_update_status() {
    local task_id="$1"
    local status="$2"
    
    python3 - "${OML_TASKS_REGISTRY}" "${task_id}" "${status}" <<'PY'
import json
import sys
from datetime import datetime

registry_path = sys.argv[1]
task_id = sys.argv[2]
new_status = sys.argv[3]

with open(registry_path, 'r') as f:
    data = json.load(f)

found = False
for task in data['tasks']:
    if task['task_id'] == task_id:
        task['status'] = new_status
        task['updated_at'] = datetime.utcnow().isoformat() + 'Z'
        found = True
        break

# Move to completed if status is terminal
if found and new_status in ['completed', 'cancelled', 'failed']:
    task = data['tasks'].pop(next(i for i, t in enumerate(data['tasks']) if t['task_id'] == task_id))
    task['completed_at'] = datetime.utcnow().isoformat() + 'Z'
    data['completed'].append(task)

with open(registry_path, 'w') as f:
    json.dump(data, f, indent=2)
PY
}

# List all tasks
oml_task_list() {
    local status_filter="${1:-all}"
    
    python3 - "${OML_TASKS_REGISTRY}" "${status_filter}" <<'PY'
import json
import sys

registry_path = sys.argv[1]
status_filter = sys.argv[2]

with open(registry_path, 'r') as f:
    data = json.load(f)

print(f"{'TASK_ID':<30} {'AGENT':<10} {'STATUS':<10} {'SCOPE':<20}")
print("=" * 75)

tasks = data['tasks'] if status_filter == 'all' else [t for t in data['tasks'] if t['status'] == status_filter]
for task in tasks:
    print(f"{task['task_id']:<30} {task['agent']:<10} {task['status']:<10} {task['scope']:<20}")

if status_filter in ['all', 'running']:
    print()
    completed = data.get('completed', [])[-5:]  # Last 5 completed
    if completed:
        print("Recently completed:")
        for task in completed:
            print(f"  ✓ {task['task_id']} ({task['status']})")
PY
}

# Get task info
oml_task_info() {
    local task_id="$1"
    
    python3 - "${OML_TASKS_REGISTRY}" "${task_id}" <<'PY'
import json
import sys

registry_path = sys.argv[1]
task_id = sys.argv[2]

with open(registry_path, 'r') as f:
    data = json.load(f)

for task in data['tasks']:
    if task['task_id'] == task_id:
        print(json.dumps(task, indent=2))
        sys.exit(0)

for task in data.get('completed', []):
    if task['task_id'] == task_id:
        print(json.dumps(task, indent=2))
        sys.exit(0)

print(f"Task not found: {task_id}", file=sys.stderr)
sys.exit(1)
PY
}

# Check scope conflicts
oml_task_check_conflict() {
    local new_scope="$1"
    
    python3 - "${OML_TASKS_REGISTRY}" "${new_scope}" <<'PY'
import json
import sys
import fnmatch

registry_path = sys.argv[1]
new_scope = sys.argv[2]

def scopes_overlap(s1, s2):
    """Simple scope overlap detection"""
    if s1 == '**' or s2 == '**':
        return True
    if s1.startswith(s2.rstrip('*')) or s2.startswith(s1.rstrip('*')):
        return True
    if s1 == s2:
        return True
    return False

with open(registry_path, 'r') as f:
    data = json.load(f)

conflicts = []
for task in data['tasks']:
    if task['status'] == 'running':
        if scopes_overlap(new_scope, task['scope']):
            conflicts.append({
                'task_id': task['task_id'],
                'scope': task['scope'],
                'task': task['task']
            })

if conflicts:
    print("Warning: Scope conflicts detected!")
    for c in conflicts:
        print(f"  - {c['task_id']}: {c['scope']} ({c['task']})")
    print()
    print("Use --force to override or adjust scope patterns")
    sys.exit(1)
else:
    print("No scope conflicts detected")
    sys.exit(0)
PY
}

# Cancel task
oml_task_cancel() {
    local task_id="$1"
    
    # Get PID
    local pid
    pid=$(python3 - "${OML_TASKS_REGISTRY}" "${task_id}" <<'PY'
import json
import sys

registry_path = sys.argv[1]
task_id = sys.argv[2]

with open(registry_path, 'r') as f:
    data = json.load(f)

for task in data['tasks']:
    if task['task_id'] == task_id:
        print(task.get('pid', 0))
        sys.exit(0)

print(0)
PY
)
    
    if [[ "$pid" -gt 0 ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        oml_task_update_status "$task_id" "cancelled"
        echo "Cancelled task: $task_id (PID: $pid)"
    else
        echo "Task not running: $task_id"
        oml_task_update_status "$task_id" "cancelled"
    fi
}

# Show task logs
oml_task_logs() {
    local task_id="$1"
    local follow="${2:-false}"
    
    local log_file="${OML_TASKS_LOGS_DIR}/${task_id}.log"
    
    if [[ -f "$log_file" ]]; then
        if [[ "$follow" == "true" || "$follow" == "-f" ]]; then
            tail -f "$log_file"
        else
            cat "$log_file"
        fi
    else
        echo "Log file not found: $log_file"
        return 1
    fi
}

# Wait for all tasks
oml_task_wait_all() {
    python3 - "${OML_TASKS_REGISTRY}" <<'PY'
import json
import sys
import os
import time

registry_path = sys.argv[1]

while True:
    with open(registry_path, 'r') as f:
        data = json.load(f)
    
    running = [t for t in data['tasks'] if t['status'] == 'running']
    
    if not running:
        print("All tasks completed")
        break
    
    print(f"Waiting for {len(running)} task(s)...")
    for task in running:
        pid = task.get('pid', 0)
        if pid > 0:
            try:
                os.kill(pid, 0)
                print(f"  Running: {task['task_id']} (PID: {pid})")
            except ProcessLookupError:
                print(f"  Process died: {task['task_id']}")
    
    time.sleep(2)
PY
}

# Main CLI entry
main() {
    local action="${1:-help}"
    shift || true
    
    case "$action" in
        init)
            oml_task_registry_init
            echo "Task registry initialized at: ${OML_TASKS_REGISTRY}"
            ;;
        register)
            oml_task_register "$@"
            ;;
        update)
            oml_task_update_status "$@"
            ;;
        list)
            oml_task_list "$@"
            ;;
        info)
            oml_task_info "$@"
            ;;
        check-conflict)
            oml_task_check_conflict "$@"
            ;;
        cancel)
            oml_task_cancel "$@"
            ;;
        logs)
            oml_task_logs "$@"
            ;;
        wait-all)
            oml_task_wait_all
            ;;
        help|--help|-h)
            cat <<EOF
OML Task Registry

Usage: oml tasks <action> [args]

Actions:
  init                      Initialize task registry
  register <id> <agent> <task> [scope] [fake_home] [pid]  Register new task
  update <id> <status>      Update task status
  list [status]             List tasks (all|running|pending)
  info <id>                 Show task details
  check-conflict <scope>    Check for scope conflicts
  cancel <id>               Cancel running task
  logs <id> [-f]            Show task logs (-f for follow)
  wait-all                  Wait for all tasks to complete

Examples:
  oml tasks init
  oml tasks list
  oml tasks list running
  oml tasks info task-12345
  oml tasks logs task-12345 -f
  oml tasks cancel task-12345
  oml tasks wait-all
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml tasks help' for usage"
            return 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
