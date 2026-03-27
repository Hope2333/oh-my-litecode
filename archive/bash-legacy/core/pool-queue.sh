#!/usr/bin/env bash
# DEPRECATED: Migrated to TypeScript (packages/core/src/pool/manager.ts)
# Archive Date: 2026-03-26
# Use: @oml/core PoolManager instead

# OML Pool Queue Manager
# 优先级队列管理 - 实现 MLFQ (多级反馈队列) 调度算法

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_POOL_QUEUE_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_POOL_QUEUE_LOADED=true

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

# ============================================================================
# 配置与常量
# ============================================================================

readonly OML_QUEUE_VERSION="0.1.0"
readonly OML_QUEUE_DIR="${OML_QUEUE_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/queue}"
readonly OML_QUEUE_STATE_FILE="${OML_QUEUE_DIR}/state.json"
readonly OML_QUEUE_LOGS_DIR="${OML_QUEUE_DIR}/logs"

# MLFQ 默认配置
readonly MLFQ_DEFAULT_QUEUES=3           # 队列数量
readonly MLFQ_DEFAULT_TIME_SLICE=100     # 时间片 (毫秒)
readonly MLFQ_DEFAULT_BOOST_INTERVAL=5   # 优先级提升间隔 (秒)
readonly MLFQ_DEFAULT_MAX_SIZE=1000      # 每队列最大任务数

# 优先级定义
readonly PRIORITY_HIGH=0
readonly PRIORITY_MEDIUM=1
readonly PRIORITY_LOW=2

# 任务状态
readonly TASK_STATUS_PENDING="pending"
readonly TASK_STATUS_RUNNING="running"
readonly TASK_STATUS_COMPLETED="completed"
readonly TASK_STATUS_FAILED="failed"
readonly TASK_STATUS_CANCELLED="cancelled"

# ============================================================================
# 工具函数
# ============================================================================

# 生成唯一任务 ID
oml_queue_generate_task_id() {
    echo "qtask-$(date +%s%N)-${RANDOM}"
}

# 获取当前时间戳（秒）
oml_queue_timestamp() {
    date +%s
}

# 获取当前时间戳（毫秒）
oml_queue_timestamp_ms() {
    python3 -c "import time; print(int(time.time() * 1000))"
}

# 获取 ISO 时间戳
oml_queue_iso_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# 日志输出
oml_queue_log() {
    local level="$1"
    local message="$2"
    local task_id="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_entry="[${timestamp}] [${level}]"
    [[ -n "$task_id" ]] && log_entry+=" [${task_id}]"
    log_entry+=" ${message}"

    echo "$log_entry" >&2

    local log_file="${OML_QUEUE_LOGS_DIR}/queue.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file" 2>/dev/null || true
}

# JSON 读取
oml_queue_json_read() {
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
# MLFQ 初始化
# ============================================================================

# 初始化 MLFQ
oml_mlfq_init() {
    local num_queues="${1:-$MLFQ_DEFAULT_QUEUES}"
    local time_slice="${2:-$MLFQ_DEFAULT_TIME_SLICE}"
    local boost_interval="${3:-$MLFQ_DEFAULT_BOOST_INTERVAL}"
    local max_size="${4:-$MLFQ_DEFAULT_MAX_SIZE}"

    mkdir -p "${OML_QUEUE_DIR}"
    mkdir -p "${OML_QUEUE_LOGS_DIR}"

    local timestamp
    timestamp="$(oml_queue_iso_timestamp)"

    # 构建队列配置
    python3 - "${OML_QUEUE_STATE_FILE}" "$num_queues" "$time_slice" "$boost_interval" "$max_size" "$timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
num_queues = int(sys.argv[2])
time_slice = int(sys.argv[3])
boost_interval = int(sys.argv[4])
max_size = int(sys.argv[5])
timestamp = sys.argv[6]

# 构建 MLFQ 配置
queues = []
for i in range(num_queues):
    queues.append({
        'queue_id': i,
        'priority': i,
        'time_slice': time_slice * (2 ** i),  # 低优先级队列时间片更长
        'max_size': max_size,
        'tasks': []
    })

state = {
    'version': '${OML_QUEUE_VERSION}',
    'created_at': timestamp,
    'updated_at': timestamp,
    'mlfq_config': {
        'num_queues': num_queues,
        'base_time_slice': time_slice,
        'boost_interval': boost_interval,
        'max_queue_size': max_size
    },
    'queues': queues,
    'tasks': {},
    'stats': {
        'total_enqueued': 0,
        'total_dequeued': 0,
        'total_completed': 0,
        'total_failed': 0,
        'total_demoted': 0,
        'total_promoted': 0,
        'priority_boosts': 0
    },
    'scheduler': {
        'last_boost': timestamp,
        'current_queue': 0,
        'round_robin_index': 0
    }
}

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"MLFQ initialized with {num_queues} queues")
PY

    oml_queue_log "INFO" "MLFQ initialized (queues=${num_queues}, time_slice=${time_slice}ms)"
    echo "MLFQ initialized at: ${OML_QUEUE_DIR}"
}

# 确保 MLFQ 已初始化
oml_mlfq_ensure_init() {
    if [[ ! -f "${OML_QUEUE_STATE_FILE}" ]]; then
        oml_mlfq_init
    fi
}

# ============================================================================
# 任务入队
# ============================================================================

# 添加任务到队列
oml_queue_enqueue() {
    local task_data="${1:-}"
    local priority="${2:-$PRIORITY_MEDIUM}"
    local deadline="${3:-}"
    local tags="${4:-}"

    oml_mlfq_ensure_init

    local task_id
    task_id="$(oml_queue_generate_task_id)"
    local timestamp
    timestamp="$(oml_queue_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_queue_iso_timestamp)"

    # 验证优先级
    if [[ "$priority" -lt 0 ]] || [[ "$priority" -ge "$MLFQ_DEFAULT_QUEUES" ]]; then
        priority=$PRIORITY_MEDIUM
    fi

    python3 - "${OML_QUEUE_STATE_FILE}" "$task_id" "$priority" "$timestamp" "$iso_timestamp" "$task_data" "$deadline" "$tags" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]
priority = int(sys.argv[3])
timestamp = int(sys.argv[4])
iso_timestamp = sys.argv[5]
task_data = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else '{}'
deadline = sys.argv[7] if len(sys.argv) > 7 and sys.argv[7] else None
tags = sys.argv[8] if len(sys.argv) > 8 and sys.argv[8] else '[]'

with open(state_file, 'r') as f:
    state = json.load(f)

# 解析任务数据
try:
    data = json.loads(task_data) if task_data else {}
except:
    data = {'raw': task_data}

# 创建任务对象
task = {
    'task_id': task_id,
    'priority': priority,
    'status': 'pending',
    'created_at': iso_timestamp,
    'updated_at': iso_timestamp,
    'enqueued_at': timestamp,
    'started_at': None,
    'completed_at': None,
    'deadline': deadline,
    'tags': json.loads(tags) if isinstance(tags, str) else tags,
    'data': data,
    'time_remaining': state['mlfq_config']['base_time_slice'] * (2 ** priority),
    'time_used': 0,
    'demotions': 0,
    'promotions': 0,
    'retries': 0
}

# 添加到对应队列
queue = state['queues'][priority]
if len(queue['tasks']) >= queue['max_size']:
    print(f"error:queue_full:{priority}")
    sys.exit(1)

queue['tasks'].append(task_id)
state['tasks'][task_id] = task
state['stats']['total_enqueued'] += 1
state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(task_id)
PY

    local result=$?
    if [[ $result -eq 0 ]]; then
        oml_queue_log "INFO" "Task enqueued: ${task_id} (priority=${priority})"
    else
        oml_queue_log "ERROR" "Failed to enqueue task (queue full)"
    fi
}

# 批量添加任务
oml_queue_enqueue_batch() {
    local tasks_json="$1"
    local default_priority="${2:-$PRIORITY_MEDIUM}"

    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" "$tasks_json" "$default_priority" <<'PY'
import json
import sys
from datetime import datetime

state_file = sys.argv[1]
tasks_json = sys.argv[2]
default_priority = int(sys.argv[3]) if len(sys.argv) > 3 else 1

with open(state_file, 'r') as f:
    state = json.load(f)

tasks = json.loads(tasks_json)
enqueued = []
failed = []

iso_timestamp = datetime.utcnow().isoformat() + 'Z'
timestamp = int(datetime.utcnow().timestamp())

for task_input in tasks:
    task_id = f"qtask-{timestamp}-{__import__('random').randint(1000, 9999)}"
    priority = task_input.get('priority', default_priority)
    
    # 验证优先级
    if priority < 0 or priority >= len(state['queues']):
        priority = default_priority
    
    queue = state['queues'][priority]
    if len(queue['tasks']) >= queue['max_size']:
        failed.append({'input': task_input, 'reason': 'queue_full'})
        continue
    
    task = {
        'task_id': task_id,
        'priority': priority,
        'status': 'pending',
        'created_at': iso_timestamp,
        'updated_at': iso_timestamp,
        'enqueued_at': timestamp,
        'started_at': None,
        'completed_at': None,
        'deadline': task_input.get('deadline'),
        'tags': task_input.get('tags', []),
        'data': task_input.get('data', {}),
        'time_remaining': state['mlfq_config']['base_time_slice'] * (2 ** priority),
        'time_used': 0,
        'demotions': 0,
        'promotions': 0,
        'retries': 0
    }
    
    queue['tasks'].append(task_id)
    state['tasks'][task_id] = task
    state['stats']['total_enqueued'] += 1
    enqueued.append(task_id)

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

result = {
    'enqueued': enqueued,
    'failed': failed,
    'total': len(tasks),
    'success_count': len(enqueued),
    'failed_count': len(failed)
}

print(json.dumps(result, indent=2))
PY
}

# ============================================================================
# 任务出队与调度
# ============================================================================

# 从队列取出下一个任务（MLFQ 调度）
oml_queue_dequeue() {
    local check_deadline="${1:-true}"

    oml_mlfq_ensure_init

    local timestamp
    timestamp="$(oml_queue_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_queue_iso_timestamp)"

    python3 - "${OML_QUEUE_STATE_FILE}" "$timestamp" "$iso_timestamp" "$check_deadline" <<'PY'
import json
import sys

state_file = sys.argv[1]
timestamp = int(sys.argv[2])
iso_timestamp = sys.argv[3]
check_deadline = sys.argv[4].lower() == 'true'

with open(state_file, 'r') as f:
    state = json.load(f)

queues = state['queues']
tasks = state['tasks']
scheduler = state['scheduler']
config = state['mlfq_config']

# MLFQ 调度算法
# 1. 从高优先级到低优先级查找
# 2. 同优先级内使用 FCFS
# 3. 考虑截止时间

selected_task = None
selected_queue_id = None

for queue in queues:
    if not queue['tasks']:
        continue
    
    # 查找队列中的第一个有效任务
    for i, task_id in enumerate(queue['tasks']):
        task = tasks.get(task_id)
        if not task or task['status'] != 'pending':
            continue
        
        # 检查截止时间
        if check_deadline and task.get('deadline'):
            try:
                deadline_ts = int(task['deadline'])
                if deadline_ts < timestamp:
                    # 任务已过期，标记为失败
                    task['status'] = 'failed'
                    task['completed_at'] = iso_timestamp
                    task['failure_reason'] = 'deadline_exceeded'
                    continue
            except:
                pass
        
        selected_task = task
        selected_queue_id = queue['queue_id']
        # 从队列移除
        queue['tasks'].pop(i)
        break
    
    if selected_task:
        break

if not selected_task:
    print("")
    sys.exit(0)

# 更新任务状态
selected_task['status'] = 'running'
selected_task['started_at'] = iso_timestamp
selected_task['updated_at'] = iso_timestamp

# 更新调度器状态
scheduler['current_queue'] = selected_queue_id
scheduler['round_robin_index'] = (scheduler.get('round_robin_index', 0) + 1) % len(queues)

state['stats']['total_dequeued'] += 1
state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

# 输出任务信息
print(json.dumps(selected_task, indent=2))
PY
}

# 完成任务
oml_queue_complete() {
    local task_id="$1"
    local result="${2:-}"
    local success="${3:-true}"

    oml_mlfq_ensure_init

    local iso_timestamp
    iso_timestamp="$(oml_queue_iso_timestamp)"

    python3 - "${OML_QUEUE_STATE_FILE}" "$task_id" "$iso_timestamp" "$success" "$result" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]
iso_timestamp = sys.argv[3]
success = sys.argv[4].lower() == 'true'
result = sys.argv[5] if len(sys.argv) > 5 else None

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if not task:
    print("error:task_not_found")
    sys.exit(1)

task['status'] = 'completed' if success else 'failed'
task['completed_at'] = iso_timestamp
task['updated_at'] = iso_timestamp

if result:
    try:
        task['result'] = json.loads(result)
    except:
        task['result'] = {'raw': result}

if not success:
    task['failure_reason'] = task.get('failure_reason', 'execution_failed')

# 更新统计
if success:
    state['stats']['total_completed'] += 1
else:
    state['stats']['total_failed'] += 1

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Task completed: {task_id} (success={success})")
PY

    oml_queue_log "INFO" "Task completed: ${task_id} (success=${success})"
}

# 任务降级（降低优先级）
oml_queue_demote() {
    local task_id="$1"

    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" "$task_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if not task:
    print("error:task_not_found")
    sys.exit(1)

current_priority = task['priority']
max_priority = len(state['queues']) - 1

if current_priority >= max_priority:
    print(f"already_lowest_priority:{current_priority}")
    sys.exit(0)

# 从当前队列移除
old_queue = state['queues'][current_priority]
if task_id in old_queue['tasks']:
    old_queue['tasks'].remove(task_id)

# 添加到下一级队列
new_priority = current_priority + 1
new_queue = state['queues'][new_priority]
new_queue['tasks'].append(task_id)

# 更新任务
task['priority'] = new_priority
task['demotions'] += 1
task['time_remaining'] = state['mlfq_config']['base_time_slice'] * (2 ** new_priority)
task['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

state['stats']['total_demoted'] += 1
state['updated_at'] = task['updated_at']

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Task demoted: {task_id} (priority {current_priority} -> {new_priority})")
PY

    oml_queue_log "INFO" "Task demoted: ${task_id}"
}

# 任务升级（提升优先级）
oml_queue_promote() {
    local task_id="$1"

    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" "$task_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if not task:
    print("error:task_not_found")
    sys.exit(1)

current_priority = task['priority']

if current_priority <= 0:
    print(f"already_highest_priority:{current_priority}")
    sys.exit(0)

# 从当前队列移除
old_queue = state['queues'][current_priority]
if task_id in old_queue['tasks']:
    old_queue['tasks'].remove(task_id)

# 添加到上一级队列
new_priority = current_priority - 1
new_queue = state['queues'][new_priority]
new_queue['tasks'].append(task_id)

# 更新任务
task['priority'] = new_priority
task['promotions'] += 1
task['time_remaining'] = state['mlfq_config']['base_time_slice'] * (2 ** new_priority)
task['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

state['stats']['total_promoted'] += 1
state['updated_at'] = task['updated_at']

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Task promoted: {task_id} (priority {current_priority} -> {new_priority})")
PY

    oml_queue_log "INFO" "Task promoted: ${task_id}"
}

# 优先级提升（老化机制）
oml_queue_priority_boost() {
    local force="${1:-false}"

    oml_mlfq_ensure_init

    local timestamp
    timestamp="$(oml_queue_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_queue_iso_timestamp)"

    python3 - "${OML_QUEUE_STATE_FILE}" "$timestamp" "$iso_timestamp" "$force" <<'PY'
import json
import sys

state_file = sys.argv[1]
timestamp = int(sys.argv[2])
iso_timestamp = sys.argv[3]
force = sys.argv[4].lower() == 'true'

with open(state_file, 'r') as f:
    state = json.load(f)

config = state['mlfq_config']
scheduler = state['scheduler']
tasks = state['tasks']

# 检查是否需要优先级提升
last_boost = scheduler.get('last_boost', 0)
boost_interval = config['boost_interval']

if not force and (timestamp - last_boost) < boost_interval:
    print(f"next_boost_in:{boost_interval - (timestamp - last_boost)}s")
    sys.exit(0)

boosted = 0

# 将所有低优先级队列中的等待任务提升到最高优先级
for queue in state['queues'][1:]:  # 跳过最高优先级队列
    for task_id in queue['tasks'][:]:
        task = tasks.get(task_id)
        if task and task['status'] == 'pending':
            # 从当前队列移除
            queue['tasks'].remove(task_id)
            
            # 添加到最高优先级队列
            state['queues'][0]['tasks'].append(task_id)
            
            # 更新任务
            task['priority'] = 0
            task['promotions'] += 1
            task['time_remaining'] = config['base_time_slice']
            task['updated_at'] = iso_timestamp
            
            boosted += 1

# 更新调度器状态
scheduler['last_boost'] = timestamp
state['stats']['priority_boosts'] += boosted
state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Priority boost completed: {boosted} task(s) promoted")
PY

    oml_queue_log "INFO" "Priority boost executed"
}

# ============================================================================
# 队列查询
# ============================================================================

# 获取任务信息
oml_queue_get_task() {
    local task_id="$1"

    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" "$task_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if not task:
    print("Task not found", file=sys.stderr)
    sys.exit(1)

print(json.dumps(task, indent=2))
PY
}

# 列出队列中的任务
oml_queue_list() {
    local queue_id="${1:-all}"
    local status_filter="${2:-pending}"
    local limit="${3:-20}"

    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" "$queue_id" "$status_filter" "$limit" <<'PY'
import json
import sys

state_file = sys.argv[1]
queue_id = sys.argv[2]
status_filter = sys.argv[3]
limit = int(sys.argv[4])

with open(state_file, 'r') as f:
    state = json.load(f)

queues = state['queues']
tasks = state['tasks']

print(f"{'TASK_ID':<30} {'PRIORITY':<10} {'STATUS':<12} {'QUEUE':<8} {'ENQUEUED_AT'}")
print("=" * 80)

count = 0
for q in queues:
    if queue_id != 'all' and q['queue_id'] != int(queue_id):
        continue
    
    for task_id in q['tasks']:
        task = tasks.get(task_id)
        if not task:
            continue
        
        if status_filter != 'all' and task['status'] != status_filter:
            continue
        
        if count >= limit:
            break
        
        enqueued = task.get('enqueued_at', 0)
        if enqueued:
            import datetime
            enqueued_str = datetime.datetime.fromtimestamp(enqueued).strftime('%Y-%m-%d %H:%M:%S')
        else:
            enqueued_str = 'N/A'
        
        print(f"{task_id:<30} {task['priority']:<10} {task['status']:<12} {q['queue_id']:<8} {enqueued_str}")
        count += 1
    
    if count >= limit:
        break

print()
print(f"Total: {count} task(s)")
PY
}

# 获取队列统计
oml_queue_stats() {
    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

config = state['mlfq_config']
queues = state['queues']
tasks = state['tasks']
stats = state['stats']
scheduler = state['scheduler']

print("=== MLFQ Queue Statistics ===")
print(f"Version: {state['version']}")
print(f"Created: {state['created_at']}")
print(f"Updated: {state['updated_at']}")
print()
print("Configuration:")
print(f"  Number of Queues: {config['num_queues']}")
print(f"  Base Time Slice: {config['base_time_slice']}ms")
print(f"  Boost Interval: {config['boost_interval']}s")
print(f"  Max Queue Size: {config['max_queue_size']}")
print()
print("Queue Status:")

for queue in queues:
    pending = sum(1 for tid in queue['tasks'] if tasks.get(tid, {}).get('status') == 'pending')
    print(f"  Queue {queue['queue_id']} (Priority {queue['priority']}):")
    print(f"    Tasks: {len(queue['tasks'])} (pending: {pending})")
    print(f"    Time Slice: {queue['time_slice']}ms")

print()
print("Scheduler:")
print(f"  Current Queue: {scheduler['current_queue']}")
print(f"  Last Boost: {scheduler.get('last_boost', 'N/A')}")

print()
print("Statistics:")
print(f"  Total Enqueued: {stats['total_enqueued']}")
print(f"  Total Dequeued: {stats['total_dequeued']}")
print(f"  Completed: {stats['total_completed']}")
print(f"  Failed: {stats['total_failed']}")
print(f"  Demoted: {stats['total_demoted']}")
print(f"  Promoted: {stats['total_promoted']}")
print(f"  Priority Boosts: {stats['priority_boosts']}")

# 计算队列深度
total_pending = sum(len(q['tasks']) for q in queues)
print()
print(f"Total Pending Tasks: {total_pending}")
PY
}

# 获取队列状态（JSON）
oml_queue_get_state() {
    oml_mlfq_ensure_init

    if [[ -f "${OML_QUEUE_STATE_FILE}" ]]; then
        cat "${OML_QUEUE_STATE_FILE}"
    else
        echo "{}"
    fi
}

# ============================================================================
# 任务管理
# ============================================================================

# 取消任务
oml_queue_cancel() {
    local task_id="$1"

    oml_mlfq_ensure_init

    local iso_timestamp
    iso_timestamp="$(oml_queue_iso_timestamp)"

    python3 - "${OML_QUEUE_STATE_FILE}" "$task_id" "$iso_timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]
iso_timestamp = sys.argv[3]

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if not task:
    print("error:task_not_found")
    sys.exit(1)

# 从队列中移除
for queue in state['queues']:
    if task_id in queue['tasks']:
        queue['tasks'].remove(task_id)
        break

task['status'] = 'cancelled'
task['completed_at'] = iso_timestamp
task['updated_at'] = iso_timestamp

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Task cancelled: {task_id}")
PY

    oml_queue_log "INFO" "Task cancelled: ${task_id}"
}

# 重试任务
oml_queue_retry() {
    local task_id="$1"
    local max_retries="${2:-3}"

    oml_mlfq_ensure_init

    local iso_timestamp
    iso_timestamp="$(oml_queue_iso_timestamp)"
    local timestamp
    timestamp="$(oml_queue_timestamp)"

    python3 - "${OML_QUEUE_STATE_FILE}" "$task_id" "$iso_timestamp" "$timestamp" "$max_retries" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]
iso_timestamp = sys.argv[3]
timestamp = int(sys.argv[4])
max_retries = int(sys.argv[5])

with open(state_file, 'r') as f:
    state = json.load(f)

task = state['tasks'].get(task_id)
if not task:
    print("error:task_not_found")
    sys.exit(1)

if task['retries'] >= max_retries:
    print(f"error:max_retries_exceeded:{task['retries']}")
    sys.exit(1)

# 重置任务状态
task['status'] = 'pending'
task['retries'] += 1
task['updated_at'] = iso_timestamp
task['enqueued_at'] = timestamp
task['started_at'] = None
task['completed_at'] = None
task.pop('result', None)
task.pop('failure_reason', None)

# 重新加入原优先级队列
priority = task['priority']
state['queues'][priority]['tasks'].append(task_id)

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Task retry scheduled: {task_id} (attempt {task['retries']}/{max_retries})")
PY

    oml_queue_log "INFO" "Task retry: ${task_id}"
}

# 搜索任务
oml_queue_search() {
    local query="$1"
    local field="${2:-all}"

    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" "$query" "$field" <<'PY'
import json
import sys

state_file = sys.argv[1]
query = sys.argv[2].lower()
field = sys.argv[3] if len(sys.argv) > 3 else 'all'

with open(state_file, 'r') as f:
    state = json.load(f)

tasks = state['tasks']
results = []

for task_id, task in tasks.items():
    match = False
    
    if field == 'all' or field == 'task_id':
        if query in task_id.lower():
            match = True
    
    if field == 'all' or field == 'tags':
        tags = task.get('tags', [])
        if any(query in str(tag).lower() for tag in tags):
            match = True
    
    if field == 'all' or field == 'data':
        data_str = json.dumps(task.get('data', {})).lower()
        if query in data_str:
            match = True
    
    if match:
        results.append({
            'task_id': task_id,
            'priority': task['priority'],
            'status': task['status'],
            'created_at': task.get('created_at'),
            'tags': task.get('tags', [])
        })

# 排序
results.sort(key=lambda x: (x['priority'], x.get('created_at', '')))

print(json.dumps({'results': results, 'count': len(results)}, indent=2))
PY
}

# ============================================================================
# 清理与维护
# ============================================================================

# 清理已完成的任务
oml_queue_cleanup() {
    local max_age_hours="${1:-24}"

    oml_mlfq_ensure_init

    python3 - "${OML_QUEUE_STATE_FILE}" "$max_age_hours" <<'PY'
import json
import sys
from datetime import datetime, timedelta

state_file = sys.argv[1]
max_age_hours = int(sys.argv[2])

with open(state_file, 'r') as f:
    state = json.load(f)

cutoff = datetime.utcnow() - timedelta(hours=max_age_hours)
cleaned = 0
task_ids_to_remove = []

for task_id, task in state['tasks'].items():
    if task['status'] in ['completed', 'failed', 'cancelled']:
        completed_at = task.get('completed_at', '')
        if completed_at:
            try:
                task_time = datetime.fromisoformat(completed_at.replace('Z', '+00:00'))
                if task_time < cutoff:
                    task_ids_to_remove.append(task_id)
            except:
                pass

for task_id in task_ids_to_remove:
    del state['tasks'][task_id]
    cleaned += 1

state['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Cleaned up {cleaned} completed task(s)")
PY

    oml_queue_log "INFO" "Cleanup completed"
}

# 重置队列
oml_queue_reset() {
    local force="${1:-false}"

    if [[ "$force" != "true" ]]; then
        echo "Warning: This will remove all pending tasks."
        echo "Use --force to confirm."
        return 1
    fi

    oml_mlfq_ensure_init

    local timestamp
    timestamp="$(oml_queue_iso_timestamp)"

    python3 - "${OML_QUEUE_STATE_FILE}" "$timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
timestamp = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

# 保留配置，清空队列和任务
config = state['mlfq_config']
stats = state['stats']

state = {
    'version': '${OML_QUEUE_VERSION}',
    'created_at': state['created_at'],
    'updated_at': timestamp,
    'mlfq_config': config,
    'queues': [
        {
            'queue_id': i,
            'priority': i,
            'time_slice': config['base_time_slice'] * (2 ** i),
            'max_size': config['max_queue_size'],
            'tasks': []
        }
        for i in range(config['num_queues'])
    ],
    'tasks': {},
    'stats': stats,
    'scheduler': {
        'last_boost': 0,
        'current_queue': 0,
        'round_robin_index': 0
    }
}

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print("Queue reset completed")
PY

    oml_queue_log "WARN" "Queue reset completed"
}

# ============================================================================
# CLI 入口
# ============================================================================

main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_mlfq_init "$@"
            ;;
        enqueue)
            oml_queue_enqueue "$@"
            ;;
        enqueue-batch)
            oml_queue_enqueue_batch "$@"
            ;;
        dequeue)
            oml_queue_dequeue "$@"
            ;;
        complete)
            oml_queue_complete "$@"
            ;;
        demote)
            oml_queue_demote "$@"
            ;;
        promote)
            oml_queue_promote "$@"
            ;;
        boost)
            oml_queue_priority_boost "$@"
            ;;
        get-task)
            oml_queue_get_task "$@"
            ;;
        list)
            oml_queue_list "$@"
            ;;
        stats)
            oml_queue_stats
            ;;
        get-state)
            oml_queue_get_state
            ;;
        cancel)
            oml_queue_cancel "$@"
            ;;
        retry)
            oml_queue_retry "$@"
            ;;
        search)
            oml_queue_search "$@"
            ;;
        cleanup)
            oml_queue_cleanup "$@"
            ;;
        reset)
            oml_queue_reset "$@"
            ;;
        help|--help|-h)
            cat <<EOF
OML Pool Queue Manager v${OML_QUEUE_VERSION}
MLFQ (Multi-Level Feedback Queue) Scheduler

用法：oml queue <action> [args]

初始化:
  init [queues] [time_slice] [boost_interval] [max_size]  初始化 MLFQ

任务入队:
  enqueue <data> [priority] [deadline] [tags]  添加任务
  enqueue-batch <json> [default_priority]      批量添加

任务调度:
  dequeue [check_deadline]    取出下一个任务（MLFQ 调度）
  complete <id> [result] [success]  完成任务

优先级管理:
  demote <id>     降低任务优先级
  promote <id>    提升任务优先级
  boost [--force] 优先级提升（老化机制）

任务查询:
  get-task <id>           获取任务信息
  list [queue] [status] [limit]  列出任务
  search <query> [field]  搜索任务
  stats                   显示统计
  get-state               获取状态 (JSON)

任务管理:
  cancel <id>             取消任务
  retry <id> [max_retries]  重试任务

维护:
  cleanup [hours]         清理已完成任务
  reset [--force]         重置队列

优先级说明:
  0 = HIGH (最高优先级)
  1 = MEDIUM (默认)
  2 = LOW (最低优先级)

示例:
  oml queue init 3 100 5 1000
  oml queue enqueue '{"cmd": "echo hello"}' 0
  oml queue dequeue
  oml queue list all pending 20
  oml queue stats
  oml queue boost --force
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml queue help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
