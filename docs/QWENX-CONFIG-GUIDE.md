# qwenx 配置指南

**更新日期**: 2026-03-23  
**适用系统**: Termux (Android)

---

## 📋 概述

qwenx 已更新到 OML 系统，现在支持：
- ✅ 交互式会话（需要配置）
- ✅ Session 管理
- ✅ Hooks 系统
- ✅ Context7 密钥管理
- ✅ MCP 服务

---

## 🚀 启动方式对比

### 更新前（实验室版）
```bash
# 直接启动交互式会话
qwenx

# 自动使用配置的 API 密钥
```

### 更新后（OML 版）
```bash
# 启动交互式会话（需要配置认证）
qwenx

# 或使用原生 qwen 命令
qwen -i

# 查看帮助
qwenx --help
```

---

## 🔧 配置认证

### 方法 1: 使用 Qwen Code 原生配置

```bash
# 编辑 settings.json
nano ~/.local/home/qwenx/.qwen/settings.json

# 添加认证配置
{
  "modelProviders": {
    "openai": [
      {
        "id": "qwen-plus",
        "name": "Qwen Plus",
        "envKey": "QWEN_API_KEY",
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1"
      }
    ]
  }
}

# 设置环境变量
export QWEN_API_KEY="sk-your-api-key"
```

### 方法 2: 使用命令行参数

```bash
# 临时设置 API 密钥
QWEN_API_KEY="sk-xxx" qwenx

# 或使用原生命令
QWEN_API_KEY="sk-xxx" qwen -i
```

### 方法 3: 使用 Context7

```bash
# 设置 Context7 密钥
qwenx ctx7 set "ctx7sk-your-key@alias"

# 验证
qwenx ctx7 current
```

---

## 📁 目录结构

```
~/.local/home/qwenx/
├── .qwen/
│   ├── settings.json          # 主配置
│   ├── AGENTS.md              # Agent 配置
│   └── commands/              # 命令配置
├── .qwenx/
│   └── secrets/
│       └── context7.keys      # Context7 密钥
└── .oml/
    └── sessions/              # Session 数据
```

---

## 🔍 故障排查

### 问题 1: 无法启动交互式会话

**症状**:
```
No auth type is selected. Please configure an auth type...
```

**解决方案**:
```bash
# 1. 检查 settings.json
cat ~/.local/home/qwenx/.qwen/settings.json

# 2. 配置 API 密钥
export QWEN_API_KEY="sk-your-key"

# 3. 使用原生命令
qwen -i
```

### 问题 2: OML 未找到

**症状**:
```
Error: OML not found at /data/data/com.termux/files/home/develop/oh-my-litecode
```

**解决方案**:
```bash
# 设置 OML_ROOT
export OML_ROOT="/data/data/com.termux/files/home/develop/oh-my-litecode"

# 或创建符号链接
ln -sf /actual/path/to/oml /data/data/com.termux/files/home/develop/oh-my-litecode
```

### 问题 3: 配置目录不存在

**解决方案**:
```bash
# 创建配置目录
mkdir -p ~/.local/home/qwenx/.qwen
mkdir -p ~/.local/home/qwenx/.qwenx/secrets

# 创建默认配置
cat > ~/.local/home/qwenx/.qwen/settings.json << 'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "protocol": "mcp",
      "enabled": true
    }
  }
}
EOF
```

---

## 📊 命令对比

| 功能 | 实验室版 | OML 版 | 说明 |
|------|---------|-------|------|
| **启动会话** | `qwenx` | `qwenx` 或 `qwen -i` | OML 版需要认证 |
| **帮助** | `qwenx --help` | `qwenx --help` | 相同 |
| **Context7** | `qwenx ctx7` | `qwenx ctx7` | 相同 |
| **Session** | ❌ | `qwenx session` | OML 新增 |
| **Hooks** | ❌ | `qwenx hooks` | OML 新增 |
| **MCP** | `qwenx mcp` | `qwenx mcp` | 相同 |

---

## 🔗 相关文档

- [更新指南](UPDATE-QWENX-GUIDE.md)
- [快速开始](QUICKSTART.md)
- [完整文档](README-OML.md)

---

**维护者**: OML Team  
**许可**: MIT License
