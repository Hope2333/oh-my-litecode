# Qwen OAuth 切换器使用指南

**版本**: 1.0.0  
**日期**: 2026-03-23

---

## 📖 简介

Qwen OAuth 切换器是一个**通过配置文件切换**来管理多个免费 Qwen 账号的工具。

### 工作原理

```
存储多个 settings.json → 复制到 Qwen 配置目录 → 实现账号切换
```

### 核心功能

- ✅ 存储多个 OAuth 配置文件
- ✅ 通过文件复制切换账号
- ✅ 备份和恢复功能
- ✅ 账号轮询
- ✅ 自动备份当前配置

---

## 🚀 快速开始

### 添加账号

```bash
# 1. 在浏览器登录 Qwen Code
# 2. 复制 ~/.local/home/qwenx/.qwen/settings.json 内容
# 3. 运行添加命令

oml qwen-oauth add work

# 粘贴 settings.json 内容，按 Ctrl+D 结束
```

### 导入现有配置

```bash
# 从当前配置导入
oml qwen-oauth import personal ~/.local/home/qwenx/.qwen/settings.json
```

### 切换账号

```bash
# 列出所有账号
oml qwen-oauth list

# 切换到工作账号
oml qwen-oauth use work

# 自动备份当前配置并切换
```

### 使用账号

```bash
# 切换后直接使用
oml qwen "你好"
```

---

## 📋 命令参考

### 账号管理

| 命令 | 功能 | 示例 |
|------|------|------|
| **list** | 列出所有账号 | `oml qwen-oauth list` |
| **add** | 添加新账号 | `oml qwen-oauth add work` |
| **import** | 导入现有配置 | `oml qwen-oauth import personal <file>` |
| **use** | 切换到指定账号 | `oml qwen-oauth use work` |
| **current** | 显示当前账号 | `oml qwen-oauth current` |
| **remove** | 删除账号 | `oml qwen-oauth remove work` |
| **rotate** | 轮询到下一个账号 | `oml qwen-oauth rotate` |

### 备份工具

| 命令 | 功能 | 示例 |
|------|------|------|
| **backup** | 备份当前配置 | `oml qwen-oauth backup` |
| **restore** | 恢复配置 | `oml qwen-oauth restore 20260323_120000` |

---

## 💾 存储说明

### 存储位置

```
~/.oml/qwen-oauth/
├── accounts/
│   ├── work/settings.json       # 工作账号配置
│   └── personal/settings.json   # 个人账号配置
├── current                      # 当前账号名称
└── backups/
    └── 20260323_120000/         # 配置备份
        └── settings.json
```

### 切换原理

```bash
# 当执行 qwen-oauth use work 时：
cp ~/.oml/qwen-oauth/accounts/work/settings.json \
   ~/.local/home/qwenx/.qwen/settings.json
```

### 文件权限

- **目录**: 700 (仅所有者)
- **文件**: 600 (仅所有者读写)

---

## 📊 使用示例

### 多账号工作流

```bash
# 1. 添加工作账号
oml qwen-oauth add work
# 粘贴工作账号的 settings.json

# 2. 添加个人账号
oml qwen-oauth add personal
# 粘贴个人账号的 settings.json

# 3. 列出所有账号
oml qwen-oauth list

# 输出示例：
# OAuth Accounts:
# 
# * work
#       Added: 2026-03-23T10:00:00+08:00
# 
#   personal
#       Added: 2026-03-23T10:01:00+08:00
# 
# Current account: work

# 4. 切换到个人账号
oml qwen-oauth use personal

# 5. 使用 qwen
oml qwen "帮我写代码"

# 6. 轮询到下一个账号（当限额用完时）
oml qwen-oauth rotate
```

### 备份和恢复

```bash
# 备份当前配置
oml qwen-oauth backup

# 输出示例：
# ✓ Backup created: ~/.oml/qwen-oauth/backups/20260323_120000

# 列出备份
ls ~/.oml/qwen-oauth/backups/

# 恢复配置
oml qwen-oauth restore 20260323_120000
```

### 导入现有配置

```bash
# 从当前配置导入为个人账号
oml qwen-oauth import personal ~/.local/home/qwenx/.qwen/settings.json

# 从备份导入
oml qwen-oauth import old ~/.oml/qwen-oauth/backups/20260322_100000/settings.json
```

---

## ❓ 常见问题

### Q: 如何获取 settings.json？

**A**: 
1. 登录 Qwen Code 到浏览器
2. 复制 `~/.local/home/qwenx/.qwen/settings.json` 内容
3. 运行 `oml qwen-oauth add <name>` 粘贴内容

### Q: 如何备份所有账号？

**A**: 
```bash
cp -r ~/.oml/qwen-oauth ~/backup/qwen-oauth-backup
```

### Q: 如何迁移账号到新设备？

**A**: 
```bash
# 1. 导出
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

- [Qwen Key Switcher](QWEN-KEY-SWITCHER-GUIDE.md) - API Key 管理
- [Qwen Agent 插件](../plugins/agents/qwen/)
- [OML 插件系统](../OML-PLUGINS.md)

---

**维护者**: OML Team  
**许可**: MIT
