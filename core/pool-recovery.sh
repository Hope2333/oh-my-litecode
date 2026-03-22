#!/usr/bin/env bash
# OML Pool Recovery Manager
# 故障恢复模块 - 提供 Worker 故障检测、自动恢复与容错机制

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_POOL_RECOVERY_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_POOL_RECOVERY_LOADED=true

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

# 源 pool-manager.sh（如果可用）
if [[ -f "${SCRIPT_DIR}/pool-manager.sh" ]]; then
    source "${SCRIPT_DIR}/pool-manager.sh"
fi

# 源 pool-monitor.sh（如果可用）
if [[ -f "${SCRIPT_DIR}/pool-monitor.sh" ]]; then
    source "${SCRIPT_DIR}/pool-monitor.sh"
fi

# 源 pool-queue.sh（如果可用）
if [[ -f "${SCRIPT_DIR}/pool-queue.sh" ]]; then
    source "${SCRIPT_DIR}/pool-queue.sh"
fi

# ============================================================================
# 配置与常量
# ============================================================================

readonly OML_RECOVERY_VERSION="0.1.0"
readonly OML_RECOVERY_DIR="${OML_RECOVERY_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/recovery}"
readonly OML_RECOVERY_STATE_FILE="${OML_RECOVERY_DIR}/state.json"
readonly OML_RECOVERY_LOGS_DIR="${OML_RECOVERY_DIR}/logs"
readonly OML_RECOVERY_CHECKPOINT_DIR="${OML_RECOVERY_DIR}/checkpoints"

# 故障检测配置
readonly DETECTION_DEFAULT_INTERVAL=10       # 检测间隔 (秒)
readonly DETECTION_DEFAULT_TIMEOUT=30        # 超时阈值 (秒)
readonly DETECTION_DEFAULT_MAX_FAILURES=3    # 最大失败次数

# 恢复策略配置
readonly RECOVERY_DEFAULT_MAX_RETRIES=3      # 最大重试次数
readonly RECOVERY_DEFAULT_RETRY_DELAY=5      # 重试延迟 (秒)
readonly RECOVERY_DEFAULT_BACKOFF_MULTIPLIER=2  # 退避倍数
readonly RECOVERY_DEFAULT_CIRCUIT_BREAKER_THRESHOLD=5  # 熔断器阈值
readonly RECOVERY_DEFAULT_CIRCUIT_BREAKER_TIMEOUT=60   # 熔断器超时 (秒)

# 故障类型
readonly FAILURE_TYPE_TIMEOUT="timeout"
readonly FAILURE_TYPE_CRASH="crash"
readonly FAILURE_TYPE_OOM="oom"
readonly FAILURE_TYPE_HEALTH_CHECK="health_check"
readonly FAILURE_TYPE_DEPENDENCY="dependency"

# 恢复状态
readonly RECOVERY_STATUS_PENDING="pending"
readonly RECOVERY_STATUS_IN_PROGRESS="in_progress"
readonly RECOVERY_STATUS_COMPLETED="completed"
readonly RECOVERY_STATUS_FAILED="failed"

# ============================================================================
# 工具函数
# ============================================================================

# 生成唯一恢复 ID
oml_recovery_generate_id() {
    echo "recovery-$(date +%s%N)-${RANDOM}"
}

# 生成唯一故障 ID
oml_recovery_generate_failure_id() {
    echo "failure-$(date +%s%N)-${RANDOM}"
}

# 获取当前时间戳（秒）
oml_recovery_timestamp() {
    date +%s
}

# 获取 ISO 时间戳
oml_recovery_iso_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# 日志输出
oml_recovery_log() {
    local level="$1"
    local message="$2"
    local component="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_entry="[${timestamp}] [${level}]"
    [[ -n "$component" ]] && log_entry+=" [${component}]"
    log_entry+=" ${message}"

    echo "$log_entry" >&2

    local log_file="${OML_RECOVERY_LOGS_DIR}/recovery.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file" 2>/dev/null || true
}

# JSON 读取
oml_recovery_json_read() {
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

# ============================================================================
# 故障恢复初始化
# ============================================================================

# 初始化故障恢复系统
oml_recovery_init() {
    local detection_interval="${1:-$DETECTION_DEFAULT_INTERVAL}"
    local max_retries="${2:-$RECOVERY_DEFAULT_MAX_RETRIES}"
    local circuit_breaker_threshold="${3:-$RECOVERY_DEFAULT_CIRCUIT_BREAKER_THRESHOLD}"

    mkdir -p "${OML_RECOVERY_DIR}"
    mkdir -p "${OML_RECOVERY_LOGS_DIR}"
    mkdir -p "${OML_RECOVERY_CHECKPOINT_DIR}"

    local timestamp
    timestamp="$(oml_recovery_iso_timestamp)"

    cat > "${OML_RECOVERY_STATE_FILE}" <<EOF
{
  "version": "${OML_RECOVERY_VERSION}",
  "created_at": "${timestamp}",
  "updated_at": "${timestamp}",
  "config": {
    "detection_interval": ${detection_interval},
    "detection_timeout": ${DETECTION_DEFAULT_TIMEOUT},
    "max_failures": ${DETECTION_DEFAULT_MAX_FAILURES},
    "max_retries": ${max_retries},
    "retry_delay": ${RECOVERY_DEFAULT_RETRY_DELAY},
    "backoff_multiplier": ${RECOVERY_DEFAULT_BACKOFF_MULTIPLIER},
    "circuit_breaker_threshold": ${circuit_breaker_threshold},
    "circuit_breaker_timeout": ${RECOVERY_DEFAULT_CIRCUIT_BREAKER_TIMEOUT}
  },
  "failures": [],
  "recoveries": {},
  "circuit_breakers": {},
  "checkpoints": {},
  "stats": {
    "total_failures": 0,
    "total_recoveries": 0,
    "successful_recoveries": 0,
    "failed_recoveries": 0,
    "circuit_breaker_trips": 0
  }
}
EOF

    oml_recovery_log "INFO" "Recovery system initialized"
    echo "Recovery system initialized at: ${OML_RECOVERY_DIR}"
}

# 确保恢复系统已初始化
oml_recovery_ensure_init() {
    if [[ ! -f "${OML_RECOVERY_STATE_FILE}" ]]; then
        oml_recovery_init
    fi
}

# ============================================================================
# 故障检测
# ============================================================================

# 报告故障
oml_recovery_report_failure() {
    local worker_id="$1"
    local failure_type="${2:-$FAILURE_TYPE_HEALTH_CHECK}"
    local details="${3:-}"
    local task_id="${4:-}"

    oml_recovery_ensure_init

    local failure_id
    failure_id="$(oml_recovery_generate_failure_id)"
    local timestamp
    timestamp="$(oml_recovery_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_recovery_iso_timestamp)"

    python3 - "${OML_RECOVERY_STATE_FILE}" "$failure_id" "$worker_id" "$failure_type" "$timestamp" "$iso_timestamp" "$details" "$task_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
failure_id = sys.argv[2]
worker_id = sys.argv[3]
failure_type = sys.argv[4]
timestamp = int(sys.argv[5])
iso_timestamp = sys.argv[6]
details = sys.argv[7] if len(sys.argv) > 7 and sys.argv[7] else '{}'
task_id = sys.argv[8] if len(sys.argv) > 8 and sys.argv[8] else None

with open(state_file, 'r') as f:
    state = json.load(f)

# 创建故障记录
failure = {
    'failure_id': failure_id,
    'worker_id': worker_id,
    'failure_type': failure_type,
    'details': json.loads(details) if details else {},
    'task_id': task_id,
    'detected_at': iso_timestamp,
    'timestamp': timestamp,
    'acknowledged': False,
    'recovery_id': None
}

state['failures'].append(failure)
state['stats']['total_failures'] += 1
state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY

    oml_recovery_log "WARN" "Failure reported: ${failure_id} (worker=${worker_id}, type=${failure_type})"
    echo "$failure_id"
}

# 检测 Worker 故障
oml_recovery_detect_worker_failure() {
    local worker_id="$1"

    oml_recovery_ensure_init

    # 检查 Worker 状态
    local worker_status="unknown"
    local worker_pid=0

    if [[ -f "${OML_POOL_WORKERS_DIR:-}/${worker_id}.json" ]]; then
        worker_status=$(oml_recovery_json_read "${OML_POOL_WORKERS_DIR}/${worker_id}.json" "status")
        worker_pid=$(oml_recovery_json_read "${OML_POOL_WORKERS_DIR}/${worker_id}.json" "pid")
    fi

    # 检查进程是否存在
    local process_alive="false"
    if [[ "$worker_pid" -gt 0 ]]; then
        if kill -0 "$worker_pid" 2>/dev/null; then
            process_alive="true"
        fi
    fi

    # 判断是否故障
    local failure_detected="false"
    local failure_type=""

    if [[ "$worker_status" == "$WORKER_STATUS_FAILED:-}" ]]; then
        failure_detected="true"
        failure_type="$FAILURE_TYPE_CRASH"
    elif [[ "$worker_pid" -gt 0 && "$process_alive" == "false" ]]; then
        failure_detected="true"
        failure_type="$FAILURE_TYPE_CRASH"
    fi

    if [[ "$failure_detected" == "true" ]]; then
        oml_recovery_report_failure "$worker_id" "$failure_type" "{\"status\": \"${worker_status}\", \"pid\": ${worker_pid}}"
        echo "failure_detected:$failure_type"
    else
        echo "ok"
    fi
}

# 运行故障检测器
oml_recovery_run_detector() {
    local interval="${1:-$DETECTION_DEFAULT_INTERVAL}"
    local count="${2:-0}"  # 0 表示无限

    oml_recovery_ensure_init

    oml_recovery_log "INFO" "Starting failure detector (interval=${interval}s)"

    local iterations=0
    while [[ $count -eq 0 ]] || [[ $iterations -lt $count ]]; do
        local detected=0

        # 检测所有 Worker
        if [[ -d "${OML_POOL_WORKERS_DIR:-}" ]]; then
            for worker_file in "${OML_POOL_WORKERS_DIR}"/*.json; do
                [[ -f "$worker_file" ]] || continue

                local worker_id
                worker_id=$(basename "$worker_file" .json)
                local result
                result=$(oml_recovery_detect_worker_failure "$worker_id")

                if [[ "$result" == failure_detected:* ]]; then
                    ((detected++))
                fi
            done
        fi

        if [[ $detected -gt 0 ]]; then
            oml_recovery_log "WARN" "Detector: ${detected} failure(s) detected"
        fi

        ((iterations++))
        sleep "$interval"
    done
}

# ============================================================================
# 恢复策略
# ============================================================================

# 启动恢复流程
oml_recovery_start() {
    local failure_id="$1"
    local strategy="${2:-retry}"  # retry, restart, failover, manual

    oml_recovery_ensure_init

    local recovery_id
    recovery_id="$(oml_recovery_generate_id)"
    local timestamp
    timestamp="$(oml_recovery_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_recovery_iso_timestamp)"

    python3 - "${OML_RECOVERY_STATE_FILE}" "$recovery_id" "$failure_id" "$strategy" "$timestamp" "$iso_timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
recovery_id = sys.argv[2]
failure_id = sys.argv[3]
strategy = sys.argv[4]
timestamp = int(sys.argv[5])
iso_timestamp = sys.argv[6]

with open(state_file, 'r') as state_fp:
    state = json.load(state_fp)

# 查找故障记录
failure = None
for failure_item in state['failures']:
    if failure_item['failure_id'] == failure_id:
        failure = failure_item
        break

if not failure:
    print("error:failure_not_found")
    sys.exit(1)

# 创建恢复记录
recovery = {
    'recovery_id': recovery_id,
    'failure_id': failure_id,
    'worker_id': failure['worker_id'],
    'strategy': strategy,
    'status': 'pending',
    'attempt': 0,
    'max_attempts': state['config']['max_retries'],
    'retry_delay': state['config']['retry_delay'],
    'backoff_multiplier': state['config']['backoff_multiplier'],
    'created_at': iso_timestamp,
    'started_at': None,
    'completed_at': None,
    'error': None,
    'result': None
}

state['recoveries'][recovery_id] = recovery
state['stats']['total_recoveries'] += 1

# 更新故障记录
failure['acknowledged'] = True
failure['recovery_id'] = recovery_id

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY

    local py_result=$?
    if [[ $py_result -ne 0 ]]; then
        oml_recovery_log "ERROR" "Failed to start recovery for failure: ${failure_id}"
        return 1
    fi

    oml_recovery_log "INFO" "Recovery started: ${recovery_id} (strategy=${strategy})"
    echo "$recovery_id"
}

# 执行恢复尝试
oml_recovery_execute() {
    local recovery_id="$1"

    oml_recovery_ensure_init

    local timestamp
    timestamp="$(oml_recovery_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_recovery_iso_timestamp)"

    python3 - "${OML_RECOVERY_STATE_FILE}" "$recovery_id" "$timestamp" "$iso_timestamp" <<'PY'
import json
import sys
import os

state_file = sys.argv[1]
recovery_id = sys.argv[2]
timestamp = int(sys.argv[3])
iso_timestamp = sys.argv[4]

with open(state_file, 'r') as f:
    state = json.load(f)

recovery = state['recoveries'].get(recovery_id)
if not recovery:
    print("error:recovery_not_found")
    sys.exit(1)

# 检查是否超过最大尝试次数
if recovery['attempt'] >= recovery['max_attempts']:
    recovery['status'] = 'failed'
    recovery['completed_at'] = iso_timestamp
    recovery['error'] = 'max_attempts_exceeded'
    state['stats']['failed_recoveries'] += 1
    state['updated_at'] = iso_timestamp

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print("failed:max_attempts_exceeded")
    sys.exit(0)

# 检查熔断器
circuit_breaker = state['circuit_breakers'].get(recovery['worker_id'], {})
if circuit_breaker.get('state') == 'open':
    if timestamp - circuit_breaker.get('opened_at', 0) < state['config']['circuit_breaker_timeout']:
        print("circuit_breaker_open")
        sys.exit(0)
    else:
        # 尝试半开状态
        circuit_breaker['state'] = 'half-open'

# 执行恢复策略
strategy = recovery['strategy']
worker_id = recovery['worker_id']
result = "success"

if strategy == 'retry':
    # 重试：重新分配任务
    result = "retry_scheduled"
elif strategy == 'restart':
    # 重启：创建新 Worker
    result = "restart_scheduled"
elif strategy == 'failover':
    # 故障转移：切换到备用 Worker
    result = "failover_scheduled"
elif strategy == 'manual':
    # 手动恢复
    result = "manual_required"
else:
    result = "unknown_strategy"

# 更新恢复状态
recovery['attempt'] += 1
recovery['status'] = 'in_progress'
recovery['started_at'] = iso_timestamp
recovery['result'] = result

# 计算下次重试延迟
next_delay = recovery['retry_delay'] * (recovery['backoff_multiplier'] ** (recovery['attempt'] - 1))
recovery['next_retry_at'] = timestamp + next_delay

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"in_progress:{result}:next_retry_in={next_delay}s")
PY

    oml_recovery_log "INFO" "Recovery executed: ${recovery_id}"
}

# 完成恢复
oml_recovery_complete() {
    local recovery_id="$1"
    local success="${2:-true}"
    local result="${3:-}"

    oml_recovery_ensure_init

    local iso_timestamp
    iso_timestamp="$(oml_recovery_iso_timestamp)"

    python3 - "${OML_RECOVERY_STATE_FILE}" "$recovery_id" "$iso_timestamp" "$success" "$result" <<'PY'
import json
import sys

state_file = sys.argv[1]
recovery_id = sys.argv[2]
iso_timestamp = sys.argv[3]
success = sys.argv[4].lower() == 'true'
result = sys.argv[5] if len(sys.argv) > 5 else None

with open(state_file, 'r') as f:
    state = json.load(f)

recovery = state['recoveries'].get(recovery_id)
if not recovery:
    print("error:recovery_not_found")
    sys.exit(1)

if success:
    recovery['status'] = 'completed'
    state['stats']['successful_recoveries'] += 1

    # 关闭熔断器（如果存在）
    worker_id = recovery.get('worker_id')
    if worker_id and worker_id in state['circuit_breakers']:
        state['circuit_breakers'][worker_id] = {
            'state': 'closed',
            'failure_count': 0,
            'last_failure': None
        }
else:
    recovery['status'] = 'failed'
    state['stats']['failed_recoveries'] += 1

    # 更新熔断器
    worker_id = recovery.get('worker_id')
    if worker_id:
        cb = state['circuit_breakers'].get(worker_id, {'state': 'closed', 'failure_count': 0})
        cb['failure_count'] = cb.get('failure_count', 0) + 1
        cb['last_failure'] = iso_timestamp

        if cb['failure_count'] >= state['config']['circuit_breaker_threshold']:
            cb['state'] = 'open'
            cb['opened_at'] = __import__('time').time()
            state['stats']['circuit_breaker_trips'] += 1

        state['circuit_breakers'][worker_id] = cb

recovery['completed_at'] = iso_timestamp
if result:
    recovery['result'] = result

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Recovery completed: {recovery_id} (success={success})")
PY

    if [[ "$success" == "true" ]]; then
        oml_recovery_log "INFO" "Recovery completed: ${recovery_id} (success)"
    else
        oml_recovery_log "ERROR" "Recovery completed: ${recovery_id} (failed)"
    fi
}

# ============================================================================
# 熔断器模式
# ============================================================================

# 获取熔断器状态
oml_recovery_circuit_breaker_status() {
    local worker_id="${1:-}"

    oml_recovery_ensure_init

    if [[ -n "$worker_id" ]]; then
        python3 - "${OML_RECOVERY_STATE_FILE}" "$worker_id" <<'PY'
import json
import sys
import time

state_file = sys.argv[1]
worker_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

cb = state['circuit_breakers'].get(worker_id, {
    'state': 'closed',
    'failure_count': 0,
    'last_failure': None
})

# 检查是否应该从 open 转为 half-open
if cb['state'] == 'open':
    timeout = state['config']['circuit_breaker_timeout']
    opened_at = cb.get('opened_at', 0)
    if time.time() - opened_at >= timeout:
        cb['state'] = 'half-open'

print(json.dumps({
    'worker_id': worker_id,
    'state': cb['state'],
    'failure_count': cb.get('failure_count', 0),
    'last_failure': cb.get('last_failure'),
    'threshold': state['config']['circuit_breaker_threshold'],
    'timeout': state['config']['circuit_breaker_timeout']
}, indent=2))
PY
    else
        python3 - "${OML_RECOVERY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

circuit_breakers = state.get('circuit_breakers', {})

print(f"{'WORKER_ID':<36} {'STATE':<12} {'FAILURES':<10} {'LAST_FAILURE'}")
print("=" * 80)

for worker_id, cb in circuit_breakers.items():
    state_val = cb.get('state', 'unknown')
    failures = cb.get('failure_count', 0)
    last_failure = cb.get('last_failure', 'never')[:19] if cb.get('last_failure') else 'never'
    print(f"{worker_id:<36} {state_val:<12} {failures:<10} {last_failure}")

print()
print(f"Total circuit breakers: {len(circuit_breakers)}")
print(f"Tripped: {state['stats']['circuit_breaker_trips']}")
PY
    fi
}

# 重置熔断器
oml_recovery_circuit_breaker_reset() {
    local worker_id="$1"

    oml_recovery_ensure_init

    python3 - "${OML_RECOVERY_STATE_FILE}" "$worker_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
worker_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

if worker_id in state['circuit_breakers']:
    state['circuit_breakers'][worker_id] = {
        'state': 'closed',
        'failure_count': 0,
        'last_failure': None
    }
    state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print(f"Circuit breaker reset: {worker_id}")
else:
    print("Circuit breaker not found", file=sys.stderr)
    sys.exit(1)
PY
}

# ============================================================================
# 检查点管理
# ============================================================================

# 创建检查点
oml_recovery_checkpoint_create() {
    local task_id="$1"
    local checkpoint_data="${2:-}"

    oml_recovery_ensure_init

    local checkpoint_id
    checkpoint_id="$(oml_recovery_generate_id)"
    local timestamp
    timestamp="$(oml_recovery_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_recovery_iso_timestamp)"

    local checkpoint_file="${OML_RECOVERY_CHECKPOINT_DIR}/${checkpoint_id}.json"

    python3 - "$checkpoint_file" "$task_id" "$checkpoint_data" "$timestamp" "$iso_timestamp" <<'PY'
import json
import sys

checkpoint_file = sys.argv[1]
task_id = sys.argv[2]
checkpoint_data = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else '{}'
timestamp = int(sys.argv[4])
iso_timestamp = sys.argv[5]

checkpoint = {
    'checkpoint_id': checkpoint_file.split('/')[-1].replace('.json', ''),
    'task_id': task_id,
    'data': json.loads(checkpoint_data) if checkpoint_data else {},
    'created_at': iso_timestamp,
    'timestamp': timestamp
}

with open(checkpoint_file, 'w') as f:
    json.dump(checkpoint, f, indent=2)
PY

    # 更新状态文件
    python3 - "${OML_RECOVERY_STATE_FILE}" "$checkpoint_id" "$task_id" "$iso_timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
checkpoint_id = sys.argv[2]
task_id = sys.argv[3]
iso_timestamp = sys.argv[4]

with open(state_file, 'r') as f:
    state = json.load(f)

state['checkpoints'][checkpoint_id] = {
    'task_id': task_id,
    'created_at': iso_timestamp
}
state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY

    oml_recovery_log "INFO" "Checkpoint created: ${checkpoint_id} (task=${task_id})"
    echo "$checkpoint_id"
}

# 恢复检查点
oml_recovery_checkpoint_restore() {
    local checkpoint_id="$1"

    local checkpoint_file="${OML_RECOVERY_CHECKPOINT_DIR}/${checkpoint_id}.json"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "Checkpoint not found: $checkpoint_id"
        return 1
    fi

    cat "$checkpoint_file"
}

# 列出检查点
oml_recovery_checkpoint_list() {
    local task_id="${1:-}"

    oml_recovery_ensure_init

    python3 - "${OML_RECOVERY_STATE_FILE}" "$task_id" <<'PY'
import json
import sys
import os

state_file = sys.argv[1]
task_id_filter = sys.argv[2] if len(sys.argv) > 2 else None

with open(state_file, 'r') as f:
    state = json.load(f)

checkpoints_dir = os.path.join(os.path.dirname(state_file), 'checkpoints')
checkpoints = []

for checkpoint_id, info in state.get('checkpoints', {}).items():
    if task_id_filter and info.get('task_id') != task_id_filter:
        continue

    checkpoint_file = os.path.join(checkpoints_dir, f"{checkpoint_id}.json")
    if os.path.exists(checkpoint_file):
        with open(checkpoint_file, 'r') as f:
            checkpoint = json.load(f)
        checkpoints.append(checkpoint)

# 按时间排序
checkpoints.sort(key=lambda x: x.get('timestamp', 0), reverse=True)

print(f"{'CHECKPOINT_ID':<36} {'TASK_ID':<30} {'CREATED_AT'}")
print("=" * 80)

for cp in checkpoints:
    print(f"{cp['checkpoint_id']:<36} {cp['task_id']:<30} {cp['created_at'][:19] if cp['created_at'] else 'N/A'}")

print()
print(f"Total: {len(checkpoints)} checkpoint(s)")
PY
}

# 删除检查点
oml_recovery_checkpoint_delete() {
    local checkpoint_id="$1"

    local checkpoint_file="${OML_RECOVERY_CHECKPOINT_DIR}/${checkpoint_id}.json"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "Checkpoint not found: $checkpoint_id"
        return 1
    fi

    rm -f "$checkpoint_file"

    # 更新状态文件
    python3 - "${OML_RECOVERY_STATE_FILE}" "$checkpoint_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
checkpoint_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

if checkpoint_id in state['checkpoints']:
    del state['checkpoints'][checkpoint_id]
    state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)
PY

    oml_recovery_log "INFO" "Checkpoint deleted: ${checkpoint_id}"
}

# 清理旧检查点
oml_recovery_checkpoint_cleanup() {
    local max_age_hours="${1:-24}"

    oml_recovery_ensure_init

    local timestamp
    timestamp=$(oml_recovery_timestamp)
    local threshold=$((timestamp - max_age_hours * 3600))

    local cleaned=0

    for checkpoint_file in "${OML_RECOVERY_CHECKPOINT_DIR}"/*.json; do
        [[ -f "$checkpoint_file" ]] || continue

        local cp_timestamp
        cp_timestamp=$(python3 -c "import json; print(json.load(open('${checkpoint_file}')).get('timestamp', 0))" 2>/dev/null || echo "0")

        if [[ "$cp_timestamp" -lt "$threshold" ]]; then
            local checkpoint_id
            checkpoint_id=$(basename "$checkpoint_file" .json)
            oml_recovery_checkpoint_delete "$checkpoint_id" 2>/dev/null
            ((cleaned++))
        fi
    done

    oml_recovery_log "INFO" "Cleaned up ${cleaned} checkpoint(s)"
    echo "Cleaned up ${cleaned} checkpoint(s)"
}

# ============================================================================
# 查询与统计
# ============================================================================

# 获取恢复状态
oml_recovery_get_status() {
    local recovery_id="$1"

    oml_recovery_ensure_init

    python3 - "${OML_RECOVERY_STATE_FILE}" "$recovery_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
recovery_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

recovery = state['recoveries'].get(recovery_id)
if not recovery:
    print("Recovery not found", file=sys.stderr)
    sys.exit(1)

print(json.dumps(recovery, indent=2))
PY
}

# 列出所有恢复
oml_recovery_list() {
    local status_filter="${1:-all}"

    oml_recovery_ensure_init

    python3 - "${OML_RECOVERY_STATE_FILE}" "$status_filter" <<'PY'
import json
import sys

state_file = sys.argv[1]
status_filter = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

recoveries = state.get('recoveries', {})

print(f"{'RECOVERY_ID':<36} {'WORKER_ID':<30} {'STRATEGY':<10} {'STATUS':<12} {'ATTEMPT'}")
print("=" * 100)

for recovery_id, recovery in recoveries.items():
    if status_filter != 'all' and recovery['status'] != status_filter:
        continue

    print(f"{recovery_id:<36} {recovery['worker_id']:<30} {recovery['strategy']:<10} {recovery['status']:<12} {recovery['attempt']}/{recovery['max_attempts']}")

print()
print(f"Total: {len([r for r in recoveries.values() if status_filter == 'all' or r['status'] == status_filter])} recovery/ies")
PY
}

# 获取统计信息
oml_recovery_stats() {
    oml_recovery_ensure_init

    python3 - "${OML_RECOVERY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

config = state['config']
stats = state['stats']

print("=== Recovery System Statistics ===")
print(f"Version: {state['version']}")
print(f"Created: {state['created_at']}")
print(f"Updated: {state['updated_at']}")
print()
print("Configuration:")
print(f"  Detection Interval: {config['detection_interval']}s")
print(f"  Detection Timeout: {config['detection_timeout']}s")
print(f"  Max Failures: {config['max_failures']}")
print(f"  Max Retries: {config['max_retries']}")
print(f"  Retry Delay: {config['retry_delay']}s")
print(f"  Backoff Multiplier: {config['backoff_multiplier']}")
print(f"  Circuit Breaker Threshold: {config['circuit_breaker_threshold']}")
print(f"  Circuit Breaker Timeout: {config['circuit_breaker_timeout']}s")
print()
print("Statistics:")
print(f"  Total Failures: {stats['total_failures']}")
print(f"  Total Recoveries: {stats['total_recoveries']}")
print(f"  Successful Recoveries: {stats['successful_recoveries']}")
print(f"  Failed Recoveries: {stats['failed_recoveries']}")
print(f"  Circuit Breaker Trips: {stats['circuit_breaker_trips']}")

if stats['total_recoveries'] > 0:
    success_rate = stats['successful_recoveries'] / stats['total_recoveries'] * 100
    print(f"  Success Rate: {success_rate:.1f}%")

print()
print(f"Active Recoveries: {len([r for r in state['recoveries'].values() if r['status'] == 'in_progress'])}")
print(f"Active Circuit Breakers: {len([cb for cb in state['circuit_breakers'].values() if cb['state'] == 'open'])}")
print(f"Checkpoints: {len(state['checkpoints'])}")
PY
}

# 获取故障历史
oml_recovery_failure_history() {
    local limit="${1:-20}"
    local worker_id="${2:-}"

    oml_recovery_ensure_init

    python3 - "${OML_RECOVERY_STATE_FILE}" "$limit" "$worker_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
limit = int(sys.argv[2])
worker_id_filter = sys.argv[3] if len(sys.argv) > 3 else None

with open(state_file, 'r') as f:
    state = json.load(f)

failures = state.get('failures', [])

# 过滤
if worker_id_filter:
    failures = [f for f in failures if f['worker_id'] == worker_id_filter]

# 排序
failures.sort(key=lambda x: x.get('timestamp', 0), reverse=True)

# 限制
failures = failures[:limit]

print(f"{'FAILURE_ID':<36} {'WORKER_ID':<30} {'TYPE':<15} {'DETECTED_AT'}")
print("=" * 95)

for f in failures:
    print(f"{f['failure_id']:<36} {f['worker_id']:<30} {f['failure_type']:<15} {f['detected_at'][:19] if f['detected_at'] else 'N/A'}")

print()
print(f"Total: {len(failures)} failure(s)")
PY
}

# ============================================================================
# 自动恢复
# ============================================================================

# 自动恢复循环
oml_recovery_auto_recover() {
    local interval="${1:-30}"
    local count="${2:-0}"

    oml_recovery_ensure_init

    oml_recovery_log "INFO" "Starting auto-recovery (interval=${interval}s)"

    local iterations=0
    while [[ $count -eq 0 ]] || [[ $iterations -lt $count ]]; do
        local recovered=0

        # 查找所有 pending 状态的恢复
        while IFS= read -r recovery_id; do
            [[ -n "$recovery_id" ]] || continue

            # 执行恢复
            local result
            result=$(oml_recovery_execute "$recovery_id")

            if [[ "$result" == in_progress:* ]]; then
                ((recovered++))
            fi
        done < <(python3 - "${OML_RECOVERY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

for recovery_id, recovery in state['recoveries'].items():
    if recovery['status'] == 'pending':
        print(recovery_id)
PY
)

        if [[ $recovered -gt 0 ]]; then
            oml_recovery_log "INFO" "Auto-recovery: ${recovered} recovery/ies processed"
        fi

        ((iterations++))
        sleep "$interval"
    done
}

# ============================================================================
# 清理与维护
# ============================================================================

# 清理已完成的恢复记录
oml_recovery_cleanup() {
    local max_age_hours="${1:-24}"

    oml_recovery_ensure_init

    local timestamp
    timestamp=$(oml_recovery_timestamp)
    local threshold=$((timestamp - max_age_hours * 3600))

    python3 - "${OML_RECOVERY_STATE_FILE}" "$threshold" <<'PY'
import json
import sys

state_file = sys.argv[1]
threshold = int(sys.argv[2])

with open(state_file, 'r') as f:
    state = json.load(f)

# 清理已完成的恢复记录
completed_to_remove = []
for recovery_id, recovery in state['recoveries'].items():
    if recovery['status'] in ['completed', 'failed']:
        completed_at = recovery.get('completed_at', '')
        if completed_at:
            try:
                ts = __import__('datetime').datetime.fromisoformat(completed_at.replace('Z', '+00:00')).timestamp()
                if ts < threshold:
                    completed_to_remove.append(recovery_id)
            except:
                pass

for recovery_id in completed_to_remove:
    del state['recoveries'][recovery_id]

# 清理已解决的故障记录
failures_to_remove = []
for i, failure in enumerate(state['failures']):
    if failure.get('acknowledged') and failure.get('recovery_id'):
        recovery = state['recoveries'].get(failure['recovery_id'])
        if recovery and recovery['status'] in ['completed', 'failed']:
            failures_to_remove.append(i)

for i in reversed(failures_to_remove):
    state['failures'].pop(i)

state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Cleaned up {len(completed_to_remove)} recovery record(s) and {len(failures_to_remove)} failure record(s)")
PY

    oml_recovery_log "INFO" "Cleanup completed"
}

# 重置恢复系统
oml_recovery_reset() {
    local force="${1:-false}"

    if [[ "$force" != "true" ]]; then
        echo "Warning: This will clear all recovery data."
        echo "Use --force to confirm."
        return 1
    fi

    oml_recovery_init

    # 清理检查点
    rm -f "${OML_RECOVERY_CHECKPOINT_DIR}"/*.json

    oml_recovery_log "WARN" "Recovery system reset completed"
    echo "Recovery system reset completed"
}

# ============================================================================
# CLI 入口
# ============================================================================

main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_recovery_init "$@"
            ;;

        # 故障检测
        report-failure)
            oml_recovery_report_failure "$@"
            ;;
        detect-worker)
            oml_recovery_detect_worker_failure "$@"
            ;;
        run-detector)
            oml_recovery_run_detector "$@"
            ;;

        # 恢复流程
        start-recovery)
            oml_recovery_start "$@"
            ;;
        execute-recovery)
            oml_recovery_execute "$@"
            ;;
        complete-recovery)
            oml_recovery_complete "$@"
            ;;
        auto-recover)
            oml_recovery_auto_recover "$@"
            ;;

        # 熔断器
        circuit-breaker-status)
            oml_recovery_circuit_breaker_status "$@"
            ;;
        circuit-breaker-reset)
            oml_recovery_circuit_breaker_reset "$@"
            ;;

        # 检查点
        checkpoint-create)
            oml_recovery_checkpoint_create "$@"
            ;;
        checkpoint-restore)
            oml_recovery_checkpoint_restore "$@"
            ;;
        checkpoint-list)
            oml_recovery_checkpoint_list "$@"
            ;;
        checkpoint-delete)
            oml_recovery_checkpoint_delete "$@"
            ;;
        checkpoint-cleanup)
            oml_recovery_checkpoint_cleanup "$@"
            ;;

        # 查询
        get-recovery)
            oml_recovery_get_status "$@"
            ;;
        list-recoveries)
            oml_recovery_list "$@"
            ;;
        failure-history)
            oml_recovery_failure_history "$@"
            ;;
        stats)
            oml_recovery_stats
            ;;

        # 维护
        cleanup)
            oml_recovery_cleanup "$@"
            ;;
        reset)
            oml_recovery_reset "$@"
            ;;

        help|--help|-h)
            cat <<EOF
OML Pool Recovery Manager v${OML_RECOVERY_VERSION}

用法：oml recovery <action> [args]

初始化:
  init [interval] [max_retries] [cb_threshold]  初始化恢复系统

故障检测:
  report-failure <worker> [type] [details] [task]  报告故障
  detect-worker <worker>                    检测 Worker 故障
  run-detector [interval] [count]           运行故障检测器

恢复流程:
  start-recovery <failure_id> [strategy]    启动恢复 (retry|restart|failover|manual)
  execute-recovery <recovery_id>            执行恢复尝试
  complete-recovery <recovery_id> [success] [result]  完成恢复
  auto-recover [interval] [count]           自动恢复循环

熔断器模式:
  circuit-breaker-status [worker]           查看熔断器状态
  circuit-breaker-reset <worker>            重置熔断器

检查点管理:
  checkpoint-create <task> [data]           创建检查点
  checkpoint-restore <checkpoint_id>        恢复检查点
  checkpoint-list [task]                    列出检查点
  checkpoint-delete <checkpoint_id>         删除检查点
  checkpoint-cleanup [hours]                清理旧检查点

查询:
  get-recovery <recovery_id>                获取恢复状态
  list-recoveries [status]                  列出恢复记录
  failure-history [limit] [worker]          故障历史
  stats                                     显示统计

维护:
  cleanup [hours]                           清理已完成记录
  reset [--force]                           重置系统

故障类型:
  timeout         超时
  crash           崩溃
  oom             内存溢出
  health_check    健康检查失败
  dependency      依赖故障

恢复策略:
  retry           重试
  restart         重启 Worker
  failover        故障转移
  manual          手动处理

示例:
  oml recovery init
  oml recovery report-failure worker-123 timeout
  oml recovery start-recovery <failure_id> retry
  oml recovery execute-recovery <recovery_id>
  oml recovery complete-recovery <recovery_id> true
  oml recovery circuit-breaker-status
  oml recovery checkpoint-create task-456 '{"progress": 50}'
  oml recovery stats
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml recovery help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
