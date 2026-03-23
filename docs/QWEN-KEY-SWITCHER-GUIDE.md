# Qwen Key Switcher 使用指南

**版本**: 1.0.0  
**日期**: 2026-03-23

---

## 📖 简介

Qwen Key Switcher 是一个**本地 API Key 管理工具**，用于在多个免费的 Qwen API Key 之间切换。

### 核心功能

- ✅ 存储多个 API Key（Base64 加密）
- ✅ 手动/自动切换 Key
- ✅ 使用统计追踪
- ✅ 健康检查（检测失效 Key）
- ✅ 自动导出到环境变量

---

## 🚀 快速开始

### 添加 Key

```bash
# 添加第一个 Key
oml qwen-key add sk-xxxxxxxxxxxxx work

# 添加第二个 Key
oml qwen-key add sk-yyyyyyyyyyyyy personal
```

### 切换 Key

```bash
# 列出所有 Key
oml qwen-key list

# 切换到工作 Key
oml qwen-key use 0

# 自动轮询到下一个 Key
oml qwen-key rotate
```

### 使用 Key

```bash
# 导出到当前 shell
eval $(oml qwen-key export)

# 或直接用 oml qwen（会自动导出）
oml qwen "你好"
```

---

## 📋 命令参考

### Key 管理

| 命令 | 功能 | 示例 |
|------|------|------|
| **list** | 列出所有 Key | `oml qwen-key list` |
| **add** | 添加新 Key | `oml qwen-key add sk-xxx work` |
| **use** | 切换到指定 Key | `oml qwen-key use 0` |
| **current** | 显示当前 Key | `oml qwen-key current` |
| **remove** | 删除 Key | `oml qwen-key remove 0` |
| **rotate** | 轮询到下一个 Key | `oml qwen-key rotate` |

### 工具命令

| 命令 | 功能 | 示例 |
|------|------|------|
| **stats** | 使用统计 | `oml qwen-key stats` |
| **health** | 健康检查 | `oml qwen-key health` |
| **export** | 导出到环境 | `eval $(oml qwen-key export)` |
| **help** | 显示帮助 | `oml qwen-key help` |

---

## 💾 存储说明

### 存储位置

```
~/.oml/qwen-keys/
├── keys.json       # 加密的 API Key 存储
├── current         # 当前 Key 索引
└── stats.json      # 使用统计
```

### 文件权限

- **目录**: 700 (仅所有者)
- **文件**: 600 (仅所有者读写)
- **加密**: Base64 编码

### 示例结构

```json
// keys.json
[
  {
    "key": "Base64 编码的密钥",
    "name": "work",
    "added_at": "2026-03-23T10:00:00+08:00",
    "last_used": "2026-03-23T12:00:00+08:00",
    "request_count": 0,
    "status": "active",
    "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1"
  }
]
```

---

## 📊 使用示例

### 多 Key 工作流

```bash
# 1. 添加多个免费 Key
oml qwen-key add sk-free1 work
oml qwen-key add sk-free2 personal
oml qwen-key add sk-free3 test

# 2. 列出所有 Key
oml qwen-key list

# 输出示例：
# Stored API Keys:
# 
# * 0: work
#       Key: sk-***abcd
#       Added: 2026-03-23T10:00:00+08:00
#       Status: active
# 
#   1: personal
#       Key: sk-***efgh
#       Added: 2026-03-23T10:01:00+08:00
#       Status: active
# 
#   2: test
#       Key: sk-***ijkl
#       Added: 2026-03-23T10:02:00+08:00
#       Status: active

# 3. 切换到工作 Key
oml qwen-key use 0

# 4. 使用 qwen
oml qwen "帮我写代码"

# 5. 轮询到下一个 Key（当当前 Key 限额用完时）
oml qwen-key rotate

# 6. 查看使用统计
oml qwen-key stats
```

### 健康检查

```bash
# 检查所有 Key 是否有效
oml qwen-key health

# 输出示例：
# Health Check:
# 
#   Key 0 (sk-***abcd): ✓ OK
#   Key 1 (sk-***efgh): ✓ OK
#   Key 2 (sk-***ijkl): ⚠ Rate limited
```

### 自动导出集成

```bash
# 在 ~/.bashrc 中添加
export QWEN_KEY_AUTO_EXPORT=true

# 使用 oml qwen 时会自动导出当前 Key
oml qwen "你好"
```

---

## ⚙️ 配置选项

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|-------|
| **QWEN_KEY_DIR** | Key 存储目录 | `~/.oml/qwen-keys` |
| **QWEN_KEY_AUTO_EXPORT** | 自动导出 | `false` |

---

## ❓ 常见问题

### Q: 如何备份 Key？

**A**: 复制存储目录：
```bash
cp -r ~/.oml/qwen-keys ~/backup/qwen-keys-backup
```

### Q: Key 用完限额怎么办？

**A**: 使用 rotate 命令切换到下一个 Key：
```bash
oml qwen-key rotate
```

### Q: 支持多少个 Key？

**A**: 理论上无限制，建议不超过 10 个。

### Q: 如何完全清除所有 Key？

**A**: 
```bash
rm -rf ~/.oml/qwen-keys
```

---

## 🔗 相关文档

- [Qwen Agent 插件](../plugins/agents/qwen/)
- [OML 插件系统](../OML-PLUGINS.md)
- [快速开始](../QUICKSTART.md)

---

**维护者**: OML Team  
**许可**: MIT
