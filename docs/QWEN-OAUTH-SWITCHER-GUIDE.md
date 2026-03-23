# Qwen OAuth 切换器使用指南

**版本**: 1.0.0  
**日期**: 2026-03-23

---

## 📖 简介

Qwen OAuth 切换器是一个多账号管理工具，支持：
- ✅ 多账号存储和切换
- ✅ 加密凭证存储
- ✅ 使用统计追踪
- ✅ API 健康检查

---

## 🚀 快速开始

### 安装

```bash
# 插件已集成，无需额外安装
cd ~/develop/oh-my-litecode
```

### 添加账号

```bash
# 添加工作账号
oml qwen-oauth add work

# 添加个人账号
oml qwen-oauth add personal
```

### 切换账号

```bash
# 切换到工作账号
oml qwen-oauth switch work

# 查看当前账号
oml qwen-oauth current
```

### 使用账号

```bash
# 导出环境变量
eval $(oml qwen-oauth switch work)

# 或使用 qwen 插件
oml qwen "你好"
```

---

## 📋 命令参考

### 账号管理

| 命令 | 功能 | 示例 |
|------|------|------|
| **list** | 列出所有账号 | `oml qwen-oauth list` |
| **add** | 添加新账号 | `oml qwen-oauth add work` |
| **switch** | 切换账号 | `oml qwen-oauth switch work` |
| **current** | 显示当前账号 | `oml qwen-oauth current` |
| **remove** | 删除账号 | `oml qwen-oauth remove work` |

### 工具命令

| 命令 | 功能 | 示例 |
|------|------|------|
| **refresh** | 刷新 token | `oml qwen-oauth refresh` |
| **stats** | 使用统计 | `oml qwen-oauth stats` |
| **health** | 健康检查 | `oml qwen-oauth health` |
| **help** | 显示帮助 | `oml qwen-oauth help` |

---

## 🔐 安全特性

### 加密存储

- **存储位置**: `~/.oml/qwen-oauth/`
- **加密方式**: Base64 编码
- **目录权限**: 700 (仅所有者)
- **文件权限**: 600 (仅所有者读写)

### 密钥掩码

```bash
# 显示时自动掩码
API Key: sk-proj...abcd
```

### 自动过期检测

```bash
# 健康检查会自动检测 token 过期
oml qwen-oauth health
```

---

## 📊 使用示例

### 多账号工作流

```bash
# 1. 添加多个账号
oml qwen-oauth add work
oml qwen-oauth add personal
oml qwen-oauth add test

# 2. 列出所有账号
oml qwen-oauth list

# 3. 切换到工作账号
oml qwen-oauth switch work

# 4. 使用 qwen
oml qwen "帮我写代码"

# 5. 切换到个人账号
oml qwen-oauth switch personal

# 6. 查看使用统计
oml qwen-oauth stats
```

### 健康检查

```bash
# 检查当前账号 API 连接
oml qwen-oauth health

# 输出示例：
# Health Check for: work
# Testing API connectivity...
# ✓ API connection successful
```

### 使用统计

```bash
# 查看所有账号使用统计
oml qwen-oauth stats

# 输出示例：
# Usage Statistics:
# 
# Total Requests: 150
# 
# Per-Account Stats:
#   work: 100 requests
#   personal: 45 requests
#   test: 5 requests
```

---

## ⚙️ 配置选项

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|-------|
| **QWEN_OAUTH_DIR** | 凭证存储目录 | `~/.oml/qwen-oauth` |

### 配置文件

```json
// ~/.oml/qwen-oauth/credentials.json
{
  "work": {
    "api_key": "Base64 编码的密钥",
    "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
    "added_at": "2026-03-23T10:00:00+08:00",
    "last_used": "2026-03-23T12:00:00+08:00"
  },
  "personal": {
    ...
  }
}
```

---

## ❓ 常见问题

### Q: 如何备份账号配置？

**A**: 复制配置目录：
```bash
cp -r ~/.oml/qwen-oauth ~/backup/qwen-oauth-backup
```

### Q: 如何迁移账号到新设备？

**A**: 
```bash
# 1. 导出配置
tar -czf qwen-oauth-backup.tar.gz ~/.oml/qwen-oauth

# 2. 在新设备上解压
tar -xzf qwen-oauth-backup.tar.gz -C ~/
```

### Q: 支持多少个账号？

**A**: 理论上无限制，建议不超过 10 个。

### Q: 如何完全清除所有账号？

**A**: 
```bash
rm -rf ~/.oml/qwen-oauth
```

---

## 🔗 相关文档

- [Qwen Agent 插件](../plugins/agents/qwen/)
- [OML 插件系统](../OML-PLUGINS.md)
- [快速开始](../QUICKSTART.md)

---

**维护者**: OML Team  
**许可**: MIT
