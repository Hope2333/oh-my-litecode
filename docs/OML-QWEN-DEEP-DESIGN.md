# OML Qwen 控制器深度设计文档

基于 Qwen Code 官方文档、源码和架构分析的完整设计方案。

---

## 一、Qwen Code 官方架构分析

### 1.1 官方包结构

```
qwen-code/
├── packages/cli          # CLI 包（前端）
│   ├── src/
│   │   ├── ui/           # 终端 UI 渲染
│   │   ├── commands/     # 斜杠命令处理
│   │   ├── config/       # 配置管理
│   │   └── input/        # 输入处理
│   └── package.json
│
├── packages/core         # 核心包（后端）
│   ├── src/
│   │   ├── tools/        # 工具模块
│   │   │   ├── file-ops.ts
│   │   │   ├── shell.ts
│   │   │   ├── search.ts
│   │   │   ├── network.ts
│   │   │   └── mcp/
│   │   ├── api/          # API 客户端
│   │   ├── prompts/      # 提示词构建
│   │   └── state/        # 状态管理
│   └── package.json
│
└── extensions/           # 扩展系统
    └── <extension-name>/
        ├── qwen-extension.json
        ├── commands/
        └── skills/
```

### 1.2 数据流

```
用户输入
    │
    ▼
┌─────────────────┐
│   packages/cli  │
│  (输入处理/渲染) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  packages/core  │
│   (后端引擎)     │
│  ┌───────────┐  │
│  │提示词构建  │  │
│  │API 客户端   │  │
│  │工具管理   │  │
│  └─────┬─────┘  │
└────────┼────────┘
         │
         ▼
┌─────────────────┐
│   Qwen Model    │
│      API        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  工具执行       │
│  (如需要)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   packages/cli  │
│  (格式化显示)    │
└────────┬────────┘
         │
         ▼
    用户查看
```

---

## 二、配置系统分析

### 2.1 配置文件层级（优先级从高到低）

```
1. 命令行参数 (--model, --sandbox, etc.)
   ↓
2. 环境变量 (OPENAI_API_KEY, QWEN_CODE_*)
   ↓
3. 项目配置 (.qwen/settings.json)
   ↓
4. 用户配置 (~/.qwen/settings.json)
   ↓
5. 系统配置 (/etc/qwen-code/settings.json)
   ↓
6. 系统默认 (/etc/qwen-code/system-defaults.json)
   ↓
7. 硬编码默认值
```

### 2.2 核心配置项

#### 模型配置
```json
{
  "model": {
    "name": "qwen3-coder-plus",
    "maxSessionTurns": -1,
    "chatCompression": {
      "contextPercentageThreshold": 0.7
    }
  },
  "modelProviders": {
    "openai": [
      {
        "id": "qwen3.5-plus",
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "envKey": "BAILIAN_API_KEY"
      }
    ]
  }
}
```

#### 工具配置
```json
{
  "tools": {
    "approvalMode": "default",
    "sandbox": "docker",
    "exclude": ["write_file"],
    "allowed": ["read_file", "search"]
  }
}
```

#### MCP 服务器配置
```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "trust": false
    }
  }
}
```

### 2.3 数据存储位置

| 数据类型 | 存储位置 |
|----------|----------|
| 用户配置 | `~/.qwen/settings.json` |
| 项目配置 | `.qwen/settings.json` |
| 会话历史 | `~/.qwen/tmp/<project_hash>/` |
| Shell 历史 | `~/.qwen/tmp/<project_hash>/shell_history` |
| 密钥 | `~/.qwenx/secrets/` (qwenx 特有) |
| OAuth 凭证 | `~/.qwenx/secrets/oauth_creds.json` |

---

## 三、命令系统分析

### 3.1 官方内置命令

#### 会话管理
| 命令 | 功能 |
|------|------|
| `/resume [id]` | 恢复会话 |
| `/compress` | 压缩聊天历史 |
| `/clear` | 清屏 |
| `/summary` | 生成项目摘要 |

#### 工具管理
| 命令 | 功能 |
|------|------|
| `/tools [desc]` | 列出工具 |
| `/mcp [desc]` | 列出 MCP 服务器 |
| `/skills [name]` | 列出技能 |
| `/approval-mode <mode>` | 设置审批模式 |

#### 配置管理
| 命令 | 功能 |
|------|------|
| `/settings` | 打开设置编辑器 |
| `/model` | 切换模型 |
| `/auth` | 更改认证方式 |
| `/extensions` | 管理扩展 |

### 3.2 自定义命令系统

#### 命令文件格式
```markdown
---
description: 命令描述（在/help 中显示）
---

提示内容在这里。
使用 {{args}} 进行参数注入。
```

#### 命令命名规则
- `~/.qwen/commands/test.md` → `/test`
- `~/.qwen/commands/git/commit.md` → `/git:commit`

---

## 四、扩展系统分析

### 4.1 扩展结构

```
~/.qwen/extensions/<name>/
├── qwen-extension.json    # 扩展配置
├── commands/              # 自定义命令
├── skills/                # 自定义技能
├── agents/                # 自定义子代理
└── QWEN.md               # 上下文文件
```

### 4.2 qwen-extension.json

```json
{
  "name": "my-extension",
  "version": "1.0.0",
  "mcpServers": {
    "my-server": {
      "command": "node my-server.js"
    }
  },
  "contextFileName": "QWEN.md",
  "commands": "commands",
  "skills": "skills",
  "agents": "agents",
  "settings": [
    {
      "name": "API Key",
      "description": "Your API key",
      "envVar": "MY_API_KEY",
      "sensitive": true
    }
  ]
}
```

### 4.3 扩展管理命令

```bash
# 安装
qwen extensions install <source>

# 卸载
qwen extensions uninstall <name>

# 启用/禁用
qwen extensions enable|disable <name> [--scope user|workspace]

# 更新
qwen extensions update <name|--all>

# 设置管理
qwen extensions settings set|list|show|unset <extension> <setting>
```

---

## 五、OML Qwen 控制器设计

### 5.1 架构设计

```
oml (主控制器)
│
├── qwen (Qwen 控制器)
│   │
│   ├── chat              # 聊天功能
│   │   ├── start         # 开始新会话
│   │   ├── resume        # 恢复会话
│   │   └── export        # 导出会话
│   │
│   ├── session           # 会话管理
│   │   ├── list          # 列出会话
│   │   ├── show          # 显示详情
│   │   ├── switch        # 切换会话
│   │   ├── delete        # 删除会话
│   │   ├── export        # 导出
│   │   └── import        # 导入
│   │
│   ├── config            # 配置管理
│   │   ├── show          # 显示配置
│   │   ├── edit          # 编辑配置
│   │   ├── reset         # 重置配置
│   │   ├── backup        # 备份配置
│   │   └── profile       # Profile 管理
│   │
│   ├── keys              # 密钥管理
│   │   ├── list          # 列出密钥
│   │   ├── add           # 添加密钥
│   │   ├── remove        # 删除密钥
│   │   ├── rotate        # 轮换密钥
│   │   └── current       # 显示当前
│   │
│   ├── mcp               # MCP 服务
│   │   ├── list          # 列出服务
│   │   ├── enable        # 启用
│   │   ├── disable       # 禁用
│   │   └── status        # 服务状态
│   │
│   ├── extensions        # 扩展管理
│   │   ├── list          # 列出扩展
│   │   ├── install       # 安装
│   │   ├── uninstall     # 卸载
│   │   ├── enable        # 启用
│   │   └── disable       # 禁用
│   │
│   └── migrate           # 数据迁移
│       ├── from-qwenx    # 从 qwenx 迁移
│       ├── to-profile    # 迁移到 Profile
│       └── archive       # 归档
│
├── build                 # 构建命令
├── plugins               # 插件管理
└── ...
```

### 5.2 命令映射（qwenx → oml qwen）

| qwenx 命令 | oml qwen 命令 | 说明 |
|-----------|--------------|------|
| `qwenx` | `oml qwen chat` | 启动聊天 |
| `qwenx <query>` | `oml qwen chat <query>` | 执行查询 |
| `qwenx --session` | `oml qwen session` | 会话管理 |
| `qwenx --ctx7` | `oml qwen keys ctx7` | Context7 密钥 |
| `qwenx --oauth` | `oml qwen keys oauth` | OAuth 管理 |
| `qwenx --config` | `oml qwen config` | 配置管理 |

### 5.3 Profile 系统

#### Profile 结构
```
~/.oml/profiles/
├── default/
│   ├── .qwen/
│   │   └── settings.json
│   └── .qwenx/
│       └── secrets/
├── work/
│   ├── .qwen/
│   └── .qwenx/
└── personal/
    ├── .qwen/
    └── .qwenx/
```

#### Profile 命令
```bash
oml qwen profile list           # 列出 Profile
oml qwen profile switch <name>  # 切换 Profile
oml qwen profile create <name>  # 创建 Profile
oml qwen profile delete <name>  # 删除 Profile
oml qwen profile export <name>  # 导出 Profile
oml qwen profile import <file>  # 导入 Profile
```

### 5.4 树形菜单帮助系统

#### 设计
```
oml help                      # 显示主菜单
oml help qwen                 # 显示 Qwen 子菜单
oml help qwen session         # 显示 session 详细用法
oml help qwen session list    # 显示 list 详细用法
```

#### 实现
```bash
_show_help() {
    local cmd="${1:-}"
    
    case "$cmd" in
        "")
            # 显示主菜单树
            _show_main_tree
            ;;
        qwen)
            # 显示 Qwen 子菜单树
            _show_qwen_tree
            ;;
        qwen.*)
            # 显示详细用法
            _show_detail "$cmd"
            ;;
    esac
}
```

---

## 六、实现方案

### 6.1 核心模块

#### oml_qwen_chat()
```bash
oml_qwen_chat() {
    local query="$*"
    local session_id="${QWEN_SESSION_ID:-}"
    
    # 确保有活动的会话
    if [[ -z "$session_id" ]]; then
        session_id=$(oml_qwen_session_create)
    fi
    
    # 调用 qwen-code
    qwen "$query"
}
```

#### oml_qwen_session_list()
```bash
oml_qwen_session_list() {
    local limit="${1:-10}"
    local format="${OML_OUTPUT_FORMAT:-text}"
    
    python3 "$OML_ROOT/scripts/session_manager.py" \
        --sessions-dir "$QWEN_SESSION_DIR" \
        --list \
        --limit "$limit" \
        ${format:+--$format}
}
```

#### oml_qwen_config_show()
```bash
oml_qwen_config_show() {
    local scope="${1:-effective}"
    
    case "$scope" in
        effective)
            # 显示合并后的配置
            jq -s '.[0] * .[1]' \
                ~/.qwen/settings.json \
                .qwen/settings.json 2>/dev/null || \
            cat ~/.qwen/settings.json
            ;;
        user)
            cat ~/.qwen/settings.json
            ;;
        project)
            cat .qwen/settings.json
            ;;
    esac
}
```

### 6.2 密钥管理

#### oml_qwen_keys_list()
```bash
oml_qwen_keys_list() {
    local keys_file="${QWENX_SECRETS_DIR}/context7.keys"
    
    if [[ ! -f "$keys_file" ]]; then
        echo "No keys configured"
        return 0
    fi
    
    echo "Context7 API Keys:"
    while IFS=: read -r alias key; do
        echo "  - $alias"
    done < "$keys_file"
}
```

#### oml_qwen_keys_add()
```bash
oml_qwen_keys_add() {
    local key="$1"
    local alias="${2:-default}"
    local keys_file="${QWENX_SECRETS_DIR}/context7.keys"
    
    mkdir -p "$(dirname "$keys_file")"
    echo "$alias:$key" >> "$keys_file"
    chmod 600 "$keys_file"
    
    echo "Added key: $alias"
}
```

### 6.3 数据迁移

#### oml_qwen_migrate_from_qwenx()
```bash
oml_qwen_migrate_from_qwenx() {
    local source="${HOME}/.local/home/qwenx"
    local target="${HOME}/.qwen"
    
    print_step "Migrating from qwenx..."
    
    # 迁移配置
    if [[ -f "$source/.qwen/settings.json" ]]; then
        cp "$source/.qwen/settings.json" "$target/settings.json"
    fi
    
    # 迁移会话
    if [[ -d "$source/.qwen/sessions" ]]; then
        cp -r "$source/.qwen/sessions" "$target/"
    fi
    
    # 迁移密钥
    if [[ -d "$source/.qwenx/secrets" ]]; then
        cp -r "$source/.qwenx/secrets" "$target/"
    fi
    
    print_success "Migration complete!"
}
```

---

## 七、与官方扩展系统集成

### 7.1 扩展安装
```bash
oml qwen extensions install https://github.com/...
```

### 7.2 扩展开发
```bash
oml qwen extensions new my-extension
cd my-extension
# 编辑 qwen-extension.json
# 添加 commands/ skills/ agents/
```

### 7.3 扩展发布
1. 发布到 GitHub
2. 用户通过 `oml qwen extensions install` 安装

---

## 八、安全性考虑

### 8.1 密钥存储
- 使用 `chmod 600` 保护密钥文件
- 敏感设置不在日志中显示
- 支持环境变量注入

### 8.2 审批模式
```bash
oml qwen config set approval-mode <mode>
# plan: 仅分析
# default: 需要批准
# auto-edit: 自动批准编辑
# yolo: 自动批准所有
```

### 8.3 沙盒支持
```bash
oml qwen config set sandbox docker
oml qwen config set sandbox-image my-image:latest
```

---

## 九、参考文档

- [Qwen Code 官方文档](https://qwenlm.github.io/qwen-code-docs/)
- [Qwen Code GitHub](https://github.com/QwenLM/qwen-code)
- [架构文档](https://qwenlm.github.io/qwen-code-docs/zh/developers/architecture/)
- [命令文档](https://qwenlm.github.io/qwen-code-docs/en/users/features/commands/)
- [扩展系统](https://qwenlm.github.io/qwen-code-docs/en/users/extension/introduction/)
- [配置文档](https://www.zdoc.app/en/QwenLM/qwen-code/blob/main/docs/cli/configuration.md)
