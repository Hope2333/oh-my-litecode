# Claude Code 定制和扩展

本目录包含针对 Claude Code 的专门定制、扩展和功能移植。

## 目录结构

```
claude/
├── extensions/          # Claude Code 扩展
├── plugins/             # MCP 服务器和插件
├── commands/            # 自定义命令
├── scripts/             # 辅助脚本
└── docs/                # 文档
```

## Claude Code 快速开始

### 安装 Claude Code
```bash
npm install -g @anthropic-ai/claude-code
```

### 认证
```bash
claude login
```

## 扩展开发

### claude-plugin.json 格式
```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "插件描述",
  "commands": "commands"
}
```

## 参考文档

- [Claude Code 文档](https://docs.anthropic.com/claude-code/)
- [Claude Code GitHub](https://github.com/anthropics/claude-code)
