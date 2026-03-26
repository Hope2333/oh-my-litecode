# Qwen Code 定制和扩展

本目录包含针对 Qwen Code (qwen-code) 的专门定制、扩展和功能移植。

## 目录结构

```
qwen/
├── extensions/          # Qwen Code 扩展 (官方规范)
│   └── qwen-session-manager/
│       ├── qwen-extension.json
│       ├── QWEN.md
│       ├── commands/
│       └── scripts/
├── plugins/             # MCP 服务器和插件
├── commands/            # 自定义命令 (TOML)
├── scripts/             # 辅助脚本
└── docs/                # 文档
```

## 可用扩展

### qwen-session-manager

Session 管理 TUI 和 CLI 工具。

**安装:**
```bash
cd /home/miao/develop/oh-my-litecode
qwen extensions link $(pwd)/qwen/extensions/qwen-session-manager
```

**使用:**
```
/session tui          # TUI 界面
/session list         # 列出会话
/session delete <id>  # 删除会话
/session clear        # 清空所有
/session help         # 帮助
```

## Qwen Code 快速开始

### 安装 Qwen Code
```bash
npm install -g @qwen-code/qwen-code
```

### 认证
```bash
qwen login
```

### 安装扩展
```bash
qwen extensions install <github-url>
qwen extensions link <local-path>
```

## 扩展开发

### qwen-extension.json 格式
```json
{
  "name": "my-extension",
  "version": "1.0.0",
  "description": "扩展描述",
  "commands": "commands",
  "contextFileName": "QWEN.md"
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
echo "Hello from command"
"""
```

## 参考文档

- [Qwen Code 官方文档](https://qwenlm.github.io/qwen-code-docs/)
- [扩展系统文档](https://qwenlm.github.io/qwen-code-docs/zh/developers/extensions/extension/)
- [阿里云文档](https://help.aliyun.com/zh/model-studio/qwen-code)
