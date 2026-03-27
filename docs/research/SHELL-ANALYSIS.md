# Shell 脚本功能分析报告

**AI-LTC Lane**: shell-migration-research
**Stage**: 1 - Analysis
**Date**: 2026 年 3 月 26 日

---

## 执行摘要

**总计**: 177 个 Shell 脚本文件
**总代码量**: 约 45,000+ 行

| 分类 | 文件数 | 代码行数 | 复杂度 | 迁移优先级 |
|------|--------|----------|--------|------------|
| core/ | 19 | ~12,000 | 高 | 🔴 P0 |
| modules/ | 15 | ~8,000 | 中 | 🔴 P0 |
| plugins/ | 124 | ~22,000 | 中 | 🟡 P1 |
| tools/ | 3 | ~1,000 | 低 | 🟢 P2 |
| scripts/ | 7 | ~2,000 | 低 | 🟢 P2 |

---

## 1. Core 核心功能 (19 文件)

### 1.1 Session 管理 (6 文件)

| 文件 | 行数 | 功能描述 | 主要函数 | 依赖 |
|------|------|----------|----------|------|
| `session-manager.sh` | ~400 | 会话生命周期管理 | session_create, session_resume, session_switch, session_list, session_delete | session-storage |
| `session-storage.sh` | ~350 | 会话持久化存储 | storage_save, storage_load, storage_delete, storage_list | - |
| `session-diff.sh` | ~300 | 会话差异比较 | diff_sessions, diff_format | - |
| `session-fork.sh` | ~350 | 会话分支/复制 | fork_session, copy_session | session-storage |
| `session-search.sh` | ~380 | 会话搜索 | search_sessions, search_messages | session-storage |
| `session-share.sh` | ~320 | 会话分享/导出 | share_session, export_session | session-storage |

**迁移策略**: 已有 TypeScript 实现 (`packages/core/src/session/`)，需补充 diff/fork/search/share 功能

### 1.2 Pool 管理 (5 文件)

| 文件 | 行数 | 功能描述 | 主要函数 | 依赖 |
|------|------|----------|----------|------|
| `pool-manager.sh` | ~450 | 连接池管理 | pool_create, pool_acquire, pool_release, pool_destroy | - |
| `pool-queue.sh` | ~480 | 池队列管理 | queue_add, queue_process, queue_priority | pool-manager |
| `pool-concurrency.sh` | ~420 | 并发控制 | concurrency_limit, semaphore_acquire, semaphore_release | pool-manager |
| `pool-monitor.sh` | ~500 | 池监控 | monitor_stats, monitor_health, monitor_alerts | pool-manager |
| `pool-recovery.sh` | ~520 | 池恢复机制 | recovery_detect, recovery_retry, recovery_fallback | pool-manager, pool-monitor |

**迁移策略**: 当前为占位实现，需要完整重构

### 1.3 Hooks 系统 (4 文件)

| 文件 | 行数 | 功能描述 | 主要函数 | 依赖 |
|------|------|----------|----------|------|
| `hooks-engine.sh` | ~400 | Hooks 引擎 | hook_register, hook_trigger, hook_execute | hooks-registry |
| `hooks-registry.sh` | ~380 | Hooks 注册表 | registry_add, registry_remove, registry_list | - |
| `hooks-dispatcher.sh` | ~350 | Hooks 分发 | dispatch_event, dispatch_async, dispatch_sync | hooks-engine, hooks-registry |
| `event-bus.sh` | ~320 | 事件总线 | event_on, event_off, event_emit | - |

**迁移策略**: 已有 TypeScript 实现 (`packages/core/src/hooks/`)，功能基本覆盖

### 1.4 平台检测 (1 文件)

| 文件 | 行数 | 功能描述 | 主要函数 | 依赖 |
|------|------|----------|----------|------|
| `platform.sh` | ~250 | 平台检测与适配 | platform_detect, platform_label, platform_config | - |

**迁移策略**: 已有 TypeScript 实现 (`packages/core/src/platform/`)，功能已覆盖

### 1.5 Fakehome (1 文件)

| 文件 | 行数 | 功能描述 | 主要函数 | 依赖 |
|------|------|----------|----------|------|
| `fakehome-fix.sh` | ~80 | Fakehome 嵌套修复 | fix_fakehome_home, detect_nesting | - |

**迁移策略**: 已有 TypeScript 实现 (`packages/core/src/fakehome/`)，功能已覆盖

### 1.6 插件系统 (2 文件)

| 文件 | 行数 | 功能描述 | 主要函数 | 依赖 |
|------|------|----------|----------|------|
| `plugin-loader.sh` | ~200 | 插件加载 | plugin_load, plugin_unload, plugin_list | - |
| `task-registry.sh` | ~180 | 任务注册表 | task_register, task_unregister, task_list | - |

**迁移策略**: 需要新建 TypeScript 模块

---

## 2. Modules 功能模块 (15 文件)

### 2.1 缓存管理

| 文件 | 行数 | 功能描述 | 迁移状态 |
|------|------|----------|----------|
| `cache-manager.sh` | ~200 | 缓存管理 | ✅ 已有 TS 实现 |

### 2.2 云同步

| 文件 | 行数 | 功能描述 | 迁移状态 |
|------|------|----------|----------|
| `cloud-sync.sh` | ~280 | 云同步 | ❌ 待迁移 |
| `cloud-sync-full.sh` | ~320 | 完整云同步 | ❌ 待迁移 |

### 2.3 错误报告

| 文件 | 行数 | 功能描述 | 迁移状态 |
|------|------|----------|----------|
| `error-reporter.sh` | ~180 | 错误报告 | ✅ 已有 TS 实现 |

### 2.4 国际化

| 文件 | 行数 | 功能描述 | 迁移状态 |
|------|------|----------|----------|
| `i18n.sh` | ~220 | 国际化支持 | ✅ 已有 TS 实现 |

### 2.5 性能监控

| 文件 | 行数 | 功能描述 | 迁移状态 |
|------|------|----------|----------|
| `perf-monitor.sh` | ~200 | 性能监控 | ❌ 待迁移 |
| `perf-tools.sh` | ~280 | 性能工具 | ❌ 待迁移 |

### 2.6 其他模块

| 文件 | 行数 | 功能描述 | 迁移状态 |
|------|------|----------|----------|
| `auto-backup.sh` | ~180 | 自动备份 | ❌ 待迁移 |
| `conflict-resolver.sh` | ~190 | 冲突解决 | ❌ 待迁移 |
| `incremental-update.sh` | ~150 | 增量更新 | ❌ 待迁移 |
| `offline-mode.sh` | ~170 | 离线模式 | ❌ 待迁移 |
| `parallel-downloader.sh` | ~140 | 并行下载 | ❌ 待迁移 |
| `startup-optimizer.sh` | ~160 | 启动优化 | ❌ 待迁移 |
| `tui-theme-manager.sh` | ~200 | TUI 主题管理 | ❌ 待迁移 |
| `qwen-deploy.sh` | ~250 | Qwen 部署 | ❌ 待迁移 |

---

## 3. Plugins 插件系统 (124 文件)

### 3.1 Agents (5 插件，~20 文件)

| 插件 | 文件数 | 功能 | 迁移优先级 |
|------|--------|------|------------|
| qwen | ~8 | Qwen 代理 | 🔴 P0 |
| qwen-key-switcher | ~3 | Key 切换 | 🟡 P1 |
| qwen-oauth-switcher | ~3 | OAuth 切换 | 🟡 P1 |
| build | ~6 | 构建代理 | 🟢 P2 |
| plan | ~6 | 计划代理 | 🟢 P2 |

### 3.2 MCPs (~15 插件，~40 文件)

| 插件 | 文件数 | 功能 | 迁移优先级 |
|------|--------|------|------------|
| context7 | ~5 | Context7 MCP | 🔴 P0 |
| grep-app | ~8 | Grep 搜索 | 🔴 P0 |
| grep-app-enhanced | ~20 | 增强 Grep | 🟡 P1 |
| websearch | ~6 | Web 搜索 | 🟡 P1 |
| 其他 MCPs | ~15 | 各种 MCP | 🟢 P2 |

### 3.3 Skills (~20 插件，~20 文件)

| 技能 | 文件数 | 功能 | 迁移优先级 |
|------|--------|------|------------|
| code-review | ~3 | 代码审查 | 🟡 P1 |
| security-scan | ~3 | 安全扫描 | 🟡 P1 |
| 其他技能 | ~14 | 各种技能 | 🟢 P2 |

### 3.4 Subagents (~10 插件，~44 文件)

| 子代理 | 文件数 | 功能 | 迁移优先级 |
|--------|--------|------|------------|
| librarian | ~10 | 图书管理员 | 🟡 P1 |
| reviewer | ~12 | 审查员 | 🟡 P1 |
| scout | ~8 | 侦察员 | 🟡 P1 |
| 其他子代理 | ~14 | 各种子代理 | 🟢 P2 |

---

## 4. Tools 工具脚本 (3 文件)

| 文件 | 行数 | 功能 | 迁移优先级 |
|------|------|------|------------|
| `healthcheck.sh` | ~100 | 健康检查 | 🟢 P2 |
| `remote-build.sh` | ~150 | 远程构建 | 🟢 P2 |
| `wait-and-build.sh` | ~120 | 等待构建 | 🟢 P2 |

---

## 5. Scripts 部署脚本 (7 文件)

| 文件 | 行数 | 功能 | 迁移优先级 |
|------|------|------|------------|
| `cleanup-fakehome.sh` | ~80 | 清理 fakehome | 🟢 P2 |
| `install-archlinux.sh` | ~150 | Arch 安装 | 🟢 P2 |
| `install-gnulinux.sh` | ~180 | Linux 安装 | 🟢 P2 |
| `migrate-to-ts.sh` | ~100 | TS 迁移工具 | ✅ 已创建 |
| `packaging-common.sh` | ~120 | 打包通用 | 🟢 P2 |
| `update-qwenx.sh` | ~100 | 更新 qwenx | 🟢 P2 |
| `verify-version.sh` | ~100 | 版本验证 | 🟢 P2 |

---

## 6. 依赖关系图

```
core/
├── session-* (相互依赖)
├── pool-* (pool-manager 为核心)
├── hooks-* (hooks-engine 为核心)
└── platform.sh, fakehome-fix.sh (独立)

modules/
├── cache-manager.sh (独立)
├── cloud-sync* (相互依赖)
├── perf-* (相互依赖)
└── 其他 (大部分独立)

plugins/
├── agents/qwen (依赖 core/session, core/hooks)
├── mcps/context7 (独立)
├── mcps/grep-app (依赖 core/session)
└── 其他 (大部分独立)
```

---

## 7. 迁移优先级矩阵

### P0 - 核心功能 (34 文件)
- core/session-* (6) - 部分已有 TS 实现
- core/pool-* (5) - 需要完整实现
- core/hooks-* (4) - 已有 TS 实现
- modules/cache-manager.sh (1) - 已有 TS 实现
- modules/cloud-sync* (2) - 待实现
- modules/perf-* (2) - 待实现
- plugins/qwen (8) - 需要对接
- plugins/context7 (5) - 需要对接
- plugins/grep-app (8) - 需要对接

### P1 - 重要功能 (~50 文件)
- core/plugin-loader.sh, task-registry.sh (2)
- modules/ 其他 (10)
- plugins/qwen-key-switcher, qwen-oauth-switcher (6)
- plugins/grep-app-enhanced, websearch (26)
- plugins/skills (code-review, security-scan) (6)
- plugins/subagents (librarian, reviewer, scout) (30)

### P2 - 辅助功能 (~93 文件)
- plugins/ 其他 (~70)
- tools/ (3)
- scripts/ (7)

---

## 8. 工作量估算

| 优先级 | 文件数 | 复杂度 | 估算时间 |
|--------|--------|--------|----------|
| P0 | 34 | 高 | 3-4 周 |
| P1 | 50 | 中 | 5-6 周 |
| P2 | 93 | 低 | 4-5 周 |

**总计**: 12-15 周

---

**Next Stage**: Stage 2 - 设计阶段，产出 `MIGRATION-STRATEGY.md`
