# OML 基准测试套件

性能基准测试套件用于评估 Oh-My-Litecode (OML) 系统各组件的性能特性。

## 快速开始

```bash
# 运行所有基准测试
./benchmarks/run-all-benchmarks.sh

# 运行单个组件测试
./benchmarks/benchmark-session.sh all
./benchmarks/benchmark-hooks.sh all
./benchmarks/benchmark-pool.sh all
./benchmarks/benchmark-system.sh all
```

## 测试脚本

| 脚本 | 说明 | 测试内容 |
|------|------|----------|
| `benchmark-session.sh` | Session 性能基准 | 创建/读取/写入/删除/消息操作 |
| `benchmark-hooks.sh` | Hooks 性能基准 | 触发延迟/注册性能/处理器性能 |
| `benchmark-pool.sh` | Worker 池性能基准 | 创建/调度/任务分配/自动扩缩容 |
| `benchmark-system.sh` | 系统整体基准 | 端到端工作流/吞吐量/压力测试 |

## 配置参数

```bash
# 环境变量配置
SAMPLE_COUNT=100     # 测试样本数量 (默认：100)
WARMUP_COUNT=10      # 预热次数 (默认：10)
POOL_SIZE=5          # Worker 池大小 (默认：5)
HOOK_COUNT=5         # Hook 数量 (默认：5)
OUTPUT_FORMAT=text   # 输出格式：text/json/markdown
```

## 使用示例

### Session 基准测试

```bash
# 运行所有 Session 测试
./benchmarks/benchmark-session.sh all

# 运行特定测试
./benchmarks/benchmark-session.sh create   # 创建性能
./benchmarks/benchmark-session.sh read     # 读取性能
./benchmarks/benchmark-session.sh write    # 写入性能
./benchmarks/benchmark-session.sh delete   # 删除性能
./benchmarks/benchmark-session.sh messages # 消息操作性能

# 生成 JSON 报告
./benchmarks/benchmark-session.sh all report.json

# 生成 Markdown 报告
./benchmarks/benchmark-session.sh all report.md
```

### Hooks 基准测试

```bash
# 运行所有 Hooks 测试
./benchmarks/benchmark-hooks.sh all

# 运行特定测试
./benchmarks/benchmark-hooks.sh single        # 单 Hook 延迟
./benchmarks/benchmark-hooks.sh multi         # 多 Hook 吞吐量
./benchmarks/benchmark-hooks.sh handler       # 处理器性能对比
./benchmarks/benchmark-hooks.sh registration  # 注册性能
./benchmarks/benchmark-hooks.sh chain         # Pre/Post 链性能
```

### Worker 池基准测试

```bash
# 运行所有 Pool 测试
./benchmarks/benchmark-pool.sh all

# 运行特定测试
./benchmarks/benchmark-pool.sh creation      # Worker 创建
./benchmarks/benchmark-pool.sh assignment    # 任务分配
./benchmarks/benchmark-pool.sh scheduling    # 调度延迟
./benchmarks/benchmark-pool.sh autoscaling   # 自动扩缩容
./benchmarks/benchmark-pool.sh concurrent    # 并发任务
./benchmarks/benchmark-pool.sh queries       # 状态查询
```

### 系统基准测试

```bash
# 运行所有系统测试
./benchmarks/benchmark-system.sh all

# 运行特定测试
./benchmarks/benchmark-system.sh e2e            # 端到端工作流
./benchmarks/benchmark-system.sh session-hooks  # Session+Hooks 集成
./benchmarks/benchmark-system.sh session-pool   # Session+Pool 集成
./benchmarks/benchmark-system.sh throughput     # 系统吞吐量
./benchmarks/benchmark-system.sh resources      # 资源使用
./benchmarks/benchmark-system.sh stress         # 压力测试
```

## 输出格式

### 文本输出 (默认)

```
=== Session Create Benchmark ===
  Samples:    100
  Warmup:     10
  Avg:        177.44 ms
  Min:        159.79 ms
  Max:        197.56 ms
  P50:        175.44 ms
  P95:        197.56 ms
  P99:        197.56 ms
```

### JSON 输出

```json
{
  "test": "session_create",
  "samples": 100,
  "warmup": 10,
  "stats": {
    "avg_ms": 177.44,
    "min_ms": 159.79,
    "max_ms": 197.56,
    "p50_ms": 175.44,
    "p95_ms": 197.56,
    "p99_ms": 197.56
  }
}
```

## 报告生成

基准测试完成后，可在 `reports/` 目录找到生成的报告：

```
reports/
├── BENCHMARK-REPORT.md      # 综合性能报告
├── PERFORMANCE-ANALYSIS.md  # 性能分析文档
├── session-results.txt      # Session 测试结果
├── hooks-results.txt        # Hooks 测试结果
├── pool-results.txt         # Pool 测试结果
└── system-results.txt       # System 测试结果
```

## 性能指标说明

| 指标 | 说明 |
|------|------|
| Avg | 平均延迟 |
| Min | 最小延迟 (最佳情况) |
| Max | 最大延迟 (最差情况) |
| P50 | 中位数，50% 请求的延迟 |
| P95 | 95% 请求的延迟上限 |
| P99 | 99% 请求的延迟上限 |
| Throughput | 每秒处理的操作数 |

## 性能基线

基于当前测试环境 (Termux/Android) 的性能基线：

| 操作 | 基线 (ms) | 目标 (ms) |
|------|-----------|-----------|
| Session Create | 177 | <100 |
| Session Read | 42 | <50 |
| Session Write | 194 | <100 |
| Session Delete | 81 | <50 |
| Worker Create | 146 | <100 |
| Task Assignment | 234 | <100 |
| End-to-End | 825 | <500 |

## 故障排查

### 测试失败

如果测试失败，检查以下内容：

```bash
# 1. 检查依赖
which python3
which jq

# 2. 检查权限
ls -la benchmarks/

# 3. 查看详细日志
SAMPLE_COUNT=5 bash -x ./benchmarks/benchmark-session.sh all 2>&1
```

### 性能异常

如果性能数据异常：

```bash
# 1. 清理临时文件
rm -rf /tmp/oml-benchmark-*

# 2. 检查磁盘空间
df -h

# 3. 检查系统负载
top -bn1
```

## 贡献指南

添加新的基准测试：

1. 在 `benchmarks/` 目录创建新的测试脚本
2. 遵循现有脚本的命名和结构规范
3. 实现 `setup_test_env` 和 `teardown_test_env` 函数
4. 添加测试结果输出和报告生成功能
5. 更新本文档

## 许可证

MIT License - 与 OML 项目保持一致
