# OML Qwenx 部署指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

Qwenx 是 OML 的 Qwen 客户端部署工具。

---

## 🚀 快速开始

### 部署 Qwenx

```bash
oml qwen deploy
```

### 查看状态

```bash
oml qwen status
```

---

## 🔧 配置

### 添加 API Key

```bash
# 使用 Key Switcher
oml qwen-key add sk-xxxxx work

# 切换 Key
oml qwen-key use 0
```

### 管理 OAuth

```bash
# 添加 OAuth 账号
oml qwen-oauth add work

# 切换账号
oml qwen-oauth use work
```

---

## 📋 功能

### 预览配置

```bash
# 查看.qwen 目录
ls -la ~/.local/home/qwenx/.qwen/

# 查看 skills
ls ~/.local/home/qwenx/.qwen/skills/

# 查看 agents
ls ~/.local/home/qwenx/.qwen/agents/
```

### 连接 OML

```bash
# 链接 OML 插件
ln -sf ~/develop/oh-my-litecode/plugins ~/.local/home/qwenx/.qwen/plugins
```

---

## 🎯 高级配置

### 自定义配置

编辑 `~/.local/home/qwenx/.qwen/settings.json`:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
  },
  "model": {
    "id": "qwen-plus",
    "name": "Qwen Plus"
  }
}
```

### 环境变量

```bash
export QWEN_API_KEY="sk-xxxxx"
export QWEN_BASE_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"
```

---

## ❓ 常见问题

### Q: 如何更新 Qwenx？

**A**: 
```bash
oml qwen update
```

### Q: 如何备份配置？

**A**: 
```bash
cp -r ~/.local/home/qwenx/.qwen ~/.local/home/qwenx/.qwen.backup
```

---

**维护者**: OML Team  
**版本**: 0.2.0
