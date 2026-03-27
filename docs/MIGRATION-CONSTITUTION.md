# OML 迁移宪法

**Version**: 1.0  
**Date**: 2026-03-26  
**Status**: Active

// Updated by Qwen on 2026-03-27: corrected stale migration status assumptions and added authority/composition rules

---

## 1. 双轨迁移定义

OML 仓库采用 **双轨迁移策略** (Two-Track Migration):

### Track 1: Legacy Shell (功能基线 + 兼容层)

| 属性 | 说明 |
|------|------|
| **位置** | `core/*.sh`, `modules/*.sh`, `plugins/**/*.sh`, `scripts/*.sh` |
| **角色** | 功能基线、兼容层、迁移参考 |
| **状态** | 维护模式 (仅修复关键 bug) |
| **淘汰计划** | 功能迁移完成后归档 |

### Track 2: TypeScript Packages (未来主线)

| 属性 | 说明 |
|------|------|
| **位置** | `packages/core`, `packages/cli`, `packages/modules` |
| **角色** | 未来主线、新功能开发 |
| **状态** | 积极开发 |
| **完成标准** | Core parity 达成 |

---

## 2. 迁移优先级

### 2026-03-27 校正说明

以下表格主要用于迁移优先级，不再被视为“当前实现存在与否”的唯一真相。
如果它与 `packages/README.md`、`docs/ARCHITECTURE-MONITORING.md`、最新 AI-LTC 审查文档冲突，以后者为准。

尤其是：

- `pool` 不再按 “placeholder only” 理解，当前问题转为 parity 证明和组合契约
- `plugin/cloud/perf/tui` 已有实现存在，但是否可宣称完成仍取决于契约、测试与组合验证

### P0 - 核心功能 (必须优先)

| 模块 | Shell 文件 | TS 状态 | 优先级 |
|------|------------|---------|--------|
| Session | `core/session-*.sh` (6) | 🟡 Partial | 🔴 P0 |
| Pool | `core/pool-*.sh` (5) | ❌ Placeholder | 🔴 P0 |
| Hooks | `core/hooks-*.sh` (4) | ✅ Complete | ✅ Done |
| Platform | `core/platform.sh` (1) | ✅ Complete | ✅ Done |
| Fakehome | `core/fakehome-fix.sh` (1) | ✅ Complete | ✅ Done |

### P1 - 重要功能 (第二阶段)

| 模块 | Shell 文件 | TS 状态 | 优先级 |
|------|------------|---------|--------|
| Plugin Loader | `core/plugin-loader.sh` | ❌ Not started | 🟡 P1 |
| Cloud Sync | `modules/cloud-sync*.sh` (2) | ❌ Not started | 🟡 P1 |
| Perf Monitor | `modules/perf-*.sh` (2) | ❌ Not started | 🟡 P1 |
| Qwen Plugin | `plugins/agents/qwen/` | ⚠️ Basic | 🟡 P1 |
| MCP Plugins | `plugins/mcps/` | ⚠️ Basic | 🟡 P1 |

### P2 - 辅助功能 (第三阶段)

| 模块 | Shell 文件 | TS 状态 | 优先级 |
|------|------------|---------|--------|
| Other Plugins | `plugins/` (rest) | ❌ Not started | 🟢 P2 |
| Tools | `tools/*.sh` (3) | ❌ Not started | 🟢 P2 |
| Scripts | `scripts/*.sh` (6) | ⚠️ Partial | 🟢 P2 |

---

## 3. 迁移流程

### 3.1 标准迁移流程

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  1. Analyze │ ──▶ │  2. Design  │ ──▶ │  3. Implement│
│  Shell 脚本  │     │  TS 接口     │     │  TypeScript  │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  6. Archive │ ◀── │  5. Verify  │ ◀── │  4. Test    │
│  Shell 脚本  │     │  功能对比    │     │  单元测试    │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 3.2 验收标准

| 阶段 | 验收标准 |
|------|----------|
| Design | API 映射文档完成 |
| Implement | TypeScript 代码通过 typecheck |
| Test | 单元测试覆盖 80%+ |
| Verify | 功能对比测试通过 |
| Archive | Shell 脚本标记为 deprecated |

---

## 4. 兼容层策略

### 4.1 Shell 兼容层

```bash
#!/usr/bin/env bash
# bin/oml.sh

OML_CLI="$(dirname "$0")/../packages/cli/dist/bin/oml.js"
exec node "$OML_CLI" "$@"
```

### 4.2 API 版本控制

```typescript
// 旧 API (兼容)
class SessionManagerV1 {
  create(name?: string): Promise<Session> { }
}

// 新 API (推荐)
class SessionManagerV2 {
  create(options: SessionCreateOptions): Promise<Session> { }
}
```

---

## 5. 文档同步规则

### 5.1 文档更新时机

| 事件 | 文档更新 |
|------|----------|
| 新模块实现 | 更新 `packages/README.md` |
| API 变更 | 更新 API 映射文档 |
| 功能完成 | 更新完成度状态 |
| Shell 归档 | 更新迁移进度 |

### 5.2 完成度状态定义

| 状态 | 定义 | 标准 |
|------|------|------|
| ✅ Complete | 功能完整 | 100% 功能覆盖 + 测试 80%+ |
| 🟡 Partial | 部分实现 | 核心功能可用 + 部分占位 |
| 🔴 WIP | 进行中 | 实现中 |
| ⏳ Planned | 计划中 | 已规划未开始 |

### 5.3 权威文档规则

当前架构与迁移真相以以下文档为准：

- `packages/README.md`
- `docs/ARCHITECTURE-MONITORING.md`
- `docs/AI-LTC-ARCHITECTURE-AUDIT-2026-03-27.md`
- `.ai/active-lane/*` 本地工作态

`docs/*SUMMARY*.md`、`docs/*FINAL*.md`、`docs/*REPORT*.md`、`docs/PROJECT-100*.md` 默认视为历史快照，不直接作为当前状态来源。

### 5.4 组合门禁

在声称某一批迁移“可组合可交付”之前，至少要满足：

- inter-package imports / dependencies / exports 对齐
- relay handoff 与 active lane 一致
- `npm run architecture:check` 通过

---

## 6. 决策记录

### 决策 1: 双轨迁移 (2026-03-26)

**问题**: `src/` 与 `packages/` 两套 TypeScript 结构并存

**决策**: 
- `packages/` 作为未来主线
- `src/` 作为过渡兼容层 (待淘汰)

**理由**: `packages/` 采用 monorepo 结构，更符合现代 TypeScript 项目规范

### 决策 2: 证据-based 完成度 (2026-03-26)

**问题**: `packages/README.md` 完成度被高估

**决策**: 
- 使用证据-based 状态追踪
- 明确标注已知 gaps

**理由**: 避免路线图被错误基线污染

### 决策 3: 价值切片迁移 (2026-03-26)

**问题**: 全量迁移工作量过大 (12-15 周)

**决策**: 
- 先做治理和 proof path
- 再做 core parity slice
- 最后大规模 plugin/shell 迁移

**理由**: 快速交付价值，降低风险

---

## 7. 参考文档

| 文档 | 说明 |
|------|------|
| `docs/research/SHELL-ANALYSIS.md` | 177 个 Shell 脚本功能分析 |
| `docs/research/MIGRATION-STRATEGY.md` | 迁移策略和设计模式 |
| `docs/research/API-MAPPING.md` | Shell -> TypeScript API 映射 |
| `docs/AI-LTC-ARCHITECTURE-AUDIT-2026-03-27.md` | 最新架构审查报告 |

---

## 8. 维护

| 角色 | 职责 |
|------|------|
| Migration Lead | 更新迁移进度 |
| Tech Lead | 审批决策记录 |
| All Contributors | 遵守迁移流程 |

**下次审查**: 2026-04-02 (每周审查)
