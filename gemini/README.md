# Gemini CLI 定制和扩展

本目录包含针对 Gemini CLI (gemini-cli) 的专门定制、扩展和功能移植。

## 目录结构

```
gemini/
├── extensions/          # Gemini CLI 扩展 (官方规范)
├── plugins/             # MCP 服务器和插件
├── commands/            # 自定义命令 (TOML)
├── scripts/             # 辅助脚本
└── docs/                # 文档
```

## Gemini CLI 快速开始

### 安装 Gemini CLI
```bash
npm install -g @anthropic-ai/gemini-cli
```

### 认证
```bash
gemini login
```

### 安装扩展
```bash
gemini extensions install <github-url>
gemini extensions link <local-path>
```

## 扩展开发

### gemini-extension.json 格式
```json
{
  "name": "my-extension",
  "version": "1.0.0",
  "description": "扩展描述",
  "commands": "commands",
  "contextFileName": "GEMINI.md"
}
```

### 命令格式 (TOML)
```toml
[command]
name = "mycommand"
description = "命令描述"

[command.script]
language = "bash"
content = """
#!/usr/bin/env bash
echo "Hello"
"""
```

## 参考文档

- [Gemini CLI 文档](https://github.com/google/gemini-cli)
- [扩展系统](https://github.com/google/gemini-cli/blob/main/docs/extensions.md)
