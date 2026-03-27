#!/usr/bin/env bash
# OML 基准测试运行器
# 运行所有基准测试并生成综合报告

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="${SCRIPT_DIR}/reports"

# 配置
SAMPLE_COUNT="${SAMPLE_COUNT:-30}"
WARMUP_COUNT="${WARMUP_COUNT:-5}"
POOL_SIZE="${POOL_SIZE:-3}"
HOOK_COUNT="${HOOK_COUNT:-2}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

# 创建报告目录
mkdir -p "$REPORTS_DIR"

echo "============================================"
echo "OML 基准测试套件"
echo "============================================"
echo ""
echo "配置:"
echo "  SAMPLE_COUNT:  ${SAMPLE_COUNT}"
echo "  WARMUP_COUNT:  ${WARMUP_COUNT}"
echo "  POOL_SIZE:     ${POOL_SIZE}"
echo "  HOOK_COUNT:    ${HOOK_COUNT}"
echo "  REPORTS_DIR:   ${REPORTS_DIR}"
echo ""

# 运行 Session 基准测试
echo "============================================"
echo "1. Session 性能基准测试"
echo "============================================"
if "${SCRIPT_DIR}/benchmark-session.sh" all 2>&1 | tee "${REPORTS_DIR}/session-results.txt"; then
    log_success "Session 基准测试完成"
else
    log_error "Session 基准测试失败"
fi
echo ""

# 运行 Hooks 基准测试
echo "============================================"
echo "2. Hooks 性能基准测试"
echo "============================================"
if "${SCRIPT_DIR}/benchmark-hooks.sh" all 2>&1 | tee "${REPORTS_DIR}/hooks-results.txt"; then
    log_success "Hooks 基准测试完成"
else
    log_error "Hooks 基准测试失败"
fi
echo ""

# 运行 Pool 基准测试
echo "============================================"
echo "3. Worker 池性能基准测试"
echo "============================================"
if "${SCRIPT_DIR}/benchmark-pool.sh" all 2>&1 | tee "${REPORTS_DIR}/pool-results.txt"; then
    log_success "Pool 基准测试完成"
else
    log_error "Pool 基准测试失败"
fi
echo ""

# 运行 System 基准测试
echo "============================================"
echo "4. 系统整体性能基准测试"
echo "============================================"
if "${SCRIPT_DIR}/benchmark-system.sh" all 2>&1 | tee "${REPORTS_DIR}/system-results.txt"; then
    log_success "System 基准测试完成"
else
    log_error "System 基准测试失败"
fi
echo ""

# 生成综合报告
echo "============================================"
echo "生成综合报告"
echo "============================================"

# 提取关键指标生成摘要
python3 - "${REPORTS_DIR}" <<'PY'
import os
import json
from datetime import datetime

reports_dir = '${REPORTS_DIR}'
summary = {
    'generated_at': datetime.utcnow().isoformat() + 'Z',
    'tests': {}
}

# 解析各个测试结果
test_files = {
    'session': 'session-results.txt',
    'hooks': 'hooks-results.txt',
    'pool': 'pool-results.txt',
    'system': 'system-results.txt'
}

for test_name, filename in test_files.items():
    filepath = os.path.join(reports_dir, filename)
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            content = f.read()
            # 提取关键指标
            metrics = {}
            for line in content.split('\n'):
                if 'Avg:' in line:
                    parts = line.split('Avg:')
                    if len(parts) > 1:
                        try:
                            metrics['avg_ms'] = float(parts[1].strip().split()[0])
                        except:
                            pass
                if 'Throughput:' in line:
                    parts = line.split('Throughput:')
                    if len(parts) > 1:
                        try:
                            metrics['throughput'] = parts[1].strip()
                        except:
                            pass
            summary['tests'][test_name] = metrics

# 保存摘要
summary_file = os.path.join(reports_dir, 'summary.json')
with open(summary_file, 'w') as f:
    json.dump(summary, f, indent=2)

print(f"Summary saved to: {summary_file}")
PY

echo ""
echo "============================================"
echo "基准测试完成"
echo "============================================"
echo ""
echo "报告位置:"
echo "  - ${REPORTS_DIR}/session-results.txt"
echo "  - ${REPORTS_DIR}/hooks-results.txt"
echo "  - ${REPORTS_DIR}/pool-results.txt"
echo "  - ${REPORTS_DIR}/system-results.txt"
echo "  - ${REPORTS_DIR}/summary.json"
echo ""
echo "详细文档:"
echo "  - ${REPORTS_DIR}/BENCHMARK-REPORT.md"
echo "  - ${REPORTS_DIR}/PERFORMANCE-ANALYSIS.md"
echo ""
