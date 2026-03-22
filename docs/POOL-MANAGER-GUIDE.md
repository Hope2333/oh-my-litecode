# Worker 池管理模块使用指南

**版本**: 0.1.0  
**状态**: 核心功能完成

## 📋 目录

1. [概述](#概述)
2. [快速开始](#快速开始)
3. [模块详解](#模块详解)
4. [使用示例](#使用示例)
5. [API 参考](#api-参考)
6. [最佳实践](#最佳实践)

---

## 概述

Worker 池管理模块提供了一套完整的任务调度与资源管理系统，包含以下核心组件：

| 模块 | 文件 | 功能 |
|------|------|------|
| Pool Manager | `core/pool-manager.sh` | Worker 池生命周期管理与动态扩缩容 |
| Concurrency | `core/pool-concurrency.sh` | 令牌桶算法并发控制 |
| Queue | `core/pool-queue.sh` | MLFQ 多级反馈队列调度 |
| Monitor | `core/pool-monitor.sh` | 系统资源监控与告警 |
| Recovery | `core/pool-recovery.sh` | 故障检测与自动恢复 |

### 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                      Task Registry                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Pool Manager (核心)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Workers    │  │   Scaling   │  │   Task Assignment   │  │
│  │  Lifecycle  │  │  Auto-scale │  │   Status Tracking   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   Concurrency   │ │     Queue       │ │    Monitor      │
│  Token Bucket   │ │   MLFQ Scheduler│ │ Resource Stats  │
│  Rate Limiting  │ │ Priority Queue  │ │ Health Checks   │
│  Circuit Breaker│ │ Task Dispatch   │ │ Alerts          │
└─────────────────┘ └─────────────────┘ └─────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Recovery Manager                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Failure    │  │  Checkpoint │  │   Auto-Recovery     │  │
│  │  Detection  │  │   Recovery  │  │   Circuit Breaker   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 快速开始

### 1. 初始化所有模块

```bash
# 加载核心模块
source core/pool-manager.sh
source core/pool-concurrency.sh
source core/pool-queue.sh
source core/pool-monitor.sh
source core/pool-recovery.sh

# 初始化 Worker 池 (最小 2 个，最大 10 个)
oml_pool_init 2 10

# 初始化令牌桶 (容量 20, 每秒补充 10 个)
oml_bucket_init "api" 20 10

# 初始化并发限制器 (最大并发 5, 队列大小 50)
oml_concurrency_init 5 50

# 初始化 MLFQ 队列 (3 级队列，时间片 100ms)
oml_mlfq_init 3 100 5 100

# 初始化监控系统
oml_monitor_init

# 初始化恢复系统
oml_recovery_init
```

### 2. 基本使用

```bash
# 创建 Worker
worker_id=$(oml_pool_create_worker)
echo "Created worker: $worker_id"

# 添加任务到队列
task_id=$(oml_queue_enqueue '{"cmd": "echo hello"}' 0)
echo "Enqueued task: $task_id"

# 从队列取出任务并分配
task_json=$(oml_queue_dequeue)
task_id=$(echo "$task_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['task_id'])")
oml_pool_assign_task "$task_id"

# 查看池状态
oml_pool_stats
```

---

## 模块详解

### 1. Pool Manager - 池管理核心

#### 功能特性
- Worker 生命周期管理（创建、启动、停止、删除）
- 动态扩缩容（手动/自动）
- 任务分配与状态跟踪
- 与 Task Registry 集成

#### 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `min_workers` | 1 | 最小 Worker 数量 |
| `max_workers` | 10 | 最大 Worker 数量 |
| `idle_timeout` | 300s | 空闲超时（秒） |
| `task_timeout` | 600s | 任务超时（秒） |

#### Worker 状态

```
idle      - 空闲，可接受任务
busy      - 忙碌，正在执行任务
stopped   - 已停止
failed    - 故障
```

### 2. Concurrency - 并发控制

#### 令牌桶算法

```
     令牌生成
        │
        ▼
┌───────────────┐
│   Token       │  容量：100 令牌
│   Bucket      │  补充率：10 令牌/秒
└───────────────┘
        │
        ▼ 消费令牌
     任务执行
```

#### 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `capacity` | 10 | 桶容量（最大令牌数） |
| `refill_rate` | 5/s | 每秒补充令牌数 |
| `min_tokens` | 1 | 执行所需最小令牌数 |

#### 熔断器状态

```
closed      - 正常，允许请求
open        - 熔断，拒绝请求
half-open   - 半开，尝试恢复
```

### 3. Queue - MLFQ 调度

#### 多级反馈队列

```
优先级 0 (高)  ──► 时间片 100ms  ──► 降级 ──┐
    ▲                                      │
    │ 提升                                 ▼
优先级 1 (中)  ──► 时间片 200ms  ──► 降级 ──┤
    ▲                                      │
    │ 提升                                 ▼
优先级 2 (低)  ──► 时间片 400ms ───────────┘
```

#### 调度规则
1. 高优先级优先
2. 同优先级 FCFS（先来先服务）
3. 长时间运行任务降级
4. 定期优先级提升（防止饥饿）

### 4. Monitor - 资源监控

#### 监控指标

| 指标 | 警告阈值 | 严重阈值 |
|------|---------|---------|
| CPU 使用率 | 70% | 90% |
| 内存使用率 | 70% | 90% |
| 磁盘使用率 | 80% | 95% |

#### 告警级别
- `OK` - 正常
- `WARNING` - 警告
- `CRITICAL` - 严重

### 5. Recovery - 故障恢复

#### 故障类型

| 类型 | 说明 |
|------|------|
| `timeout` | 任务超时 |
| `crash` | Worker 崩溃 |
| `oom` | 内存溢出 |
| `health_check` | 健康检查失败 |
| `dependency` | 依赖故障 |

#### 恢复策略

| 策略 | 说明 |
|------|------|
| `retry` | 重试执行 |
| `restart` | 重启 Worker |
| `failover` | 故障转移 |
| `manual` | 手动处理 |

---

## 使用示例

### 示例 1: 基本任务执行

```bash
#!/usr/bin/env bash
# 示例：基本任务执行流程

source core/pool-manager.sh
source core/pool-queue.sh

# 初始化
oml_pool_init 2 5
oml_mlfq_init 3 100 5 100

# 创建 Worker
for i in {1..3}; do
    worker_id=$(oml_pool_create_worker)
    echo "Created worker: $worker_id"
done

# 添加任务
for i in {1..5}; do
    priority=$((i % 3))  # 循环使用 0,1,2 优先级
    task_id=$(oml_queue_enqueue "{\"task\": $i, \"data\": \"test-$i\"}" $priority)
    echo "Enqueued task $task_id with priority $priority"
done

# 处理任务
while true; do
    task_json=$(oml_queue_dequeue)
    [[ -z "$task_json" ]] && break

    task_id=$(echo "$task_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['task_id'])")

    # 分配给空闲 Worker
    worker=$(oml_pool_assign_task "$task_id" "$task_json")

    if [[ -n "$worker" ]]; then
        echo "Task $task_id assigned to $worker"
        # 模拟任务执行
        sleep 1
        oml_pool_complete_task "$task_id" '{"status": "done"}' "true"
        oml_queue_complete "$task_id"
    else
        echo "No available worker for task $task_id"
        break
    fi
done

# 查看统计
oml_pool_stats
oml_queue_stats
```

### 示例 2: 并发控制

```bash
#!/usr/bin/env bash
# 示例：使用令牌桶进行 API 限流

source core/pool-concurrency.sh

# 初始化令牌桶 (API 限流：100 次/分钟)
oml_bucket_init "api-limit" 100 1.67  # 100/60 ≈ 1.67/s

# 初始化并发限制器
oml_concurrency_init 10 50  # 最大 10 并发，队列 50

# 模拟 API 请求
for i in {1..150}; do
    # 尝试获取令牌
    result=$(oml_bucket_consume "api-limit" 1 "true" 30)

    if [[ "$result" == success:* ]]; then
        # 获取执行槽位
        slot=$(oml_concurrency_acquire 30 "request-$i")

        if [[ "$slot" == acquired:* ]]; then
            echo "Request $i: executing..."
            # 模拟 API 调用
            sleep 0.1
            oml_concurrency_release
        else
            echo "Request $i: queued (${slot})"
        fi
    else
        echo "Request $i: rate limited (${result})"
        sleep 1
    fi
done

# 查看状态
oml_bucket_status "api-limit"
oml_concurrency_status
```

### 示例 3: 自动扩缩容

```bash
#!/usr/bin/env bash
# 示例：基于负载的自动扩缩容

source core/pool-manager.sh
source core/pool-monitor.sh

# 初始化
oml_pool_init 2 10
oml_monitor_init

# 模拟负载变化
simulate_load() {
    local intensity=$1

    for ((i=0; i<intensity; i++)); do
        worker_id=$(oml_pool_get_worker "$(oml_pool_list_workers idle | head -1 | awk '{print $1}')" 2>/dev/null)
        if [[ -n "$worker_id" ]]; then
            task_id="task-$(date +%s%N)-$i"
            oml_pool_assign_task "$task_id" '{"load": true}'
        fi
    done
}

# 主循环
for cycle in {1..5}; do
    echo "=== Cycle $cycle ==="

    # 模拟不同负载
    case $cycle in
        1) simulate_load 2 ;;   # 低负载
        2) simulate_load 5 ;;   # 中负载
        3) simulate_load 8 ;;   # 高负载
        4) simulate_load 3 ;;   # 降低负载
        5) simulate_load 1 ;;   # 低负载
    esac

    # 自动扩缩容（目标利用率 70%）
    oml_pool_autoscale 70

    # 采样监控
    oml_monitor_sample

    # 显示状态
    oml_pool_stats | grep -E "(Total|Idle|Busy|Utilization)"

    sleep 2
done
```

### 示例 4: 故障恢复

```bash
#!/usr/bin/env bash
# 示例：故障检测与自动恢复

source core/pool-manager.sh
source core/pool-recovery.sh
source core/pool-monitor.sh

# 初始化
oml_pool_init 2 5
oml_recovery_init 10 3 5
oml_monitor_init

# 创建 Worker 并注册监控
worker_id=$(oml_pool_create_worker)
oml_monitor_register_worker "$worker_id" "$$"

# 创建检查点
checkpoint_id=$(oml_recovery_checkpoint_create "main-task" '{"progress": 0, "step": "init"}')
echo "Created checkpoint: $checkpoint_id"

# 模拟任务执行与故障
for step in {1..5}; do
    echo "=== Step $step ==="

    # 更新检查点
    om_recovery_checkpoint_create "main-task" "{\"progress\": $((step*20)), \"step\": $step}"

    # 模拟故障（在 step 3）
    if [[ $step -eq 3 ]]; then
        echo "Simulating failure..."

        # 报告故障
        failure_id=$(oml_recovery_report_failure "$worker_id" "timeout" '{"step": 3}')
        echo "Reported failure: $failure_id"

        # 启动恢复
        recovery_id=$(oml_recovery_start "$failure_id" "retry")
        echo "Started recovery: $recovery_id"

        # 执行恢复
        oml_recovery_execute "$recovery_id"

        # 恢复检查点
        checkpoint_data=$(oml_recovery_checkpoint_restore "$checkpoint_id")
        echo "Restored checkpoint: $checkpoint_data"

        # 完成恢复
        oml_recovery_complete "$recovery_id" "true" '{"recovered": true}'
    fi

    sleep 1
done

# 查看恢复统计
oml_recovery_stats
oml_recovery_failure_history 10
```

### 示例 5: 完整监控仪表板

```bash
#!/usr/bin/env bash
# 示例：监控仪表板

source core/pool-manager.sh
source core/pool-monitor.sh
source core/pool-recovery.sh

display_dashboard() {
    clear
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              OML Worker Pool Dashboard                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    # 资源使用
    echo "┌─ Resource Usage ─────────────────────────────────────────┐"
    local sample=$(oml_monitor_sample)
    local cpu=$(echo "$sample" | python3 -c "import json,sys; print(json.load(sys.stdin)['cpu'])")
    local mem=$(echo "$sample" | python3 -c "import json,sys; print(json.load(sys.stdin)['memory'])")
    printf "│ CPU: %-6s%%  │  Memory: %-6s%%                              │\n" "$cpu" "$mem"
    echo "└────────────────────────────────────────────────────────────┘"
    echo ""

    # Worker 池状态
    echo "┌─ Worker Pool ────────────────────────────────────────────┐"
    oml_pool_stats 2>/dev/null | grep -E "(Total|Idle|Busy|Utilization)" | head -4 | while read line; do
        printf "│ %-60s │\n" "$line"
    done
    echo "└────────────────────────────────────────────────────────────┘"
    echo ""

    # 告警
    echo "┌─ Active Alerts ──────────────────────────────────────────┐"
    local alerts=$(oml_monitor_get_alerts)
    local count=$(echo "$alerts" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
    if [[ "$count" -eq 0 ]]; then
        echo "│ No active alerts                                          │"
    else
        echo "$alerts" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for alert in data['active_alerts']:
    print(f\"│ [{alert['level'].upper():7}] {alert['type']}: {alert['value']}%\".ljust(62) + '│')
"
    fi
    echo "└────────────────────────────────────────────────────────────┘"
}

# 持续显示
while true; do
    display_dashboard
    sleep 5
done
```

---

## API 参考

### Pool Manager

| 命令 | 参数 | 说明 |
|------|------|------|
| `oml_pool_init` | `[min] [max]` | 初始化 Worker 池 |
| `oml_pool_create_worker` | - | 创建新 Worker |
| `oml_pool_start_worker` | `<id> [script]` | 启动 Worker |
| `oml_pool_stop_worker` | `<id> [--force]` | 停止 Worker |
| `oml_pool_scale_up` | `[count]` | 扩容 |
| `oml_pool_scale_down` | `[count]` | 缩容 |
| `oml_pool_autoscale` | `[target%]` | 自动扩缩容 |
| `oml_pool_assign_task` | `<id> [data] [worker]` | 分配任务 |
| `oml_pool_complete_task` | `<id> [result] [success]` | 完成任务 |
| `oml_pool_list_workers` | `[status]` | 列出 Worker |
| `oml_pool_stats` | - | 显示统计 |

### Concurrency

| 命令 | 参数 | 说明 |
|------|------|------|
| `oml_bucket_init` | `[id] [capacity] [rate] [min]` | 初始化令牌桶 |
| `oml_bucket_consume` | `[id] [tokens] [--wait] [--timeout]` | 消费令牌 |
| `oml_bucket_status` | `[id]` | 查看桶状态 |
| `oml_concurrency_init` | `[limit] [queue_size]` | 初始化并发限制器 |
| `oml_concurrency_acquire` | `[timeout] [task_id]` | 获取槽位 |
| `oml_concurrency_release` | `[slot_id]` | 释放槽位 |

### Queue

| 命令 | 参数 | 说明 |
|------|------|------|
| `oml_mlfq_init` | `[queues] [slice] [boost] [size]` | 初始化 MLFQ |
| `oml_queue_enqueue` | `<data> [priority] [deadline] [tags]` | 入队 |
| `oml_queue_dequeue` | `[check_deadline]` | 出队 |
| `oml_queue_complete` | `<id> [result] [success]` | 完成任务 |
| `oml_queue_promote` | `<id>` | 提升优先级 |
| `oml_queue_demote` | `<id>` | 降低优先级 |
| `oml_queue_boost` | `[--force]` | 优先级提升 |
| `oml_queue_list` | `[queue] [status] [limit]` | 列出任务 |

### Monitor

| 命令 | 参数 | 说明 |
|------|------|------|
| `oml_monitor_init` | `[cpu_w] [cpu_c] [mem_w] [mem_c]` | 初始化监控 |
| `oml_monitor_sample` | - | 采集样本 |
| `oml_monitor_watch` | `[interval] [count]` | 连续采样 |
| `oml_monitor_check` | - | 检查阈值 |
| `oml_monitor_status` | - | 显示状态 |
| `oml_monitor_alerts` | - | 获取告警 |
| `oml_monitor_register_worker` | `<id> [pid]` | 注册 Worker |
| `oml_monitor_report` | `[period]` | 生成报告 |

### Recovery

| 命令 | 参数 | 说明 |
|------|------|------|
| `oml_recovery_init` | `[interval] [retries] [cb_threshold]` | 初始化恢复 |
| `oml_recovery_report_failure` | `<worker> [type] [details]` | 报告故障 |
| `oml_recovery_start` | `<failure_id> [strategy]` | 启动恢复 |
| `oml_recovery_execute` | `<recovery_id>` | 执行恢复 |
| `oml_recovery_complete` | `<id> [success] [result]` | 完成恢复 |
| `oml_recovery_checkpoint_create` | `<task> [data]` | 创建检查点 |
| `oml_recovery_circuit_breaker_status` | `[worker]` | 熔断器状态 |

---

## 最佳实践

### 1. Worker 池配置

```bash
# 根据负载特性配置
# CPU 密集型：较少 Worker，接近 CPU 核心数
oml_pool_init $(nproc) $(( $(nproc) * 2 ))

# I/O 密集型：较多 Worker
oml_pool_init 10 50

# 混合型：中等数量
oml_pool_init 5 20
```

### 2. 令牌桶配置

```bash
# API 限流：根据服务容量
oml_bucket_init "api" 1000 100  # 1000 容量，100/s 补充

# 数据库连接：限制并发查询
oml_bucket_init "db" 50 10 1    # 最多 50 并发，10/s 补充

# 文件操作：限制 I/O
oml_bucket_init "io" 20 5 1     # 最多 20 并发，5/s 补充
```

### 3. MLFQ 配置

```bash
# 短任务优先
oml_mlfq_init 4 50 10 500  # 4 级队列，50ms 基础时间片

# 长任务处理
oml_mlfq_init 3 200 30 1000  # 3 级队列，200ms 基础时间片
```

### 4. 监控告警

```bash
# 生产环境：严格阈值
oml_monitor_init 60 85 60 85

# 开发环境：宽松阈值
oml_monitor_init 80 95 80 95
```

### 5. 故障恢复

```bash
# 关键任务：多次重试，快速恢复
oml_recovery_init 5 5 3  # 5s 检测，5 次重试，3 次熔断

# 非关键任务：少次重试
oml_recovery_init 30 2 10  # 30s 检测，2 次重试，10 次熔断
```

### 6. 检查点策略

```bash
# 长任务：定期保存检查点
for step in {1..100}; do
    # 执行任务...

    # 每 10 步保存一次
    if (( step % 10 == 0 )); then
        oml_recovery_checkpoint_create "long-task" "{\"step\": $step}"
    fi
done
```

---

## 故障排查

### 常见问题

1. **Worker 无法创建**
   ```bash
   # 检查是否达到最大数量
   oml_pool_stats | grep Total

   # 检查系统资源
   oml_monitor_sample
   ```

2. **任务排队过长**
   ```bash
   # 查看队列深度
   oml_queue stats

   # 扩容 Worker
   oml_pool_scale_up 5
   ```

3. **频繁触发熔断**
   ```bash
   # 查看熔断器状态
   oml_recovery_circuit_breaker-status

   # 调整阈值
   oml_recovery_init 10 5 10  # 增加熔断阈值
   ```

4. **内存告警**
   ```bash
   # 查看内存使用
   oml_monitor memory

   # 缩容 Worker
   oml_pool_scale_down 3
   ```

---

## 与 Task Registry 集成

Worker 池模块自动与 Task Registry 集成：

```bash
# 任务自动注册到 Task Registry
oml_pool_assign_task "task-123" '{"cmd": "test"}'

# 在 Task Registry 中查看
oml tasks list running
```

---

**最后更新**: 2024-03-22  
**维护者**: OML Team
