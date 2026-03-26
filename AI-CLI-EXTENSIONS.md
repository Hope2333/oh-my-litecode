# AI CLI 工具扩展仓库

本仓库提供多个 AI CLI 工具的扩展、插件和功能移植。

## 支持的 AI 工具

| 工具 | 目录 | 扩展系统 | 状态 |
|------|------|----------|------|
| **Qwen Code** | `qwen/` | qwen-extension.json | ✅ 已实现 |
| **Aider** | `aider/` | .aider.commands | 📋 入口 |
| **Gemini CLI** | `gemini/` | gemini-extension.json | 📋 入口 |
| **OpenCode** | `opencode/` | MCP Servers | 📋 入口 |
| **Claude Code** | `claude/` | claude-plugin.json | 📋 入口 |
| **Codex CLI** | `codex/` | - | 📋 入口 |
| **ForgeCode** | `forgecode/` | - | 📋 入口 |

## 目录结构

```
oh-my-litecode/
├── qwen/           # Qwen Code 定制
├── aider/          # Aider 定制
├── gemini/         # Gemini CLI 定制
├── opencode/       # OpenCode 定制
├── claude/         # Claude Code 定制
├── codex/          # Codex CLI 定制
├── forgecode/      # ForgeCode 定制
├── modules/        # 共享模块
├── core/           # 核心功能
└── plugins/        # OML 插件系统
```

## 各工具扩展/插件结构

### Qwen Code (官方规范)
```
qwen/extensions/my-extension/
├── qwen-extension.json
├── QWEN.md
├── commands/
│   └── command.toml
└── scripts/
```

### Gemini CLI
```
gemini/extensions/my-extension/
├── gemini-extension.json
├── GEMINI.md
└── commands/
```

### Claude Code
```
claude/plugins/my-plugin/
├── claude-plugin.json
└── commands/
```

### Aider
```
aider/commands/
└── mycommand.sh
```

## 共享功能移植

以下功能可在多个工具间移植：

| 功能 | Qwen | Gemini | Claude | Aider |
|------|------|--------|--------|-------|
| Session 管理 TUI | ✅ | 🔄 | 🔄 | 🔄 |
| OAuth 自动检测 | ✅ | 🔄 | 🔄 | - |
| MCP 服务器 | ✅ | ✅ | ✅ | ✅ |
| 自定义命令 | ✅ | ✅ | ✅ | ✅ |

## 快速开始

### Qwen Code
```bash
cd /home/miao/develop/oh-my-litecode
qwen extensions link $(pwd)/qwen/extensions/qwen-session-manager
```

### Gemini CLI
```bash
gemini extensions link $(pwd)/gemini/extensions/my-extension
```

### Claude Code
```bash
# 待实现
```

## 开发指南

1. 在对应工具目录下创建扩展
2. 遵循各工具的扩展规范
3. 使用 `link` 命令进行开发测试
4. 功能成熟后可发布到各平台

## 参考文档

- [Qwen Code 扩展文档](https://qwenlm.github.io/qwen-code-docs/)
- [Gemini CLI 扩展](https://github.com/google/gemini-cli)
- [Claude Code 文档](https://docs.anthropic.com/claude-code/)
- [Aider 文档](https://aider.chat/)
- [MCP 协议](https://modelcontextprotocol.io/)
