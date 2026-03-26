# OML Qwen 控制器设计方案

将 qwenx 功能迁移到 `oml qwen` 子命令，实现统一的控制器方案。

## 架构设计

```
oml (主控制器)
├── qwen (Qwen 控制器)
│   ├── chat (聊天)
│   ├── session (会话管理)
│   ├── config (配置管理)
│   ├── keys (密钥管理)
│   ├── mcp (MCP 服务)
│   ├── extensions (扩展管理)
│   └── migrate (数据迁移)
├── build (构建)
├── plugins (插件)
└── ...
```

## 命令树

### `oml qwen` - Qwen 控制器

```
oml qwen
├── chat [query]              # 开始聊天/执行查询
│   ├── --session <id>        # 指定会话
│   ├── --model <name>        # 指定模型
│   └── --context <file>      # 指定上下文
│
├── session                   # 会话管理
│   ├── list [limit]          # 列出会话
│   ├── show <id>             # 显示会话详情
│   ├── switch <id>           # 切换会话
│   ├── create [name]         # 创建会话
│   ├── delete <id>           # 删除会话
│   ├── export <id>           # 导出会话
│   └── import <file>         # 导入会话
│
├── config                    # 配置管理
│   ├── show                  # 显示配置
│   ├── edit                  # 编辑配置
│   ├── reset                 # 重置配置
│   └── backup                # 备份配置
│
├── keys                      # 密钥管理
│   ├── list                  # 列出密钥
│   ├── add <key> [@alias]    # 添加密钥
│   ├── remove <alias>        # 删除密钥
│   ├── rotate                # 轮换密钥
│   └── current               # 显示当前密钥
│
├── mcp                       # MCP 服务管理
│   ├── list                  # 列出 MCP 服务
│   ├── enable <name>         # 启用服务
│   ├── disable <name>        # 禁用服务
│   └── status                # 服务状态
│
├── extensions                # 扩展管理
│   ├── list                  # 列出扩展
│   ├── install <source>      # 安装扩展
│   ├── uninstall <name>      # 卸载扩展
│   ├── enable <name>         # 启用扩展
│   └── disable <name>        # 禁用扩展
│
├── migrate                   # 数据迁移
│   ├── from-qwenx            # 从 qwenx 迁移
│   ├── to-profile <name>     # 迁移到配置文件
│   └── archive <name>        # 归档配置
│
└── help                      # 显示帮助
```

### 树形菜单帮助系统

```
oml help
├── qwen                      # Qwen 相关命令
│   └── (显示 qwen 子命令树)
├── build                     # 构建相关
├── plugins                   # 插件管理
└── ...

oml help qwen
├── chat                      # 聊天命令
├── session                   # 会话管理
├── config                    # 配置管理
└── ...

oml help qwen session
└── (显示 session 详细用法)
```

## 配置文件管理

### Profile 系统

```
~/.oml/profiles/
├── default/                  # 默认配置
│   ├── .qwen/
│   └── .qwenx/
├── work/                     # 工作配置
│   ├── .qwen/
│   └── .qwenx/
└── personal/                 # 个人配置
    ├── .qwen/
    └── .qwenx/
```

### 切换配置
```bash
oml qwen profile switch work
oml qwen profile list
```

## 迁移 qwenx 命令

| 原 qwenx 命令 | 新 oml qwen 命令 |
|--------------|-----------------|
| `qwenx` | `oml qwen chat` |
| `qwenx --help` | `oml qwen --help` |
| `qwenx <query>` | `oml qwen chat <query>` |
| `qwenx --session` | `oml qwen session` |
| `qwenx --ctx7` | `oml qwen keys` |

## 实现示例

### qwen_chat()
```bash
qwen_chat() {
    local query="$*"
    local session_id="${QWEN_SESSION_ID:-}"
    
    # 确保有活动的会话
    if [[ -z "$session_id" ]]; then
        session_id=$(qwen_session_create)
    fi
    
    # 调用 qwen-code
    qwen "$query"
}
```

### qwen_session_list()
```bash
qwen_session_list() {
    local limit="${1:-10}"
    python3 "$SCRIPT_DIR/scripts/session_manager.py" --list --limit "$limit"
}
```

## 优势

1. **统一管理**: 所有 AI 工具命令都在 `oml` 下
2. **配置隔离**: 通过 profile 系统实现配置隔离
3. **数据迁移**: 轻松在不同配置间迁移数据
4. **扩展性**: 易于添加新的子命令
