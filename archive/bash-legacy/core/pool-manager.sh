#!/usr/bin/env bash
# DEPRECATED: Migrated to TypeScript (packages/core/src/pool/manager.ts)
# Archive Date: 2026-03-26
# Use: @oml/core PoolManager instead

# OML Worker Pool Manager
# Worker 池管理核心 - 提供 Worker 生命周期管理和动态扩缩容

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_POOL_MANAGER_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_POOL_MANAGER_LOADED=true

# 尝试查找 OML 根目录
if [[ -z "${OML_ROOT:-}" ]]; then
    if [[ "$(basename "$SCRIPT_DIR")" == "core" ]]; then
        export OML_ROOT="$(dirname "$SCRIPT_DIR")"
    fi
fi

# 源平台模块（如果可用）
if [[ -z "${OML_PLATFORM_LOADED:-}" && -f "${SCRIPT_DIR}/platform.sh" ]]; then
    source "${SCRIPT_DIR}/platform.sh"
    export OML_PLATFORM_LOADED=true
fi

# 源 Task Registry（如果可用）
if [[ -f "${SCRIPT_DIR}/task-registry.sh" ]]; then
    source "${SCRIPT_DIR}/task-registry.sh"
fi

# ============================================================================
# 配置与常量
# ============================================================================

readonly OML_POOL_VERSION="0.1.0"
readonly OML_POOL_DIR="${OML_POOL_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/pool}"
readonly OML_POOL_WORKERS_DIR="${OML_POOL_DIR}/workers"
readonly OML_POOL_STATE_FILE="${OML_POOL_DIR}/state.json"
readonly OML_POOL_LOGS_DIR="${OML_POOL_DIR}/logs"

# Worker 状态
readonly WORKER_STATUS_IDLE="idle"
readonly WORKER_STATUS_BUSY="busy"
readonly WORKER_STATUS_STOPPED="stopped"
readonly WORKER_STATUS_FAILED="failed"

# 池配置默认值
readonly POOL_DEFAULT_MIN_WORKERS=1
readonly POOL_DEFAULT_MAX_WORKERS=10
readonly POOL_DEFAULT_IDLE_TIMEOUT=300  # 5 分钟
readonly POOL_DEFAULT_TASK_TIMEOUT=600  # 10 分钟

# ============================================================================
# 工具函数
# ============================================================================

# 生成唯一 Worker ID
oml_pool_generate_worker_id() {
    echo "worker-$(date +%s%N)-$$-${RANDOM}"
}

# 生成唯一任务 ID
oml_pool_generate_task_id() {
    echo "task-$(date +%s%N)-${RANDOM}"
}

# 获取当前时间戳（秒）
oml_pool_timestamp() {
    date +%s
}

# 获取 ISO 时间戳
oml_pool_iso_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# 日志输出
oml_pool_log() {
    local level="$1"
    local message="$2"
    local worker_id="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_entry="[${timestamp}] [${level}]"
    [[ -n "$worker_id" ]] && log_entry+=" [${worker_id}]"
    log_entry+=" ${message}"

    echo "$log_entry" >&2

    # 写入日志文件
    local log_file="${OML_POOL_LOGS_DIR}/pool-manager.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file" 2>/dev/null || true
}

# 验证 Worker ID
oml_pool_validate_worker_id() {
    local worker_id="$1"
    if [[ -z "$worker_id" ]]; then
        return 1
    fi
    if [[ ! "$worker_id" =~ ^worker-[a-zA-Z0-9_-]+$ ]]; then
        return 1
    fi
    return 0
}

# JSON 辅助函数
oml_pool_json_read() {
    local file="$1"
    local query="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import json
import sys

with open('${file}', 'r') as f:
    data = json.load(f)

query = '${query}'
if not query:
    print(json.dumps(data))
else:
    keys = query.split('.')
    result = data
    for key in keys:
        if isinstance(result, dict):
            result = result.get(key)
        elif isinstance(result, list) and key.isdigit():
            result = result[int(key)]
        else:
            result = None
            break
    if isinstance(result, (dict, list)):
        print(json.dumps(result))
    else:
        print(result if result is not None else '')
" 2>/dev/null || echo ""
}

oml_pool_json_write() {
    local file="$1"
    local data="$2"

    mkdir -p "$(dirname "$file")"
    echo "$data" > "$file"
}

oml_pool_json_update() {
    local file="$1"
    local update_json="$2"

    if [[ ! -f "$file" ]]; then
        echo "{}" > "$file"
    fi

    python3 -c "
import json
import sys

with open('${file}', 'r') as f:
    data = json.load(f)

update = json.loads('${update_json}')
data.update(update)

with open('${file}', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# ============================================================================
# 池初始化
# ============================================================================

# 初始化 Worker 池
oml_pool_init() {
    local min_workers="${1:-$POOL_DEFAULT_MIN_WORKERS}"
    local max_workers="${2:-$POOL_DEFAULT_MAX_WORKERS}"

    mkdir -p "${OML_POOL_WORKERS_DIR}"
    mkdir -p "${OML_POOL_LOGS_DIR}"

    # 初始化状态文件
    local timestamp
    timestamp="$(oml_pool_iso_timestamp)"

    cat > "${OML_POOL_STATE_FILE}" <<EOF
{
  "version": "${OML_POOL_VERSION}",
  "created_at": "${timestamp}",
  "updated_at": "${timestamp}",
  "config": {
    "min_workers": ${min_workers},
    "max_workers": ${max_workers},
    "idle_timeout": ${POOL_DEFAULT_IDLE_TIMEOUT},
    "task_timeout": ${POOL_DEFAULT_TASK_TIMEOUT}
  },
  "workers": {},
  "tasks": {},
  "stats": {
    "total_tasks": 0,
    "completed_tasks": 0,
    "failed_tasks": 0,
    "total_workers_created": 0
  }
}
EOF

    oml_pool_log "INFO" "Pool initialized (min=${min_workers}, max=${max_workers})"

    # 初始化 Task Registry（如果可用）
    if type -t oml_task_registry_init >/dev/null 2>&1; then
        oml_task_registry_init 2>/dev/null || true
    fi

    echo "Pool initialized at: ${OML_POOL_DIR}"
}

# 确保池已初始化
oml_pool_ensure_init() {
    if [[ ! -f "${OML_POOL_STATE_FILE}" ]]; then
        oml_pool_init
    fi
}

# ============================================================================
# Worker 生命周期管理
# ============================================================================

# 创建 Worker
oml_pool_create_worker() {
    local worker_id
    worker_id="$(oml_pool_generate_worker_id)"

    local timestamp
    timestamp="$(oml_pool_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_pool_iso_timestamp)"

    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"

    cat > "$worker_file" <<EOF
{
  "worker_id": "${worker_id}",
  "status": "${WORKER_STATUS_IDLE}",
  "created_at": "${iso_timestamp}",
  "updated_at": "${iso_timestamp}",
  "last_active": ${timestamp},
  "current_task": null,
  "tasks_completed": 0,
  "tasks_failed": 0,
  "pid": 0,
  "metadata": {}
}
EOF

    # 更新池状态
    python3 - "${OML_POOL_STATE_FILE}" "$worker_id" "$worker_file" <<'PY'
import json
import sys

state_file = sys.argv[1]
worker_id = sys.argv[2]
worker_file = sys.argv[3]

with open(state_file, 'r') as f:
    state = json.load(f)

with open(worker_file, 'r') as f:
    worker = json.load(f)

state['workers'][worker_id] = worker
state['stats']['total_workers_created'] += 1
state['updated_at'] = worker['updated_at']

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY

    oml_pool_log "INFO" "Worker created: ${worker_id}"
    echo "$worker_id"
}

# 启动 Worker 进程
oml_pool_start_worker() {
    local worker_id="$1"
    local worker_script="${2:-}"

    if ! oml_pool_validate_worker_id "$worker_id"; then
        oml_pool_log "ERROR" "Invalid worker ID: $worker_id"
        return 1
    fi

    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"
    if [[ ! -f "$worker_file" ]]; then
        oml_pool_log "ERROR" "Worker not found: $worker_id"
        return 1
    fi

    # 更新状态为 busy
    local timestamp
    timestamp="$(oml_pool_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_pool_iso_timestamp)"

    python3 - "$worker_file" "$timestamp" "$iso_timestamp" <<'PY'
import json
import sys

worker_file = sys.argv[1]
timestamp = int(sys.argv[2])
iso_timestamp = sys.argv[3]

with open(worker_file, 'r') as f:
    worker = json.load(f)

worker['status'] = 'busy'
worker['updated_at'] = iso_timestamp
worker['last_active'] = timestamp

with open(worker_file, 'w') as f:
    json.dump(worker, f, indent=2)
PY

    # 如果有 worker 脚本，启动后台进程
    if [[ -n "$worker_script" && -f "$worker_script" ]]; then
        local log_file="${OML_POOL_LOGS_DIR}/${worker_id}.log"
        nohup bash "$worker_script" --worker-id "$worker_id" > "$log_file" 2>&1 &
        local pid=$!

        # 更新 PID
        python3 - "$worker_file" "$pid" <<'PY'
import json
import sys

worker_file = sys.argv[1]
pid = int(sys.argv[2])

with open(worker_file, 'r') as f:
    worker = json.load(f)

worker['pid'] = pid

with open(worker_file, 'w') as f:
    json.dump(worker, f, indent=2)
PY

        oml_pool_log "INFO" "Worker started: ${worker_id} (PID: ${pid})"
    else
        oml_pool_log "INFO" "Worker marked as busy: ${worker_id}"
    fi

    # 更新池状态
    oml_pool_sync_worker_state "$worker_id"

    echo "$worker_id"
}

# 停止 Worker
oml_pool_stop_worker() {
    local worker_id="$1"
    local force="${2:-false}"

    if ! oml_pool_validate_worker_id "$worker_id"; then
        oml_pool_log "ERROR" "Invalid worker ID: $worker_id"
        return 1
    fi

    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"
    if [[ ! -f "$worker_file" ]]; then
        oml_pool_log "ERROR" "Worker not found: $worker_id"
        return 1
    fi

    # 获取 PID
    local pid
    pid=$(oml_pool_json_read "$worker_file" "pid")

    if [[ "$pid" -gt 0 ]] && kill -0 "$pid" 2>/dev/null; then
        if [[ "$force" == "true" ]]; then
            kill -9 "$pid" 2>/dev/null || true
            oml_pool_log "WARN" "Worker force killed: ${worker_id} (PID: ${pid})"
        else
            kill "$pid" 2>/dev/null || true
            oml_pool_log "INFO" "Worker stop signal sent: ${worker_id} (PID: ${pid})"
        fi
    fi

    # 更新状态为 stopped
    local iso_timestamp
    iso_timestamp="$(oml_pool_iso_timestamp)"

    python3 - "$worker_file" "$iso_timestamp" <<'PY'
import json
import sys

worker_file = sys.argv[1]
iso_timestamp = sys.argv[2]

with open(worker_file, 'r') as f:
    worker = json.load(f)

worker['status'] = 'stopped'
worker['updated_at'] = iso_timestamp
worker['pid'] = 0

with open(worker_file, 'w') as f:
    json.dump(worker, f, indent=2)
PY

    oml_pool_sync_worker_state "$worker_id"
    oml_pool_log "INFO" "Worker stopped: ${worker_id}"
}

# 删除 Worker
oml_pool_delete_worker() {
    local worker_id="$1"

    if ! oml_pool_validate_worker_id "$worker_id"; then
        oml_pool_log "ERROR" "Invalid worker ID: $worker_id"
        return 1
    fi

    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"
    if [[ ! -f "$worker_file" ]]; then
        oml_pool_log "ERROR" "Worker not found: $worker_id"
        return 1
    fi

    # 先停止
    oml_pool_stop_worker "$worker_id" "true" 2>/dev/null || true

    # 删除文件
    rm -f "$worker_file"

    # 从池状态中移除
    python3 - "${OML_POOL_STATE_FILE}" "$worker_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
worker_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

if worker_id in state['workers']:
    del state['workers'][worker_id]

state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY

    oml_pool_log "INFO" "Worker deleted: ${worker_id}"
}

# 同步 Worker 状态到池
oml_pool_sync_worker_state() {
    local worker_id="$1"

    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"
    if [[ ! -f "$worker_file" ]]; then
        return 1
    fi

    python3 - "${OML_POOL_STATE_FILE}" "$worker_id" "$worker_file" <<'PY'
import json
import sys

state_file = sys.argv[1]
worker_id = sys.argv[2]
worker_file = sys.argv[3]

with open(state_file, 'r') as f:
    state = json.load(f)

with open(worker_file, 'r') as f:
    worker = json.load(f)

state['workers'][worker_id] = worker
state['updated_at'] = worker['updated_at']

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY
}

# ============================================================================
# 动态扩缩容
# ============================================================================

# 获取空闲 Worker 数量
oml_pool_get_idle_count() {
    oml_pool_ensure_init

    python3 - "${OML_POOL_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

count = sum(1 for w in state['workers'].values() if w['status'] == 'idle')
print(count)
PY
}

# 获取忙碌 Worker 数量
oml_pool_get_busy_count() {
    oml_pool_ensure_init

    python3 - "${OML_POOL_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

count = sum(1 for w in state['workers'].values() if w['status'] == 'busy')
print(count)
PY
}

# 获取总 Worker 数量
oml_pool_get_total_count() {
    oml_pool_ensure_init

    python3 - "${OML_POOL_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

print(len(state['workers']))
PY
}

# 扩容：添加 Worker
oml_pool_scale_up() {
    local count="${1:-1}"
    local max_workers
    max_workers=$(oml_pool_json_read "${OML_POOL_STATE_FILE}" "config.max_workers")

    local current_total
    current_total=$(oml_pool_get_total_count)

    local available_slots=$((max_workers - current_total))
    if [[ $available_slots -le 0 ]]; then
        oml_pool_log "WARN" "Cannot scale up: pool at max capacity (${max_workers})"
        echo "0"
        return 1
    fi

    local to_create=$count
    if [[ $to_create -gt $available_slots ]]; then
        to_create=$available_slots
        oml_pool_log "WARN" "Scaling up limited to ${to_create} workers (max: ${max_workers})"
    fi

    local created=0
    for ((i=0; i<to_create; i++)); do
        local worker_id
        worker_id=$(oml_pool_create_worker)
        if [[ -n "$worker_id" ]]; then
            ((created++))
        fi
    done

    oml_pool_log "INFO" "Scaled up: created ${created} worker(s)"
    echo "$created"
}

# 缩容：移除空闲 Worker
oml_pool_scale_down() {
    local count="${1:-1}"

    local idle_workers=()
    while IFS= read -r worker_id; do
        [[ -n "$worker_id" ]] && idle_workers+=("$worker_id")
    done < <(python3 - "${OML_POOL_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

for worker_id, worker in state['workers'].items():
    if worker['status'] == 'idle':
        print(worker_id)
PY
)

    local min_workers
    min_workers=$(oml_pool_json_read "${OML_POOL_STATE_FILE}" "config.min_workers")
    local current_total=${#idle_workers[@]}

    local to_remove=$count
    local min_remaining=$((current_total - to_remove))
    if [[ $min_remaining -lt $min_workers ]]; then
        to_remove=$((current_total - min_workers))
        oml_pool_log "WARN" "Scaling down limited to ${to_remove} workers (min: ${min_workers})"
    fi

    if [[ $to_remove -le 0 ]]; then
        oml_pool_log "INFO" "Cannot scale down: at minimum capacity"
        echo "0"
        return 0
    fi

    local removed=0
    for ((i=0; i<to_remove && i<${#idle_workers[@]}; i++)); do
        oml_pool_delete_worker "${idle_workers[$i]}" 2>/dev/null && ((removed++)) || true
    done

    oml_pool_log "INFO" "Scaled down: removed ${removed} worker(s)"
    echo "$removed"
}

# 自动扩缩容（基于负载）
oml_pool_autoscale() {
    local target_utilization="${1:-70}"  # 目标利用率百分比

    local total
    total=$(oml_pool_get_total_count)
    local busy
    busy=$(oml_pool_get_busy_count)

    if [[ $total -eq 0 ]]; then
        oml_pool_scale_up 1
        return 0
    fi

    local utilization=$((busy * 100 / total))

    if [[ $utilization -gt $((target_utilization + 10)) ]]; then
        # 利用率过高，扩容
        local scale_count=$(( (utilization - target_utilization) / 20 + 1 ))
        oml_pool_scale_up "$scale_count"
    elif [[ $utilization -lt $((target_utilization - 30)) && $total -gt 1 ]]; then
        # 利用率过低，缩容
        local scale_count=$(( (target_utilization - utilization) / 20 + 1 ))
        oml_pool_scale_down "$scale_count"
    else
        oml_pool_log "DEBUG" "Autoscale: utilization=${utilization}% (target=${target_utilization}%), no action needed"
        echo "0"
    fi
}

# ============================================================================
# 任务调度
# ============================================================================

# 分配任务给 Worker
oml_pool_assign_task() {
    local task_id="$1"
    local task_data="${2:-}"
    local worker_id="${3:-}"

    oml_pool_ensure_init

    # 如果没有指定 Worker，查找空闲 Worker
    if [[ -z "$worker_id" ]]; then
        worker_id=$(python3 - "${OML_POOL_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

for worker_id, worker in state['workers'].items():
    if worker['status'] == 'idle':
        print(worker_id)
        break
PY
)
    fi

    if [[ -z "$worker_id" ]]; then
        oml_pool_log "WARN" "No idle worker available for task: $task_id"
        echo ""
        return 1
    fi

    local timestamp
    timestamp="$(oml_pool_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_pool_iso_timestamp)"

    # 更新 Worker 状态
    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"

    python3 - "$worker_file" "$task_id" "$timestamp" "$iso_timestamp" "$task_data" <<'PY'
import json
import sys

worker_file = sys.argv[1]
task_id = sys.argv[2]
timestamp = int(sys.argv[3])
iso_timestamp = sys.argv[4]
task_data = sys.argv[5] if len(sys.argv) > 5 else '{}'

with open(worker_file, 'r') as f:
    worker = json.load(f)

worker['status'] = 'busy'
worker['current_task'] = {
    'task_id': task_id,
    'assigned_at': iso_timestamp,
    'data': json.loads(task_data) if task_data else {}
}
worker['updated_at'] = iso_timestamp
worker['last_active'] = timestamp

with open(worker_file, 'w') as f:
    json.dump(worker, f, indent=2)
PY

    # 更新池状态中的任务记录
    python3 - "${OML_POOL_STATE_FILE}" "$task_id" "$worker_id" "$iso_timestamp" "$task_data" <<'PY'
import json
import sys
from datetime import datetime

state_file = sys.argv[1]
task_id = sys.argv[2]
worker_id = sys.argv[3]
iso_timestamp = sys.argv[4]
task_data = sys.argv[5] if len(sys.argv) > 5 else '{}'

with open(state_file, 'r') as f:
    state = json.load(f)

state['tasks'][task_id] = {
    'task_id': task_id,
    'worker_id': worker_id,
    'status': 'running',
    'assigned_at': iso_timestamp,
    'data': json.loads(task_data) if task_data else {}
}
state['stats']['total_tasks'] += 1
state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY

    # 同步 Worker 状态
    oml_pool_sync_worker_state "$worker_id"

    # 注册到 Task Registry（如果可用）
    if type -t oml_task_register >/dev/null 2>&1; then
        oml_task_register "$task_id" "worker" "Pool task" "**" "" "0" >/dev/null 2>&1 || true
    fi

    oml_pool_log "INFO" "Task assigned: ${task_id} -> ${worker_id}"
    echo "$worker_id"
}

# 完成任务
oml_pool_complete_task() {
    local task_id="$1"
    local result="${2:-}"
    local success="${3:-true}"

    oml_pool_ensure_init

    # 查找任务所在的 Worker
    local worker_id
    worker_id=$(python3 - "${OML_POOL_STATE_FILE}" "$task_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if task:
    print(task.get('worker_id', ''))
PY
)

    if [[ -z "$worker_id" ]]; then
        oml_pool_log "WARN" "Task not found: $task_id"
        return 1
    fi

    local iso_timestamp
    iso_timestamp="$(oml_pool_iso_timestamp)"

    # 更新 Worker 状态
    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"

    python3 - "$worker_file" "$iso_timestamp" "$success" <<'PY'
import json
import sys

worker_file = sys.argv[1]
iso_timestamp = sys.argv[2]
success = sys.argv[3].lower() == 'true'

with open(worker_file, 'r') as f:
    worker = json.load(f)

if success:
    worker['tasks_completed'] += 1
else:
    worker['tasks_failed'] += 1

worker['status'] = 'idle'
worker['current_task'] = None
worker['updated_at'] = iso_timestamp

with open(worker_file, 'w') as f:
    json.dump(worker, f, indent=2)
PY

    # 更新池状态
    python3 - "${OML_POOL_STATE_FILE}" "$task_id" "$iso_timestamp" "$success" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]
iso_timestamp = sys.argv[3]
success = sys.argv[4].lower() == 'true'

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if task:
    task['status'] = 'completed' if success else 'failed'
    task['completed_at'] = iso_timestamp
    if result := sys.argv[5] if len(sys.argv) > 5 else '':
        task['result'] = json.loads(result) if result else {}

if success:
    state['stats']['completed_tasks'] += 1
else:
    state['stats']['failed_tasks'] += 1

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY
    _ "$result"

    # 同步 Worker 状态
    oml_pool_sync_worker_state "$worker_id"

    # 更新 Task Registry
    if type -t oml_task_update_status >/dev/null 2>&1; then
        oml_task_update_status "$task_id" "completed" 2>/dev/null || true
    fi

    oml_pool_log "INFO" "Task completed: ${task_id} (success=${success})"
}

# ============================================================================
# 查询与统计
# ============================================================================

# 获取 Worker 信息
oml_pool_get_worker() {
    local worker_id="$1"

    local worker_file="${OML_POOL_WORKERS_DIR}/${worker_id}.json"
    if [[ ! -f "$worker_file" ]]; then
        oml_pool_log "ERROR" "Worker not found: $worker_id"
        return 1
    fi

    cat "$worker_file"
}

# 列出所有 Worker
oml_pool_list_workers() {
    local status_filter="${1:-all}"

    oml_pool_ensure_init

    python3 - "${OML_POOL_STATE_FILE}" "$status_filter" <<'PY'
import json
import sys

state_file = sys.argv[1]
status_filter = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

print(f"{'WORKER_ID':<36} {'STATUS':<10} {'TASKS':<10} {'PID':<10} {'LAST_ACTIVE'}")
print("=" * 85)

for worker_id, worker in state['workers'].items():
    if status_filter != 'all' and worker['status'] != status_filter:
        continue

    tasks = f"{worker['tasks_completed']}/{worker['tasks_failed']}"
    pid = worker.get('pid', 0)
    last_active = worker.get('last_active', 0)
    if last_active:
        import datetime
        last_active_str = datetime.datetime.fromtimestamp(last_active).strftime('%Y-%m-%d %H:%M:%S')
    else:
        last_active_str = 'never'

    print(f"{worker_id:<36} {worker['status']:<10} {tasks:<10} {pid:<10} {last_active_str}")
PY
}

# 获取池统计
oml_pool_stats() {
    oml_pool_ensure_init

    python3 - "${OML_POOL_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

workers = state['workers']
stats = state['stats']
config = state['config']

total = len(workers)
idle = sum(1 for w in workers.values() if w['status'] == 'idle')
busy = sum(1 for w in workers.values() if w['status'] == 'busy')
stopped = sum(1 for w in workers.values() if w['status'] == 'stopped')

utilization = (busy / total * 100) if total > 0 else 0

print(f"=== Worker Pool Statistics ===")
print(f"Version: {state['version']}")
print(f"Created: {state['created_at']}")
print(f"Updated: {state['updated_at']}")
print()
print("Configuration:")
print(f"  Min Workers: {config['min_workers']}")
print(f"  Max Workers: {config['max_workers']}")
print(f"  Idle Timeout: {config['idle_timeout']}s")
print(f"  Task Timeout: {config['task_timeout']}s")
print()
print("Workers:")
print(f"  Total: {total}")
print(f"  Idle: {idle}")
print(f"  Busy: {busy}")
print(f"  Stopped: {stopped}")
print(f"  Utilization: {utilization:.1f}%")
print()
print("Task Statistics:")
print(f"  Total Tasks: {stats['total_tasks']}")
print(f"  Completed: {stats['completed_tasks']}")
print(f"  Failed: {stats['failed_tasks']}")
print(f"  Total Workers Created: {stats['total_workers_created']}")
PY
}

# 获取池状态（JSON）
oml_pool_get_state() {
    oml_pool_ensure_init

    if [[ -f "${OML_POOL_STATE_FILE}" ]]; then
        cat "${OML_POOL_STATE_FILE}"
    else
        echo "{}"
    fi
}

# ============================================================================
# 清理与维护
# ============================================================================

# 清理超时 Worker
oml_pool_cleanup_idle_workers() {
    local idle_timeout="${1:-$POOL_DEFAULT_IDLE_TIMEOUT}"

    oml_pool_ensure_init

    local current_time
    current_time=$(oml_pool_timestamp)
    local threshold=$((current_time - idle_timeout))

    local cleaned=0

    while IFS= read -r worker_id; do
        [[ -n "$worker_id" ]] || continue

        local min_workers
        min_workers=$(oml_pool_json_read "${OML_POOL_STATE_FILE}" "config.min_workers")
        local current_total
        current_total=$(oml_pool_get_total_count)

        if [[ $current_total -le $min_workers ]]; then
            break
        fi

        oml_pool_delete_worker "$worker_id" 2>/dev/null && ((cleaned++)) || true
    done < <(python3 - "${OML_POOL_STATE_FILE}" "$threshold" <<'PY'
import json
import sys

state_file = sys.argv[1]
threshold = int(sys.argv[2])

with open(state_file, 'r') as f:
    state = json.load(f)

for worker_id, worker in state['workers'].items():
    if worker['status'] == 'idle' and worker.get('last_active', 0) < threshold:
        print(worker_id)
PY
)

    oml_pool_log "INFO" "Cleaned up ${cleaned} idle worker(s)"
    echo "$cleaned"
}

# 清理已完成的任务记录
oml_pool_cleanup_tasks() {
    local max_age_hours="${1:-24}"

    oml_pool_ensure_init

    python3 - "${OML_POOL_STATE_FILE}" "$max_age_hours" <<'PY'
import json
import sys
from datetime import datetime, timedelta

state_file = sys.argv[1]
max_age_hours = int(sys.argv[2])

with open(state_file, 'r') as f:
    state = json.load(f)

cutoff = datetime.utcnow() - timedelta(hours=max_age_hours)
tasks_to_remove = []

for task_id, task in state['tasks'].items():
    if task['status'] in ['completed', 'failed']:
        completed_at = task.get('completed_at', '')
        if completed_at:
            try:
                task_time = datetime.fromisoformat(completed_at.replace('Z', '+00:00'))
                if task_time < cutoff:
                    tasks_to_remove.append(task_id)
            except:
                pass

for task_id in tasks_to_remove:
    del state['tasks'][task_id]

state['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(len(tasks_to_remove))
PY

    oml_pool_log "INFO" "Cleaned up old task records"
}

# 重置池状态
oml_pool_reset() {
    local force="${1:-false}"

    if [[ "$force" != "true" ]]; then
        echo "Warning: This will remove all workers and tasks."
        echo "Use --force to confirm."
        return 1
    fi

    # 停止所有 Worker
    while IFS= read -r worker_id; do
        [[ -n "$worker_id" ]] && oml_pool_stop_worker "$worker_id" "true" 2>/dev/null || true
    done < <(python3 - "${OML_POOL_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

for worker_id in state['workers'].keys():
    print(worker_id)
PY
)

    # 删除所有 Worker 文件
    rm -f "${OML_POOL_WORKERS_DIR}"/*.json

    # 重置状态文件
    local timestamp
    timestamp="$(oml_pool_iso_timestamp)"

    local min_workers
    min_workers=$(oml_pool_json_read "${OML_POOL_STATE_FILE}" "config.min_workers")
    local max_workers
    max_workers=$(oml_pool_json_read "${OML_POOL_STATE_FILE}" "config.max_workers")

    cat > "${OML_POOL_STATE_FILE}" <<EOF
{
  "version": "${OML_POOL_VERSION}",
  "created_at": "${timestamp}",
  "updated_at": "${timestamp}",
  "config": {
    "min_workers": ${min_workers:-$POOL_DEFAULT_MIN_WORKERS},
    "max_workers": ${max_workers:-$POOL_DEFAULT_MAX_WORKERS},
    "idle_timeout": ${POOL_DEFAULT_IDLE_TIMEOUT},
    "task_timeout": ${POOL_DEFAULT_TASK_TIMEOUT}
  },
  "workers": {},
  "tasks": {},
  "stats": {
    "total_tasks": 0,
    "completed_tasks": 0,
    "failed_tasks": 0,
    "total_workers_created": 0
  }
}
EOF

    oml_pool_log "WARN" "Pool reset completed"
    echo "Pool reset completed"
}

# ============================================================================
# CLI 入口
# ============================================================================

main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_pool_init "$@"
            ;;
        create-worker)
            oml_pool_create_worker
            ;;
        start-worker)
            oml_pool_start_worker "$@"
            ;;
        stop-worker)
            oml_pool_stop_worker "$@"
            ;;
        delete-worker)
            oml_pool_delete_worker "$@"
            ;;
        scale-up)
            oml_pool_scale_up "$@"
            ;;
        scale-down)
            oml_pool_scale_down "$@"
            ;;
        autoscale)
            oml_pool_autoscale "$@"
            ;;
        assign-task)
            oml_pool_assign_task "$@"
            ;;
        complete-task)
            oml_pool_complete_task "$@"
            ;;
        get-worker)
            oml_pool_get_worker "$@"
            ;;
        list-workers)
            oml_pool_list_workers "$@"
            ;;
        stats)
            oml_pool_stats
            ;;
        get-state)
            oml_pool_get_state
            ;;
        cleanup)
            oml_pool_cleanup_idle_workers "$@"
            ;;
        reset)
            oml_pool_reset "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Worker Pool Manager v${OML_POOL_VERSION}

用法：oml pool <action> [args]

池管理:
  init [min] [max]          初始化 Worker 池
  stats                     显示池统计信息
  get-state                 获取池状态 (JSON)
  reset [--force]           重置池状态

Worker 管理:
  create-worker             创建新 Worker
  start-worker <id> [script] 启动 Worker
  stop-worker <id> [--force] 停止 Worker
  delete-worker <id>        删除 Worker
  get-worker <id>           获取 Worker 信息
  list-workers [status]     列出 Worker (all|idle|busy|stopped)

扩缩容:
  scale-up [count]          扩容 (添加 Worker)
  scale-down [count]        缩容 (移除空闲 Worker)
  autoscale [target%]       自动扩缩容

任务调度:
  assign-task <id> [data] [worker]  分配任务
  complete-task <id> [result] [success]  完成任务

维护:
  cleanup [timeout]         清理超时 Worker
  cleanup-tasks [hours]     清理旧任务记录

示例:
  oml pool init 2 10
  oml pool create-worker
  oml pool scale-up 3
  oml pool list-workers
  oml pool stats
  oml pool assign-task task-123 '{"cmd": "echo hello"}'
  oml pool autoscale 70
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml pool help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
