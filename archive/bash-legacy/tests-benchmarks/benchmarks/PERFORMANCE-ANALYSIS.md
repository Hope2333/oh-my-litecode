# OML 性能分析与优化指南

**版本:** 1.0  
**最后更新:** 2026-03-22

---

## 目录

1. [概述](#概述)
2. [基准测试套件](#基准测试套件)
3. [性能分析方法](#性能分析方法)
4. [已知瓶颈](#已知瓶颈)
5. [优化策略](#优化策略)
6. [最佳实践](#最佳实践)
7. [故障排查](#故障排查)

---

## 概述

本文档提供 Oh-My-Litecode (OML) 系统的性能分析方法和优化指南。通过系统的性能测试和分析，帮助开发者识别瓶颈并实施有效的优化措施。

### 性能目标

| 操作 | 目标延迟 | 当前性能 | 状态 |
|------|----------|----------|------|
| Session Create | <100ms | 177ms | ❌ |
| Session Read | <50ms | 42ms | ✅ |
| Session Write | <100ms | 194ms | ❌ |
| Session Delete | <50ms | 81ms | ❌ |
| Worker Create | <100ms | 146ms | ❌ |
| Task Assign | <100ms | 234ms | ❌ |

---

## 基准测试套件

### 测试脚本位置

```
benchmarks/
├── benchmark-session.sh    # Session 性能基准
├── benchmark-hooks.sh      # Hooks 性能基准
├── benchmark-pool.sh       # Worker 池性能基准
└── benchmark-system.sh     # 系统整体基准
```

### 运行基准测试

```bash
# 运行所有 Session 测试
./benchmarks/benchmark-session.sh all

# 运行特定测试
./benchmarks/benchmark-session.sh create
./benchmarks/benchmark-session.sh read
./benchmarks/benchmark-session.sh write
./benchmarks/benchmark-session.sh delete

# 自定义参数
SAMPLE_COUNT=100 WARMUP_COUNT=10 ./benchmarks/benchmark-session.sh all

# 生成报告
./benchmarks/benchmark-session.sh all report.json
./benchmarks/benchmark-session.sh all report.md
```

### 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| SAMPLE_COUNT | 100 | 测试样本数量 |
| WARMUP_COUNT | 10 | 预热次数 |
| POOL_SIZE | 5 | Worker 池大小 |
| HOOK_COUNT | 5 | Hook 数量 |
| OUTPUT_FORMAT | text | 输出格式 (text/json/markdown) |

---

## 性能分析方法

### 1. 时间测量

使用纳秒级时间戳进行精确测量：

```bash
get_timestamp_ns() {
    python3 -c "import time; print(int(time.time_ns()))"
}

start_ns=$(get_timestamp_ns)
# ... 执行操作 ...
end_ns=$(get_timestamp_ns)
duration_ms=$(( (end_ns - start_ns) / 1000000 ))
```

### 2. 统计分析

计算关键统计指标：

- **平均值 (Avg)**: 反映整体性能水平
- **最小值 (Min)**: 最佳情况性能
- **最大值 (Max)**: 最差情况性能
- **P50**: 中位数，50% 请求的延迟
- **P95**: 95% 请求的延迟上限
- **P99**: 99% 请求的延迟上限

### 3. 性能 profiling

使用 bash 内置工具进行 profiling：

```bash
# 启用执行跟踪
set -x

# 测量命令执行时间
time ./oml session create test-session

# 分析脚本性能
bash -x ./benchmarks/benchmark-session.sh 2>&1 | grep -E "^\+" | sort | uniq -c | sort -rn | head -20
```

---

## 已知瓶颈

### 1. JSON 文件 I/O

**问题描述:**
每次 Session 操作都涉及完整的 JSON 文件读取和写入，导致较高的 I/O 开销。

**影响范围:**
- Session Create: ~177ms
- Session Write: ~194ms
- Session Delete: ~81ms

**根本原因:**
```python
# 当前实现 - 每次更新都重写整个文件
with open(data_path, 'r') as f:
    data = json.load(f)
data[key] = value
with open(data_path, 'w') as f:
    json.dump(data, f, indent=2)
```

### 2. 索引同步开销

**问题描述:**
每次 Session 操作后都同步更新索引文件，增加了额外的 I/O。

**影响范围:**
所有 Session 操作增加约 20-30ms 开销

### 3. Python 子进程调用

**问题描述:**
频繁调用 `python3 -c` 进行 JSON 处理，每次调用都有进程启动开销。

**影响范围:**
每次调用增加约 50-100ms 开销

### 4. 锁竞争

**问题描述:**
并发访问 Session 文件时存在锁竞争。

**影响范围:**
高并发场景下性能下降 30-50%

---

## 优化策略

### 策略 1: 内存缓存层

**目标:** 减少文件 I/O 次数

**实现方案:**
```bash
# 声明关联数组作为缓存
declare -A SESSION_CACHE=()
declare -A SESSION_CACHE_DIRTY=()

# 读取时先检查缓存
oml_session_read_cached() {
    local session_id="$1"
    if [[ -n "${SESSION_CACHE[$session_id]:-}" ]]; then
        echo "${SESSION_CACHE[$session_id]}"
        return 0
    fi
    
    # 从文件读取并缓存
    local data
    data=$(cat "${OML_SESSIONS_DIR}/data/${session_id}.json")
    SESSION_CACHE[$session_id]="$data"
    echo "$data"
}

# 写入时标记为脏数据
oml_session_update_cached() {
    local session_id="$1"
    local update="$2"
    SESSION_CACHE[$session_id]="$update"
    SESSION_CACHE_DIRTY[$session_id]=1
}

# 定期刷新脏数据
oml_session_flush_cache() {
    for session_id in "${!SESSION_CACHE_DIRTY[@]}"; do
        echo "${SESSION_CACHE[$session_id]}" > "${OML_SESSIONS_DIR}/data/${session_id}.json"
        unset SESSION_CACHE_DIRTY[$session_id]
    done
}
```

**预期效果:** 减少 50-70% 的文件 I/O

### 策略 2: 批量索引更新

**目标:** 减少索引文件写入频率

**实现方案:**
```bash
# 批量更新索引
declare -a INDEX_PENDING_UPDATES=()

oml_session_update_index_pending() {
    local session_id="$1"
    local update="$2"
    INDEX_PENDING_UPDATES+=("${session_id}:${update}")
}

oml_session_flush_index() {
    if [[ ${#INDEX_PENDING_UPDATES[@]} -eq 0 ]]; then
        return 0
    fi
    
    # 一次性处理所有待更新
    python3 - "${OML_SESSIONS_INDEX}" "${INDEX_PENDING_UPDATES[@]}" <<'PY'
import json
import sys

index_path = sys.argv[1]
updates = sys.argv[2:]

with open(index_path, 'r') as f:
    index = json.load(f)

for update in updates:
    session_id, data = update.split(':', 1)
    # 处理更新...

with open(index_path, 'w') as f:
    json.dump(index, f, indent=2)
PY
    
    INDEX_PENDING_UPDATES=()
}
```

**预期效果:** 减少 80-90% 的索引写入

### 策略 3: 使用 jq 替代 Python

**目标:** 减少进程启动开销

**实现方案:**
```bash
# 使用 jq 进行 JSON 处理
oml_session_get_jq() {
    local session_id="$1"
    local key="$2"
    jq -r ".${key}" "${OML_SESSIONS_DIR}/data/${session_id}.json"
}

oml_session_update_jq() {
    local session_id="$1"
    local key="$2"
    local value="$3"
    local tmp_file
    tmp_file=$(mktemp)
    jq ".${key} = ${value}" "${OML_SESSIONS_DIR}/data/${session_id}.json" > "$tmp_file"
    mv "$tmp_file" "${OML_SESSIONS_DIR}/data/${session_id}.json"
}
```

**预期效果:** 减少 30-50% 的处理时间

### 策略 4: 异步持久化

**目标:** 将同步 I/O 转为异步

**实现方案:**
```bash
# 使用后台进程进行异步写入
oml_session_async_write() {
    local session_id="$1"
    local data="$2"
    
    # 写入队列
    echo "${session_id}:${data}" >> "${OML_SESSIONS_DIR}/queue/write_queue"
    
    # 触发异步处理
    if [[ ! -f "${OML_SESSIONS_DIR}/queue/processor.pid" ]]; then
        oml_session_queue_processor &
        echo $! > "${OML_SESSIONS_DIR}/queue/processor.pid"
    fi
}

oml_session_queue_processor() {
    while true; do
        if [[ -s "${OML_SESSIONS_DIR}/queue/write_queue" ]]; then
            # 批量处理队列
            while IFS=: read -r session_id data; do
                echo "$data" > "${OML_SESSIONS_DIR}/data/${session_id}.json"
            done < "${OML_SESSIONS_DIR}/queue/write_queue"
            > "${OML_SESSIONS_DIR}/queue/write_queue"
        fi
        sleep 1
    done
}
```

**预期效果:** 响应时间减少 60-80%

---

## 最佳实践

### 1. Session 管理

```bash
# ✅ 推荐：批量操作
oml_session_begin_batch
oml_session_set "$session_id" "key1" "value1"
oml_session_set "$session_id" "key2" "value2"
oml_session_set "$session_id" "key3" "value3"
oml_session_end_batch

# ❌ 避免：单独操作
oml_session_set "$session_id" "key1" "value1"
oml_session_set "$session_id" "key2" "value2"
oml_session_set "$session_id" "key3" "value3"
```

### 2. Worker 池使用

```bash
# ✅ 推荐：预创建 Worker
oml_pool_init 5 10  # 预创建 5 个 Worker

# ❌ 避免：按需创建
for task in "${tasks[@]}"; do
    oml_pool_create_worker
    oml_pool_assign_task "$task"
done
```

### 3. Hooks 注册

```bash
# ✅ 推荐：批量注册
oml_hooks_batch_register hooks-config.json

# ❌ 避免：逐个注册
oml_hook_register hook1 event1 handler1
oml_hook_register hook2 event2 handler2
```

### 4. 并发控制

```bash
# ✅ 推荐：使用文件锁
flock -x "${OML_SESSIONS_DIR}/lock" -c "
    oml_session_update \"$session_id\" \"$data\"
"

# ❌ 避免：无锁并发
oml_session_update "$session_id" "$data" &
oml_session_update "$session_id" "$data" &
```

---

## 故障排查

### 性能问题诊断流程

```
1. 运行基准测试确定问题范围
   ./benchmarks/benchmark-system.sh all

2. 检查资源使用
   - 内存使用：free -h
   - 磁盘 I/O: iostat -x 1
   - CPU 使用：top -bn1

3. 分析日志
   tail -f ~/.oml/logs/*.log

4. 启用详细日志
   export OML_LOG_LEVEL=debug
```

### 常见问题

#### 问题 1: Session 操作缓慢

**症状:** Session Create/Write 操作超过 500ms

**排查步骤:**
```bash
# 检查磁盘 I/O
iostat -x 1

# 检查文件大小
du -sh ~/.oml/sessions/data/*

# 检查索引大小
wc -l ~/.oml/sessions/index.json
```

**解决方案:**
- 清理旧 Session
- 重建索引
- 启用缓存

#### 问题 2: Worker 池响应慢

**症状:** Task Assignment 延迟高

**排查步骤:**
```bash
# 检查 Worker 状态
oml_pool_list_workers

# 检查池统计
oml_pool_stats
```

**解决方案:**
- 增加 Worker 数量
- 优化任务分配算法

#### 问题 3: Hooks 触发延迟

**症状:** Hook 执行时间过长

**排查步骤:**
```bash
# 检查 Hook 数量
oml_hooks_registry_stats

# 检查 Handler 执行时间
export OML_HOOKS_LOG_LEVEL=debug
```

**解决方案:**
- 优化 Handler 脚本
- 减少 Hook 数量
- 使用并行执行

---

## 附录

### A. 性能监控脚本

```bash
#!/usr/bin/env bash
# OML 性能监控脚本

monitor_oml_performance() {
    echo "=== OML Performance Monitor ==="
    echo ""
    
    # Session 统计
    echo "Sessions:"
    oml_session_stats 2>/dev/null || echo "  N/A"
    echo ""
    
    # Pool 统计
    echo "Worker Pool:"
    oml_pool_stats 2>/dev/null || echo "  N/A"
    echo ""
    
    # Hooks 统计
    echo "Hooks:"
    oml_hooks_registry_stats 2>/dev/null || echo "  N/A"
}

monitor_oml_performance
```

### B. 性能测试清单

- [ ] 运行基准测试套件
- [ ] 记录基线性能数据
- [ ] 识别性能瓶颈
- [ ] 实施优化措施
- [ ] 验证优化效果
- [ ] 更新性能文档

---

*本文档由 OML 性能分析团队维护*
