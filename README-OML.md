# Oh-My-Litecode (OML) - 插件化 AI 开发工具链

**版本**: 0.2.0-alpha  
**许可**: MIT  
**平台**: Termux (Android) / GNU/Linux

## 📖 概述

Oh-My-Litecode (OML) 是一个**插件化**的 AI 辅助开发工具链管理器，参照 [oh-my-qwencoder](https://github.com/asdlkjw/oh-my-qwencoder) 的 Commander-Worker 架构设计，专为 Termux/Android 和 GNU/Linux 环境优化。

### 核心特性

- 🧩 **插件化架构**: Agents、Subagents、MCPs、Skills 全部插件化
- 🔄 **qwenx 迁移**: 原 qwenx 功能已重构为 `oml qwen` 插件
- 🌐 **跨平台**: Termux 和 GNU/Linux 双平台原生支持
- 🔒 **安全隔离**: 每个 Agent 运行在独立的 Fake HOME 环境
- 📦 **统一管理**: 单一 `oml` 入口管理所有子功能

## 🚀 快速开始

### Termux 安装

```bash
# 1. 安装依赖
pkg install nodejs python3 git bash

# 2. 克隆仓库
git clone https://github.com/your-org/oh-my-litecode.git
cd oh-my-litecode

# 3. 添加 PATH (可选)
export PATH="$HOME/develop/oh-my-litecode:$PATH"
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc

# 4. 验证安装
oml --help
oml platform doctor
```

### GNU/Linux 安装

```bash
# 1. 安装依赖
sudo apt install nodejs python3 git bash  # Debian/Ubuntu
# 或
sudo pacman -S nodejs python git bash     # Arch

# 2. 克隆仓库
git clone https://github.com/your-org/oh-my-litecode.git
cd oh-my-litecode

# 3. 添加 PATH (可选)
export PATH="$HOME/develop/oh-my-litecode:$PATH"
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc

# 4. 验证安装
oml --help
oml platform doctor
```

## 📋 命令参考

### 核心命令

```bash
# 显示帮助
oml --help

# 平台检测
oml platform detect          # 输出：termux 或 gnu-linux
oml platform info            # 显示完整平台信息
oml platform doctor          # 健康检查

# 版本信息
oml version
```

### 插件管理

```bash
# 列出所有插件
oml plugins list
oml plugins list agents      # 仅列出 agents
oml plugins list all json    # JSON 格式输出

# 安装插件
oml plugins install ./my-plugin agent
oml plugins install https://github.com/user/oml-plugin.git

# 启用/禁用插件
oml plugins enable qwen
oml plugins disable qwen

# 运行插件
oml plugins run qwen ctx7 list
oml plugins info qwen

# 创建插件模板
oml plugins create my-agent agent
```

### Qwen Agent (原 qwenx 功能)

```bash
# 对话 (qwenx 兼容)
oml qwen "你好，请帮我写一个 Python 函数"

# Context7 密钥管理
oml qwen ctx7 list                    # 列出所有密钥
oml qwen ctx7 current                 # 显示当前密钥
oml qwen ctx7 set "key1@alias1"       # 设置密钥
oml qwen ctx7 rotate                  # 切换到下一个密钥
oml qwen ctx7 mode local              # 切换到本地模式
oml qwen ctx7 mode remote             # 切换到远程模式

# 模型管理
oml qwen models list                  # 列出配置的模型
oml qwen models sync                  # 从 API 同步 (需要 QWEN_API_KEY)

# MCP 服务
oml qwen mcp list                     # 列出 MCP 服务器
```

### 构建系统

```bash
# 构建 opencode
oml build --project opencode --target termux-dpkg --ver 1.2.10
oml build --project opencode --target gnu-arch --ver 1.2.10

# 构建 bun
oml build --project bun --target termux-pacman --ver 1.3.9

# 调试构建
oml build --project opencode --debug --dry-run
```

### OpenCode 集成

```bash
# 诊断
oml opencode diagnose

# 插件管理
oml opencode plugin list
oml opencode plugin install

# 技能系统
oml opencode skill list
oml opencode skill hook post_upgrade
```

## 🏗️ 架构设计

### 目录结构

```
oh-my-litecode/
├── oml                          # 主入口脚本
├── core/                        # 核心运行时
│   ├── platform.sh              # 平台检测与适配
│   └── plugin-loader.sh         # 插件加载器
├── plugins/                     # 插件仓库
│   ├── agents/                  # Agent 插件
│   │   └── qwen/                # Qwen Agent (原 qwenx)
│   │       ├── plugin.json      # 插件元数据
│   │       ├── main.sh          # 主入口
│   │       └── scripts/         # 钩子脚本
│   ├── subagents/               # Subagent 插件
│   ├── mcps/                    # MCP 服务插件
│   └── skills/                  # 系统技能
├── solve-android/               # Android 特定子项目
│   ├── opencode/                # OpenCode for Termux
│   └── bun/                     # Bun for Termux
├── configs/                     # 配置模板
│   ├── termux/
│   └── gnu-linux/
└── docs/                        # 文档
```

### 插件类型

| 类型 | 用途 | 示例 |
|------|------|------|
| **agents** | 主代理，处理用户对话 | qwen, gemini, opencode |
| **subagents** | 子代理，并行执行任务 | worker, scout, librarian |
| **mcps** | MCP 服务，提供工具调用 | context7, websearch, filesystem |
| **skills** | 系统技能，响应事件 | post_install, post_upgrade |

### 插件元数据

`plugin.json` 示例：

```json
{
  "name": "qwen",
  "version": "1.0.0",
  "type": "agent",
  "description": "Qwen Code 兼容代理",
  "platforms": ["termux", "gnu-linux"],
  "dependencies": ["nodejs", "python3", "git"],
  "env": {
    "QWEN_API_KEY": {"required": false, "default": ""},
    "QWEN_BASE_URL": {"required": false, "default": ""}
  },
  "commands": [
    {"name": "chat", "handler": "main.sh chat"},
    {"name": "ctx7", "handler": "main.sh ctx7"}
  ],
  "hooks": {
    "post_install": "scripts/post-install.sh",
    "pre_uninstall": "scripts/pre-uninstall.sh"
  },
  "fakeHome": {
    "enabled": true,
    "path": "~/.local/home/qwen"
  }
}
```

## 🔧 配置

### 环境变量

```bash
# Qwen API 配置
export QWEN_API_KEY="sk-..."        # API 密钥
export QWEN_BASE_URL="https://..."  # API 端点

# Context7 配置
export CONTEXT7_API_KEY="ctx7sk-..."  # Context7 密钥

# OML 配置
export OML_ROOT="/path/to/oh-my-litecode"
export OML_PLUGINS_ROOT="/path/to/plugins"
```

### 配置文件

```bash
# 全局配置
~/.oml/config.json

# Agent 特定配置
~/.local/home/qwen/.qwen/settings.json

# 平台特定配置
~/.oml/termux/paths.json
~/.oml/gnu-linux/paths.json
```

## 🛡️ 安全模型

### Fake HOME 隔离

每个 Agent 运行在独立的假 HOME 环境中：

```
~/.local/home/
├── qwen/       # Qwen Agent 配置
├── gemini/     # Gemini Agent 配置
└── opencode/   # OpenCode Agent 配置
```

### API 密钥管理

```bash
# 加密存储
oml qwen ctx7 set "your-key@alias"

# 或使用环境变量
export QWEN_API_KEY="sk-..."
oml qwen "查询"  # 自动继承环境变量
```

## 📝 迁移指南

### 从 qwenx 迁移

**旧用法 (qwenx)**:
```bash
qwenx "查询内容"
qwenx ctx7 set <key>
qwenx models list
```

**新用法 (oml qwen)**:
```bash
oml qwen "查询内容"
oml qwen ctx7 set <key>
oml qwen models list
```

**兼容性包装**:
```bash
# 在 ~/.bashrc 中添加
qwenx() { oml qwen "$@"; }
```

## 🧪 开发指南

### 创建新插件

```bash
# 生成模板
oml plugins create my-agent agent

# 编辑插件
cd plugins/agents/my-agent
nano plugin.json
nano main.sh

# 测试插件
oml plugins run my-agent
```

### 插件开发规范

1. **入口脚本**: 必须是 `main.sh` 且可执行
2. **配置**: 使用 `plugin.json` 声明元数据
3. **钩子**: 实现 `post_install` 和 `pre_uninstall`
4. **日志**: 输出到 `~/.oml/logs/<plugin>.log`
5. **错误处理**: 使用 `set -euo pipefail`

### 测试

```bash
# 平台检测
oml platform detect

# 健康检查
oml platform doctor

# 插件测试
oml plugins list
oml plugins info <plugin-name>
```

## 📚 文档

- [OML 插件系统架构](OML-PLUGINS.md)
- [平台适配指南](docs/platform/README.md)
- [插件开发指南](docs/plugins/developer-guide.md)

## 🤝 贡献

欢迎贡献！请遵循以下步骤：

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 提交 Pull Request

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE)

## 🔗 相关链接

- [oh-my-qwencoder](https://github.com/asdlkjw/oh-my-qwencoder) - 参考架构
- [OpenCode](https://github.com/anomalyco/opencode) - 上游项目
- [Bun](https://github.com/oven-sh/bun) - 运行时支持

## 📊 状态

| 组件 | 状态 | 平台支持 |
|------|------|---------|
| 核心系统 | ✅ 完成 | Termux, GNU/Linux |
| Qwen Agent | ✅ 完成 | Termux, GNU/Linux |
| 插件加载器 | ✅ 完成 | Termux, GNU/Linux |
| Subagents | 🚧 开发中 | - |
| MCPs | 🚧 开发中 | - |
| Skills | 📋 计划中 | - |

---

**最后更新**: 2024-03-21
