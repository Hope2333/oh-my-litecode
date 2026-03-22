# OML 深度探索初步评估报告

**版本**: 0.4.0-alpha  
**日期**: 2026-03-22  
**状态**: 初步评估完成

---

## 📋 执行摘要

### 当前状态 (v0.3.0)

| 维度 | 状态 | 完成度 |
|------|------|--------|
| 基础架构 | ✅ 完成 | 100% |
| Qwen Agent | ✅ 完成 | 100% |
| Worker Subagent | ✅ 完成 | 80% |
| MCPs 集成 | 🚧 进行中 | 60% |
| 任务注册表 | ✅ 完成 | 90% |
| 文档系统 | ✅ 完成 | 85% |

### 探索发现

通过本次深度探索，识别出以下关键发现：

1. **qwenx 原始能力**: 已完全迁移核心功能 (Fake HOME、Context7、MCPs)
2. **OMO 级能力**: 多代理编排、Hooks 自动化、Session 协议未实现
3. **MCP 服务**: 3 个服务已验证可用，但官方服务器列表有 30+ 候选
4. **Subagents**: Worker 已实现，但 Scout/Librarian/Reviewer/Tester 缺失

---

## 🎯 能力对比矩阵

### qwenx 原始能力 vs OML 实现

| 功能模块 | qwenx 原始 | OML v0.3.0 | 迁移状态 |
|---------|-----------|-----------|----------|
| **基础对话** | ✅ | ✅ | ✅ 完全迁移 |
| **Fake HOME** | ✅ | ✅ | ✅ 完全迁移 |
| **Context7 密钥** | ✅ | ✅ | ✅ 完全迁移 |
| **Models 管理** | ✅ | ✅ | ✅ 完全迁移 |
| **MCP 集成** | ✅ | ✅ | ✅ 完全迁移 |
| **Worker 并行** | ❌ | ✅ | 🆕 新增 |
| **Task Registry** | ❌ | ✅ | 🆕 新增 |
| **Scope 冲突检测** | ❌ | ✅ | 🆕 新增 |

### OMO 级能力差距分析

| 能力 | OMO | OML | 优先级 | 复杂度 |
|------|-----|-----|--------|--------|
| 多代理编排 | ✅ | ❌ | 🔴 高 | 高 |
| Hooks 自动化链 | ✅ | ❌ | 🔴 高 | 高 |
| Session 协议 | ✅ | ❌ | 🔴 高 | 中 |
| Background 任务 | ✅ | 🚧 | 🟡 中 | 中 |
| Tmux 可视化 | ✅ | ❌ | 🟡 中 | 高 |
| Slash 命令扩展 | ✅ | ❌ | 🟢 低 | 低 |
| Claude 兼容层 | ✅ | ❌ | 🟢 低 | 中 |

---

## 🔍 MCP 服务能力评估

### 已验证可用 (3)

| MCP 服务 | 工具数 | 状态 | 使用场景 |
|---------|--------|------|---------|
| **Context7** | 2 | ✅ Connected | 库文档查询 |
| **WebSearch (Exa)** | 4 | ✅ Connected | 网络搜索/代码示例 |
| **Grep-App** | 5 | ✅ Connected | 代码搜索/统计 |

### 候选扩展 (30+)

| 类别 | 服务数 | 优先级 | 说明 |
|------|--------|--------|------|
| 官方基础 | 7 | 🟡 中 | Fetch/Filesystem/Git/Memory 等 |
| 云服务 | 12 | 🟢 低 | GitHub/Stripe/MongoDB/Redis 等 |
| 协作工具 | 6 | 🟢 低 | Slack/Notion/Linear/Jira 等 |
| 数据服务 | 5 | 🟢 低 | BigQuery/Elasticsearch/ClickHouse 等 |

### 推荐优先集成

1. **Memory MCP** - 会话记忆持久化
2. **Git MCP** - Git 操作自动化
3. **Filesystem MCP** - 增强文件操作
4. **Browser MCP** - 浏览器自动化

---

## 📊 缺失功能清单

### 🔴 高优先级 (Phase 2)

| 功能 | 说明 | 预计工作量 |
|------|------|-----------|
| **Scout Subagent** | 代码库探测/分析 | 2-3 天 |
| **Librarian Subagent** | 文档检索/整理 | 2-3 天 |
| **Session 协议** | fork/share/unshare/diff | 3-5 天 |
| **Hooks 自动化** | UserPromptSubmit/PreToolUse 等 | 5-7 天 |

### 🟡 中优先级 (Phase 3)

| 功能 | 说明 | 预计工作量 |
|------|------|-----------|
| **Reviewer Subagent** | 代码审查 | 2-3 天 |
| **Tester Subagent** | 测试生成/执行 | 2-3 天 |
| **Background 任务** | 完整 background_output/cancel | 3-5 天 |
| **Tmux 可视化** | 背景代理 pane 可视化 | 5-7 天 |

### 🟢 低优先级 (Phase 4)

| 功能 | 说明 | 预计工作量 |
|------|------|-----------|
| **Slash 命令扩展** | /ralph-loop /refactor 等 | 2-3 天 |
| **Claude 兼容层** | .claude/commands 加载器 | 3-5 天 |
| **Worker 池管理** | 并发限制/资源监控 | 3-5 天 |
| **插件市场** | 在线插件仓库 | 7-10 天 |

---

## 🏗️ 架构演进路线

### 当前架构 (v0.3.0)

```
OML Commander
    ├── Qwen Agent (主代理)
    └── Worker Subagent (并行任务)
```

### 目标架构 (v0.5.0)

```
OML Commander
    ├── Agent 层
    │   ├── Qwen Agent
    │   ├── Gemini Agent (候选)
    │   └── OpenCode Agent (候选)
    ├── Subagent 层
    │   ├── Worker (实现)
    │   ├── Scout (探测)
    │   ├── Librarian (检索)
    │   ├── Reviewer (审查)
    │   └── Tester (测试)
    ├── MCP 层
    │   ├── Context7
    │   ├── WebSearch
    │   ├── Grep-App
    │   ├── Memory (候选)
    │   └── Git (候选)
    └── 服务层
        ├── Task Registry
        ├── Session Manager
        └── Hooks Engine
```

---

## 📝 文档需求分析

### 长期文档 (面向所有用户)

| 文档 | 受众 | 状态 | 优先级 |
|------|------|------|--------|
| README-OML.md | 所有用户 | ✅ 完成 | - |
| QUICKSTART.md | 新用户 | ✅ 完成 | - |
| OML-PLUGINS.md | 开发者 | ✅ 完成 | - |
| **MCP 集成指南** | 开发者 | ❌ 缺失 | 🔴 高 |
| **Subagents 开发指南** | 开发者 | ❌ 缺失 | 🔴 高 |
| **架构演进史** | 所有用户 | ❌ 缺失 | 🟡 中 |

### 任务文档 (面向开发团队)

| 文档 | 用途 | 状态 |
|------|------|------|
| **Phase 2 任务清单** | 追踪高优先级功能 | ❌ 待创建 |
| **Phase 3 任务清单** | 追踪中优先级功能 | ❌ 待创建 |
| **API 设计文档** | 接口规范 | ❌ 待创建 |
| **测试计划** | 测试策略 | ❌ 待创建 |

### 任务状态文档 (实时追踪)

| 文档 | 更新频率 | 状态 |
|------|---------|------|
| **TODOS.md** | 每日 | ❌ 待创建 |
| **SESSION_SUMMARY.md** | 每会话 | ❌ 待创建 |
| **DECISION_LOG.md** | 每决策 | ❌ 待创建 |

### 提示词工程文档

| 文档 | 用途 | 状态 |
|------|------|------|
| **Agent 提示词模板** | Subagent 行为定义 | ❌ 待创建 |
| **Task 提示词模板** | 任务分解策略 | ❌ 待创建 |
| **MCP 工具调用示例** | 工具使用指南 | ❌ 待创建 |

---

## 🎯 下一步行动计划

### 纲：Phase 2 高优先级功能开发

#### 1. Scout Subagent 实现
- 1.1 代码库探测逻辑
- 1.2 文件结构分析
- 1.3 依赖关系图谱
- 1.4 与 Worker 集成

#### 2. Librarian Subagent 实现
- 2.1 文档检索逻辑
- 2.2 Context7 MCP 集成
- 2.3 WebSearch MCP 集成
- 2.4 知识图谱构建

#### 3. Session 协议实现
- 3.1 Session 存储结构
- 3.2 fork/share/unshare/diff 命令
- 3.3 会话状态管理
- 3.4 与 Task Registry 集成

#### 4. Hooks 自动化引擎
- 4.1 事件系统基础架构
- 4.2 UserPromptSubmit Hook
- 4.3 PreToolUse Hook
- 4.4 PostToolUse Hook
- 4.5 Stop Hook

---

## 📊 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| MCP 服务不稳定 | 中 | 高 | 本地 fallback + 重试机制 |
| Subagent 冲突 | 高 | 中 | Scope 隔离 + 冲突检测 |
| 性能下降 | 中 | 中 | Worker 池限制 + 资源监控 |
| 文档滞后 | 高 | 低 | 边做边写 + 自动化生成 |

---

## 📈 成功指标

### Phase 2 完成标准

- [ ] Scout/Librarian 子代理可用
- [ ] Session 协议完整实现
- [ ] Hooks 自动化链可用
- [ ] 测试覆盖率 > 90%
- [ ] 文档完整度 > 95%

### 长期成功指标

- [ ] 与 oh-my-qwencoder 能力对齐 > 80%
- [ ] 插件数量 > 10
- [ ] 用户满意度 > 90%
- [ ] 月活跃用户 > 100

---

**报告生成时间**: 2026-03-22  
**下次评估**: Phase 2 完成后  
**维护者**: OML Team
