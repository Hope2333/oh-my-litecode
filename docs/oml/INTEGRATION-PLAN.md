# OML 组件整合计划

**版本**: 0.5.0-integration  
**日期**: 2026-03-22  
**状态**: 🟡 规划中

---

## 📋 执行摘要

通过深度探索发现，本地 qwenx 和 OML 实验代码中包含大量可复用组件：

### 发现概览

| 类别 | 数量 | 状态 | 可复用性 |
|------|------|------|---------|
| **Agents/Subagents** | 13 个 | 部分实现 | ⭐⭐⭐⭐⭐ |
| **MCPs 服务** | 4 个已实现 + 30+ 候选 | 3 个可用 | ⭐⭐⭐⭐ |
| **核心模块** | 3 个 | 完成 | ⭐⭐⭐⭐⭐ |
| **实验性组件** | 10+ | 实验中 | ⭐⭐⭐ |
| **文档** | 66+ 份 | 完成 | ⭐⭐⭐⭐⭐ |

---

## 1️⃣ 可复用组件清单

### 1.1 Agents/Subagents (13 个)

#### 已实现 (3)

| Agent | 类型 | 路径 | 复用优先级 |
|-------|------|------|-----------|
| **qwen** | agent | `plugins/agents/qwen/` | ⭐⭐⭐⭐⭐ 已整合 |
| **worker** | subagent | `plugins/subagents/worker/` | ⭐⭐⭐⭐⭐ 已整合 |
| **scout** | subagent | `plugins/subagents/scout/` | ⭐⭐⭐⭐⭐ 已整合 |
| **librarian** | subagent | `plugins/subagents/librarian/` | ⭐⭐⭐⭐⭐ 已整合 |

#### 配置中 (9)

| Agent | 类型 | 配置文件 | 复用优先级 |
|-------|------|---------|-----------|
| **build** | agent | `.qwen/agents/build.md` | ⭐⭐⭐⭐ 高 |
| **plan** | agent | `.qwen/agents/plan.md` | ⭐⭐⭐⭐ 高 |
| **atlas** | agent | `.qwen/agents/atlas.md` | ⭐⭐⭐⭐ 高 |
| **reviewer** | subagent | `.qwen/agents/reviewer.md` | ⭐⭐⭐⭐ 高 |
| **security-auditor** | subagent | `.qwen/agents/security-auditor.md` | ⭐⭐⭐⭐ 高 |
| **oracle** | subagent | `.qwen/agents/oracle.md` | ⭐⭐⭐ 中 |
| **metis** | subagent | `.qwen/agents/metis.md` | ⭐⭐⭐ 中 |
| **momus** | subagent | `.qwen/agents/momus.md` | ⭐⭐⭐ 中 |
| **multimodal-looker** | subagent | `.qwen/agents/multimodal-looker.md` | ⭐⭐ 低 |

### 1.2 MCPs 服务

#### 已实现 (4)

| MCP | 类型 | 状态 | 复用优先级 |
|-----|------|------|-----------|
| **context7** | mcp | ✅ Connected | ⭐⭐⭐⭐⭐ 已整合 |
| **websearch** | mcp | ✅ Connected | ⭐⭐⭐⭐⭐ 已整合 (Librarian) |
| **grep-app** | mcp | ✅ Connected | ⭐⭐⭐⭐ 待整合 |
| **playwright** | mcp | ❌ Disconnected | ⭐⭐ 占位 |
| **rag** | mcp | ❌ Disconnected | ⭐⭐ 占位 |
| **code-analyzer** | mcp | ❌ Disconnected | ⭐⭐ 占位 |

#### 候选扩展 (30+)

推荐优先集成：
1. **Memory MCP** - 会话记忆持久化
2. **Git MCP** - Git 操作自动化
3. **Filesystem MCP** - 增强文件操作
4. **Browser MCP** - 浏览器自动化

### 1.3 核心模块 (3)

| 模块 | 路径 | 行数 | 复用优先级 |
|------|------|------|-----------|
| **task-registry.sh** | `core/task-registry.sh` | 398 | ⭐⭐⭐⭐⭐ 已整合 |
| **plugin-loader.sh** | `core/plugin-loader.sh` | 504 | ⭐⭐⭐⭐⭐ 已整合 |
| **platform.sh** | `core/platform.sh` | 262 | ⭐⭐⭐⭐⭐ 已整合 |

### 1.4 实验性组件

| 组件 | 路径 | 状态 | 复用价值 |
|------|------|------|---------|
| **OML Orchestrator** | `~/.local/state/oml/orchestrator/` | 实验中 | ⭐⭐⭐⭐ |
| **Session 管理** | `~/.local/state/oml/sessions/` | 实验中 | ⭐⭐⭐⭐ |
| **Librarian 缓存** | `~/.local/cache/oml/librarian/` | 实验中 | ⭐⭐⭐ |
| **Task Registry 数据** | `~/.oml/tasks/registry.json` | 实验中 | ⭐⭐⭐⭐⭐ |

---

## 2️⃣ 整合策略

### 2.1 立即整合 (Phase 2.5)

#### Grep-App MCP 整合

**目标**: 将 grep-app MCP 整合到 Scout Subagent

**实施步骤**:
1. 创建 `plugins/mcps/grep-app/` 目录
2. 编写 plugin.json 元数据
3. 实现 main.sh 主入口
4. 与 Scout 集成 (依赖分析增强)

**预期收益**:
- Scout 代码搜索能力增强
- 依赖分析准确率提升

#### Agent 配置整合

**目标**: 将 9 个配置中的 Agent 实现为插件

**实施步骤**:
1. 读取 `.qwen/agents/*.md` 配置
2. 创建插件模板
3. 实现核心功能
4. 集成到 OML 命令系统

**优先级**:
1. build, plan, atlas (主代理)
2. reviewer, security-auditor (子代理)
3. oracle, metis, momus (顾问)
4. multimodal-looker (特殊用途)

---

### 2.2 中期整合 (Phase 3)

#### Session 协议整合

**目标**: 实现完整的 Session 管理系统

**可复用组件**:
- `~/.local/state/oml/orchestrator/sessions/` - 会话数据存储
- `.qwen/projects/[hash]/chats/*.jsonl` - 聊天记录
- `.qwen/todos/[session-id].json` - TODO 列表

**实施步骤**:
1. 设计 Session 元数据结构
2. 实现 fork/share/unshare/diff 命令
3. 集成 Task Registry
4. 可视化支持

#### Hooks 自动化引擎

**目标**: 实现完整的事件钩子系统

**可复用组件**:
- `.qwen/commands/` 中的命令配置
- Safety preflight 检查逻辑
- Migration overlay 机制

**实施步骤**:
1. 实现事件总线
2. 注册 Hook 处理器
3. 实现 UserPromptSubmit/PreToolUse/PostToolUse/Stop Hooks
4. 集成到 Agent 路由

---

### 2.3 长期整合 (Phase 4)

#### 占位 MCP 实现

**目标**: 实现或移除占位 MCP 服务

**选项**:
1. **Playwright MCP** - 评估 Termux 可行性，如不可行则移除
2. **RAG MCP** - 使用轻量级向量库实现
3. **Code-Analyzer MCP** - 集成现有 grep-app 或实现新服务

#### Worker 池管理

**目标**: 实现并发控制和资源管理

**功能**:
- 最大并行任务数限制
- CPU/内存资源监控
- 任务优先级队列
- 自动故障恢复

---

## 3️⃣ 整合路线图

### Phase 2.5 (2026-03-23 ~ 2026-03-29)

| 任务 | 负责人 | 截止 | 状态 |
|------|--------|------|------|
| Grep-App MCP 整合 | TBD | 3/25 | 📋 计划 |
| Build Agent 实现 | TBD | 3/26 | 📋 计划 |
| Plan Agent 实现 | TBD | 3/27 | 📋 计划 |
| Reviewer Subagent 实现 | TBD | 3/28 | 📋 计划 |
| Security Auditor 实现 | TBD | 3/29 | 📋 计划 |

### Phase 3 (2026-03-30 ~ 2026-04-12)

| 任务 | 负责人 | 截止 | 状态 |
|------|--------|------|------|
| Session 协议设计 | TBD | 4/2 | 📋 计划 |
| Session 协议实现 | TBD | 4/5 | 📋 计划 |
| Hooks 引擎设计 | TBD | 4/6 | 📋 计划 |
| Hooks 引擎实现 | TBD | 4/12 | 📋 计划 |

### Phase 4 (2026-04-13 ~ 2026-04-26)

| 任务 | 负责人 | 截止 | 状态 |
|------|--------|------|------|
| Worker 池管理 | TBD | 4/19 | 📋 计划 |
| 占位 MCP 评估 | TBD | 4/22 | 📋 计划 |
| 插件市场原型 | TBD | 4/26 | 📋 计划 |

---

## 4️⃣ 文件路径映射

### 4.1 Qwenx → OML

| Qwenx 路径 | OML 路径 | 状态 |
|-----------|---------|------|
| `~/.local/home/qwenx/.qwen/AGENTS.md` | `docs/oml/AGENTS-INTEGRATION.md` | 📋 计划 |
| `~/.local/home/qwenx/.qwen/agents/*.md` | `plugins/agents/*/plugin.json` | 🟡 进行中 |
| `~/.local/home/qwenx/.qwen/commands/*.md` | `docs/oml/COMMANDS.md` | 📋 计划 |
| `~/.local/home/qwenx/.oml/tasks/registry.json` | `~/.oml/tasks/registry.json` | ✅ 已整合 |

### 4.2 实验 → 生产

| 实验路径 | 生产路径 | 状态 |
|---------|---------|------|
| `~/.local/state/oml/orchestrator/` | `core/orchestrator.sh` | 📋 计划 |
| `~/.local/state/oml/sessions/` | `~/.oml/sessions/` | 📋 计划 |
| `~/.local/cache/oml/librarian/` | `~/.oml/cache/librarian/` | ✅ 已整合 |

---

## 5️⃣ 配置片段复用

### 5.1 Agent 路由配置

```json
{
  "routing": {
    "primary": ["qwen", "build", "plan", "atlas"],
    "subagents": ["worker", "scout", "librarian", "reviewer", "security-auditor"],
    "advisors": ["oracle", "metis", "momus"],
    "special": ["multimodal-looker"]
  },
  "guideline": {
    "需求不明确": "plan",
    "实现阶段": "build",
    "提交前": ["reviewer", "security-auditor"],
    "对外说明": "doc-writer"
  }
}
```

### 5.2 Safety Baseline

```json
{
  "safety": {
    "default_no_write_to_PREFIX": true,
    "REALHOME_readonly_default": true,
    "project_dir_writable": true,
    "compat_layer_preserved": true
  }
}
```

### 5.3 Gate-Oriented Workflow

```json
{
  "gates": {
    "变更前行": "/safety-preflight",
    "叠加迁移": "/migration-overlay",
    "收尾校验": ["validation-gate", "release-check"]
  }
}
```

---

## 6️⃣ 代码复用示例

### 6.1 Task Registry API

```bash
# 从 Qwenx 复用的任务管理 API
oml tasks init
oml tasks register <id> <agent> <task> [scope]
oml tasks update <id> <status>
oml tasks list [status]
oml tasks info <id>
oml tasks check-conflict <scope>
oml tasks cancel <id>
oml tasks logs <id> [-f]
oml tasks wait-all
```

### 6.2 Worker 命令 API

```bash
# 从 Qwenx 复用的 Worker 命令
oml worker spawn <agent> --task "<desc>" [--scope "<pattern>"]
oml worker status [filter]
oml worker logs --task-id "<id>" [-f]
oml worker cancel --task-id "<id>"
oml worker wait
```

### 6.3 Context7 管理

```bash
# 从 Qwenx 复用的 Context7 管理
oml qwen ctx7 set <k1[@alias]> [k2...]
oml qwen ctx7 add <k1[@alias]> [k2...]
oml qwen ctx7 rotate
oml qwen ctx7 current
oml qwen ctx7 list
oml qwen ctx7 remove <alias>
oml qwen ctx7 mode <local|remote|current>
oml qwen ctx7 clear
```

---

## 7️⃣ 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| 配置冲突 | 中 | 高 | 配置迁移脚本 |
| 数据丢失 | 低 | 高 | 完整备份策略 |
| 性能下降 | 中 | 中 | 性能基准测试 |
| 文档滞后 | 高 | 低 | 边做边写文档 |

---

## 8️⃣ 成功指标

### Phase 2.5 完成标准

- [ ] Grep-App MCP 整合完成
- [ ] 3 个新 Agent 实现 (build/plan/reviewer)
- [ ] 测试覆盖率 > 90%
- [ ] 文档完整度 > 95%

### Phase 3 完成标准

- [ ] Session 协议完整实现
- [ ] Hooks 自动化引擎可用
- [ ] 与 Qwenx 配置完全兼容
- [ ] 用户满意度 > 90%

### Phase 4 完成标准

- [ ] Worker 池管理可用
- [ ] 占位 MCP 评估完成
- [ ] 插件市场原型可用
- [ ] 与 oh-my-qwencoder 能力对齐 > 90%

---

## 🔗 相关链接

- [Qwenx AGENTS.md](file:///data/data/com.termux/files/home/.local/home/qwenx/.qwen/AGENTS.md)
- [Qwenx Agents 目录](file:///data/data/com.termux/files/home/.local/home/qwenx/.qwen/agents/)
- [OML Task Registry](file:///data/data/com.termux/files/home/develop/oh-my-litecode/core/task-registry.sh)
- [Phase 2 TODOS](docs/oml/PHASE2-TODOS.md)
- [探索评估报告](docs/oml/EXPLORATION-ASSESSMENT.md)

---

**维护者**: OML Team  
**更新频率**: 每周审查  
**下次更新**: 2026-03-29
