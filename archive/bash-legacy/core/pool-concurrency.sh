#!/usr/bin/env bash
# DEPRECATED: Migrated to TypeScript (packages/core/src/pool/manager.ts)
# Archive Date: 2026-03-26
# Use: @oml/core PoolManager instead

# OML Pool Concurrency Control
# 并发控制模块 - 实现令牌桶算法进行流量控制

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_POOL_CONCURRENCY_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_POOL_CONCURRENCY_LOADED=true

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

readonly OML_CONCURRENCY_VERSION="0.1.0"
readonly OML_CONCURRENCY_DIR="${OML_CONCURRENCY_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/concurrency}"
readonly OML_CONCURRENCY_STATE_FILE="${OML_CONCURRENCY_DIR}/state.json"
readonly OML_CONCURRENCY_LOGS_DIR="${OML_CONCURRENCY_DIR}/logs"

# 令牌桶默认配置
readonly BUCKET_DEFAULT_CAPACITY=10      # 桶容量（最大令牌数）
readonly BUCKET_DEFAULT_REFILL_RATE=5    # 每秒补充令牌数
readonly BUCKET_DEFAULT_MIN_TOKENS=1     # 执行所需最小令牌数

# 并发限制默认配置
readonly CONCURRENCY_DEFAULT_LIMIT=10    # 最大并发数
readonly CONCURRENCY_DEFAULT_QUEUE_SIZE=100  # 队列大小

# ============================================================================
# 工具函数
# ============================================================================

# 获取当前时间戳（毫秒）
oml_concurrency_timestamp_ms() {
    python3 -c "import time; print(int(time.time() * 1000))"
}

# 获取当前时间戳（秒，带小数）
oml_concurrency_timestamp() {
    python3 -c "import time; print(time.time())"
}

# 日志输出
oml_concurrency_log() {
    local level="$1"
    local message="$2"
    local bucket_id="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_entry="[${timestamp}] [${level}]"
    [[ -n "$bucket_id" ]] && log_entry+=" [${bucket_id}]"
    log_entry+=" ${message}"

    echo "$log_entry" >&2

    local log_file="${OML_CONCURRENCY_LOGS_DIR}/concurrency.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file" 2>/dev/null || true
}

# 生成唯一桶 ID
oml_concurrency_generate_bucket_id() {
    echo "bucket-$(date +%s)-${RANDOM}"
}

# JSON 读取
oml_concurrency_json_read() {
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
# 令牌桶算法核心
# ============================================================================

# 初始化令牌桶
oml_bucket_init() {
    local bucket_id="${1:-default}"
    local capacity="${2:-$BUCKET_DEFAULT_CAPACITY}"
    local refill_rate="${3:-$BUCKET_DEFAULT_REFILL_RATE}"
    local min_tokens="${4:-$BUCKET_DEFAULT_MIN_TOKENS}"

    mkdir -p "${OML_CONCURRENCY_DIR}"
    mkdir -p "${OML_CONCURRENCY_LOGS_DIR}"

    local timestamp
    timestamp="$(oml_concurrency_timestamp)"

    # 创建/更新桶状态
    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" "$capacity" "$refill_rate" "$min_tokens" "$timestamp" <<'PY'
import json
import sys
import os

state_file = sys.argv[1]
bucket_id = sys.argv[2]
capacity = int(sys.argv[3])
refill_rate = float(sys.argv[4])
min_tokens = int(sys.argv[5])
timestamp = float(sys.argv[6])

# 读取或创建状态文件
if os.path.exists(state_file):
    with open(state_file, 'r') as f:
        state = json.load(f)
else:
    state = {'buckets': {}, 'created_at': __import__('datetime').datetime.utcnow().isoformat() + 'Z'}

# 初始化桶
state['buckets'][bucket_id] = {
    'bucket_id': bucket_id,
    'capacity': capacity,
    'tokens': capacity,  # 初始满桶
    'refill_rate': refill_rate,
    'min_tokens': min_tokens,
    'last_refill': timestamp,
    'total_consumed': 0,
    'total_refilled': 0,
    'created_at': __import__('datetime').datetime.utcnow().isoformat() + 'Z',
    'updated_at': __import__('datetime').datetime.utcnow().isoformat() + 'Z'
}

state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Bucket initialized: {bucket_id}")
PY

    oml_concurrency_log "INFO" "Bucket initialized: ${bucket_id} (capacity=${capacity}, refill=${refill_rate}/s)"
}

# 确保桶已初始化
oml_bucket_ensure_init() {
    local bucket_id="${1:-default}"

    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        oml_bucket_init "$bucket_id"
    fi

    # 检查桶是否存在
    local exists
    exists=$(python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" <<'PY'
import json
import sys
import os

state_file = sys.argv[1]
bucket_id = sys.argv[2]

if not os.path.exists(state_file):
    print("false")
    sys.exit(0)

with open(state_file, 'r') as f:
    state = json.load(f)

print("true" if bucket_id in state.get('buckets', {}) else "false")
PY
)

    if [[ "$exists" != "true" ]]; then
        oml_bucket_init "$bucket_id"
    fi
}

# 补充令牌（内部函数，基于时间流逝）
oml_bucket_refill() {
    local bucket_id="${1:-default}"

    oml_bucket_ensure_init "$bucket_id"

    local current_time
    current_time=$(oml_concurrency_timestamp)

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" "$current_time" <<'PY'
import json
import sys

state_file = sys.argv[1]
bucket_id = sys.argv[2]
current_time = float(sys.argv[3])

with open(state_file, 'r') as f:
    state = json.load(f)

bucket = state['buckets'].get(bucket_id)
if not bucket:
    print("0")
    sys.exit(1)

# 计算时间差和应补充的令牌数
time_diff = current_time - bucket['last_refill']
tokens_to_add = time_diff * bucket['refill_rate']

if tokens_to_add > 0:
    old_tokens = bucket['tokens']
    bucket['tokens'] = min(bucket['capacity'], bucket['tokens'] + tokens_to_add)
    bucket['last_refill'] = current_time
    bucket['total_refilled'] += (bucket['tokens'] - old_tokens)
    bucket['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print(f"{bucket['tokens'] - old_tokens:.2f}")
else:
    print("0")
PY
}

# 消费令牌
oml_bucket_consume() {
    local bucket_id="${1:-default}"
    local tokens="${2:-1}"
    local wait="${3:-false}"
    local timeout="${4:-30}"

    oml_bucket_ensure_init "$bucket_id"

    # 先补充令牌
    oml_bucket_refill "$bucket_id" >/dev/null

    local start_time
    start_time=$(oml_concurrency_timestamp_ms)

    while true; do
        local result
        result=$(python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" "$tokens" <<'PY'
import json
import sys

state_file = sys.argv[1]
bucket_id = sys.argv[2]
tokens = int(sys.argv[3])

with open(state_file, 'r') as f:
    state = json.load(f)

bucket = state['buckets'].get(bucket_id)
if not bucket:
    print("error:bucket_not_found")
    sys.exit(1)

# 检查是否有足够令牌
min_tokens = bucket.get('min_tokens', 1)
if bucket['tokens'] >= tokens:
    bucket['tokens'] -= tokens
    bucket['total_consumed'] += tokens
    bucket['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print(f"success:{bucket['tokens']:.2f}")
else:
    available = bucket['tokens']
    print(f"insufficient:{available:.2f}:{min_tokens}")
PY
)

        if [[ "$result" == success:* ]]; then
            local remaining="${result#success:}"
            oml_concurrency_log "DEBUG" "Consumed ${tokens} token(s) from ${bucket_id}, remaining: ${remaining}"
            echo "success:$remaining"
            return 0
        fi

        if [[ "$wait" != "true" ]]; then
            oml_concurrency_log "DEBUG" "Insufficient tokens in ${bucket_id}: ${result}"
            echo "$result"
            return 1
        fi

        # 检查超时
        local current_time
        current_time=$(oml_concurrency_timestamp_ms)
        local elapsed=$(( (current_time - start_time) / 1000 ))
        if [[ $elapsed -ge $timeout ]]; then
            oml_concurrency_log "ERROR" "Timeout waiting for tokens in ${bucket_id}"
            echo "timeout:elapsed=${elapsed}s"
            return 1
        fi

        # 等待一小段时间后重试
        sleep 0.1
    done
}

# 获取桶状态
oml_bucket_status() {
    local bucket_id="${1:-default}"

    oml_bucket_ensure_init "$bucket_id"

    # 先补充令牌
    oml_bucket_refill "$bucket_id" >/dev/null

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
bucket_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

bucket = state['buckets'].get(bucket_id)
if not bucket:
    print("Bucket not found", file=sys.stderr)
    sys.exit(1)

# 计算可用令牌百分比
utilization = (bucket['tokens'] / bucket['capacity'] * 100) if bucket['capacity'] > 0 else 0

print(f"=== Token Bucket: {bucket_id} ===")
print(f"Capacity: {bucket['capacity']}")
print(f"Available Tokens: {bucket['tokens']:.2f}")
print(f"Utilization: {utilization:.1f}%")
print(f"Refill Rate: {bucket['refill_rate']}/s")
print(f"Min Tokens Required: {bucket['min_tokens']}")
print(f"Total Consumed: {bucket['total_consumed']}")
print(f"Total Refilled: {bucket['total_refilled']:.2f}")
print(f"Last Refill: {bucket['last_refill']}")
PY
}

# 获取桶状态（JSON）
oml_bucket_status_json() {
    local bucket_id="${1:-default}"

    oml_bucket_ensure_init "$bucket_id"
    oml_bucket_refill "$bucket_id" >/dev/null

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
bucket_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

bucket = state['buckets'].get(bucket_id)
if not bucket:
    print("{}")
    sys.exit(1)

# 输出桶信息（不包含内部状态）
output = {
    'bucket_id': bucket['bucket_id'],
    'capacity': bucket['capacity'],
    'tokens': round(bucket['tokens'], 2),
    'refill_rate': bucket['refill_rate'],
    'min_tokens': bucket['min_tokens'],
    'utilization': round(bucket['tokens'] / bucket['capacity'] * 100, 2) if bucket['capacity'] > 0 else 0,
    'total_consumed': bucket['total_consumed'],
    'total_refilled': round(bucket['total_refilled'], 2)
}

print(json.dumps(output, indent=2))
PY
}

# 更新桶配置
oml_bucket_configure() {
    local bucket_id="${1:-default}"
    local capacity="${2:-}"
    local refill_rate="${3:-}"
    local min_tokens="${4:-}"

    oml_bucket_ensure_init "$bucket_id"

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" "$capacity" "$refill_rate" "$min_tokens" <<'PY'
import json
import sys

state_file = sys.argv[1]
bucket_id = sys.argv[2]
capacity = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
refill_rate = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
min_tokens = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None

with open(state_file, 'r') as f:
    state = json.load(f)

bucket = state['buckets'].get(bucket_id)
if not bucket:
    print("Bucket not found", file=sys.stderr)
    sys.exit(1)

if capacity:
    bucket['capacity'] = int(capacity)
    # 如果当前令牌超过新容量，调整为容量值
    if bucket['tokens'] > bucket['capacity']:
        bucket['tokens'] = bucket['capacity']

if refill_rate:
    bucket['refill_rate'] = float(refill_rate)

if min_tokens:
    bucket['min_tokens'] = int(min_tokens)

bucket['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Bucket configured: {bucket_id}")
PY

    oml_concurrency_log "INFO" "Bucket configured: ${bucket_id}"
}

# 重置桶
oml_bucket_reset() {
    local bucket_id="${1:-default}"

    oml_bucket_ensure_init "$bucket_id"

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
bucket_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

bucket = state['buckets'].get(bucket_id)
if not bucket:
    print("Bucket not found", file=sys.stderr)
    sys.exit(1)

bucket['tokens'] = bucket['capacity']
bucket['last_refill'] = __import__('time').time()
bucket['total_consumed'] = 0
bucket['total_refilled'] = 0
bucket['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Bucket reset: {bucket_id}")
PY

    oml_concurrency_log "INFO" "Bucket reset: ${bucket_id}"
}

# 删除桶
oml_bucket_delete() {
    local bucket_id="${1:-default}"

    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        oml_concurrency_log "WARN" "State file not found"
        return 1
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$bucket_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
bucket_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

if bucket_id in state.get('buckets', {}):
    del state['buckets'][bucket_id]
    state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print(f"Bucket deleted: {bucket_id}")
else:
    print("Bucket not found", file=sys.stderr)
    sys.exit(1)
PY

    oml_concurrency_log "INFO" "Bucket deleted: ${bucket_id}"
}

# ============================================================================
# 并发限制器
# ============================================================================

# 初始化并发限制器
oml_concurrency_init() {
    local limit="${1:-$CONCURRENCY_DEFAULT_LIMIT}"
    local queue_size="${2:-$CONCURRENCY_DEFAULT_QUEUE_SIZE}"

    mkdir -p "${OML_CONCURRENCY_DIR}"

    local timestamp
    timestamp="$(oml_concurrency_timestamp)"

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$limit" "$queue_size" "$timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
limit = int(sys.argv[2])
queue_size = int(sys.argv[3])
timestamp = float(sys.argv[4])

with open(state_file, 'r') as f:
    state = json.load(f) if __import__('os').path.exists(state_file) else {}

state['concurrency_limiter'] = {
    'limit': limit,
    'queue_size': queue_size,
    'current_count': 0,
    'queue': [],
    'total_acquired': 0,
    'total_released': 0,
    'peak_concurrency': 0,
    'created_at': __import__('datetime').datetime.utcnow().isoformat() + 'Z',
    'updated_at': __import__('datetime').datetime.utcnow().isoformat() + 'Z'
}

state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Concurrency limiter initialized (limit={limit}, queue_size={queue_size})")
PY

    oml_concurrency_log "INFO" "Concurrency limiter initialized (limit=${limit})"
}

# 获取执行槽位
oml_concurrency_acquire() {
    local timeout="${1:-30}"
    local task_id="${2:-}"

    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        oml_concurrency_init
    fi

    local start_time
    start_time=$(oml_concurrency_timestamp_ms)

    while true; do
        local result
        result=$(python3 - "${OML_CONCURRENCY_STATE_FILE}" "$task_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2] if len(sys.argv) > 2 else None

with open(state_file, 'r') as f:
    state = json.load(f)

limiter = state.get('concurrency_limiter', {})
limit = limiter.get('limit', 10)
queue_size = limiter.get('queue_size', 100)
current = limiter.get('current_count', 0)
queue = limiter.get('queue', [])

if current < limit:
    # 有空闲槽位
    limiter['current_count'] = current + 1
    limiter['total_acquired'] = limiter.get('total_acquired', 0) + 1
    if limiter['current_count'] > limiter.get('peak_concurrency', 0):
        limiter['peak_concurrency'] = limiter['current_count']

    slot_id = f"slot-{__import__('time').time()}-{__import__('random').randint(1000, 9999)}"

    state['concurrency_limiter'] = limiter
    state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print(f"acquired:{slot_id}:{limiter['current_count']}/{limit}")
elif len(queue) < queue_size:
    # 加入队列
    if task_id:
        queue.append({'task_id': task_id, 'queued_at': __import__('time').time()})
    else:
        queue.append({'task_id': f"anon-{__import__('time').time()}", 'queued_at': __import__('time').time()})

    limiter['queue'] = queue
    state['concurrency_limiter'] = limiter
    state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print(f"queued:{len(queue)}/{queue_size}")
else:
    print("rejected:queue_full")
PY
)

        if [[ "$result" == acquired:* ]]; then
            local slot_info="${result#acquired:}"
            oml_concurrency_log "DEBUG" "Slot acquired: ${slot_info}"
            echo "$result"
            return 0
        elif [[ "$result" == queued:* ]]; then
            if [[ "$timeout" -le 0 ]]; then
                echo "$result"
                return 1
            fi

            # 检查超时
            local current_time
            current_time=$(oml_concurrency_timestamp_ms)
            local elapsed=$(( (current_time - start_time) / 1000 ))
            if [[ $elapsed -ge $timeout ]]; then
                # 从队列移除
                python3 - "${OML_CONCURRENCY_STATE_FILE}" "$task_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
task_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

limiter = state.get('concurrency_limiter', {})
queue = limiter.get('queue', [])

# 移除超时任务
queue = [q for q in queue if q.get('task_id') != task_id]
limiter['queue'] = queue
state['concurrency_limiter'] = limiter

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY
                echo "timeout:elapsed=${elapsed}s"
                return 1
            fi

            sleep 0.2
        else
            echo "$result"
            return 1
        fi
    done
}

# 释放执行槽位
oml_concurrency_release() {
    local slot_id="${1:-}"

    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        oml_concurrency_log "WARN" "State file not found"
        return 1
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

limiter = state.get('concurrency_limiter', {})
current = limiter.get('current_count', 0)

if current > 0:
    limiter['current_count'] = current - 1
    limiter['total_released'] = limiter.get('total_released', 0) + 1

    # 处理队列中的下一个任务（如果有）
    queue = limiter.get('queue', [])
    if queue:
        # 队列中的任务会在下次 acquire 时自动处理
        pass

    state['concurrency_limiter'] = limiter
    state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

    print(f"released:{limiter['current_count']}/{limiter.get('limit', 10)}")
else:
    print("warning:no_active_slots")
PY

    oml_concurrency_log "DEBUG" "Slot released: ${slot_id:-unknown}"
}

# 获取并发状态
oml_concurrency_status() {
    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        echo "Concurrency limiter not initialized"
        return 1
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

limiter = state.get('concurrency_limiter', {})

print("=== Concurrency Limiter Status ===")
print(f"Limit: {limiter.get('limit', 'N/A')}")
print(f"Queue Size: {limiter.get('queue_size', 'N/A')}")
print(f"Current Count: {limiter.get('current_count', 0)}")
print(f"Queue Length: {len(limiter.get('queue', []))}")
print(f"Peak Concurrency: {limiter.get('peak_concurrency', 0)}")
print(f"Total Acquired: {limiter.get('total_acquired', 0)}")
print(f"Total Released: {limiter.get('total_released', 0)}")
PY
}

# 获取并发状态（JSON）
oml_concurrency_status_json() {
    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        echo "{}"
        return 1
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

limiter = state.get('concurrency_limiter', {})
queue = limiter.get('queue', [])

output = {
    'limit': limiter.get('limit', 0),
    'queue_size': limiter.get('queue_size', 0),
    'current_count': limiter.get('current_count', 0),
    'queue_length': len(queue),
    'peak_concurrency': limiter.get('peak_concurrency', 0),
    'total_acquired': limiter.get('total_acquired', 0),
    'total_released': limiter.get('total_released', 0),
    'utilization': round(limiter.get('current_count', 0) / limiter.get('limit', 1) * 100, 2)
}

print(json.dumps(output, indent=2))
PY
}

# 更新并发限制
oml_concurrency_configure() {
    local limit="${1:-}"
    local queue_size="${2:-}"

    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        oml_concurrency_log "ERROR" "Concurrency limiter not initialized"
        return 1
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" "$limit" "$queue_size" <<'PY'
import json
import sys

state_file = sys.argv[1]
limit = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
queue_size = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None

with open(state_file, 'r') as f:
    state = json.load(f)

limiter = state.get('concurrency_limiter', {})

if limit:
    limiter['limit'] = int(limit)

if queue_size:
    limiter['queue_size'] = int(queue_size)

state['concurrency_limiter'] = limiter
state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Concurrency limiter configured (limit={limiter.get('limit')}, queue_size={limiter.get('queue_size')})")
PY

    oml_concurrency_log "INFO" "Concurrency limiter configured"
}

# 重置并发限制器
oml_concurrency_reset() {
    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        return 0
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

limiter = state.get('concurrency_limiter', {})

limiter['current_count'] = 0
limiter['queue'] = []
limiter['total_acquired'] = 0
limiter['total_released'] = 0
limiter['peak_concurrency'] = 0
limiter['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

state['concurrency_limiter'] = limiter
state['updated_at'] = __import__('datetime').datetime.utcnow().isoformat() + 'Z'

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print("Concurrency limiter reset")
PY

    oml_concurrency_log "INFO" "Concurrency limiter reset"
}

# ============================================================================
# 批量操作与工具
# ============================================================================

# 列出所有桶
oml_bucket_list() {
    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        echo "No buckets found"
        return 0
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

buckets = state.get('buckets', {})

if not buckets:
    print("No buckets found")
    sys.exit(0)

print(f"{'BUCKET_ID':<30} {'TOKENS':<12} {'CAPACITY':<10} {'REFILL':<10} {'UTILIZATION'}")
print("=" * 75)

for bucket_id, bucket in buckets.items():
    utilization = (bucket['tokens'] / bucket['capacity'] * 100) if bucket['capacity'] > 0 else 0
    print(f"{bucket_id:<30} {bucket['tokens']:.2f}/{bucket['capacity']:<8} {bucket['refill_rate']:<10} {utilization:.1f}%")
PY
}

# 获取所有统计
oml_concurrency_stats() {
    if [[ ! -f "${OML_CONCURRENCY_STATE_FILE}" ]]; then
        echo "Concurrency system not initialized"
        return 1
    fi

    python3 - "${OML_CONCURRENCY_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

print("=== Concurrency Control Statistics ===")
print(f"Version: ${OML_CONCURRENCY_VERSION}")
print(f"Created: {state.get('created_at', 'N/A')}")
print(f"Updated: {state.get('updated_at', 'N/A')}")
print()

# 桶统计
buckets = state.get('buckets', {})
print(f"Token Buckets: {len(buckets)}")
if buckets:
    total_capacity = sum(b['capacity'] for b in buckets.values())
    total_tokens = sum(b['tokens'] for b in buckets.values())
    total_consumed = sum(b['total_consumed'] for b in buckets.values())
    print(f"  Total Capacity: {total_capacity}")
    print(f"  Total Available: {total_tokens:.2f}")
    print(f"  Total Consumed: {total_consumed}")
print()

# 并发限制器统计
limiter = state.get('concurrency_limiter', {})
if limiter:
    print("Concurrency Limiter:")
    print(f"  Limit: {limiter.get('limit', 'N/A')}")
    print(f"  Current: {limiter.get('current_count', 0)}")
    print(f"  Peak: {limiter.get('peak_concurrency', 0)}")
    print(f"  Total Acquired: {limiter.get('total_acquired', 0)}")
    print(f"  Total Released: {limiter.get('total_released', 0)}")
PY
}

# ============================================================================
# CLI 入口
# ============================================================================

main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        # 令牌桶操作
        bucket-init)
            oml_bucket_init "$@"
            ;;
        bucket-consume)
            oml_bucket_consume "$@"
            ;;
        bucket-status)
            oml_bucket_status "$@"
            ;;
        bucket-status-json)
            oml_bucket_status_json "$@"
            ;;
        bucket-configure)
            oml_bucket_configure "$@"
            ;;
        bucket-reset)
            oml_bucket_reset "$@"
            ;;
        bucket-delete)
            oml_bucket_delete "$@"
            ;;
        bucket-list)
            oml_bucket_list
            ;;

        # 并发限制器操作
        concurrency-init)
            oml_concurrency_init "$@"
            ;;
        concurrency-acquire)
            oml_concurrency_acquire "$@"
            ;;
        concurrency-release)
            oml_concurrency_release "$@"
            ;;
        concurrency-status)
            oml_concurrency_status
            ;;
        concurrency-status-json)
            oml_concurrency_status_json
            ;;
        concurrency-configure)
            oml_concurrency_configure "$@"
            ;;
        concurrency-reset)
            oml_concurrency_reset
            ;;

        # 统计
        stats)
            oml_concurrency_stats
            ;;

        # 帮助
        help|--help|-h)
            cat <<EOF
OML Pool Concurrency Control v${OML_CONCURRENCY_VERSION}

用法：oml concurrency <action> [args]

令牌桶算法:
  bucket-init [id] [capacity] [refill_rate] [min_tokens]  初始化令牌桶
  bucket-consume [id] [tokens] [--wait] [--timeout]       消费令牌
  bucket-status [id]                                      查看桶状态
  bucket-status-json [id]                                 查看桶状态 (JSON)
  bucket-configure [id] [capacity] [refill_rate] [min]    配置桶参数
  bucket-reset [id]                                       重置桶
  bucket-delete [id]                                      删除桶
  bucket-list                                             列出所有桶

并发限制器:
  concurrency-init [limit] [queue_size]     初始化并发限制器
  concurrency-acquire [timeout] [task_id]   获取执行槽位
  concurrency-release [slot_id]             释放执行槽位
  concurrency-status                        查看状态
  concurrency-status-json                   查看状态 (JSON)
  concurrency-configure [limit] [queue]     配置限制器
  concurrency-reset                         重置限制器

统计:
  stats                                     显示完整统计

示例:
  oml concurrency bucket-init api 100 10 1
  oml concurrency bucket-consume api 5
  oml concurrency bucket-status api
  oml concurrency concurrency-init 20 50
  oml concurrency concurrency-acquire 30 task-123
  oml concurrency concurrency-release
  oml concurrency stats
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml concurrency help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
