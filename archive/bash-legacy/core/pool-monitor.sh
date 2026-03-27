#!/usr/bin/env bash
# DEPRECATED: Migrated to TypeScript (packages/core/src/pool/manager.ts)
# Archive Date: 2026-03-26
# Use: @oml/core PoolManager instead

# OML Pool Resource Monitor
# 资源监控模块 - 实时监控系统资源与 Worker 健康状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防止重复 source
if [[ -n "${__OML_POOL_MONITOR_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__OML_POOL_MONITOR_LOADED=true

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

# ============================================================================
# 配置与常量
# ============================================================================

readonly OML_MONITOR_VERSION="0.1.0"
readonly OML_MONITOR_DIR="${OML_MONITOR_DIR:-$(oml_config_dir 2>/dev/null || echo "${HOME}/.oml")/monitor}"
readonly OML_MONITOR_STATE_FILE="${OML_MONITOR_DIR}/state.json"
readonly OML_MONITOR_HISTORY_DIR="${OML_MONITOR_DIR}/history"
readonly OML_MONITOR_LOGS_DIR="${OML_MONITOR_DIR}/logs"
readonly OML_MONITOR_ALERTS_FILE="${OML_MONITOR_DIR}/alerts.json"

# 监控阈值默认值
readonly THRESHOLD_CPU_WARNING=70       # CPU 警告阈值 (%)
readonly THRESHOLD_CPU_CRITICAL=90      # CPU 严重阈值 (%)
readonly THRESHOLD_MEM_WARNING=70       # 内存警告阈值 (%)
readonly THRESHOLD_MEM_CRITICAL=90      # 内存严重阈值 (%)
readonly THRESHOLD_DISK_WARNING=80      # 磁盘警告阈值 (%)
readonly THRESHOLD_DISK_CRITICAL=95     # 磁盘严重阈值 (%)
readonly THRESHOLD_WORKER_TIMEOUT=300   # Worker 超时 (秒)

# 采样间隔
readonly SAMPLE_INTERVAL=5              # 采样间隔 (秒)
readonly HISTORY_RETENTION=3600         # 历史数据保留 (秒)

# ============================================================================
# 工具函数
# ============================================================================

# 获取当前时间戳（秒）
oml_monitor_timestamp() {
    date +%s
}

# 获取 ISO 时间戳
oml_monitor_iso_timestamp() {
    python3 -c "from datetime import datetime; print(datetime.utcnow().isoformat() + 'Z')"
}

# 日志输出
oml_monitor_log() {
    local level="$1"
    local message="$2"
    local component="${3:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_entry="[${timestamp}] [${level}]"
    [[ -n "$component" ]] && log_entry+=" [${component}]"
    log_entry+=" ${message}"

    echo "$log_entry" >&2

    local log_file="${OML_MONITOR_LOGS_DIR}/monitor.log"
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file" 2>/dev/null || true
}

# 生成告警 ID
oml_monitor_generate_alert_id() {
    echo "alert-$(date +%s)-${RANDOM}"
}

# JSON 读取
oml_monitor_json_read() {
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
# 系统资源监控
# ============================================================================

# 获取 CPU 使用率
oml_monitor_cpu() {
    python3 <<'PY'
import os
import time

def get_cpu_usage():
    """获取 CPU 使用率"""
    try:
        # 读取 /proc/stat
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        parts = line.split()
        user = int(parts[1])
        nice = int(parts[2])
        system = int(parts[3])
        idle = int(parts[4])
        iowait = int(parts[5]) if len(parts) > 5 else 0
        
        total1 = user + nice + system + idle + iowait
        idle1 = idle + iowait
        
        time.sleep(0.1)
        
        with open('/proc/stat', 'r') as f:
            line = f.readline()
        parts = line.split()
        user = int(parts[1])
        nice = int(parts[2])
        system = int(parts[3])
        idle = int(parts[4])
        iowait = int(parts[5]) if len(parts) > 5 else 0
        
        total2 = user + nice + system + idle + iowait
        idle2 = idle + iowait
        
        total_diff = total2 - total1
        idle_diff = idle2 - idle1
        
        if total_diff > 0:
            usage = (1 - idle_diff / total_diff) * 100
        else:
            usage = 0
        
        return round(usage, 2)
    except:
        # 回退方法：使用 top 或 ps
        try:
            import subprocess
            result = subprocess.run(['top', '-bn1'], capture_output=True, text=True, timeout=5)
            for line in result.stdout.split('\n'):
                if 'Cpu(s)' in line or '%Cpu' in line:
                    parts = line.split()
                    for i, p in enumerate(parts):
                        if p == 'id,':
                            idle = float(parts[i-1])
                            return round(100 - idle, 2)
        except:
            pass
        return 0.0

print(get_cpu_usage())
PY
}

# 获取内存使用情况
oml_monitor_memory() {
    python3 <<'PY'
import os

def get_memory_info():
    """获取内存信息"""
    try:
        with open('/proc/meminfo', 'r') as f:
            lines = f.readlines()
        
        mem_info = {}
        for line in lines:
            parts = line.split()
            key = parts[0].rstrip(':')
            value = int(parts[1])  # KB
            mem_info[key] = value
        
        total = mem_info.get('MemTotal', 0)
        available = mem_info.get('MemAvailable', mem_info.get('MemFree', 0))
        used = total - available
        
        if total > 0:
            usage_percent = (used / total) * 100
        else:
            usage_percent = 0
        
        return {
            'total_kb': total,
            'used_kb': used,
            'available_kb': available,
            'usage_percent': round(usage_percent, 2)
        }
    except Exception as e:
        return {
            'total_kb': 0,
            'used_kb': 0,
            'available_kb': 0,
            'usage_percent': 0,
            'error': str(e)
        }

import json
print(json.dumps(get_memory_info()))
PY
}

# 获取磁盘使用情况
oml_monitor_disk() {
    local path="${1:-/}"

    python3 - "$path" <<'PY'
import os
import json

def get_disk_info(path):
    """获取磁盘信息"""
    try:
        stat = os.statvfs(path)
        
        total = stat.f_blocks * stat.f_frsize
        free = stat.f_bfree * stat.f_frsize
        available = stat.f_bavail * stat.f_frsize
        used = total - free
        
        if total > 0:
            usage_percent = (used / total) * 100
        else:
            usage_percent = 0
        
        return {
            'path': path,
            'total_bytes': total,
            'used_bytes': used,
            'free_bytes': free,
            'available_bytes': available,
            'usage_percent': round(usage_percent, 2)
        }
    except Exception as e:
        return {
            'path': path,
            'total_bytes': 0,
            'used_bytes': 0,
            'free_bytes': 0,
            'available_bytes': 0,
            'usage_percent': 0,
            'error': str(e)
        }

print(json.dumps(get_disk_info('${path}')))
PY
}

# 获取进程信息
oml_monitor_process() {
    local pid="${1:-}"

    if [[ -z "$pid" ]]; then
        echo "PID required"
        return 1
    fi

    python3 - "$pid" <<'PY'
import os
import json

def get_process_info(pid):
    """获取进程信息"""
    try:
        pid = int(pid)
        proc_dir = f'/proc/{pid}'
        
        if not os.path.exists(proc_dir):
            return {'error': 'Process not found'}
        
        # 读取 cmdline
        try:
            with open(f'{proc_dir}/cmdline', 'r') as f:
                cmdline = f.read().replace('\x00', ' ').strip()
        except:
            cmdline = ''
        
        # 读取 stat
        try:
            with open(f'{proc_dir}/stat', 'r') as f:
                stat_parts = f.read().split()
                state = stat_parts[2] if len(stat_parts) > 2 else '?'
                utime = int(stat_parts[13]) if len(stat_parts) > 13 else 0
                stime = int(stat_parts[14]) if len(stat_parts) > 14 else 0
                num_threads = int(stat_parts[19]) if len(stat_parts) > 19 else 1
        except:
            state = '?'
            utime = 0
            stime = 0
            num_threads = 1
        
        # 读取 statm (内存)
        try:
            with open(f'{proc_dir}/statm', 'r') as f:
                statm_parts = f.read().split()
                vms = int(statm_parts[0]) * 4096 if len(statm_parts) > 0 else 0
                rss = int(statm_parts[1]) * 4096 if len(statm_parts) > 1 else 0
        except:
            vms = 0
            rss = 0
        
        return {
            'pid': pid,
            'cmdline': cmdline,
            'state': state,
            'utime': utime,
            'stime': stime,
            'num_threads': num_threads,
            'vms_bytes': vms,
            'rss_bytes': rss
        }
    except Exception as e:
        return {'error': str(e)}

import sys
print(json.dumps(get_process_info(sys.argv[1])))
PY
}

# 获取网络统计
oml_monitor_network() {
    python3 <<'PY'
import os
import json

def get_network_stats():
    """获取网络统计"""
    try:
        with open('/proc/net/dev', 'r') as f:
            lines = f.readlines()
        
        interfaces = {}
        for line in lines[2:]:  # 跳过表头
            parts = line.strip().split(':')
            if len(parts) != 2:
                continue
            
            iface = parts[0].strip()
            stats = parts[1].split()
            
            interfaces[iface] = {
                'rx_bytes': int(stats[0]) if len(stats) > 0 else 0,
                'rx_packets': int(stats[1]) if len(stats) > 1 else 0,
                'tx_bytes': int(stats[8]) if len(stats) > 8 else 0,
                'tx_packets': int(stats[9]) if len(stats) > 9 else 0
            }
        
        return interfaces
    except Exception as e:
        return {'error': str(e)}

print(json.dumps(get_network_stats()))
PY
}

# ============================================================================
# 监控初始化
# ============================================================================

# 初始化监控系统
oml_monitor_init() {
    local cpu_warning="${1:-$THRESHOLD_CPU_WARNING}"
    local cpu_critical="${2:-$THRESHOLD_CPU_CRITICAL}"
    local mem_warning="${3:-$THRESHOLD_MEM_WARNING}"
    local mem_critical="${4:-$THRESHOLD_MEM_CRITICAL}"

    mkdir -p "${OML_MONITOR_DIR}"
    mkdir -p "${OML_MONITOR_HISTORY_DIR}"
    mkdir -p "${OML_MONITOR_LOGS_DIR}"

    local timestamp
    timestamp="$(oml_monitor_iso_timestamp)"

    # 初始化状态文件
    cat > "${OML_MONITOR_STATE_FILE}" <<EOF
{
  "version": "${OML_MONITOR_VERSION}",
  "created_at": "${timestamp}",
  "updated_at": "${timestamp}",
  "thresholds": {
    "cpu_warning": ${cpu_warning},
    "cpu_critical": ${cpu_critical},
    "mem_warning": ${mem_warning},
    "mem_critical": ${mem_critical},
    "disk_warning": ${THRESHOLD_DISK_WARNING},
    "disk_critical": ${THRESHOLD_DISK_CRITICAL},
    "worker_timeout": ${THRESHOLD_WORKER_TIMEOUT}
  },
  "current": {
    "cpu_usage": 0,
    "memory_usage": 0,
    "disk_usage": 0,
    "active_workers": 0,
    "sample_time": 0
  },
  "workers": {},
  "alerts": [],
  "stats": {
    "total_samples": 0,
    "total_alerts": 0,
    "alerts_resolved": 0
  }
}
EOF

    # 初始化告警文件
    cat > "${OML_MONITOR_ALERTS_FILE}" <<EOF
{
  "active_alerts": [],
  "alert_history": []
}
EOF

    oml_monitor_log "INFO" "Monitor initialized"
    echo "Monitor initialized at: ${OML_MONITOR_DIR}"
}

# 确保监控已初始化
oml_monitor_ensure_init() {
    if [[ ! -f "${OML_MONITOR_STATE_FILE}" ]]; then
        oml_monitor_init
    fi
}

# ============================================================================
# 采样与记录
# ============================================================================

# 采集系统资源样本
oml_monitor_sample() {
    oml_monitor_ensure_init

    local timestamp
    timestamp="$(oml_monitor_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_monitor_iso_timestamp)"

    # 采集各项指标
    local cpu_usage
    cpu_usage=$(oml_monitor_cpu)

    local mem_info
    mem_info=$(oml_monitor_memory)
    local mem_usage
    mem_usage=$(echo "$mem_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('usage_percent', 0))")

    local disk_info
    disk_info=$(oml_monitor_disk "/")
    local disk_usage
    disk_usage=$(echo "$disk_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('usage_percent', 0))")

    # 获取 Worker 数量
    local active_workers=0
    if [[ -f "${OML_POOL_DIR:-}/state.json" ]]; then
        active_workers=$(python3 -c "
import json
try:
    with open('${OML_POOL_DIR}/state.json', 'r') as f:
        state = json.load(f)
    active_workers = sum(1 for w in state.get('workers', {}).values() if w.get('status') == 'busy')
except:
    pass
print(active_workers)
" 2>/dev/null || echo "0")
    fi

    # 更新状态文件
    python3 - "${OML_MONITOR_STATE_FILE}" "$cpu_usage" "$mem_usage" "$disk_usage" "$active_workers" "$timestamp" "$iso_timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
cpu_usage = float(sys.argv[2])
mem_usage = float(sys.argv[3])
disk_usage = float(sys.argv[4])
active_workers = int(sys.argv[5])
timestamp = int(sys.argv[6])
iso_timestamp = sys.argv[7]

with open(state_file, 'r') as f:
    state = json.load(f)

state['current'] = {
    'cpu_usage': cpu_usage,
    'memory_usage': mem_usage,
    'disk_usage': disk_usage,
    'active_workers': active_workers,
    'sample_time': timestamp
}
state['updated_at'] = iso_timestamp
state['stats']['total_samples'] += 1

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
PY

    # 保存到历史记录
    local history_file="${OML_MONITOR_HISTORY_DIR}/$(date +%Y%m%d).json"
    python3 - "$history_file" "$timestamp" "$cpu_usage" "$mem_usage" "$disk_usage" "$active_workers" <<'PY'
import json
import sys
import os

history_file = sys.argv[1]
timestamp = int(sys.argv[2])
cpu_usage = float(sys.argv[3])
mem_usage = float(sys.argv[4])
disk_usage = float(sys.argv[5])
active_workers = int(sys.argv[6])

# 读取或创建历史文件
if os.path.exists(history_file):
    with open(history_file, 'r') as f:
        history = json.load(f)
else:
    history = {'samples': []}

# 添加样本
history['samples'].append({
    'timestamp': timestamp,
    'cpu_usage': cpu_usage,
    'memory_usage': mem_usage,
    'disk_usage': disk_usage,
    'active_workers': active_workers
})

# 限制历史记录大小（保留最近 1000 条）
if len(history['samples']) > 1000:
    history['samples'] = history['samples'][-1000:]

with open(history_file, 'w') as f:
    json.dump(history, f, indent=2)
PY

    echo "{\"cpu\":${cpu_usage},\"memory\":${mem_usage},\"disk\":${disk_usage},\"workers\":${active_workers},\"timestamp\":${timestamp}}"
}

# 连续采样
oml_monitor_watch() {
    local interval="${1:-$SAMPLE_INTERVAL}"
    local count="${2:-0}"  # 0 表示无限

    oml_monitor_ensure_init

    oml_monitor_log "INFO" "Starting watch (interval=${interval}s, count=${count})"

    local iterations=0
    while [[ $count -eq 0 ]] || [[ $iterations -lt $count ]]; do
        local sample
        sample=$(oml_monitor_sample)
        echo "$sample"

        ((iterations++))
        sleep "$interval"
    done
}

# ============================================================================
# 告警管理
# ============================================================================

# 检查阈值并生成告警
oml_monitor_check_thresholds() {
    oml_monitor_ensure_init

    local timestamp
    timestamp="$(oml_monitor_timestamp)"
    local iso_timestamp
    iso_timestamp="$(oml_monitor_iso_timestamp)"

    python3 - "${OML_MONITOR_STATE_FILE}" "${OML_MONITOR_ALERTS_FILE}" "$timestamp" "$iso_timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
alerts_file = sys.argv[2]
timestamp = int(sys.argv[3])
iso_timestamp = sys.argv[4]

with open(state_file, 'r') as f:
    state = json.load(f)

with open(alerts_file, 'r') as f:
    alerts_data = json.load(f)

thresholds = state['thresholds']
current = state['current']
new_alerts = []

def create_alert(type, level, value, threshold):
    return {
        'alert_id': f"alert-{timestamp}-{__import__('random').randint(1000, 9999)}",
        'type': type,
        'level': level,
        'value': value,
        'threshold': threshold,
        'created_at': iso_timestamp,
        'resolved_at': None,
        'status': 'active'
    }

# 检查 CPU
cpu = current.get('cpu_usage', 0)
if cpu >= thresholds['cpu_critical']:
    new_alerts.append(create_alert('cpu', 'critical', cpu, thresholds['cpu_critical']))
elif cpu >= thresholds['cpu_warning']:
    new_alerts.append(create_alert('cpu', 'warning', cpu, thresholds['cpu_warning']))

# 检查内存
mem = current.get('memory_usage', 0)
if mem >= thresholds['mem_critical']:
    new_alerts.append(create_alert('memory', 'critical', mem, thresholds['mem_critical']))
elif mem >= thresholds['mem_warning']:
    new_alerts.append(create_alert('memory', 'warning', mem, thresholds['mem_warning']))

# 检查磁盘
disk = current.get('disk_usage', 0)
if disk >= thresholds['disk_critical']:
    new_alerts.append(create_alert('disk', 'critical', disk, thresholds['disk_critical']))
elif disk >= thresholds['disk_warning']:
    new_alerts.append(create_alert('disk', 'warning', disk, thresholds['disk_warning']))

# 添加新告警
for alert in new_alerts:
    alerts_data['active_alerts'].append(alert)
    alerts_data['alert_history'].append(alert)
    state['stats']['total_alerts'] += 1

# 检查已解决的告警
resolved = []
for alert in alerts_data['active_alerts'][:]:
    if alert['type'] == 'cpu' and cpu < thresholds['cpu_warning']:
        alert['resolved_at'] = iso_timestamp
        alert['status'] = 'resolved'
        resolved.append(alert)
    elif alert['type'] == 'memory' and mem < thresholds['mem_warning']:
        alert['resolved_at'] = iso_timestamp
        alert['status'] = 'resolved'
        resolved.append(alert)
    elif alert['type'] == 'disk' and disk < thresholds['disk_warning']:
        alert['resolved_at'] = iso_timestamp
        alert['status'] = 'resolved'
        resolved.append(alert)

for alert in resolved:
    alerts_data['active_alerts'].remove(alert)
    state['stats']['alerts_resolved'] += 1

# 保存
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

with open(alerts_file, 'w') as f:
    json.dump(alerts_data, f, indent=2)

# 输出结果
if new_alerts:
    for alert in new_alerts:
        print(f"ALERT:{alert['type']}:{alert['level']}:{alert['value']}")
if resolved:
    for alert in resolved:
        print(f"RESOLVED:{alert['type']}")
if not new_alerts and not resolved:
    print("OK")
PY
}

# 获取活动告警
oml_monitor_get_alerts() {
    oml_monitor_ensure_init

    if [[ -f "${OML_MONITOR_ALERTS_FILE}" ]]; then
        python3 - "${OML_MONITOR_ALERTS_FILE}" <<'PY'
import json
import sys

alerts_file = sys.argv[1]

with open(alerts_file, 'r') as f:
    data = json.load(f)

print(json.dumps({'active_alerts': data['active_alerts'], 'count': len(data['active_alerts'])}, indent=2))
PY
    else
        echo '{"active_alerts": [], "count": 0}'
    fi
}

# 清除告警
oml_monitor_clear_alerts() {
    oml_monitor_ensure_init

    if [[ -f "${OML_MONITOR_ALERTS_FILE}" ]]; then
        python3 - "${OML_MONITOR_ALERTS_FILE}" <<'PY'
import json
import sys
from datetime import datetime

alerts_file = sys.argv[1]

with open(alerts_file, 'r') as f:
    data = json.load(f)

iso_timestamp = datetime.utcnow().isoformat() + 'Z'

# 将所有活动告警标记为已解决
for alert in data['active_alerts']:
    alert['resolved_at'] = iso_timestamp
    alert['status'] = 'resolved'
    data['alert_history'].append(alert)

cleared = len(data['active_alerts'])
data['active_alerts'] = []

with open(alerts_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Cleared {cleared} alert(s)")
PY
    fi
}

# ============================================================================
# Worker 健康监控
# ============================================================================

# 注册 Worker 进行监控
oml_monitor_register_worker() {
    local worker_id="$1"
    local pid="${2:-0}"

    oml_monitor_ensure_init

    local iso_timestamp
    iso_timestamp="$(oml_monitor_iso_timestamp)"

    python3 - "${OML_MONITOR_STATE_FILE}" "$worker_id" "$pid" "$iso_timestamp" <<'PY'
import json
import sys

state_file = sys.argv[1]
worker_id = sys.argv[2]
pid = int(sys.argv[3]) if sys.argv[3] else 0
iso_timestamp = sys.argv[4]

with open(state_file, 'r') as f:
    state = json.load(f)

state['workers'][worker_id] = {
    'worker_id': worker_id,
    'pid': pid,
    'registered_at': iso_timestamp,
    'last_check': iso_timestamp,
    'status': 'healthy',
    'cpu_samples': [],
    'memory_samples': [],
    'health_checks': 0,
    'failures': 0
}

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(f"Worker registered: {worker_id}")
PY

    oml_monitor_log "INFO" "Worker registered: ${worker_id}"
}

# 检查 Worker 健康状态
oml_monitor_check_worker() {
    local worker_id="$1"

    oml_monitor_ensure_init

    local iso_timestamp
    iso_timestamp="$(oml_monitor_iso_timestamp)"
    local timestamp
    timestamp="$(oml_monitor_timestamp)"

    python3 - "${OML_MONITOR_STATE_FILE}" "$worker_id" "$iso_timestamp" "$timestamp" <<'PY'
import json
import sys
import os

state_file = sys.argv[1]
worker_id = sys.argv[2]
iso_timestamp = sys.argv[3]
timestamp = int(sys.argv[4])

with open(state_file, 'r') as f:
    state = json.load(f)

worker = state['workers'].get(worker_id)
if not worker:
    print("error:worker_not_found")
    sys.exit(1)

pid = worker.get('pid', 0)
status = 'healthy'

if pid > 0:
    # 检查进程是否存在
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        status = 'dead'
    except PermissionError:
        status = 'unknown'
else:
    status = 'no_pid'

# 更新 Worker 状态
worker['last_check'] = iso_timestamp
worker['status'] = status
worker['health_checks'] += 1

if status != 'healthy':
    worker['failures'] += 1

state['updated_at'] = iso_timestamp

with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)

print(status)
PY
}

# 获取 Worker 健康状态
oml_monitor_worker_status() {
    local worker_id="${1:-}"

    oml_monitor_ensure_init

    if [[ -n "$worker_id" ]]; then
        python3 - "${OML_MONITOR_STATE_FILE}" "$worker_id" <<'PY'
import json
import sys

state_file = sys.argv[1]
worker_id = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

worker = state['workers'].get(worker_id)
if not worker:
    print("Worker not found", file=sys.stderr)
    sys.exit(1)

print(json.dumps(worker, indent=2))
PY
    else
        python3 - "${OML_MONITOR_STATE_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]

with open(state_file, 'r') as f:
    state = json.load(f)

workers = state.get('workers', {})

print(f"{'WORKER_ID':<36} {'PID':<10} {'STATUS':<12} {'CHECKS':<10} {'FAILURES'}")
print("=" * 80)

for worker_id, worker in workers.items():
    pid = worker.get('pid', 0)
    status = worker.get('status', 'unknown')
    checks = worker.get('health_checks', 0)
    failures = worker.get('failures', 0)
    print(f"{worker_id:<36} {pid:<10} {status:<12} {checks:<10} {failures}")
PY
    fi
}

# 取消注册 Worker
oml_monitor_unregister_worker() {
    local worker_id="$1"

    oml_monitor_ensure_init

    python3 - "${OML_MONITOR_STATE_FILE}" "$worker_id" <<'PY'
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

    print(f"Worker unregistered: {worker_id}")
else:
    print("Worker not found", file=sys.stderr)
    sys.exit(1)
PY
}

# ============================================================================
# 报告与统计
# ============================================================================

# 获取监控状态
oml_monitor_status() {
    oml_monitor_ensure_init

    # 先采样
    oml_monitor_sample >/dev/null

    python3 - "${OML_MONITOR_STATE_FILE}" "${OML_MONITOR_ALERTS_FILE}" <<'PY'
import json
import sys

state_file = sys.argv[1]
alerts_file = sys.argv[2]

with open(state_file, 'r') as f:
    state = json.load(f)

with open(alerts_file, 'r') as f:
    alerts = json.load(f)

current = state['current']
thresholds = state['thresholds']
stats = state['stats']

print("=== Resource Monitor Status ===")
print(f"Version: {state['version']}")
print(f"Updated: {state['updated_at']}")
print()
print("Current Resource Usage:")

# CPU
cpu = current.get('cpu_usage', 0)
cpu_level = "OK"
if cpu >= thresholds['cpu_critical']:
    cpu_level = "CRITICAL"
elif cpu >= thresholds['cpu_warning']:
    cpu_level = "WARNING"
print(f"  CPU: {cpu}% [{cpu_level}]")

# 内存
mem = current.get('memory_usage', 0)
mem_level = "OK"
if mem >= thresholds['mem_critical']:
    mem_level = "CRITICAL"
elif mem >= thresholds['mem_warning']:
    mem_level = "WARNING"
print(f"  Memory: {mem}% [{mem_level}]")

# 磁盘
disk = current.get('disk_usage', 0)
disk_level = "OK"
if disk >= thresholds['disk_critical']:
    disk_level = "CRITICAL"
elif disk >= thresholds['disk_warning']:
    disk_level = "WARNING"
print(f"  Disk: {disk}% [{disk_level}]")

print()
print(f"Active Workers: {current.get('active_workers', 0)}")
print(f"Monitored Workers: {len(state.get('workers', {}))}")
print()
print("Active Alerts:", len(alerts['active_alerts']))
for alert in alerts['active_alerts']:
    print(f"  - [{alert['level'].upper()}] {alert['type']}: {alert['value']}% (threshold: {alert['threshold']}%)")

print()
print("Statistics:")
print(f"  Total Samples: {stats['total_samples']}")
print(f"  Total Alerts: {stats['total_alerts']}")
print(f"  Alerts Resolved: {stats['alerts_resolved']}")
PY
}

# 获取监控状态（JSON）
oml_monitor_status_json() {
    oml_monitor_ensure_init
    oml_monitor_sample >/dev/null

    if [[ -f "${OML_MONITOR_STATE_FILE}" ]]; then
        cat "${OML_MONITOR_STATE_FILE}"
    else
        echo "{}"
    fi
}

# 获取历史数据
oml_monitor_history() {
    local date="${1:-$(date +%Y%m%d)}"
    local limit="${2:-100}"

    local history_file="${OML_MONITOR_HISTORY_DIR}/${date}.json"

    if [[ ! -f "$history_file" ]]; then
        echo "No history for date: $date"
        return 1
    fi

    python3 - "$history_file" "$limit" <<'PY'
import json
import sys

history_file = sys.argv[1]
limit = int(sys.argv[2])

with open(history_file, 'r') as f:
    history = json.load(f)

samples = history.get('samples', [])[-limit:]

print(json.dumps({'date': '${date}', 'samples': samples, 'count': len(samples)}, indent=2))
PY
}

# 生成报告
oml_monitor_report() {
    local period="${1:-hour}"  # hour, day, week

    oml_monitor_ensure_init

    python3 - "${OML_MONITOR_HISTORY_DIR}" "$period" <<'PY'
import json
import sys
import os
from datetime import datetime, timedelta

history_dir = sys.argv[1]
period = sys.argv[2]

# 确定时间范围
now = datetime.utcnow()
if period == 'hour':
    cutoff = now - timedelta(hours=1)
elif period == 'day':
    cutoff = now - timedelta(days=1)
elif period == 'week':
    cutoff = now - timedelta(weeks=1)
else:
    cutoff = now - timedelta(days=1)

# 收集样本
all_samples = []
today = now.strftime('%Y%m%d')
yesterday = (now - timedelta(days=1)).strftime('%Y%m%d')

for date_file in [today, yesterday]:
    history_file = os.path.join(history_dir, f"{date_file}.json")
    if os.path.exists(history_file):
        with open(history_file, 'r') as f:
            history = json.load(f)
        for sample in history.get('samples', []):
            if sample['timestamp'] >= cutoff.timestamp():
                all_samples.append(sample)

if not all_samples:
    print("No data available for the specified period")
    sys.exit(0)

# 计算统计
cpu_values = [s['cpu_usage'] for s in all_samples]
mem_values = [s['memory_usage'] for s in all_samples]
disk_values = [s['disk_usage'] for s in all_samples]
worker_values = [s['active_workers'] for s in all_samples]

def calc_stats(values):
    if not values:
        return {'min': 0, 'max': 0, 'avg': 0}
    return {
        'min': round(min(values), 2),
        'max': round(max(values), 2),
        'avg': round(sum(values) / len(values), 2)
    }

report = {
    'period': period,
    'from': datetime.fromtimestamp(all_samples[0]['timestamp']).isoformat() + 'Z',
    'to': datetime.fromtimestamp(all_samples[-1]['timestamp']).isoformat() + 'Z',
    'sample_count': len(all_samples),
    'cpu': calc_stats(cpu_values),
    'memory': calc_stats(mem_values),
    'disk': calc_stats(disk_values),
    'workers': calc_stats(worker_values)
}

print("=== Resource Monitor Report ===")
print(f"Period: {period}")
print(f"From: {report['from']}")
print(f"To: {report['to']}")
print(f"Samples: {report['sample_count']}")
print()
print("CPU Usage:")
print(f"  Min: {report['cpu']['min']}%")
print(f"  Max: {report['cpu']['max']}%")
print(f"  Avg: {report['cpu']['avg']}%")
print()
print("Memory Usage:")
print(f"  Min: {report['memory']['min']}%")
print(f"  Max: {report['memory']['max']}%")
print(f"  Avg: {report['memory']['avg']}%")
print()
print("Disk Usage:")
print(f"  Min: {report['disk']['min']}%")
print(f"  Max: {report['disk']['max']}%")
print(f"  Avg: {report['disk']['avg']}%")
print()
print("Active Workers:")
print(f"  Min: {report['workers']['min']}")
print(f"  Max: {report['workers']['max']}")
print(f"  Avg: {report['workers']['avg']}")
PY
}

# ============================================================================
# 清理与维护
# ============================================================================

# 清理历史数据
oml_monitor_cleanup_history() {
    local max_age_days="${1:-7}"

    oml_monitor_ensure_init

    local cutoff
    cutoff=$(date -d "$max_age_days days ago" +%Y%m%d 2>/dev/null || date +%Y%m%d)

    local cleaned=0
    for history_file in "${OML_MONITOR_HISTORY_DIR}"/*.json; do
        [[ -f "$history_file" ]] || continue

        local file_date
        file_date=$(basename "$history_file" .json)

        if [[ "$file_date" < "$cutoff" ]]; then
            rm -f "$history_file"
            ((cleaned++))
        fi
    done

    oml_monitor_log "INFO" "Cleaned up ${cleaned} history file(s)"
    echo "Cleaned up ${cleaned} history file(s)"
}

# 重置监控
oml_monitor_reset() {
    local force="${1:-false}"

    if [[ "$force" != "true" ]]; then
        echo "Warning: This will clear all monitoring data."
        echo "Use --force to confirm."
        return 1
    fi

    oml_monitor_init

    # 清理历史
    rm -f "${OML_MONITOR_HISTORY_DIR}"/*.json

    oml_monitor_log "WARN" "Monitor reset completed"
    echo "Monitor reset completed"
}

# ============================================================================
# CLI 入口
# ============================================================================

main() {
    local action="${1:-help}"
    shift || true

    case "$action" in
        init)
            oml_monitor_init "$@"
            ;;
        sample)
            oml_monitor_sample
            ;;
        watch)
            oml_monitor_watch "$@"
            ;;
        check)
            oml_monitor_check_thresholds
            ;;
        status)
            oml_monitor_status
            ;;
        status-json)
            oml_monitor_status_json
            ;;
        alerts)
            oml_monitor_get_alerts
            ;;
        alerts-clear)
            oml_monitor_clear_alerts
            ;;
        register-worker)
            oml_monitor_register_worker "$@"
            ;;
        check-worker)
            oml_monitor_check_worker "$@"
            ;;
        worker-status)
            oml_monitor_worker_status "$@"
            ;;
        unregister-worker)
            oml_monitor_unregister_worker "$@"
            ;;
        history)
            oml_monitor_history "$@"
            ;;
        report)
            oml_monitor_report "$@"
            ;;
        cleanup)
            oml_monitor_cleanup_history "$@"
            ;;
        reset)
            oml_monitor_reset "$@"
            ;;
        # 底层资源查询
        cpu)
            oml_monitor_cpu
            ;;
        memory)
            oml_monitor_memory
            ;;
        disk)
            oml_monitor_disk "$@"
            ;;
        process)
            oml_monitor_process "$@"
            ;;
        network)
            oml_monitor_network
            ;;
        help|--help|-h)
            cat <<EOF
OML Pool Resource Monitor v${OML_MONITOR_VERSION}

用法：oml monitor <action> [args]

初始化:
  init [cpu_warn] [cpu_crit] [mem_warn] [mem_crit]  初始化监控系统

采样与监控:
  sample                采集一次样本
  watch [interval] [count]  连续采样
  check                 检查阈值并生成告警

状态查询:
  status                显示监控状态
  status-json           显示监控状态 (JSON)
  alerts                获取活动告警
  alerts-clear          清除所有告警
  history [date] [limit]  查看历史数据
  report [period]       生成报告 (hour|day|week)

Worker 健康监控:
  register-worker <id> [pid]  注册 Worker
  check-worker <id>           检查 Worker 健康
  worker-status [id]          查看 Worker 状态
  unregister-worker <id>      取消注册

底层资源查询:
  cpu                 获取 CPU 使用率
  memory              获取内存使用情况
  disk [path]         获取磁盘使用情况
  process <pid>       获取进程信息
  network             获取网络统计

维护:
  cleanup [days]      清理历史数据
  reset [--force]     重置监控

阈值默认值:
  CPU: 警告 70%, 严重 90%
  内存：警告 70%, 严重 90%
  磁盘：警告 80%, 严重 95%

示例:
  oml monitor init
  oml monitor sample
  oml monitor watch 5
  oml monitor check
  oml monitor status
  oml monitor register-worker worker-123 12345
  oml monitor report hour
EOF
            ;;
        *)
            echo "Unknown action: $action"
            echo "Use 'oml monitor help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main（非 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
