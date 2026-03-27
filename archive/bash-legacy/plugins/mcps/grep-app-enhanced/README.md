# grep-app Enhanced - 高性能代码搜索 MCP 服务

**版本**: 2.0.0  
**状态**: ✅ 生产就绪  
**许可**: MIT

---

## 📖 简介

grep-app Enhanced 是一个高性能、本地优先的代码搜索 MCP 服务，支持三层缓存和智能降级。

### 核心特性

- ✅ **三层缓存架构** - L1 内存/SQLite、L2 Git 仓库、L3 远程通路
- ✅ **ZSTD 高压缩** - 5-10:1 压缩比，读性能影响 <15%
- ✅ **智能降级** - 自动通路切换，降级延迟 <100ms
- ✅ **多平台支持** - GitHub/GitLab/Gitee
- ✅ **远程通路 2** - 爬虫 + git 命令组合
- ✅ **完整 Git 历史** - 支持任意 commit 版本

---

## 🚀 快速开始

### 安装

```bash
# 克隆仓库
cd plugins/mcps/grep-app-enhanced

# 安装依赖
./scripts/install.sh

# 安装 ZSTD 扩展（可选，提升压缩比）
./scripts/setup-zstd.sh

# 测试连接
./scripts/test-connection.sh
```

### 基本使用

```bash
# 启动 MCP 服务
python -m grep_app_enhanced.mcp_server

# 或使用 stdio 模式
grep-app-mcp --stdio
```

### MCP 工具

| 工具 | 功能 |
|------|------|
| `search_local` | 本地代码搜索 |
| `search_remote` | 远程仓库搜索 |
| `search_remote_three_layer` | 三层缓存远程搜索 ⭐ |
| `search_with_fallback` | 带智能降级的搜索 ⭐ |
| `get_file_content` | 获取文件内容 |
| `clone_repository` | 克隆仓库到缓存 |
| `get_three_layer_stats` | 三层缓存统计 |
| `get_fallback_metrics` | 降级通路指标 |
| `health_check` | 健康检查 |

---

## 📊 性能基准

### 缓存命中率

| 场景 | L1 命中率 | L2 命中率 | L3 命中率 |
|------|----------|----------|----------|
| **重复搜索** | 95% | 4% | 1% |
| **相似搜索** | 80% | 15% | 5% |
| **全新搜索** | 20% | 30% | 50% |

### 压缩性能

| 压缩级别 | 压缩比 | 读性能 | 写性能 | 磁盘占用 |
|---------|--------|--------|--------|---------|
| **无压缩** | 1:1 | 1.0ms | 5.0ms | 100MB |
| **ZSTD 3** | 5:1 | 1.1ms | 5.5ms | 20MB |
| **ZSTD 9** | 8:1 | 1.2ms | 6.0ms | 12.5MB |

### 降级延迟

| 通路 | 正常延迟 | 降级延迟 | 目标 |
|------|---------|---------|------|
| **gh CLI** | 50ms | - | ✅ |
| **API** | 100ms | - | ✅ |
| **爬虫** | 300ms | <100ms | ✅ |
| **Git 克隆** | 5s | <100ms | ✅ |

---

## 🏗️ 架构设计

### 三层缓存架构

```
搜索请求
    │
    ▼
┌─────────────────────────┐
│ L1: SQLite+ZSTD 缓存    │ ← 压缩比 8:1
│ - 内存缓存 (LRU)        │
│ - 压缩数据库            │
│ - TTL 过期              │
└──────────┬──────────────┘
           │ 未命中 (20%)
           ▼
┌─────────────────────────┐
│ L2: 本地 Git 仓库       │ ← 完整历史
│ - 已克隆仓库            │
│ - git 命令搜索          │
└──────────┬──────────────┘
           │ 未找到 (5%)
           ▼
┌─────────────────────────┐
│ L3: 远程通路            │
│ - gh CLI (首选)         │
│ - 爬虫+git (备用)       │
│ - API (可选)            │
└─────────────────────────┘
```

### 智能降级策略

```
通路健康检查
    │
    ├──────┬──────┬──────┐
    ▼      ▼      ▼      ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│ HEALTHY│ │DEGRADED│ │UNHEALTHY│ │  DOWN  │
└────────┘ └────────┘ └────────┘ └────────┘
    │          │          │          │
    ▼          ▼          ▼          ▼
  使用     限流使用    自动降级    跳过
```

---

## 🔧 配置选项

### 数据库配置

```python
{
    "db_path": "cache.db",
    "compression_level": 5,  # ZSTD 压缩级别 (1-9)
    "cache_size_mb": 64,     # SQLite 缓存大小
    "wal_mode": true,        # WAL 模式
}
```

### 缓存配置

```python
{
    "l1_max_size": 1000,     # L1 最大条目数
    "l1_ttl_seconds": 3600,  # L1 TTL
    "l2_git_cache_dir": "~/.cache/grep-app/repos",
    "l3_rate_limit": 10,     # 远程通路速率限制 (req/s)
}
```

### 降级配置

```python
{
    "fallback_enabled": true,
    "circuit_breaker_threshold": 5,  # 熔断阈值
    "circuit_breaker_timeout": 60,   # 熔断超时 (秒)
    "max_retries": 3,                # 最大重试次数
}
```

---

## 📚 API 文档

### RemoteSearch 类

```python
from grep_app_enhanced.search import RemoteSearch

search = RemoteSearch(
    token="ghp_xxx",
    db_path="/tmp/grep.db",
    git_cache_dir="/tmp/git-cache"
)
await search.initialize()

# 三层缓存搜索
results, stats = await search.search_with_three_layer_cache(
    "def main",
    repo="microsoft/vscode",
    platform="github"
)

print(f"L1 命中率：{stats.l1_hit_rate:.2%}")
print(f"总耗时：{stats.total_time_ms:.2f}ms")
```

### FallbackStrategy 类

```python
from grep_app_enhanced.search import FallbackStrategy

strategy = FallbackStrategy()
await strategy.initialize()

# 带降级的搜索
result = await strategy.execute_with_fallback(
    primary_search_func,
    fallback_chain=[fallback_func],
    pathway_id="github:owner/repo"
)

# 获取降级指标
metrics = await strategy.get_metrics("github:owner/repo")
print(f"健康状态：{metrics.health_status}")
print(f"成功率：{metrics.success_rate:.2%}")
```

---

## 🧪 测试

### 运行测试

```bash
# 单元测试
pytest tests/ -v

# 集成测试
pytest tests/test_integration.py -v

# 性能测试
pytest tests/test_benchmark.py -v

# 测试覆盖率
pytest --cov=grep_app_enhanced --cov-report=html
```

### 测试覆盖率

| 模块 | 覆盖率 |
|------|-------|
| **database** | 95% |
| **remote** | 92% |
| **search** | 93% |
| **总计** | 93% |

---

## ❓ FAQ

### Q: ZSTD 压缩扩展必须安装吗？

**A**: 不是必须的。不安装 ZSTD 扩展会使用外部压缩包装类，压缩比略低但功能完整。

### Q: 如何提升 L1 缓存命中率？

**A**: 
1. 增加 `l1_max_size` 配置
2. 延长 `l1_ttl_seconds`
3. 使用缓存预热功能

### Q: 智能降级如何工作？

**A**: 
1. 监控每个通路的成功率/延迟
2. 当通路失败率超过阈值时触发熔断
3. 自动切换到备用通路
4. 定期尝试恢复主通路

### Q: 支持哪些 Git 平台？

**A**: 
- ✅ GitHub (完整支持)
- ✅ GitLab (完整支持)
- ✅ Gitee (完整支持)
- ⚠️ 其他平台 (通过 git URL)

---

## 🔗 相关文档

- [架构设计](IMPLEMENTATION.md)
- [性能基准](BENCHMARK.md)
- [使用示例](examples/)
- [增强方案 v3](../../docs/GREP-APP-ENHANCEMENT-V3.md)

---

**维护者**: OML Team  
**许可**: MIT
