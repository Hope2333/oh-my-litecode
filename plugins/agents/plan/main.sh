#!/usr/bin/env bash
# Plan Agent Plugin for OML
# 任务规划、分解、依赖分析与进度追踪
# Enhanced with Session and Hooks integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"
PLUGIN_NAME="plan"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi
if [[ -f "${OML_CORE_DIR}/plugin-loader.sh" ]]; then
    source "${OML_CORE_DIR}/plugin-loader.sh"
fi
if [[ -f "${OML_CORE_DIR}/task-registry.sh" ]]; then
    source "${OML_CORE_DIR}/task-registry.sh"
fi

# Source OML session and hooks modules (if available)
if [[ -f "${OML_CORE_DIR}/session-manager.sh" ]]; then
    source "${OML_CORE_DIR}/session-manager.sh" 2>/dev/null || true
fi
if [[ -f "${OML_CORE_DIR}/hooks-engine.sh" ]]; then
    source "${OML_CORE_DIR}/hooks-engine.sh" 2>/dev/null || true
fi
if [[ -f "${OML_CORE_DIR}/hooks-dispatcher.sh" ]]; then
    source "${OML_CORE_DIR}/hooks-dispatcher.sh" 2>/dev/null || true
fi

# ============================================================================
# 配置与常量
# ============================================================================

# OML 根目录
OML_ROOT="${OML_ROOT:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../ && pwd)}"

# 数据目录
PLAN_DATA_DIR="${OML_PLAN_DATA_DIR:-${HOME}/.oml/plans}"
PLANS_FILE="${PLAN_DATA_DIR}/plans.json"
TEMPLATES_FILE="${PLAN_DATA_DIR}/templates.json"

# 输出格式
OUTPUT_FORMAT="${OML_OUTPUT_FORMAT:-text}"

# 任务复杂度系数
COMPLEXITY_FACTORS=(
    "simple:1.0"
    "medium:1.5"
    "complex:2.0"
    "expert:3.0"
)

# 默认工作量估算 (小时)
DEFAULT_ESTIMATES=(
    "research:2"
    "design:4"
    "implement:8"
    "test:4"
    "review:2"
    "deploy:2"
)

# ============================================================================
# Session Configuration
# ============================================================================
PLAN_SESSION_ENABLED="${PLAN_SESSION_ENABLED:-true}"
PLAN_SESSION_DIR=""
PLAN_SESSION_ID=""
PLAN_SESSION_DATA_FILE=""

# ============================================================================
# Hooks Configuration
# ============================================================================
PLAN_HOOKS_ENABLED="${PLAN_HOOKS_ENABLED:-true}"
PLAN_HOOKS_DIR="${PLUGIN_DIR}/hooks"

# Hook events
readonly HOOK_PLAN_CREATE="plan:create"
readonly HOOK_PLAN_UPDATE="plan:update"
readonly HOOK_PLAN_COMPLETE="plan:complete"
readonly HOOK_TASK_COMPLETE="plan:task:complete"
readonly HOOK_PLAN_DELETE="plan:delete"

# ============================================================================
# 工具函数
# ============================================================================

# 获取当前时间戳 (ISO 8601)
get_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ'
}

# 生成唯一 ID
generate_id() {
    local prefix="${1:-plan}"
    echo "${prefix}-$(date +%s)-$$-${RANDOM}"
}

# 输出 JSON
output_json() {
    local data="$1"
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "$data"
    fi
}

# 输出文本
output_text() {
    local msg="$1"
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        echo "$msg"
    fi
}

# 输出错误
output_error() {
    local msg="$1"
    local code="${2:-1}"
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        python3 -c "
import json, sys
data = {'error': True, 'message': sys.argv[1], 'code': int(sys.argv[2])}
print(json.dumps(data, ensure_ascii=False, indent=2))
" "$msg" "$code"
    else
        echo "ERROR: $msg" >&2
    fi
}

# 获取平台信息
get_platform_info() {
    local platform
    platform="$(oml_platform_label 2>/dev/null || echo "unknown")"
    local arch
    arch="$(oml_arch 2>/dev/null || echo "unknown")"
    echo "${platform}/${arch}"
}

# ============================================================================
# Session Management
# ============================================================================

# Initialize session system
plan_session_init() {
    if [[ "${PLAN_SESSION_ENABLED}" != "true" ]]; then
        return 0
    fi

    PLAN_SESSION_DIR="${HOME}/.oml/sessions/plan"
    mkdir -p "${PLAN_SESSION_DIR}" 2>/dev/null || true
}

# Generate session ID
plan_session_generate_id() {
    echo "plan-session-$(date +%s)-$$-${RANDOM}"
}

# Create new plan session
plan_session_create() {
    local name="${1:-unnamed}"
    local metadata="${2:-{}}"

    if [[ "${PLAN_SESSION_ENABLED}" != "true" ]]; then
        return 0
    fi

    local session_id
    session_id="$(plan_session_generate_id)"
    local timestamp
    timestamp="$(get_timestamp)"

    local session_data
    session_data=$(python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'type': 'plan',
    'created_at': '${timestamp}',
    'updated_at': '${timestamp}',
    'status': 'active',
    'metadata': ${metadata},
    'plans': [],
    'context': {}
}, indent=2))
")

    local session_file="${PLAN_SESSION_DIR}/${session_id}.json"
    echo "$session_data" > "$session_file"
    chmod 600 "$session_file" 2>/dev/null || true

    PLAN_SESSION_ID="$session_id"
    PLAN_SESSION_DATA_FILE="$session_file"

    # Trigger hook
    plan_hooks_trigger "$HOOK_PLAN_CREATE" "session_create" "$session_id" 2>/dev/null || true

    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'status': 'active',
    'created_at': '${timestamp}'
}, indent=2))
"
    else
        echo "Created plan session: ${session_id}"
    fi

    echo "$session_id"
}

# Get current session
plan_session_current() {
    if [[ -z "${PLAN_SESSION_ID:-}" ]]; then
        echo "No active plan session" >&2
        return 1
    fi

    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        cat "${PLAN_SESSION_DATA_FILE}" 2>/dev/null || echo '{"error": "Session file not found"}'
    else
        echo "Current plan session: ${PLAN_SESSION_ID}"
    fi
}

# Add plan record to session
plan_session_add_plan() {
    local plan_id="$1"
    local title="$2"
    local status="$3"

    if [[ "${PLAN_SESSION_ENABLED}" != "true" ]] || [[ -z "${PLAN_SESSION_ID:-}" ]]; then
        return 0
    fi

    local timestamp
    timestamp="$(get_timestamp)"

    python3 - "${PLAN_SESSION_DATA_FILE}" "${plan_id}" "${title}" "${status}" "${timestamp}" <<'PY'
import json
import sys

session_file = sys.argv[1]
plan_id = sys.argv[2]
title = sys.argv[3]
status = sys.argv[4]
timestamp = sys.argv[5]

with open(session_file, 'r') as f:
    data = json.load(f)

plan_record = {
    'plan_id': plan_id,
    'title': title,
    'status': status,
    'timestamp': timestamp
}

if 'plans' not in data:
    data['plans'] = []

data['plans'].append(plan_record)
data['updated_at'] = timestamp

with open(session_file, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
}

# ============================================================================
# Hooks Management
# ============================================================================

# Initialize hooks system
plan_hooks_init() {
    if [[ "${PLAN_HOOKS_ENABLED}" != "true" ]]; then
        return 0
    fi

    mkdir -p "${PLAN_HOOKS_DIR}" 2>/dev/null || true

    # Register built-in hooks if they exist
    for hook_script in "${PLAN_HOOKS_DIR}"/*.sh; do
        if [[ -x "$hook_script" ]]; then
            local hook_name
            hook_name="$(basename "$hook_script" .sh)"
            # Hooks are auto-discovered and executed by trigger
        fi
    done
}

# Trigger hooks for an event
plan_hooks_trigger() {
    local event="$1"
    shift
    local payload=("$@")

    if [[ "${PLAN_HOOKS_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Check if hooks directory exists
    if [[ ! -d "${PLAN_HOOKS_DIR}" ]]; then
        return 0
    fi

    # Find and execute matching hook scripts
    for hook_script in "${PLAN_HOOKS_DIR}"/*.sh; do
        if [[ ! -x "$hook_script" ]]; then
            continue
        fi

        # Check if hook script handles this event
        local handles_event
        handles_event=$("$hook_script" --check-event "$event" 2>/dev/null || echo "false")

        if [[ "$handles_event" == "true" ]]; then
            "$hook_script" "$event" "${payload[@]}" || true
        fi
    done

    # Also try to use OML hooks dispatcher if available
    if type -t oml_hooks_dispatch >/dev/null 2>&1; then
        oml_hooks_dispatch "$event" "${payload[@]}" --timeout 10 2>/dev/null || true
    fi
}

# Check if hook is enabled
plan_hooks_is_enabled() {
    [[ "${PLAN_HOOKS_ENABLED}" == "true" ]]
}

# Enable hooks
plan_hooks_enable() {
    export PLAN_HOOKS_ENABLED="true"
    echo "Plan hooks enabled"
}

# Disable hooks
plan_hooks_disable() {
    export PLAN_HOOKS_ENABLED="false"
    echo "Plan hooks disabled"
}

# ============================================================================
# 数据管理
# ============================================================================

# 初始化数据目录
init_data_dir() {
    mkdir -p "${PLAN_DATA_DIR}"
    
    if [[ ! -f "${PLANS_FILE}" ]]; then
        cat > "${PLANS_FILE}" <<'EOF'
{
  "plans": [],
  "templates": [],
  "metadata": {
    "version": "1.0.0",
    "created_at": "",
    "updated_at": ""
  }
}
EOF
        # 更新创建时间
        python3 - "${PLANS_FILE}" <<'PY'
import json
import sys
from datetime import datetime, timezone
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
data['metadata']['created_at'] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
PY
    fi
}

# 读取 plans.json
read_plans() {
    if [[ ! -f "${PLANS_FILE}" ]]; then
        echo '{"plans":[],"templates":[],"metadata":{}}'
        return
    fi
    cat "${PLANS_FILE}"
}

# 保存 plans.json
save_plans() {
    local data="$1"
    echo "$data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data['metadata']['updated_at'] = sys.argv[1]
print(json.dumps(data, ensure_ascii=False, indent=2))
" "$(get_timestamp)" > "${PLANS_FILE}.tmp"
    mv "${PLANS_FILE}.tmp" "${PLANS_FILE}"
}

# ============================================================================
# 任务分解算法
# ============================================================================

# 智能任务分解
decompose_task() {
    local task_title="$1"
    local complexity="${2:-medium}"
    local context="${3:-}"

    python3 - "${task_title}" "${complexity}" "${context}" <<'PY'
import json
import sys
from datetime import datetime, timezone

task_title = sys.argv[1]
complexity = sys.argv[2] if len(sys.argv) > 2 else 'medium'
context = sys.argv[3] if len(sys.argv) > 3 else ''

# 复杂度系数
complexity_factors = {
    'simple': 1.0,
    'medium': 1.5,
    'complex': 2.0,
    'expert': 3.0
}
factor = complexity_factors.get(complexity, 1.5)

# 标准任务模板
standard_phases = [
    {'phase': 'research', 'name': '调研分析', 'base_hours': 2, 'order': 1},
    {'phase': 'design', 'name': '方案设计', 'base_hours': 4, 'order': 2},
    {'phase': 'implement', 'name': '实现开发', 'base_hours': 8, 'order': 3},
    {'phase': 'test', 'name': '测试验证', 'base_hours': 4, 'order': 4},
    {'phase': 'review', 'name': '代码审查', 'base_hours': 2, 'order': 5},
    {'phase': 'deploy', 'name': '部署上线', 'base_hours': 2, 'order': 6},
]

# 根据任务标题智能调整
title_lower = task_title.lower()
tasks = []
task_id = 0

# 检测任务类型关键词
is_build = any(kw in title_lower for kw in ['build', '构建', 'compile', '编译'])
is_feature = any(kw in title_lower for kw in ['feature', '功能', 'add', '添加', 'new', '新'])
is_fix = any(kw in title_lower for kw in ['fix', 'bug', '修复', 'patch', '补丁'])
is_refactor = any(kw in title_lower for kw in ['refactor', '重构', 'optimize', '优化'])

if is_fix:
    # Bug 修复类任务简化流程
    phases = [p for p in standard_phases if p['phase'] in ['research', 'implement', 'test', 'review']]
elif is_refactor:
    # 重构类任务
    phases = [p for p in standard_phases if p['phase'] in ['research', 'design', 'implement', 'test']]
else:
    phases = standard_phases

for phase in phases:
    hours = int(phase['base_hours'] * factor)
    task_id += 1
    
    # 计算依赖
    dependencies = []
    if task_id > 1:
        dependencies.append(f"task-{task_id - 1}")
    
    # 估算时间范围
    min_hours = max(1, int(hours * 0.8))
    max_hours = int(hours * 1.2)
    
    task = {
        'task_id': f'task-{task_id}',
        'title': f"{phase['name']}: {task_title}",
        'phase': phase['phase'],
        'description': f"完成{task_title}的{phase['name']}阶段",
        'estimated_hours': hours,
        'estimated_range': {'min': min_hours, 'max': max_hours},
        'dependencies': dependencies,
        'status': 'pending',
        'priority': 'normal',
        'order': phase['order'],
        'created_at': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    }
    tasks.append(task)

# 计算总工作量
total_hours = sum(t['estimated_hours'] for t in tasks)
total_days = max(1, round(total_hours / 8))

result = {
    'tasks': tasks,
    'summary': {
        'total_tasks': len(tasks),
        'total_hours': total_hours,
        'total_days': total_days,
        'complexity': complexity,
        'phases': [t['phase'] for t in tasks]
    }
}

print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

# ============================================================================
# 依赖关系分析
# ============================================================================

# 分析任务依赖
analyze_dependencies() {
    local tasks_json="$1"

    python3 - "${tasks_json}" <<'PY'
import json
import sys

tasks = json.loads(sys.argv[1])

# 构建依赖图
dependency_graph = {}
reverse_deps = {}

for task in tasks:
    task_id = task['task_id']
    deps = task.get('dependencies', [])
    dependency_graph[task_id] = deps
    
    # 构建反向依赖
    for dep in deps:
        if dep not in reverse_deps:
            reverse_deps[dep] = []
        reverse_deps[dep].append(task_id)

# 检测循环依赖
def detect_cycle(graph):
    visited = set()
    rec_stack = set()
    
    def dfs(node):
        visited.add(node)
        rec_stack.add(node)
        
        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                if dfs(neighbor):
                    return True
            elif neighbor in rec_stack:
                return True
        
        rec_stack.remove(node)
        return False
    
    for node in graph:
        if node not in visited:
            if dfs(node):
                return True
    return False

# 拓扑排序
def topological_sort(graph):
    in_degree = {node: 0 for node in graph}
    for node in graph:
        for dep in graph[node]:
            if dep in in_degree:
                in_degree[node] += 1
    
    queue = [node for node in in_degree if in_degree[node] == 0]
    result = []
    
    while queue:
        node = queue.pop(0)
        result.append(node)
        
        for dependent in [n for n in graph if node in graph.get(n, [])]:
            in_degree[dependent] -= 1
            if in_degree[dependent] == 0:
                queue.append(dependent)
    
    return result if len(result) == len(graph) else None

has_cycle = detect_cycle(dependency_graph)
execution_order = topological_sort(dependency_graph) if not has_cycle else None

# 关键路径分析
def find_critical_path(graph, tasks_dict):
    if not graph:
        return [], 0
    
    # 计算最早开始时间
    earliest_start = {}
    earliest_finish = {}
    
    order = topological_sort(graph)
    if not order:
        return [], 0
    
    for task_id in order:
        deps = graph.get(task_id, [])
        if not deps:
            earliest_start[task_id] = 0
        else:
            earliest_start[task_id] = max(earliest_finish.get(dep, 0) for dep in deps)
        
        duration = tasks_dict.get(task_id, {}).get('estimated_hours', 1)
        earliest_finish[task_id] = earliest_start[task_id] + duration
    
    if not earliest_finish:
        return [], 0
    
    # 找到结束时间最晚的任务
    max_finish = max(earliest_finish.values())
    
    # 回溯关键路径
    critical_path = []
    current_finish = max_finish
    
    for task_id in reversed(order):
        if abs(earliest_finish.get(task_id, 0) - current_finish) < 0.1:
            critical_path.append(task_id)
            current_finish = earliest_start.get(task_id, 0)
    
    return list(reversed(critical_path)), max_finish

tasks_dict = {t['task_id']: t for t in tasks}
critical_path, critical_duration = find_critical_path(dependency_graph, tasks_dict)

# 识别阻塞任务
blocking_tasks = []
for task_id, dependents in reverse_deps.items():
    if len(dependents) > 0:
        blocking_tasks.append({
            'task_id': task_id,
            'blocks': dependents,
            'impact': len(dependents)
        })

blocking_tasks.sort(key=lambda x: x['impact'], reverse=True)

result = {
    'has_cycle': has_cycle,
    'execution_order': execution_order or [],
    'critical_path': critical_path,
    'critical_duration_hours': critical_duration,
    'blocking_tasks': blocking_tasks[:5],  # Top 5
    'dependency_matrix': {
        'total_dependencies': sum(len(deps) for deps in dependency_graph.values()),
        'max_depth': max(len(deps) for deps in dependency_graph.values()) if dependency_graph else 0,
        'independent_tasks': [t for t in dependency_graph if not dependency_graph[t]]
    }
}

print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

# ============================================================================
# 工作量估算
# ============================================================================

# 估算工作量
estimate_effort() {
    local tasks_json="$1"
    local team_size="${2:-1}"
    local velocity="${3:-1.0}"

    python3 - "${tasks_json}" "${team_size}" "${velocity}" <<'PY'
import json
import sys
from datetime import datetime, timedelta

tasks = json.loads(sys.argv[1])
team_size = int(sys.argv[2]) if sys.argv[2] else 1
velocity = float(sys.argv[3]) if sys.argv[3] else 1.0

# 计算各项指标
total_hours = sum(t.get('estimated_hours', 0) for t in tasks)
total_hours_adjusted = total_hours / velocity

# 按阶段分组
phase_breakdown = {}
for task in tasks:
    phase = task.get('phase', 'unknown')
    if phase not in phase_breakdown:
        phase_breakdown[phase] = {'hours': 0, 'tasks': 0}
    phase_breakdown[phase]['hours'] += task.get('estimated_hours', 0)
    phase_breakdown[phase]['tasks'] += 1

# 按优先级分组
priority_breakdown = {}
for task in tasks:
    priority = task.get('priority', 'normal')
    if priority not in priority_breakdown:
        priority_breakdown[priority] = {'hours': 0, 'tasks': 0}
    priority_breakdown[priority]['hours'] += task.get('estimated_hours', 0)
    priority_breakdown[priority]['tasks'] += 1

# 计算工期
hours_per_day = 8
daily_capacity = team_size * hours_per_day * velocity
total_days = max(1, round(total_hours_adjusted / daily_capacity))

# 里程碑估算
milestones = []
cumulative_hours = 0
milestone_phases = ['research', 'design', 'implement', 'test', 'deploy']

for phase in milestone_phases:
    if phase in phase_breakdown:
        cumulative_hours += phase_breakdown[phase]['hours']
        milestone_days = round(cumulative_hours / daily_capacity)
        milestones.append({
            'phase': phase,
            'cumulative_hours': cumulative_hours,
            'estimated_day': milestone_days,
            'tasks_completed': sum(1 for t in tasks if t.get('phase') in milestone_phases[:milestone_phases.index(phase)+1])
        })

# 风险评估
risk_factors = []
if total_hours > 40:
    risk_factors.append({'type': 'scope', 'level': 'high', 'message': '工作量超过 40 小时，建议拆分'})
if team_size > 3:
    risk_factors.append({'type': 'coordination', 'level': 'medium', 'message': '团队规模较大，沟通成本增加'})
if any(t.get('estimated_hours', 0) > 16 for t in tasks):
    risk_factors.append({'type': 'task_size', 'level': 'medium', 'message': '存在超过 2 天的任务，建议细化'})

result = {
    'summary': {
        'total_hours': total_hours,
        'adjusted_hours': round(total_hours_adjusted, 1),
        'team_size': team_size,
        'velocity': velocity,
        'estimated_days': total_days,
        'estimated_weeks': max(1, round(total_days / 5))
    },
    'phase_breakdown': phase_breakdown,
    'priority_breakdown': priority_breakdown,
    'milestones': milestones,
    'risk_factors': risk_factors,
    'confidence': {
        'level': 'medium' if len(tasks) >= 5 else 'low',
        'factors': [
            f"基于 {len(tasks)} 个任务估算",
            f"团队速度系数：{velocity}",
            f"每日产能：{daily_capacity} 小时"
        ]
    }
}

print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

# ============================================================================
# 进度追踪
# ============================================================================

# 计算计划进度
calculate_progress() {
    local plan_json="$1"

    python3 - "${plan_json}" <<'PY'
import json
import sys
from datetime import datetime

plan = json.loads(sys.argv[1])
tasks = plan.get('tasks', [])

if not tasks:
    print(json.dumps({
        'progress_percent': 0,
        'completed': 0,
        'total': 0,
        'status': 'empty'
    }))
    sys.exit(0)

total = len(tasks)
completed = sum(1 for t in tasks if t.get('status') == 'completed')
in_progress = sum(1 for t in tasks if t.get('status') == 'in_progress')
pending = sum(1 for t in tasks if t.get('status') == 'pending')
blocked = sum(1 for t in tasks if t.get('status') == 'blocked')

# 加权进度 (完成=100%, 进行中=50%, 其他=0%)
weighted_progress = completed * 100 + in_progress * 50
progress_percent = round(weighted_progress / total, 1) if total > 0 else 0

# 确定整体状态
if completed == total:
    status = 'completed'
elif blocked > 0:
    status = 'blocked'
elif in_progress > 0:
    status = 'in_progress'
elif pending == total:
    status = 'pending'
else:
    status = 'mixed'

# 计算时间进度
created_at = plan.get('created_at', '')
deadline = plan.get('deadline', '')

time_progress = None
if created_at and deadline:
    try:
        start = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
        end = datetime.fromisoformat(deadline.replace('Z', '+00:00'))
        now = datetime.now(timezone.utc).replace(tzinfo=start.tzinfo)

        total_duration = (end - start).total_seconds()
        elapsed = (now - start).total_seconds()

        if total_duration > 0:
            time_progress = round(min(100, max(0, elapsed / total_duration * 100)), 1)
    except:
        pass

# 燃尽图数据
burndown = {
    'ideal': total,
    'actual': total - completed,
    'remaining_tasks': [t['task_id'] for t in tasks if t.get('status') not in ['completed']],
    'completed_tasks': [t['task_id'] for t in tasks if t.get('status') == 'completed']
}

result = {
    'progress_percent': progress_percent,
    'status': status,
    'task_counts': {
        'total': total,
        'completed': completed,
        'in_progress': in_progress,
        'pending': pending,
        'blocked': blocked
    },
    'time_progress': time_progress,
    'burndown': burndown,
    'health': 'good' if progress_percent >= time_progress else 'at_risk' if time_progress else 'unknown'
}

print(json.dumps(result, ensure_ascii=False, indent=2))
PY
}

# ============================================================================
# 格式化输出
# ============================================================================

# 输出 Markdown 格式计划
format_markdown() {
    local plan_json="$1"

    python3 - "${plan_json}" <<'PY'
import json
import sys

plan = json.loads(sys.argv[1])

title = plan.get('title', 'Untitled Plan')
description = plan.get('description', '')
status = plan.get('status', 'pending')
created_at = plan.get('created_at', '')
deadline = plan.get('deadline', '')
tasks = plan.get('tasks', [])

# 计算进度
total = len(tasks)
completed = sum(1 for t in tasks if t.get('status') == 'completed')
progress = round(completed / total * 100, 1) if total > 0 else 0

output = []
output.append(f"# 📋 {title}")
output.append("")
if description:
    output.append(f"> {description}")
    output.append("")

# 状态徽章
status_emoji = {'completed': '✅', 'in_progress': '🔄', 'pending': '⏳', 'blocked': '🚫'}
output.append(f"**状态**: {status_emoji.get(status, '❓')} {status}")
output.append(f"**进度**: {progress}% ({completed}/{total} 任务)")
if created_at:
    output.append(f"**创建**: {created_at}")
if deadline:
    output.append(f"**截止**: {deadline}")
output.append("")

# 进度条
bar_length = 20
filled = int(bar_length * progress / 100)
bar = '█' * filled + '░' * (bar_length - filled)
output.append(f"进度：[{bar}] {progress}%")
output.append("")

# 任务列表
output.append("## 📝 任务列表")
output.append("")
output.append("| ID | 任务 | 阶段 | 估算 | 状态 | 依赖 |")
output.append("|----|------|------|------|------|------|")

status_icons = {'completed': '✅', 'in_progress': '🔄', 'pending': '⏳', 'blocked': '🚫'}

for task in tasks:
    task_id = task.get('task_id', '?')
    task_title = task.get('title', 'Untitled')
    phase = task.get('phase', 'unknown')
    hours = task.get('estimated_hours', 0)
    task_status = task.get('status', 'pending')
    deps = task.get('dependencies', [])
    
    deps_str = ', '.join(deps) if deps else '-'
    output.append(f"| {task_id} | {task_title} | {phase} | {hours}h | {status_icons.get(task_status, '?')} | {deps_str} |")

output.append("")

# 工作量统计
total_hours = sum(t.get('estimated_hours', 0) for t in tasks)
output.append("## 📊 工作量统计")
output.append("")
output.append(f"- **总任务数**: {total}")
output.append(f"- **总估算**: {total_hours} 小时")
output.append(f"- **已完成**: {completed} 任务")
output.append(f"- **剩余**: {total - completed} 任务")
output.append("")

# 依赖分析
if plan.get('dependency_analysis'):
    analysis = plan['dependency_analysis']
    output.append("## 🔗 依赖分析")
    output.append("")
    if analysis.get('critical_path'):
        output.append(f"**关键路径**: {' → '.join(analysis['critical_path'])}")
    if analysis.get('blocking_tasks'):
        output.append("**阻塞任务**:")
        for bt in analysis['blocking_tasks'][:3]:
            output.append(f"- {bt['task_id']} (影响 {bt['impact']} 个任务)")
    output.append("")

# 时间线
if plan.get('timeline'):
    output.append("## 📅 时间线")
    output.append("")
    for milestone in plan.get('timeline', []):
        if isinstance(milestone, dict):
            output.append(f"- **{milestone.get('phase', 'unknown')}**: 第 {milestone.get('estimated_day', 0)} 天完成")
    output.append("")

print('\n'.join(output))
PY
}

# 输出 JSON 格式计划
format_json() {
    local plan_json="$1"
    echo "$plan_json"
}

# ============================================================================
# 核心命令实现
# ============================================================================

# plan create - 创建计划
cmd_create() {
    local title=""
    local description=""
    local complexity="medium"
    local deadline=""
    local template=""
    local format="text"

    # Initialize session and hooks
    plan_session_init
    plan_hooks_init

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title=*)
                title="${1#*=}"
                ;;
            --desc=*)
                description="${1#*=}"
                ;;
            --complexity=*)
                complexity="${1#*=}"
                ;;
            --deadline=*)
                deadline="${1#*=}"
                ;;
            --template=*)
                template="${1#*=}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            -*)
                output_error "Unknown option: $1" 1
                return 1
                ;;
            *)
                if [[ -z "$title" ]]; then
                    title="$1"
                elif [[ -z "$description" ]]; then
                    description="$1"
                fi
                ;;
        esac
        shift || true
    done

    if [[ -z "$title" ]]; then
        output_error "Title is required. Usage: plan create <title> [OPTIONS]" 1
        return 1
    fi

    # Trigger pre-create hooks
    plan_hooks_trigger "$HOOK_PLAN_CREATE" "title" "$title" "complexity" "$complexity" 2>/dev/null || true

    init_data_dir

    # 分解任务
    local decomposed
    decomposed=$(decompose_task "$title" "$complexity" "$description")

    # 分析依赖
    local tasks_json
    tasks_json=$(echo "$decomposed" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['tasks']))")

    local dependency_analysis
    dependency_analysis=$(analyze_dependencies "$tasks_json")

    # 估算工作量
    local effort_estimate
    effort_estimate=$(estimate_effort "$tasks_json")

    # 创建计划
    local plan_id
    plan_id=$(generate_id "plan")
    local timestamp
    timestamp=$(get_timestamp)

    local new_plan
    new_plan=$(python3 - "$plan_id" "$title" "$description" "$complexity" "$deadline" "$decomposed" "$dependency_analysis" "$effort_estimate" "$timestamp" <<'PY'
import json
import sys

plan_id = sys.argv[1]
title = sys.argv[2]
description = sys.argv[3]
complexity = sys.argv[4]
deadline = sys.argv[5] if sys.argv[5] else None
decomposed = json.loads(sys.argv[6])
dependency_analysis = json.loads(sys.argv[7])
effort_estimate = json.loads(sys.argv[8])
timestamp = sys.argv[9]

tasks = decomposed.get('tasks', [])
summary = decomposed.get('summary', {})

plan = {
    'plan_id': plan_id,
    'title': title,
    'description': description,
    'complexity': complexity,
    'status': 'pending',
    'created_at': timestamp,
    'updated_at': timestamp,
    'deadline': deadline,
    'tasks': tasks,
    'summary': {
        'total_tasks': summary.get('total_tasks', len(tasks)),
        'total_hours': summary.get('total_hours', 0),
        'total_days': summary.get('total_days', 1),
        'phases': summary.get('phases', [])
    },
    'dependency_analysis': dependency_analysis,
    'effort_estimate': effort_estimate,
    'timeline': effort_estimate.get('milestones', []),
    'progress': {
        'percent': 0,
        'completed': 0,
        'total': len(tasks)
    }
}

print(json.dumps(plan, ensure_ascii=False, indent=2))
PY
)

    # 保存到 plans.json
    local plans_data
    plans_data=$(read_plans)
    
    plans_data=$(python3 - "$plans_data" "$new_plan" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
new_plan = json.loads(sys.argv[2])

data['plans'].append(new_plan)
print(json.dumps(data, ensure_ascii=False, indent=2))
PY
)
    save_plans "$plans_data"

    # 输出结果
    if [[ "$format" == "json" ]] || [[ "$OUTPUT_FORMAT" == "json" ]]; then
        format_json "$new_plan"
    else
        format_markdown "$new_plan"
        

        output_text ""
        output_text "✅ 计划已创建：${plan_id}"
        local task_count
        task_count=$(echo "$new_plan" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['tasks']))")
        local total_hours
        total_hours=$(echo "$new_plan" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['total_hours'])")
        output_text "   任务数：${task_count}"
        output_text "   估算：${total_hours} 小时"
    fi

    # Add to session if enabled
    plan_session_add_plan "$plan_id" "$title" "pending" 2>/dev/null || true

    # Trigger post-create hooks
    plan_hooks_trigger "$HOOK_PLAN_CREATE" "plan_id" "$plan_id" "status" "created" 2>/dev/null || true

    echo "$plan_id"
}

# plan list - 列出计划
cmd_list() {
    local status_filter="all"
    local format="text"
    local limit=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status=*)
                status_filter="${1#*=}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --limit=*)
                limit="${1#*=}"
                ;;
            -*)
                output_error "Unknown option: $1" 1
                return 1
                ;;
            *)
                status_filter="$1"
                ;;
        esac
        shift || true
    done

    init_data_dir

    local plans_data
    plans_data=$(read_plans)

    python3 - "$plans_data" "$status_filter" "$limit" "$format" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
status_filter = sys.argv[2]
limit = int(sys.argv[3]) if sys.argv[3] else None
output_format = sys.argv[4]

plans = data.get('plans', [])

# 过滤
if status_filter != 'all':
    plans = [p for p in plans if p.get('status') == status_filter]

# 限制数量
if limit:
    plans = plans[:limit]

# 排序 (按创建时间倒序)
plans.sort(key=lambda x: x.get('created_at', ''), reverse=True)

if output_format == 'json':
    print(json.dumps({'plans': plans, 'total': len(plans)}, ensure_ascii=False, indent=2))
else:
    if not plans:
        print("暂无计划")
        sys.exit(0)
    
    print(f"{'PLAN_ID':<35} {'TITLE':<25} {'STATUS':<12} {'PROGRESS':<10} {'TASKS':<8}")
    print("=" * 95)
    
    status_icons = {'completed': '✅', 'in_progress': '🔄', 'pending': '⏳', 'blocked': '🚫'}
    
    for plan in plans:
        plan_id = plan.get('plan_id', '?')[:35]
        title = plan.get('title', 'Untitled')[:25]
        status = plan.get('status', 'unknown')
        progress = plan.get('progress', {}).get('percent', 0)
        total = plan.get('progress', {}).get('total', 0)
        completed = plan.get('progress', {}).get('completed', 0)
        
        icon = status_icons.get(status, '❓')
        print(f"{plan_id:<35} {title:<25} {icon} {status:<10} {progress}% ({completed}/{total})")
PY
}

# plan status - 计划状态
cmd_status() {
    local plan_id="$1"
    local format="${2:-text}"

    if [[ -z "$plan_id" ]]; then
        output_error "Plan ID is required. Usage: plan status <plan-id>" 1
        return 1
    fi

    init_data_dir

    local plans_data
    plans_data=$(read_plans)

    python3 - "$plans_data" "$plan_id" "$format" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
plan_id = sys.argv[2]
output_format = sys.argv[3]

plan = None
for p in data.get('plans', []):
    if p.get('plan_id') == plan_id:
        plan = p
        break

if not plan:
    if output_format == 'json':
        print(json.dumps({'error': True, 'message': f'Plan not found: {plan_id}'}))
    else:
        print(f"ERROR: Plan not found: {plan_id}")
    sys.exit(1)

# 计算实时进度
tasks = plan.get('tasks', [])
total = len(tasks)
completed = sum(1 for t in tasks if t.get('status') == 'completed')
in_progress = sum(1 for t in tasks if t.get('status') == 'in_progress')
pending = sum(1 for t in tasks if t.get('status') == 'pending')
blocked = sum(1 for t in tasks if t.get('status') == 'blocked')

progress_percent = round((completed * 100 + in_progress * 50) / total, 1) if total > 0 else 0

# 确定状态
if completed == total:
    status = 'completed'
elif blocked > 0:
    status = 'blocked'
elif in_progress > 0:
    status = 'in_progress'
else:
    status = plan.get('status', 'pending')

plan['status'] = status
plan['progress'] = {
    'percent': progress_percent,
    'completed': completed,
    'in_progress': in_progress,
    'pending': pending,
    'blocked': blocked,
    'total': total
}

if output_format == 'json':
    print(json.dumps(plan, ensure_ascii=False, indent=2))
else:
    print(f"=== 计划状态: {plan.get('title', 'Untitled')} ===")
    print(f"ID: {plan.get('plan_id')}")
    print(f"状态: {status}")
    print(f"进度: {progress_percent}%")
    print(f"创建: {plan.get('created_at')}")
    if plan.get('deadline'):
        print(f"截止: {plan.get('deadline')}")
    print("")
    print("任务详情:")
    print(f"{'ID':<15} {'任务':<30} {'状态':<12} {'估算':<8}")
    print("-" * 70)
    
    status_icons = {'completed': '✅', 'in_progress': '🔄', 'pending': '⏳', 'blocked': '🚫'}
    for task in tasks:
        tid = task.get('task_id', '?')
        ttitle = task.get('title', 'Untitled')[:30]
        tstatus = status_icons.get(task.get('status', 'pending'), '?')
        hours = task.get('estimated_hours', 0)
        print(f"{tid:<15} {ttitle:<30} {tstatus:<12} {hours}h")
PY
}

# plan update - 更新计划
cmd_update() {
    local plan_id="$1"
    local title=""
    local description=""
    local deadline=""
    local status=""

    # Initialize hooks
    plan_hooks_init

    if [[ -z "$plan_id" ]]; then
        output_error "Plan ID is required. Usage: plan update <plan-id> [OPTIONS]" 1
        return 1
    fi

    # Trigger pre-update hooks
    plan_hooks_trigger "$HOOK_PLAN_UPDATE" "plan_id" "$plan_id" 2>/dev/null || true

    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title=*)
                title="${1#*=}"
                ;;
            --desc=*)
                description="${1#*=}"
                ;;
            --deadline=*)
                deadline="${1#*=}"
                ;;
            --status=*)
                status="${1#*=}"
                ;;
            *)
                output_error "Unknown option: $1" 1
                return 1
                ;;
        esac
        shift || true
    done

    init_data_dir

    local plans_data
    plans_data=$(read_plans)

    local updated
    updated=$(python3 - "$plans_data" "$plan_id" "$title" "$description" "$deadline" "$status" "$(get_timestamp)" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
plan_id = sys.argv[2]
title = sys.argv[3]
description = sys.argv[4]
deadline = sys.argv[5]
status = sys.argv[6]
timestamp = sys.argv[7]

found = False
for plan in data.get('plans', []):
    if plan.get('plan_id') == plan_id:
        if title:
            plan['title'] = title
        if description:
            plan['description'] = description
        if deadline:
            plan['deadline'] = deadline
        if status:
            plan['status'] = status
        plan['updated_at'] = timestamp
        found = True
        break

if not found:
    print(json.dumps({'error': True, 'message': f'Plan not found: {plan_id}'}))
    sys.exit(1)

print(json.dumps({'success': True, 'plan': data, 'updated_plan': plan}))
PY
)

    local error
    error=$(echo "$updated" | python3 -c "import json,sys; d=json.load(sys.stdin); print('error' if d.get('error') else '')" 2>/dev/null || echo "error")

    if [[ "$error" == "error" ]]; then
        output_error "Plan not found: ${plan_id}" 1
        return 1
    fi

    plans_data=$(echo "$updated" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['plan'], ensure_ascii=False, indent=2))")
    save_plans "$plans_data"

    output_text "✅ 计划已更新: ${plan_id}"
    # Trigger post-update hooks
    plan_hooks_trigger "$HOOK_PLAN_UPDATE" "plan_id" "$plan_id" "status" "updated" 2>/dev/null || true
}

# plan complete - 标记完成
cmd_complete() {
    local plan_id="$1"
    # Initialize hooks
    plan_hooks_init

    # Trigger pre-complete hooks
    if [[ -n "$task_id" ]]; then
        plan_hooks_trigger "$HOOK_TASK_COMPLETE" "plan_id" "$plan_id" "task_id" "$task_id" 2>/dev/null || true
    else
        plan_hooks_trigger "$HOOK_PLAN_COMPLETE" "plan_id" "$plan_id" 2>/dev/null || true
    fi

    local task_id="${2:-}"

    if [[ -z "$plan_id" ]]; then
        output_error "Plan ID is required. Usage: plan complete <plan-id> [task-id]" 1
        return 1
    fi

    init_data_dir

    local plans_data
    plans_data=$(read_plans)

    local result
    result=$(python3 - "$plans_data" "$plan_id" "$task_id" "$(get_timestamp)" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
plan_id = sys.argv[2]
task_id = sys.argv[3]
timestamp = sys.argv[4]

found = False
for plan in data.get('plans', []):
    if plan.get('plan_id') == plan_id:
        found = True
        
        if task_id:
            # 完成特定任务
            task_found = False
            for task in plan.get('tasks', []):
                if task.get('task_id') == task_id:
                    task['status'] = 'completed'
                    task['completed_at'] = timestamp
                    task_found = True
                    break
            
            if not task_found:
                print(json.dumps({'error': True, 'message': f'Task not found: {task_id}'}))
                sys.exit(1)
        else:
            # 完成所有任务
            for task in plan.get('tasks', []):
                if task.get('status') != 'completed':
                    task['status'] = 'completed'
                    task['completed_at'] = timestamp
        
        # 重新计算进度
        tasks = plan.get('tasks', [])
        total = len(tasks)
        completed = sum(1 for t in tasks if t.get('status') == 'completed')
        
        if completed == total:
            plan['status'] = 'completed'
            plan['completed_at'] = timestamp
        
        plan['progress'] = {
            'percent': round(completed / total * 100, 1) if total > 0 else 0,
            'completed': completed,
            'total': total
        }
        plan['updated_at'] = timestamp
        
        print(json.dumps({'success': True, 'plan': plan}))
        sys.exit(0)

if not found:
    print(json.dumps({'error': True, 'message': f'Plan not found: {plan_id}'}))
    sys.exit(1)
PY
)

    local error
    error=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print('error' if d.get('error') else '')" 2>/dev/null || echo "error")

    if [[ "$error" == "error" ]]; then
        local msg
        msg=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('message', 'Unknown error'))" 2>/dev/null || echo "Unknown error")
        output_error "$msg" 1
        return 1
    fi

    plans_data=$(echo "$result" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
# 更新 plans 数据
result = json.loads(sys.argv[1])
for i, p in enumerate(data['plans']):
    if p.get('plan_id') == result['plan']['plan_id']:
        data['plans'][i] = result['plan']
        break
print(json.dumps(data, ensure_ascii=False, indent=2))
" "$result")
    save_plans "$plans_data"

    if [[ -z "$task_id" ]]; then
        output_text "✅ 计划已完成: ${plan_id}"
    else
        output_text "✅ 任务已完成: ${task_id}"
    fi
}

# ============================================================================
# 帮助信息
# ============================================================================

show_help() {
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        python3 -c "
import json
help_data = {
    'name': 'plan',
    'version': '1.0.0',
    'description': 'Plan Agent - 任务规划、分解、依赖分析与进度追踪',
    'commands': [
        {
            'name': 'create',
            'usage': 'plan create <title> [OPTIONS]',
            'description': '创建新计划，自动分解任务',
            'options': {
                '--title=TITLE': '计划标题',
                '--desc=DESC': '计划描述',
                '--complexity=LEVEL': '复杂度 (simple|medium|complex|expert)',
                '--deadline=DATE': '截止日期 (ISO 8601)',
                '--format=FORMAT': '输出格式 (text|json|markdown)'
            },
            'examples': [
                'plan create \"实现用户登录功能\"',
                'plan create \"重构支付模块\" --complexity=complex',
                'plan create \"Bug 修复\" --deadline=2024-12-31'
            ]
        },
        {
            'name': 'list',
            'usage': 'plan list [OPTIONS]',
            'description': '列出所有计划',
            'options': {
                '--status=STATUS': '状态过滤 (all|pending|in_progress|completed)',
                '--format=FORMAT': '输出格式 (text|json)',
                '--limit=N': '限制显示数量'
            },
            'examples': [
                'plan list',
                'plan list --status=in_progress',
                'plan list --format=json --limit=10'
            ]
        },
        {
            'name': 'status',
            'usage': 'plan status <plan-id>',
            'description': '查看计划详细状态',
            'examples': [
                'plan status plan-123456',
                'plan status plan-123456 --format=json'
            ]
        },
        {
            'name': 'update',
            'usage': 'plan update <plan-id> [OPTIONS]',
            'description': '更新计划信息',
            'options': {
                '--title=TITLE': '新标题',
                '--desc=DESC': '新描述',
                '--deadline=DATE': '新截止日期',
                '--status=STATUS': '新状态'
            },
            'examples': [
                'plan update plan-123456 --status=blocked',
                'plan update plan-123456 --deadline=2024-12-31'
            ]
        },
        {
            'name': 'complete',
            'usage': 'plan complete <plan-id> [task-id]',
            'description': '标记计划或任务为完成',
            'examples': [
                'plan complete plan-123456',
                'plan complete plan-123456 task-1'
            ]
        }
    ],
    'features': [
        '智能任务分解 (基于复杂度)',
        '依赖关系分析与关键路径',
        '工作量估算与里程碑',
        '进度追踪与燃尽图',
        'JSON/Markdown 双格式输出'
    ]
}
print(json.dumps(help_data, ensure_ascii=False, indent=2))
"
    else
        cat <<'EOF'
Plan Agent - 任务规划与进度追踪

用法：plan <command> [args]

命令:
  create <title> [OPTIONS]  创建新计划，自动分解任务
  list [OPTIONS]            列出所有计划
  status <plan-id>          查看计划详细状态
  update <plan-id> [OPTS]   更新计划信息
  complete <plan-id> [TASK] 标记计划或任务完成

创建计划 (create):
  plan create "实现用户登录功能"
  plan create "重构支付模块" --complexity=complex
  plan create "Bug 修复" --deadline=2024-12-31
  plan create "新功能" --desc="详细描述" --format=markdown

选项:
  --title=TITLE       计划标题
  --desc=DESC         计划描述
  --complexity=LEVEL  复杂度：simple|medium|complex|expert (默认：medium)
  --deadline=DATE     截止日期 (ISO 8601 格式)
  --format=FORMAT     输出格式：text|json|markdown

列出计划 (list):
  plan list
  plan list --status=in_progress
  plan list --format=json --limit=10

查看状态 (status):
  plan status plan-123456
  plan status plan-123456 --format=json

更新计划 (update):
  plan update plan-123456 --status=blocked
  plan update plan-123456 --deadline=2024-12-31
  plan update plan-123456 --title="新标题"

标记完成 (complete):
  plan complete plan-123456           # 完成所有任务
  plan complete plan-123456 task-1    # 完成特定任务

核心功能:
  • 智能任务分解 - 根据复杂度自动分解为 6 个阶段
  • 依赖分析 - 检测循环依赖，计算关键路径
  • 工作量估算 - 基于团队规模和速度系数
  • 进度追踪 - 实时计算完成百分比和燃尽数据

环境变量:
  OML_PLAN_VERBOSE=true     启用详细输出
  OML_PLAN_DATA_DIR=PATH    自定义数据目录
  OML_OUTPUT_FORMAT=json    默认输出格式

数据位置:
  ~/.oml/plans/plans.json   计划数据存储
EOF
    fi
}

# ============================================================================
# 主入口
# ============================================================================

main() {
    # 初始化环境、session 和 hooks
    init_data_dir
    plan_session_init
    plan_hooks_init

    local action="${1:-help}"
    shift || true

    case "$action" in
        # 创建计划
        create|c|new)
            cmd_create "$@"
            ;;

        # 列出计划
        list|ls|l)
            cmd_list "$@"
            ;;

        # 计划状态
        status|s|stat)
            cmd_status "$@"
            ;;

        # 更新计划
        update|u|edit)
            cmd_update "$@"
            ;;

        # 标记完成
        complete|done|finish)
            cmd_complete "$@"
            ;;

        # 帮助
        help|--help|-h)
            show_help
            ;;

        # 版本
        version|--version|-v)
            echo "plan agent v1.0.0"
            ;;

        # 未知命令
        *)
            output_error "Unknown command: ${action}" 1
            show_help
            return 1
            ;;
    esac
}

main "$@"
