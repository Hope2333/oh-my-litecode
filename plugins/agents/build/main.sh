#!/usr/bin/env bash
# Build Agent Plugin for OML
# 项目构建、清理、状态和日志管理
# Enhanced with Session and Hooks integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"
PLUGIN_NAME="build"

# Source OML core
OML_CORE_DIR="${OML_CORE_DIR:-$(cd "$(dirname "${SCRIPT_DIR}")" && cd ../../core && pwd)}"
if [[ -f "${OML_CORE_DIR}/platform.sh" ]]; then
    source "${OML_CORE_DIR}/platform.sh"
fi
if [[ -f "${OML_CORE_DIR}/plugin-loader.sh" ]]; then
    source "${OML_CORE_DIR}/plugin-loader.sh"
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

# 构建相关目录
SOLVE_ANDROID_DIR="${OML_ROOT}/solve-android"
OPENCODE_DIR="${SOLVE_ANDROID_DIR}/opencode"
BUN_DIR="${SOLVE_ANDROID_DIR}/bun"
DIST_DIR="${OML_ROOT}/dist"
TMP_DIR="${OML_ROOT}/.tmp"
BUILD_LOGS_DIR="${OML_BUILD_LOG_DIR:-${OML_ROOT}/.logs/build}"

# 支持的子项目
SUBPROJECTS=("opencode" "bun")

# 构建参数默认值
DEFAULT_VER="current"
DEFAULT_PKGMGR="pacman"
DEFAULT_DEBUG="false"
DEFAULT_PARALLEL="auto"

# 输出格式
OUTPUT_FORMAT="${OML_OUTPUT_FORMAT:-text}"

# ============================================================================
# Session Configuration
# ============================================================================
BUILD_SESSION_ENABLED="${BUILD_SESSION_ENABLED:-true}"
BUILD_SESSION_DIR=""
BUILD_SESSION_ID=""
BUILD_SESSION_DATA_FILE=""

# ============================================================================
# Hooks Configuration
# ============================================================================
BUILD_HOOKS_ENABLED="${BUILD_HOOKS_ENABLED:-true}"
BUILD_HOOKS_DIR="${PLUGIN_DIR}/hooks"

# Hook events
readonly HOOK_BUILD_START="build:start"
readonly HOOK_BUILD_COMPLETE="build:complete"
readonly HOOK_BUILD_FAILED="build:failed"
readonly HOOK_CLEAN_START="build:clean:start"
readonly HOOK_CLEAN_COMPLETE="build:clean:complete"
readonly HOOK_STATUS_REQUEST="build:status:request"
readonly HOOK_LOGS_ACCESS="build:logs:access"

# ============================================================================
# Session Management
# ============================================================================

# Initialize session system
build_session_init() {
    if [[ "${BUILD_SESSION_ENABLED}" != "true" ]]; then
        return 0
    fi

    BUILD_SESSION_DIR="${HOME}/.oml/sessions/build"
    mkdir -p "${BUILD_SESSION_DIR}" 2>/dev/null || true
}

# Generate session ID
build_session_generate_id() {
    echo "build-session-$(date +%s)-$$-${RANDOM}"
}

# Create new build session
build_session_create() {
    local name="${1:-unnamed}"
    local metadata="${2:-{}}"

    if [[ "${BUILD_SESSION_ENABLED}" != "true" ]]; then
        return 0
    fi

    local session_id
    session_id="$(build_session_generate_id)"
    local timestamp
    timestamp="$(get_timestamp)"

    local session_data
    session_data=$(python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'type': 'build',
    'created_at': '${timestamp}',
    'updated_at': '${timestamp}',
    'status': 'active',
    'metadata': ${metadata},
    'builds': [],
    'context': {}
}, indent=2))
")

    local session_file="${BUILD_SESSION_DIR}/${session_id}.json"
    echo "$session_data" > "$session_file"
    chmod 600 "$session_file" 2>/dev/null || true

    BUILD_SESSION_ID="$session_id"
    BUILD_SESSION_DATA_FILE="$session_file"

    # Trigger hook
    build_hooks_trigger "$HOOK_BUILD_START" "session_create" "$session_id" 2>/dev/null || true

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
        echo "Created build session: ${session_id}"
    fi

    echo "$session_id"
}

# Get current session
build_session_current() {
    if [[ -z "${BUILD_SESSION_ID:-}" ]]; then
        echo "No active build session" >&2
        return 1
    fi

    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        cat "${BUILD_SESSION_DATA_FILE}" 2>/dev/null || echo '{"error": "Session file not found"}'
    else
        echo "Current build session: ${BUILD_SESSION_ID}"
    fi
}

# Add build record to session
build_session_add_build() {
    local project="$1"
    local action="$2"
    local status="$3"
    local exit_code="${4:-0}"
    local duration="${5:-0}"

    if [[ "${BUILD_SESSION_ENABLED}" != "true" ]] || [[ -z "${BUILD_SESSION_ID:-}" ]]; then
        return 0
    fi

    local timestamp
    timestamp="$(get_timestamp)"

    python3 - "${BUILD_SESSION_DATA_FILE}" "${project}" "${action}" "${status}" "${exit_code}" "${duration}" "${timestamp}" <<'PY'
import json
import sys

session_file = sys.argv[1]
project = sys.argv[2]
action = sys.argv[3]
status = sys.argv[4]
exit_code = int(sys.argv[5])
duration = float(sys.argv[6])
timestamp = sys.argv[7]

with open(session_file, 'r') as f:
    data = json.load(f)

build_record = {
    'project': project,
    'action': action,
    'status': status,
    'exit_code': exit_code,
    'duration_seconds': duration,
    'timestamp': timestamp
}

if 'builds' not in data:
    data['builds'] = []

data['builds'].append(build_record)
data['updated_at'] = timestamp

with open(session_file, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
}

# ============================================================================
# Hooks Management
# ============================================================================

# Initialize hooks system
build_hooks_init() {
    if [[ "${BUILD_HOOKS_ENABLED}" != "true" ]]; then
        return 0
    fi

    mkdir -p "${BUILD_HOOKS_DIR}" 2>/dev/null || true

    # Register built-in hooks if they exist
    for hook_script in "${BUILD_HOOKS_DIR}"/*.sh; do
        if [[ -x "$hook_script" ]]; then
            local hook_name
            hook_name="$(basename "$hook_script" .sh)"
            # Hooks are auto-discovered and executed by trigger
        fi
    done
}

# Trigger hooks for an event
build_hooks_trigger() {
    local event="$1"
    shift
    local payload=("$@")

    if [[ "${BUILD_HOOKS_ENABLED}" != "true" ]]; then
        return 0
    fi

    # Check if hooks directory exists
    if [[ ! -d "${BUILD_HOOKS_DIR}" ]]; then
        return 0
    fi

    # Find and execute matching hook scripts
    for hook_script in "${BUILD_HOOKS_DIR}"/*.sh; do
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
build_hooks_is_enabled() {
    [[ "${BUILD_HOOKS_ENABLED}" == "true" ]]
}

# Enable hooks
build_hooks_enable() {
    export BUILD_HOOKS_ENABLED="true"
    echo "Build hooks enabled"
}

# Disable hooks
build_hooks_disable() {
    export BUILD_HOOKS_ENABLED="false"
    echo "Build hooks disabled"
}

# ============================================================================
# 工具函数
# ============================================================================

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
import json
import sys
data = {'error': True, 'message': sys.argv[1], 'code': int(sys.argv[2])}
print(json.dumps(data, ensure_ascii=False, indent=2))
" "$msg" "$code"
    else
        echo "ERROR: $msg" >&2
    fi
}

# 获取当前时间戳
get_timestamp() {
    date '+%Y-%m-%d_%H-%M-%S'
}

# 获取平台信息
get_platform_info() {
    local platform
    platform="$(oml_platform_label 2>/dev/null || echo "unknown")"
    local arch
    arch="$(oml_arch 2>/dev/null || echo "unknown")"
    echo "${platform}/${arch}"
}

# 检测可用的包管理器
detect_pkgmgr() {
    if [[ -d "/data/data/com.termux/files/usr" ]]; then
        if command -v pacman >/dev/null 2>&1; then
            echo "pacman"
        else
            echo "dpkg"
        fi
    elif command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    else
        echo "make"
    fi
}

# 获取并行构建数
get_parallel_jobs() {
    local parallel="${OML_BUILD_PARALLEL:-$DEFAULT_PARALLEL}"
    if [[ "$parallel" == "auto" ]]; then
        if command -v nproc >/dev/null 2>&1; then
            nproc
        elif command -v sysctl >/dev/null 2>&1; then
            sysctl -n hw.ncpu 2>/dev/null || echo "1"
        else
            echo "1"
        fi
    else
        echo "$parallel"
    fi
}

# ============================================================================
# 日志管理
# ============================================================================

# 初始化日志目录
init_logs_dir() {
    mkdir -p "${BUILD_LOGS_DIR}"
}

# 记录构建日志
log_build() {
    local project="$1"
    local action="$2"
    local status="$3"
    local message="${4:-}"
    local timestamp
    timestamp="$(get_timestamp)"
    
    local log_file="${BUILD_LOGS_DIR}/${project}_${timestamp}.log"
    
    {
        echo "=== Build Log ==="
        echo "Timestamp: ${timestamp}"
        echo "Project: ${project}"
        echo "Action: ${action}"
        echo "Status: ${status}"
        echo "Platform: $(get_platform_info)"
        echo "Message: ${message}"
        echo "================="
    } >> "$log_file"
    
    echo "$log_file"
}

# 获取最新日志文件
get_latest_log() {
    local project="${1:-}"
    local pattern="*.log"
    
    if [[ -n "$project" ]]; then
        pattern="${project}_*.log"
    fi
    
    ls -t "${BUILD_LOGS_DIR}"/${pattern} 2>/dev/null | head -n 1
}

# ============================================================================
# Makefile 调用封装
# ============================================================================

# 获取项目 Makefile 路径
get_makefile_path() {
    local project="$1"
    
    case "$project" in
        opencode)
            echo "${OPENCODE_DIR}/Makefile"
            ;;
        bun)
            echo "${BUN_DIR}/Makefile"
            ;;
        all|"")
            echo "${OML_ROOT}/Makefile"
            ;;
        *)
            # 检查是否为有效目录
            if [[ -d "${OML_ROOT}/${project}" ]]; then
                echo "${OML_ROOT}/${project}/Makefile"
            elif [[ -d "${SOLVE_ANDROID_DIR}/${project}" ]]; then
                echo "${SOLVE_ANDROID_DIR}/${project}/Makefile"
            else
                echo ""
            fi
            ;;
    esac
}

# 调用 Makefile
invoke_make() {
    local project="$1"
    local target="$2"
    local extra_args="${3:-}"
    
    local makefile
    makefile="$(get_makefile_path "$project")"
    
    if [[ -z "$makefile" ]] || [[ ! -f "$makefile" ]]; then
        output_error "Makefile not found for project: ${project}" 2
        return 2
    fi
    
    local parallel
    parallel="$(get_parallel_jobs)"
    local verbose_flag=""
    
    if [[ "${OML_BUILD_VERBOSE:-false}" == "true" ]]; then
        verbose_flag="--print-directory"
    fi
    
    # 构建 make 命令
    local make_cmd="make -f ${makefile} -j${parallel} ${verbose_flag} ${target} ${extra_args}"
    
    output_text "Executing: ${make_cmd}"
    
    # 执行并捕获输出
    local exit_code=0
    local output=""
    
    if [[ "${OML_BUILD_VERBOSE:-false}" == "true" ]]; then
        output=$(eval "$make_cmd" 2>&1) || exit_code=$?
    else
        output=$(eval "$make_cmd" 2>&1) || exit_code=$?
    fi
    
    echo "$output"
    return $exit_code
}

# ============================================================================
# 构建参数管理
# ============================================================================

# 解析构建参数
parse_build_args() {
    local project="${1:-all}"
    local ver="${DEFAULT_VER}"
    local pkgmgr="${DEFAULT_PKGMGR}"
    local debug="${DEFAULT_DEBUG}"
    local extra_args=""
    
    shift || true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ver=*)
                ver="${1#*=}"
                ;;
            --pkgmgr=*)
                pkgmgr="${1#*=}"
                ;;
            --debug)
                debug="true"
                ;;
            --debug=*)
                debug="${1#*=}"
                ;;
            --output=*)
                OUTPUT_FORMAT="${1#*=}"
                ;;
            -j*|--jobs=*)
                if [[ "$1" == -j* ]]; then
                    OML_BUILD_PARALLEL="${1#-j}"
                else
                    OML_BUILD_PARALLEL="${1#*=}"
                fi
                ;;
            --*)
                extra_args="${extra_args} $1"
                ;;
            *)
                # 可能是项目名或其他参数
                if [[ -z "$project" || "$project" == "all" ]]; then
                    project="$1"
                else
                    extra_args="${extra_args} $1"
                fi
                ;;
        esac
        shift || true
    done
    
    # 自动检测包管理器
    if [[ "$pkgmgr" == "auto" ]]; then
        pkgmgr="$(detect_pkgmgr)"
    fi
    
    echo "${project}|${ver}|${pkgmgr}|${debug}|${extra_args}"
}

# ============================================================================
# 构建结果解析
# ============================================================================

# 解析构建输出
parse_build_output() {
    local output="$1"
    local exit_code="$2"
    
    local success=false
    local errors=()
    local warnings=()
    local targets_built=()
    
    if [[ $exit_code -eq 0 ]]; then
        success=true
    fi
    
    # 解析错误
    while IFS= read -r line; do
        if [[ "$line" =~ [Ee]rror: ]] || [[ "$line" =~ \*\*\*.*\*\*\* ]]; then
            errors+=("$line")
        elif [[ "$line" =~ [Ww]arning: ]]; then
            warnings+=("$line")
        elif [[ "$line" =~ ^\[.*\] ]]; then
            targets_built+=("$line")
        fi
    done <<< "$output"
    
    # 生成结果 JSON
    python3 -c "
import json
import sys

success = sys.argv[1] == 'true'
exit_code = int(sys.argv[2])
errors = sys.argv[3].split('|||') if sys.argv[3] else []
warnings = sys.argv[4].split('|||') if sys.argv[4] else []
targets = sys.argv[5].split('|||') if sys.argv[5] else []

# 过滤空字符串
errors = [e for e in errors if e.strip()]
warnings = [w for w in warnings if w.strip()]
targets = [t for t in targets if t.strip()]

result = {
    'success': success,
    'exit_code': exit_code,
    'errors': errors,
    'warnings': warnings,
    'targets_built': targets,
    'error_count': len(errors),
    'warning_count': len(warnings)
}

print(json.dumps(result, ensure_ascii=False, indent=2))
" "$success" "$exit_code" "$(IFS='|||'; echo "${errors[*]}")" "$(IFS='|||'; echo "${warnings[*]}")" "$(IFS='|||'; echo "${targets_built[*]}")"
}

# ============================================================================
# 错误报告生成
# ============================================================================

# 生成错误报告
generate_error_report() {
    local project="$1"
    local output="$2"
    local exit_code="$3"
    local timestamp
    timestamp="$(get_timestamp)"
    
    local report_file="${BUILD_LOGS_DIR}/error_report_${project}_${timestamp}.json"
    
    python3 -c "
import json
import sys
import os

project = sys.argv[1]
output = sys.argv[2]
exit_code = int(sys.argv[3])
timestamp = sys.argv[4]

# 分析错误
errors = []
error_context = []
lines = output.split('\n')

for i, line in enumerate(lines):
    if 'error' in line.lower() or '***' in line:
        errors.append(line.strip())
        # 获取上下文
        start = max(0, i - 2)
        end = min(len(lines), i + 3)
        error_context.append({
            'line': i + 1,
            'content': line.strip(),
            'context': lines[start:end]
        })

report = {
    'project': project,
    'timestamp': timestamp,
    'exit_code': exit_code,
    'platform': os.uname().sysname + '/' + os.uname().machine if hasattr(os, 'uname') else 'unknown',
    'summary': {
        'total_errors': len(errors),
        'build_failed': exit_code != 0
    },
    'errors': errors[:20],  # 限制错误数量
    'error_context': error_context[:10],
    'full_output': output[:10000]  # 限制输出长度
}

print(json.dumps(report, ensure_ascii=False, indent=2))
" "$project" "$output" "$exit_code" "$timestamp" > "$report_file"
    
    echo "$report_file"
}

# ============================================================================
# 核心命令实现
# ============================================================================

# build project - 构建项目
cmd_project() {
    local args
    args="$(parse_build_args "$@")"

    IFS='|' read -r project ver pkgmgr debug extra_args <<< "$args"

    # Initialize session and hooks
    build_session_init
    build_hooks_init

    # Trigger pre-build hooks
    build_hooks_trigger "$HOOK_BUILD_START" "project" "$project" "ver" "$ver" 2>/dev/null || true

    output_text "=== Build Project ==="
    output_text "Project: ${project}"
    output_text "Version: ${ver}"
    output_text "Package Manager: ${pkgmgr}"
    output_text "Debug: ${debug}"
    output_text "Platform: $(get_platform_info)"
    output_text ""

    # 初始化日志
    init_logs_dir

    # 构建 make 参数
    local make_args="VER=${ver} PKGMGR=${pkgmgr} DEBUG=${debug}"
    if [[ -n "$extra_args" ]]; then
        make_args="${make_args} ${extra_args}"
    fi

    local target="build"
    if [[ "$project" != "all" ]]; then
        target="build-project"
        make_args="${make_args} PROJECT=${project}"
    fi

    # 执行构建
    local start_time
    start_time=$(date +%s)

    local build_output
    local exit_code=0

    build_output=$(invoke_make "$project" "$target" "$make_args" 2>&1) || exit_code=$?

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 记录日志
    local status="success"
    if [[ $exit_code -ne 0 ]]; then
        status="failed"
    fi
    log_build "$project" "build" "$status" "duration=${duration}s exit_code=${exit_code}"

    # Add to session if enabled
    build_session_add_build "$project" "build" "$status" "$exit_code" "$duration" 2>/dev/null || true

    # Trigger post-build hooks
    if [[ $exit_code -eq 0 ]]; then
        build_hooks_trigger "$HOOK_BUILD_COMPLETE" "project" "$project" "status" "$status" "duration" "$duration" 2>/dev/null || true
    else
        build_hooks_trigger "$HOOK_BUILD_FAILED" "project" "$project" "exit_code" "$exit_code" 2>/dev/null || true
    fi

    # 解析结果
    local result
    result=$(parse_build_output "$build_output" "$exit_code")

    # 输出结果
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        python3 -c "
import json
import sys

result = json.loads(sys.argv[1])
output = {
    'command': 'build project',
    'project': sys.argv[2],
    'version': sys.argv[3],
    'pkgmgr': sys.argv[4],
    'duration_seconds': int(sys.argv[5]),
    'exit_code': int(sys.argv[6]),
    'status': sys.argv[7],
    'result': result
}
print(json.dumps(output, ensure_ascii=False, indent=2))
" "$result" "$project" "$ver" "$pkgmgr" "$duration" "$exit_code" "$status"
    else
        echo ""
        echo "=== Build Result ==="
        echo "Status: ${status}"
        echo "Duration: ${duration}s"
        echo "Exit Code: ${exit_code}"
        echo ""

        if [[ $exit_code -ne 0 ]]; then
            echo "Build failed. Recent errors:"
            echo "$build_output" | tail -n 20
            echo ""
            echo "Full log saved to: $(get_latest_log "$project")"

            # 生成错误报告
            local error_report
            error_report=$(generate_error_report "$project" "$build_output" "$exit_code")
            echo "Error report: ${error_report}"
        else
            echo "Build completed successfully!"
        fi
    fi
    
    return $exit_code
}

# build clean - 清理构建
cmd_clean() {
    local project="${1:-all}"

    # Initialize hooks
    build_hooks_init

    # Trigger pre-clean hooks
    build_hooks_trigger "$HOOK_CLEAN_START" "project" "$project" 2>/dev/null || true

    output_text "=== Clean Build ==="
    output_text "Project: ${project}"
    output_text ""

    init_logs_dir

    local exit_code=0
    local output=""

    if [[ "$project" == "all" ]]; then
        # 清理所有项目
        output=$(invoke_make "all" "clean" "" 2>&1) || exit_code=$?

        # 额外清理临时目录
        if [[ -d "$TMP_DIR" ]]; then
            rm -rf "$TMP_DIR"
            output="${output}"$'\n'"Removed ${TMP_DIR}"
        fi
    else
        output=$(invoke_make "$project" "clean" "PROJECT=${project}" 2>&1) || exit_code=$?
    fi

    # 记录日志
    local status="success"
    if [[ $exit_code -ne 0 ]]; then
        status="failed"
    fi
    log_build "$project" "clean" "$status" "exit_code=${exit_code}"

    # Trigger post-clean hooks
    build_hooks_trigger "$HOOK_CLEAN_COMPLETE" "project" "$project" "status" "$status" 2>/dev/null || true

    # 输出结果
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        python3 -c "
import json
print(json.dumps({
    'command': 'build clean',
    'project': '$project',
    'status': '$status',
    'exit_code': $exit_code,
    'output': '''$output'''
}, ensure_ascii=False, indent=2))
"
    else
        echo "=== Clean Result ==="
        echo "Status: ${status}"
        echo ""
        echo "$output"
    fi

    return $exit_code
}

# build status - 构建状态
cmd_status() {
    local project="${1:-all}"

    # Initialize hooks
    build_hooks_init

    # Trigger status request hooks
    build_hooks_trigger "$HOOK_STATUS_REQUEST" "project" "$project" 2>/dev/null || true

    init_logs_dir

    # 收集状态信息
    local status_data
    
    status_data=$(python3 -c "
import json
import os
import glob
from pathlib import Path

project = '$project'
logs_dir = '${BUILD_LOGS_DIR}'
oml_root = '${OML_ROOT}'

# 获取最近的构建日志
recent_logs = []
pattern = '*.log'
if project != 'all':
    pattern = f'{project}_*.log'

log_files = sorted(glob.glob(os.path.join(logs_dir, pattern)), reverse=True)[:5]

for log_file in log_files:
    try:
        with open(log_file, 'r') as f:
            content = f.read()
            # 解析日志
            log_info = {
                'file': os.path.basename(log_file),
                'timestamp': os.path.basename(log_file).split('_')[1].replace('.log', '') if len(os.path.basename(log_file).split('_')) > 1 else 'unknown',
            }
            
            for line in content.split('\n'):
                if line.startswith('Action:'):
                    log_info['action'] = line.split(':')[1].strip()
                elif line.startswith('Status:'):
                    log_info['status'] = line.split(':')[1].strip()
            
            recent_logs.append(log_info)
    except Exception as e:
        pass

# 检查项目目录
projects_status = {}
subprojects = ['opencode', 'bun']
solve_android = os.path.join(oml_root, 'solve-android')

for proj in subprojects:
    proj_dir = os.path.join(solve_android, proj)
    proj_info = {
        'exists': os.path.isdir(proj_dir),
        'has_makefile': os.path.isfile(os.path.join(proj_dir, 'Makefile')),
    }
    
    # 检查是否有构建产物
    dist_dir = os.path.join(oml_root, 'dist')
    has_dist = False
    if os.path.isdir(dist_dir):
        for f in os.listdir(dist_dir):
            if proj in f:
                has_dist = True
                break
    proj_info['has_dist'] = has_dist
    
    projects_status[proj] = proj_info

# 总体状态
overall = {
    'project_filter': project,
    'logs_dir': logs_dir,
    'total_logs': len(recent_logs),
    'recent_builds': recent_logs,
    'projects': projects_status,
}

print(json.dumps(overall, ensure_ascii=False, indent=2))
")
    
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "$status_data"
    else
        echo "=== Build Status ==="
        echo ""
        
        python3 -c "
import json
import sys

data = json.loads(sys.argv[1])

print('Recent Builds:')
if data['recent_builds']:
    for log in data['recent_builds']:
        status_icon = '✓' if log.get('status') == 'success' else '✗'
        print(f\"  {status_icon} {log.get('timestamp', 'unknown')} - {log.get('action', 'unknown')} [{log.get('status', 'unknown')}]\")
else:
    print('  No recent build logs found.')

print('')
print('Projects:')
for name, info in data['projects'].items():
    exists = '✓' if info['exists'] else '✗'
    makefile = '✓' if info['has_makefile'] else '✗'
    dist = '✓' if info.get('has_dist') else '✗'
    print(f\"  {name}:\")
    print(f\"    Directory: {exists}\")
    print(f\"    Makefile:  {makefile}\")
    print(f\"    Dist:      {dist}\")
" "$status_data"
    fi
}

# build logs - 查看日志
cmd_logs() {
    local project="${1:-}"
    local lines="${OML_LOG_LINES:-50}"
    local follow=false
    local format="text"

    # Initialize hooks
    build_hooks_init

    # Trigger logs access hooks
    build_hooks_trigger "$HOOK_LOGS_ACCESS" "project" "${project:-all}" 2>/dev/null || true

    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--lines)
                lines="$2"
                shift 2 || true
                ;;
            -n=*|--lines=*)
                lines="${1#*=}"
                shift
                ;;
            -f|--follow)
                follow=true
                shift
                ;;
            --format=*)
                format="${1#*=}"
                shift
                ;;
            *)
                if [[ -z "$project" ]]; then
                    project="$1"
                fi
                shift
                ;;
        esac
    done
    
    init_logs_dir
    
    local log_file
    log_file="$(get_latest_log "$project")"
    
    if [[ -z "$log_file" ]] || [[ ! -f "$log_file" ]]; then
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            echo '{"error": true, "message": "No build logs found"}'
        else
            echo "No build logs found."
            echo "Logs directory: ${BUILD_LOGS_DIR}"
        fi
        return 1
    fi
    
    if [[ "$follow" == true ]]; then
        tail -f "$log_file"
    else
        if [[ "$format" == "json" ]] || [[ "$OUTPUT_FORMAT" == "json" ]]; then
            python3 -c "
import json
import sys

log_file = sys.argv[1]
lines_count = int(sys.argv[2])

with open(log_file, 'r') as f:
    content = f.read()
    lines = content.split('\n')
    
    # 获取最后 N 行
    recent_lines = lines[-lines_count:] if len(lines) > lines_count else lines
    
    output = {
        'file': log_file,
        'total_lines': len(lines),
        'returned_lines': len(recent_lines),
        'content': '\n'.join(recent_lines)
    }
    
    print(json.dumps(output, ensure_ascii=False, indent=2))
" "$log_file" "$lines"
        else
            echo "=== Build Log: $(basename "$log_file") ==="
            echo ""
            tail -n "$lines" "$log_file"
        fi
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
    'name': 'build',
    'version': '1.0.0',
    'description': '构建代理 - 项目构建、清理、状态和日志管理',
    'commands': [
        {
            'name': 'project',
            'usage': 'build project [PROJECT] [OPTIONS]',
            'description': '构建项目',
            'options': {
                '--ver=VERSION': '目标版本 (默认：current)',
                '--pkgmgr=MANAGER': '包管理器 (默认：auto 检测)',
                '--debug': '构建调试版本',
                '-j N, --jobs=N': '并行构建数 (默认：auto)',
                '--output=FORMAT': '输出格式 (text|json)'
            },
            'examples': [
                'build project',
                'build project opencode --ver=1.1.65',
                'build project bun --debug -j4'
            ]
        },
        {
            'name': 'clean',
            'usage': 'build clean [PROJECT]',
            'description': '清理构建产物',
            'examples': [
                'build clean',
                'build clean opencode'
            ]
        },
        {
            'name': 'status',
            'usage': 'build status [PROJECT]',
            'description': '查看构建状态',
            'examples': [
                'build status',
                'build status opencode'
            ]
        },
        {
            'name': 'logs',
            'usage': 'build logs [PROJECT] [OPTIONS]',
            'description': '查看构建日志',
            'options': {
                '-n N, --lines=N': '显示行数 (默认：50)',
                '-f, --follow': '持续跟踪日志',
                '--format=FORMAT': '输出格式 (text|json)'
            },
            'examples': [
                'build logs',
                'build logs opencode -n 100',
                'build logs --follow'
            ]
        }
    ],
    'environment': {
        'OML_BUILD_VERBOSE': '详细输出 (true|false)',
        'OML_BUILD_PARALLEL': '并行构建数 (auto|N)',
        'OML_BUILD_LOG_DIR': '日志目录路径',
        'OML_OUTPUT_FORMAT': '输出格式 (text|json)'
    }
}
print(json.dumps(help_data, ensure_ascii=False, indent=2))
"
    else
        cat <<'EOF'
Build Agent - 项目构建管理

用法: build <command> [args]

命令:
  project [PROJECT] [OPTIONS]  构建项目
  clean [PROJECT]              清理构建产物
  status [PROJECT]             查看构建状态
  logs [PROJECT] [OPTIONS]     查看构建日志

构建项目 (project):
  build project                           # 构建所有项目
  build project opencode                  # 构建 opencode
  build project bun --ver=1.2.20          # 指定版本构建 bun
  build project opencode --debug -j4      # 调试模式，4 并行
  build project --pkgmgr=dpkg --ver=1.0   # 指定包管理器

清理构建 (clean):
  build clean                             # 清理所有
  build clean opencode                    # 清理 opencode

查看状态 (status):
  build status                            # 总体状态
  build status bun                        # bun 项目状态

查看日志 (logs):
  build logs                              # 最近日志
  build logs opencode -n 100              # 最近 100 行
  build logs --follow                     # 持续跟踪

环境变量:
  OML_BUILD_VERBOSE     详细输出 (true|false)
  OML_BUILD_PARALLEL    并行构建数 (auto|N)
  OML_BUILD_LOG_DIR     日志目录路径
  OML_OUTPUT_FORMAT     输出格式 (text|json)

集成项目:
  - 顶层 Makefile: ${OML_ROOT}/Makefile
  - opencode: solve-android/opencode/Makefile
  - bun: solve-android/bun/Makefile

示例:
  build project opencode --ver=1.1.65 --debug
  build clean && build project bun -j4
  build status | build logs -n 20
EOF
    fi
}

# ============================================================================
# 主入口
# ============================================================================

main() {
    # 初始化环境和 session/hooks
    init_logs_dir
    build_session_init
    build_hooks_init

    local action="${1:-help}"
    shift || true

    case "$action" in
        # 构建项目
        project|p|build)
            cmd_project "$@"
            ;;

        # 清理构建
        clean|c)
            cmd_clean "$@"
            ;;

        # 构建状态
        status|s|stat)
            cmd_status "$@"
            ;;

        # 构建日志
        logs|log|l)
            cmd_logs "$@"
            ;;

        # 帮助
        help|--help|-h)
            show_help
            ;;

        # 版本
        version|--version|-v)
            echo "build agent v1.0.0"
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
