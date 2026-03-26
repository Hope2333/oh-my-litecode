# Qwenx 配置文件和数据存储树

通过分析 fakehome 目录结构，整理出完整的 qwen-code 配置和数据存储方案。

## 核心目录结构

```
~/.local/home/qwenx/                    # qwenx fakehome (sandbox)
├── .qwen/                              # Qwen Code 主配置目录
│   ├── agents/                         # 自定义 Agent 配置
│   │   └── <agent-name>/
│   │       └── AGENT.md                # Agent 定义文件
│   ├── debug/                          # 调试信息
│   │   └── <date>/
│   │       └── <session-id>/
│   ├── projects/                       # 项目配置
│   │   └── <project-hash>/
│   │       ├── QWEN.md                 # 项目上下文
│   │       └── chats/                  # 聊天历史
│   │           └── <session-id>.json
│   ├── sessions/                       # 会话数据
│   │   └── <session-id>.json
│   ├── skills/                         # 技能配置
│   │   └── <skill-name>/
│   │       └── SKILL.md
│   ├── tmp/                            # 临时文件
│   │   └── <hash>/
│   └── todos/                          # 待办事项
│       └── <todo-id>.md
│
├── .qwenx/                             # Qwenx 特定配置
│   └── secrets/                        # 密钥存储
│       ├── context7.keys               # Context7 API 密钥
│       ├── context7.index              # 密钥索引
│       └── oauth_creds.json            # OAuth 凭证
│
├── .oml/                               # OML (Oh-My-Litecode) 数据
│   ├── cache/                          # OML 缓存
│   │   └── websearch/
│   └── sessions/                       # OML 会话管理
│
├── .npm/                               # npm 缓存
│   └── _npx/
│
├── .cache/                             # 系统缓存
│   ├── fontconfig/
│   ├── gh/                             # GitHub CLI 缓存
│   ├── mesa_shader_cache/
│   ├── mozilla/                        # Firefox 缓存
│   └── qtshadercache/
│
├── 文档/                                # 文档目录 (符号链接)
└── 下载/                                # 下载目录 (符号链接)
```

## 配置文件详解

### 1. `.qwen/settings.json`
Qwen Code 主配置文件
```json
{
  "modelProviders": {
    "openai": [...]
  },
  "mcpServers": {
    "context7": {...}
  },
  "model": {...}
}
```

### 2. `.qwen/sessions/<session-id>.json`
会话数据文件
```json
{
  "session_id": "qwen-session-xxx",
  "name": "session name",
  "status": "active|inactive",
  "created_at": "ISO8601",
  "updated_at": "ISO8601",
  "messages": [...]
}
```

### 3. `.qwenx/secrets/context7.keys`
Context7 API 密钥环
```
alias1:key1
alias2:key2
```

### 4. `.qwenx/secrets/oauth_creds.json`
OAuth 凭证
```json
{
  "access_token": "...",
  "refresh_token": "...",
  "expiry_date": 1234567890
}
```

### 5. `.qwen/projects/<hash>/QWEN.md`
项目上下文文件
```markdown
# Project Context

## Rules
- Rule 1
- Rule 2
```

## 数据流向

```
用户输入 → oml qwen → qwen-code → MCP Servers
    ↓         ↓          ↓           ↓
  会话管理  配置管理   模型调用    外部服务
```

## 配置隔离级别

| 级别 | 路径 | 用途 |
|------|------|------|
| 全局 | `~/.qwen/` | 全局配置 |
| 项目 | `~/.qwen/projects/<hash>/` | 项目特定配置 |
| 会话 | `~/.qwen/sessions/` | 会话数据 |
| 密钥 | `~/.qwenx/secrets/` | 敏感信息 |

## 迁移到 OML Qwen 控制器

### 命令映射
```
qwenx --help           → oml qwen --help
qwenx <query>          → oml qwen chat <query>
qwenx session list     → oml qwen session list
qwenx ctx7 set         → oml qwen ctx7 set
```

### 配置管理
```
oml qwen config show    # 显示当前配置
oml qwen config edit    # 编辑配置
oml qwen config reset   # 重置配置
```

### 会话管理
```
oml qwen session list   # 列出会话
oml qwen session switch # 切换会话
oml qwen session delete # 删除会话
```

### 密钥管理
```
oml qwen keys list      # 列出密钥
oml qwen keys add       # 添加密钥
oml qwen keys rotate    # 轮换密钥
```
