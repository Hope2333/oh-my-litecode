# OML Phase 3 插件迁移详细评估

**版本**: 1.0
**评估日期**: 2026-03-23
**评估人**: OML Team

---

## 📊 评估摘要

### 可迁移性结论

| 插件 | 可迁移 | 难度 | 建议 | 理由 |
|------|--------|------|------|------|
| **qwen agent** | ⚠️ 部分 | 高 | 保留 Bash | 重度依赖 qwen CLI 原生行为 |
| **context7 MCP** | ✅ 是 | 中 | 迁移到 TS | 主要是配置管理，逻辑简单 |
| **grep-app MCP** | ✅ 是 | 中 | 迁移到 Python | grep/find 包装，Python 更合适 |
| **build agent** | ⚠️ 部分 | 中 | 保留 Bash | 调用 make/pacman 等系统命令 |
| **plan agent** | ✅ 是 | 低 | 迁移到 Python | 纯逻辑处理，无系统依赖 |
| **subagents** | ✅ 是 | 低 | 混合迁移 | 大部分是纯逻辑 |

---

## 🔍 详细分析

### 1. qwen agent (1,358 行)

#### 功能模块
```
- qwen_init()                      # 环境初始化
- qwen_session_*()                 # 会话管理 (8 个函数)
- qwen_hooks_*()                   # Hooks 触发 (4 个函数)
- models_*()                       # 模型管理
- mcp_list()                       # MCP 列表
- qwen_chat()                      # 核心对话
- main()                           # CLI 入口
```

#### 外部依赖
- **qwen CLI** (`exec qwen "${ARGS[@]}"`) - 调用原生 qwen 命令
- **Fake HOME** - 依赖 `~/.local/home/qwen` 目录结构
- **OAuth** - 依赖 `~/.qwen/oauth_creds.json`

#### 迁移难点
1. **qwen CLI 包装**: 核心功能是调用 `qwen` 命令，这不是能迁移的逻辑
2. **Fake HOME 隔离**: 需要保持与 Bash 版本完全一致的行为
3. **Hooks 集成**: 依赖 Phase 2 的 Python Hooks 引擎

#### 建议
**保留 Bash 实现**，原因：
- 核心逻辑是包装 `qwen` CLI，没有迁移价值
- Fake HOME 和 OAuth 逻辑已经在 Bash 中成熟
- 可以提取 session/hooks 管理到 TypeScript

#### 可提取部分
```typescript
// src/plugins/qwen-session.ts
export function createSession() { ... }
export function switchSession() { ... }
export function listSessions() { ... }
```

---

### 2. context7 MCP (984 行)

#### 功能模块
```
- mcp_list()                       # 列出 MCP 服务
- mcp_enable()                     # 启用服务
- enable_local_mode()              # 本地模式 (npx)
- enable_remote_mode()             # 远程模式 (API)
- mcp_disable()                    # 禁用服务
- mcp_status()                     # 状态检查
- mcp_config()                     # 配置管理
```

#### 外部依赖
- **npx** - 运行 `@upstash/context7-mcp`
- **settings.json** - Qwen Code 配置文件

#### 迁移难点
1. **settings.json 编辑**: 需要 JSON 操作库
2. **npx 调用**: 简单的子进程调用

#### 建议
**迁移到 TypeScript**，原因：
- 逻辑简单，主要是文件操作
- 与 Qwen Code 配置交互，TS 更方便
- 可以使用官方 MCP SDK

#### 目标实现
```typescript
// plugins/mcps/context7/src/index.ts
import { writeJsonConfig } from '@oml/core';

export async function enableLocalMode() {
  const settings = await loadSettings();
  settings.mcpServers.context7 = {
    command: 'npx',
    args: ['-y', '@upstash/context7-mcp@latest'],
    enabled: true,
  };
  await saveSettings(settings);
}
```

---

### 3. grep-app MCP (2,146 行)

#### 功能模块
```
- cmd_search()                     # 自然语言搜索
- cmd_regex()                      # 正则搜索
- cmd_count()                      # 统计匹配
- cmd_files()                      # 列出文件
- build_grep_exclude()             # 构建 grep 排除
- build_find_exclude()             # 构建 find 排除
- detect_extensions()              # 检测文件类型
```

#### 外部依赖
- **grep** - GNU grep
- **find** - GNU find
- **python3** - 部分逻辑使用 Python

#### 迁移难点
1. **grep/find 调用**: 系统命令包装
2. **复杂参数构建**: 排除目录、文件类型等

#### 建议
**迁移到 Python**，原因：
- 已有部分 Python 实现
- grep/find 调用在 Python 中更简洁
- 文本处理是 Python 强项

#### 目标实现
```python
# plugins/mcps/grep-app/main.py
import subprocess
import json

async def search(query: str, path: str = ".", extensions: list[str] = None):
    exclude_dirs = ['node_modules', '.git', '__pycache__']
    grep_cmd = ['grep', '-r', '--exclude-dir=' + '|'.join(exclude_dirs)]
    
    if extensions:
        for ext in extensions:
            grep_cmd.append(f'--include=*.{ext}')
    
    grep_cmd.extend([query, path])
    result = await asyncio.create_subprocess_exec(*grep_cmd, ...)
```

---

### 4. build agent (1,257 行)

#### 功能模块
```
- cmd_project()                    # 构建项目
- cmd_status()                     # 构建状态
- cmd_logs()                       # 查看日志
- build_run_make()                 # 运行 make
- build_get_logs()                 # 获取日志
```

#### 外部依赖
- **make** - GNU Make
- **pacman/apt** - 包管理器
- **opencode-termux Makefile** - 外部构建脚本

#### 迁移难点
1. **Makefile 调用**: 依赖外部构建系统
2. **包管理器**: pacman/apt 命令包装
3. **日志解析**: 复杂的文本解析

#### 建议
**保留 Bash**，原因：
- 核心是调用 make 和包管理器
- Shell 脚本更适合系统命令编排
- 迁移收益低

---

### 5. plan agent (1,737 行)

#### 功能模块
```
- cmd_create()                     # 创建计划
- cmd_list()                       # 列出计划
- cmd_analyze()                    # 分析依赖
- cmd_progress()                   # 追踪进度
- plan_validate()                  # 验证计划
- plan_export()                    # 导出计划
```

#### 外部依赖
- **python3** - 部分逻辑已使用 Python
- **无系统依赖** - 纯逻辑处理

#### 迁移难点
1. **依赖分析**: 需要图算法
2. **进度追踪**: 状态管理

#### 建议
**迁移到 Python**，原因：
- 纯逻辑处理，无系统依赖
- 依赖分析适合 Python (networkx 等库)
- 已有部分 Python 实现

#### 目标实现
```python
# plugins/agents/plan/main.py
from dataclasses import dataclass
from typing import Optional
import networkx as nx

@dataclass
class Plan:
    id: str
    title: str
    tasks: list['Task']
    dependencies: nx.DiGraph
    
    def analyze_dependencies(self) -> list[str]:
        """Analyze task dependencies and return execution order"""
        return list(nx.topological_sort(self.dependencies))
```

---

### 6. subagents (worker/scout/librarian/reviewer)

#### worker (349 行)
- **功能**: 任务执行包装
- **依赖**: nodejs, python3
- **建议**: 迁移到 TypeScript (与 pool-manager 集成)

#### scout (2,332 行)
- **功能**: 代码分析、复杂度计算
- **依赖**: git, find, python3
- **建议**: 迁移到 Python (代码分析库)

#### librarian (703 行)
- **功能**: 文档检索
- **依赖**: context7, websearch
- **建议**: 迁移到 TypeScript (MCP 集成)

#### reviewer (893 行)
- **功能**: 代码审查
- **依赖**: python3
- **建议**: 迁移到 Python (AST 分析)

---

## 📈 迁移优先级重估

### P0 - 高价值易迁移

| 插件 | 行数 | 难度 | 工作量 | 价值 |
|------|------|------|--------|------|
| context7 MCP | 984 | 中 | 3 天 | 高 (MCP 集成) |
| plan agent | 1,737 | 低 | 4 天 | 中 (纯逻辑) |

### P1 - 中等价值

| 插件 | 行数 | 难度 | 工作量 | 价值 |
|------|------|------|--------|------|
| grep-app MCP | 2,146 | 中 | 5 天 | 高 (代码搜索) |
| worker | 349 | 低 | 2 天 | 中 (池集成) |
| librarian | 703 | 低 | 3 天 | 中 (文档) |

### P2 - 低价值或高难度

| 插件 | 行数 | 难度 | 工作量 | 建议 |
|------|------|------|--------|------|
| qwen agent | 1,358 | 高 | 10 天 | 保留 Bash |
| build agent | 1,257 | 中 | 5 天 | 保留 Bash |
| scout | 2,332 | 中 | 6 天 | 可选迁移 |
| reviewer | 893 | 低 | 4 天 | 可选迁移 |

---

## 🎯 修订后的迁移计划

### Phase 3A - 核心 MCP (1-2 周)
- [ ] context7 MCP → TypeScript
- [ ] grep-app MCP → Python

### Phase 3B - 功能 Agent (2-3 周)
- [ ] plan agent → Python
- [ ] worker → TypeScript
- [ ] librarian → TypeScript

### Phase 3C - 可选增强 (1-2 周)
- [ ] scout → Python (可选)
- [ ] reviewer → Python (可选)

### 保留 Bash
- qwen agent (包装 qwen CLI)
- build agent (系统命令编排)

---

## 📊 修订工作量评估

| 阶段 | 原评估 | 修订后 | 说明 |
|------|--------|--------|------|
| P0 | 12 天 | 7 天 | qwen agent 保留 |
| P1 | 17 天 | 10 天 | build 保留 |
| P2 | 18 天 | 10 天 | 可选迁移 |
| **总计** | **47 天** | **27 天** | 减少 42% |

---

## ✅ 建议

1. **优先迁移 context7 和 grep-app** - MCP 是核心功能
2. **qwen agent 保留 Bash** - 包装逻辑无需迁移
3. **build agent 保留 Bash** - 系统命令编排更适合 Shell
4. **subagents 选择性迁移** - 根据实际需求

---

**维护者**: OML Team
**许可**: MIT License
