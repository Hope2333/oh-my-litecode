# OML 性能调优指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

本指南帮助优化 OML 性能。

---

## 🚀 启动优化

### 目标

- 启动时间 <100ms
- 命令响应 <50ms

### 方法

#### 1. 启用懒加载

```bash
# 添加到 ~/.oml/config.json
{
  "lazy_load": true,
  "preload_commands": ["help", "status"]
}
```

#### 2. 预编译脚本

```bash
# 检查语法
for f in modules/*.sh; do
    bash -n "$f"
done
```

#### 3. 缓存索引

```bash
# 建立命令索引
oml cache set commands "$(oml --help)"
```

---

## 📊 性能监控

### 启动监控

```bash
oml perf monitor start
```

### 查看状态

```bash
oml perf monitor status
```

### 生成报告

```bash
oml perf monitor report
```

---

## 🔧 性能优化

### 1. 缓存优化

```bash
# 设置缓存大小
export MAX_SIZE=1000

# 设置 TTL
export TTL=3600

# 清理过期缓存
oml cache cleanup
```

### 2. 内存管理

```bash
# 监控内存
oml perf monitor status

# 清理内存
unset OML_DEBUG
```

### 3. 磁盘 I/O 优化

```bash
# 使用 SSD 存储
# 避免网络文件系统
# 定期清理日志
find ~/.oml -name "*.log" -mtime +7 -delete
```

---

## 📈 性能基准

### 运行基准测试

```bash
oml perf benchmark
```

### 目标指标

| 指标 | 目标 | 当前 |
|------|------|------|
| 启动时间 | <100ms | ~200ms |
| 命令响应 | <50ms | ~100ms |
| 缓存命中率 | >90% | ~80% |
| 内存占用 | <50MB | ~80MB |

---

## 🔍 性能分析

### 1. CPU 分析

```bash
# 使用 perf
perf record -g oml <command>
perf report
```

### 2. 内存分析

```bash
# 使用 valgrind
valgrind --tool=massif oml <command>
```

### 3. I/O 分析

```bash
# 使用 iostat
iostat -x 1
```

---

## 📚 相关文档

- [API 参考](../api/API-REFERENCE.md)
- [最佳实践](BEST-PRACTICES.md)
- [故障排查](TROUBLESHOOTING.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
