#!/usr/bin/env bash
# OML Subagent Worker Plugin
# Implements Commander-Worker architecture pattern

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi
if [[ -f "${OML_CORE_DIR}/task-registry.sh" ]]; then
    source "${OML_CORE_DIR}/task-registry.sh"
fi

PLUGIN_NAME="worker"

# Spawn a new subagent task
oml_subagent_spawn() {
    local agent="${1:-qwen}"
    local task_desc=""
    local scope="**"
    local exclude=""
    local background=false
    local force=false
    local session_id=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task)
                task_desc="$2"
                shift 2
                ;;
            --scope)
                scope="$2"
                shift 2
                ;;
            --exclude)
                exclude="$2"
                shift 2
                ;;
            --background|-b)
                background=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --session-id)
                session_id="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$task_desc" ]]; then
        echo "Error: --task is required" >&2
        echo "Usage: oml worker spawn <agent> --task \"<description>\" [--scope \"<pattern>\"]" >&2
        return 1
    fi
    
    # Generate session ID if not provided
    if [[ -z "$session_id" ]]; then
        session_id="$(oml_task_generate_id)"
    fi
    
    # Check scope conflicts (unless --force)
    if [[ "$force" != true ]]; then
        echo "Checking scope conflicts..."
        if ! oml_task_check_conflict "$scope" 2>&1; then
            echo ""
            echo "Scope conflicts detected. Use --force to override." >&2
            return 1
        fi
    fi
    
    # Setup isolated fake home for this task
    local fake_home
    fake_home="$(oml_get_fake_home "${agent}-${session_id}")"
    echo "Setting up isolated environment: ${fake_home}"
    mkdir -p "${fake_home}/.qwen"
    mkdir -p "${fake_home}/.cache"
    mkdir -p "${fake_home}/.local/share"
    
    # Copy base config if exists
    local base_config="${HOME}/.local/home/${agent}/.qwen/settings.json"
    if [[ -f "$base_config" ]]; then
        cp "$base_config" "${fake_home}/.qwen/"
    fi
    
    # Create task-specific config
    cat > "${fake_home}/.qwen/task.json" <<EOF
{
  "task_id": "${session_id}",
  "task": "${task_desc}",
  "scope": "${scope}",
  "exclude": "${exclude}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    # Start the agent in background
    echo "Spawning subagent: ${agent}"
    echo "  Task: ${task_desc}"
    echo "  Scope: ${scope}"
    echo "  Session: ${session_id}"
    
    local log_file="${OML_TASKS_LOGS_DIR}/${session_id}.log"
    
    (
        # Setup environment for isolated execution
        export HOME="${fake_home}"
        export _FAKEHOME="${fake_home}"
        export OML_TASK_ID="${session_id}"
        export OML_TASK_SCOPE="${scope}"
        export OML_TASK_EXCLUDE="${exclude}"
        
        # Add task context to prompt
        local task_context="[任务：${task_desc}] [Scope: ${scope}]"
        
        # Run the agent with task context
        # Note: This assumes 'oml <agent>' command exists
        if command -v oml >/dev/null 2>&1; then
            oml "${agent}" "${task_context}"
        else
            echo "Error: oml command not found" >&2
            exit 1
        fi
        
        # Update status on completion
        if [[ -f "${OML_CORE_DIR}/task-registry.sh" ]]; then
            source "${OML_CORE_DIR}/task-registry.sh"
            oml_task_update_status "${session_id}" "completed"
        fi
    ) > "${log_file}" 2>&1 &
    
    local pid=$!
    
    # Register task
    oml_task_register "${session_id}" "${agent}" "${task_desc}" "${scope}" "${fake_home}" "${pid}"
    
    echo ""
    echo "✓ Spawned subagent task: ${session_id}"
    echo "  Agent: ${agent}"
    echo "  Task: ${task_desc}"
    echo "  Scope: ${scope}"
    echo "  PID: ${pid}"
    echo "  Log: ${log_file}"
    echo ""
    
    if [[ "$background" != true ]]; then
        echo "Waiting for task to complete..."
        wait "${pid}"
        echo ""
        echo "Task completed!"
        
        # Show result
        if [[ -f "$log_file" ]]; then
            echo ""
            echo "=== Task Output ==="
            tail -20 "$log_file"
        fi
    else
        echo "Task running in background."
        echo "Use 'oml worker status' to check progress."
        echo "Use 'oml worker logs ${session_id}' to view logs."
    fi
}

# Show status of all tasks
oml_subagent_status() {
    local status_filter="${1:-all}"
    
    echo "Subagent Tasks"
    echo "=============="
    echo ""
    oml_task_list "$status_filter"
}

# Show logs for a task
oml_subagent_logs() {
    local task_id=""
    local follow=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task-id)
                task_id="$2"
                shift 2
                ;;
            --follow|-f)
                follow=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$task_id" ]]; then
        echo "Error: --task-id is required" >&2
        return 1
    fi
    
    local follow_flag="false"
    if [[ "$follow" == true ]]; then
        follow_flag="true"
    fi
    
    oml_task_logs "$task_id" "$follow_flag"
}

# Cancel a running task
oml_subagent_cancel() {
    local task_id=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task-id)
                task_id="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$task_id" ]]; then
        echo "Error: --task-id is required" >&2
        return 1
    fi
    
    oml_task_cancel "$task_id"
}

# Wait for all background tasks
oml_subagent_wait() {
    echo "Waiting for all subagent tasks to complete..."
    oml_task_wait_all
}

# Show detailed info about a task
oml_subagent_info() {
    local task_id=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task-id)
                task_id="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$task_id" ]]; then
        echo "Error: --task-id is required" >&2
        return 1
    fi
    
    oml_task_info "$task_id"
}

# Main entry point
main() {
    # Initialize task registry
    oml_task_registry_init
    
    local action="${1:-help}"
    shift || true
    
    case "$action" in
        spawn)
            oml_subagent_spawn "$@"
            ;;
        status)
            oml_subagent_status "$@"
            ;;
        logs)
            oml_subagent_logs "$@"
            ;;
        cancel)
            oml_subagent_cancel "$@"
            ;;
        wait)
            oml_subagent_wait
            ;;
        info)
            oml_subagent_info "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Subagent Worker

Usage: oml worker <action> [args]

Actions:
  spawn <agent> --task "<desc>" [options]  Spawn a new subagent task
  status [filter]                          Show task status
  logs --task-id "<id>" [-f]               Show task logs
  cancel --task-id "<id>"                  Cancel running task
  wait                                     Wait for all tasks
  info --task-id "<id>"                    Show task details

Spawn Options:
  --task "<desc>"       Task description (required)
  --scope "<pattern>"   File scope pattern (default: **)
  --exclude "<pattern>" Excluded patterns
  --background|-b       Run in background
  --force               Override scope conflicts
  --session-id "<id>"   Custom session ID

Examples:
  oml worker spawn qwen --task "实现用户认证模块" --scope "src/auth/**"
  oml worker spawn qwen --task "实现 API" --scope "src/api/**" --background
  oml worker status
  oml worker status running
  oml worker logs --task-id "task-12345"
  oml worker logs --task-id "task-12345" -f
  oml worker cancel --task-id "task-12345"
  oml worker wait

Scope Patterns:
  **              All files
  src/**          All files in src/
  **/*.ts         All TypeScript files
  src/auth/**     All files in src/auth/
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml worker help' for usage"
            return 1
            ;;
    esac
}

main "$@"
