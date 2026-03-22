# Oh-My-Litecode (OML) 插件系统架构

**版本**: 0.2.0-alpha  
**目标**: 将 oh-my-qwen 生态重构为模块化插件系统

## 1. 设计目标

### 核心理念
参照 [oh-my-qwencoder](https://github.com/asdlkjw/oh-my-qwencoder) 的 Commander-Worker 架构，OML 插件系统提供：

- **统一入口**: `oml` 作为唯一 CLI 入口，管理所有子功能
- **模块化插件**: agents、subagents、MCPs、skills 全部插件化
- **跨平台**: Termux 和 GNU/Linux 双平台原生支持
- **安全隔离**: 每个插件运行在独立的 fake HOME 环境中

### 架构对比

| oh-my-qwencoder | OML (新架构) |
|-----------------|-------------|
| Commander (primary) | `oml` (主控制器) |
| Worker (subagents) | agents/subagents 插件 |
| Scout/Librarian (bg) | MCP 服务插件 |
| vLLM (local GPU) | 多后端支持 (Qwen/Gemini/OpenAI 兼容) |
| opencode.json | `~/.oml/config.json` |

## 2. 插件类型

### 2.1 Agents (主代理)
```
oml agents list
oml agents install <agent-name>
oml agents run <agent-name> [args]
```

**内置 agents**:
- `qwen`: Qwen Code 兼容代理
- `gemini`: Gemini Code 兼容代理
- `opencode`: OpenCode 主代理

### 2.2 Subagents (子代理)
```
oml subagents list
oml subagents spawn <agent> --task "<description>"
oml subagents status
```

**示例**:
```bash
# 并行执行多个子任务
oml subagents spawn qwen --task "实现用户认证模块" --scope "src/auth/**"
oml subagents spawn qwen --task "实现数据 API" --scope "src/api/**"
```

### 2.3 MCPs (Model Context Protocol 服务)
```
oml mcps list
oml mcps enable <mcp-name>
oml mcps disable <mcp-name>
oml mcps status
```

**内置 MCPs**:
- `context7`: 文档查询服务
- `websearch`: 网络搜索服务
- `filesystem`: 文件系统服务
- `git`: Git 操作服务

### 2.4 Skills (系统技能)
```
oml skills list
oml skills trigger <event>
```

**系统事件**:
- `post_install`: 安装后触发
- `post_upgrade`: 升级后触发
- `pre_uninstall`: 卸载前触发

## 3. 目录结构

```
oh-my-litecode/
├── oml                          # 主入口脚本
├── core/                        # 核心运行时
│   ├── platform.sh              # 平台检测与适配
│   ├── fake-home.sh             # Fake HOME 管理
│   └── plugin-loader.sh         # 插件加载器
├── plugins/                     # 插件仓库
│   ├── agents/                  # Agent 插件
│   │   ├── qwen/
│   │   │   ├── plugin.json      # 插件元数据
│   │   │   ├── main.sh          # 主入口
│   │   │   └── config.default   # 默认配置
│   │   ├── gemini/
│   │   └── opencode/
│   ├── subagents/               # Subagent 插件
│   ├── mcps/                    # MCP 服务插件
│   └── skills/                  # 系统技能
├── configs/                     # 配置模板
│   ├── termux/
│   └── gnu-linux/
└── docs/                        # 文档
```

## 4. 插件元数据格式

### `plugin.json`
```json
{
  "name": "qwen",
  "version": "1.0.0",
  "type": "agent",
  "description": "Qwen Code 兼容代理",
  "author": "OML Team",
  "license": "MIT",
  "platforms": ["termux", "gnu-linux"],
  "dependencies": ["nodejs", "python3"],
  "env": {
    "QWEN_API_KEY": {"required": false, "default": ""},
    "QWEN_BASE_URL": {"required": false, "default": ""}
  },
  "commands": [
    {
      "name": "chat",
      "description": "启动对话",
      "handler": "main.sh chat"
    },
    {
      "name": "mcp",
      "description": "MCP 管理",
      "handler": "main.sh mcp"
    }
  ],
  "hooks": {
    "post_install": "scripts/post-install.sh",
    "pre_uninstall": "scripts/pre-uninstall.sh"
  }
}
```

## 5. 跨平台支持

### 平台检测
```bash
# 自动检测运行环境
oml platform detect
# 输出：termux 或 gnu-linux
```

### 配置分离
```
~/.oml/
├── config.json           # 通用配置
├── termux/               # Termux 特定配置
│   └── paths.json
└── gnu-linux/            # GNU/Linux 特定配置
    └── paths.json
```

### 包管理器适配
| 平台 | 包管理器 | 输出格式 |
|------|---------|---------|
| Termux | pacman/dpkg | .pkg.tar.xz / .deb |
| GNU/Linux | pacman/dpkg/apt | .pkg.tar.xz / .deb / .rpm |

## 6. qwenx 迁移到 OML

### 旧用法 (qwenx)
```bash
qwenx "查询内容"
qwenx ctx7 set <key>
qwenx models list
```

### 新用法 (oml)
```bash
oml qwen "查询内容"
oml qwen ctx7 set <key>
oml qwen models list
```

### 兼容性包装
```bash
# 保留 qwenx 命令作为兼容层
qwenx() { oml qwen "$@"; }
```

## 7. 安装流程

### Termux 安装
```bash
# 1. 安装依赖
pkg install nodejs python3 git

# 2. 克隆仓库
git clone https://github.com/your-org/oh-my-litecode.git
cd oh-my-litecode

# 3. 安装 OML
./oml install

# 4. 安装插件
oml plugins install qwen
oml plugins enable context7

# 5. 验证安装
oml doctor
```

### GNU/Linux 安装
```bash
# 1. 安装依赖 (Debian/Ubuntu)
sudo apt install nodejs python3 git

# 2. 克隆仓库
git clone https://github.com/your-org/oh-my-litecode.git
cd oh-my-litecode

# 3. 安装 OML
sudo ./oml install --global

# 4. 安装插件
oml plugins install qwen

# 5. 验证安装
oml doctor
```

## 8. 安全模型

### Fake HOME 隔离
```bash
# 每个 agent 运行在独立的假 HOME 中
~/.local/home/
├── qwen/       # Qwen agent 配置
├── gemini/     # Gemini agent 配置
└── opencode/   # OpenCode agent 配置
```

### API KEY 管理
```bash
# 加密存储 API KEY
oml secrets set QWEN_API_KEY <key>
oml secrets get QWEN_API_KEY  # 运行时自动解密

# 或使用环境变量
export QWEN_API_KEY="sk-..."
oml qwen "查询"  # 自动继承环境变量
```

## 9. 开发者指南

### 创建新插件
```bash
# 生成插件模板
oml plugins create my-agent --type agent

# 目录结构
plugins/agents/my-agent/
├── plugin.json
├── main.sh
├── config.default
└── scripts/
    ├── post-install.sh
    └── pre-uninstall.sh
```

### 插件开发规范
1. **入口脚本**: 必须是 `main.sh` 且可执行
2. **配置**: 使用 `plugin.json` 声明元数据
3. **钩子**: 实现 `post_install` 和 `pre_uninstall`
4. **日志**: 输出到 `~/.oml/logs/<plugin>.log`
5. **错误处理**: 使用 `set -euo pipefail`

## 10. 迁移路线图

| 阶段 | 目标 | 时间线 |
|------|------|--------|
| Phase 1 | 核心架构 + qwen 插件 | 2024 Q1 |
| Phase 2 | subagents + MCPs | 2024 Q2 |
| Phase 3 | skills + 完整文档 | 2024 Q3 |
| Phase 4 | GNU/Linux 完整支持 | 2024 Q4 |

## 11. 与 oh-my-qwencoder 对比

| 特性 | oh-my-qwencoder | OML |
|------|-----------------|-----|
| 目标平台 | GNU/Linux (vLLM) | Termux + GNU/Linux |
| 模型后端 | 本地 vLLM | 多后端 (API/本地) |
| 插件系统 | TypeScript | Bash/Shell |
| 包管理 | npm | pacman/dpkg |
| 适用场景 | 企业内网 | 移动/桌面通用 |
