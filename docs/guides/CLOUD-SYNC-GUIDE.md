# OML 云同步指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

OML 云同步支持双向同步、冲突解决和离线队列。

---

## 🚀 快速开始

### 初始化云同步

```bash
oml cloud init
```

### 认证

```bash
# 获取授权码
# 访问：https://oml.dev/auth

# 输入授权码
oml cloud auth
```

### 同步

```bash
# 从云端拉取
oml cloud sync pull

# 推送到云端
oml cloud sync push

# 查看状态
oml cloud sync status
```

---

## 🔧 配置

### 同步配置

编辑 `~/.oml/sync-config.json`:

```json
{
  "enabled": true,
  "auto_sync": false,
  "sync_interval": 3600,
  "conflict_resolution": "ask",
  "last_sync": null
}
```

### 配置项说明

| 配置项 | 说明 | 默认值 |
|--------|------|-------|
| `enabled` | 启用同步 | true |
| `auto_sync` | 自动同步 | false |
| `sync_interval` | 同步间隔 (秒) | 3600 |
| `conflict_resolution` | 冲突解决策略 | ask |

---

## 🔄 冲突解决

### 冲突检测

当本地和云端都有修改时，会检测到冲突。

### 解决策略

1. **ask** - 手动选择 (默认)
2. **local** - 优先本地
3. **remote** - 优先云端
4. **merge** - 自动合并

### 手动解决冲突

```bash
# 查看冲突文件
ls ~/.oml/conflicts/

# 查看冲突详情
cat ~/.oml/conflicts/<file>.conflict

# 解决后删除冲突文件
rm ~/.oml/conflicts/<file>.conflict
```

---

## 📦 离线模式

### 启用离线模式

```bash
oml offline enable
```

### 队列命令

```bash
oml offline queue "oml update all"
```

### 同步队列

```bash
oml offline sync
```

### 查看状态

```bash
oml offline status
```

---

## 📊 同步状态

### 查看同步状态

```bash
oml cloud sync status
```

**输出示例**:
```
Cloud Sync Status:

Authentication: ✓ Authenticated
Sync Enabled: true
Last Sync: 2026-03-23T12:00:00+08:00
Sync Queue: 0 items
```

---

## 🔍 故障排查

### 认证失败

```bash
# 重新认证
oml cloud auth

# 检查认证文件
cat ~/.oml/cloud-auth.json
```

### 同步失败

```bash
# 清除缓存
rm -rf ~/.oml/sync-queue.json

# 重新同步
oml cloud sync pull
```

### 冲突无法解决

```bash
# 查看冲突日志
cat ~/.oml/conflicts.log

# 手动解决冲突
# 编辑冲突文件，保留需要的内容
```

---

## 📚 相关文档

- [API 参考](../api/API-REFERENCE.md)
- [故障排查](guides/TROUBLESHOOTING.md)
- [最佳实践](BEST-PRACTICES.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
