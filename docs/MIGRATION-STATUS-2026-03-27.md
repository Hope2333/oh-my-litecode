# Bash → TypeScript 迁移状态报告

**Date**: 2026-03-27  
**Version**: 0.2.1-bashoff (准备中)

---

## 文件统计

| 类型 | 数量 | 说明 |
|------|------|------|
| Bash (.sh) | 187 | 视为草稿/待归档 |
| TypeScript (.ts) | 3252 | 已迁移/新开发 |
| Python (.py) | 33 | 工具脚本/保留 |

---

## Bash 文件分布

| 目录 | 文件数 | 迁移状态 |
|------|--------|----------|
| core/*.sh | 19 | ✅ 已迁移 (Pool 5 + Session 6 + Plugin 1 + 其他 7) |
| modules/*.sh | 15 | ✅ 已迁移 (Cloud 2 + Perf 2 + Backup 1 + Conflict 1 + I18n 1 + TUI 1 + 其他 7) |
| plugins/**/*.sh | 124 | ⚠️ 部分迁移 (Qwen 插件保留) |
| lib/*.sh | 3 | ⚠️ 待评估 |
| scripts/*.sh | 7 | ⚠️ 待评估 |
| bin/*.sh | 3 | ⚠️ 待评估 |

---

## 已迁移模块 (可归档)

### Core (11 文件)

| 模块 | Bash 文件 | TS 实现 | 状态 |
|------|----------|--------|------|
| Pool | 5 | `packages/core/src/pool/` | ✅ 可归档 |
| Session | 6 | `packages/core/src/session/` | ✅ 可归档 |
| Plugin Loader | 1 | `packages/core/src/plugin/` | ✅ 可归档 |

### Modules (8 文件)

| 模块 | Bash 文件 | TS 实现 | 状态 |
|------|----------|--------|------|
| Cloud Sync | 2 | `packages/modules/src/cloud/` | ✅ 可归档 |
| Perf Monitor | 2 | `packages/modules/src/perf/` | ✅ 可归档 |
| Auto Backup | 1 | `packages/modules/src/backup/` | ✅ 可归档 |
| Conflict Resolver | 1 | `packages/modules/src/conflict/` | ✅ 可归档 |
| I18n | 1 | `packages/modules/src/i18n/` | ✅ 可归档 |
| TUI | 1 | `packages/modules/src/tui/` | ✅ 可归档 |

---

## 保留文件 (暂不归档)

### Plugins (124 文件)

- Qwen Agent 插件：保留（用户确认机制已添加）
- 其他插件：待评估

### 工具脚本

- `lib/*.sh` (3): 待评估
- `scripts/*.sh` (7): 待评估
- `bin/*.sh` (3): 待评估

---

## 归档计划

### Phase 1: Core + Modules (本次)

**可归档文件**: 19 个
- `core/pool-*.sh` (5)
- `core/session-*.sh` (6)
- `core/plugin-loader.sh` (1)
- `modules/cloud-*.sh` (2)
- `modules/perf-*.sh` (2)
- `modules/auto-backup.sh` (1)
- `modules/conflict-resolver.sh` (1)
- `modules/i18n.sh` (1)
- `modules/tui-*.sh` (1)

**操作**: 移动到 `archive/bash-legacy/`

### Phase 2: Plugins (后续)

**待评估**: 124 文件
- 确定哪些插件需要保留
- 确定哪些插件需要迁移

### Phase 3: Tools (后续)

**待评估**: 13 文件
- `lib/*.sh`, `scripts/*.sh`, `bin/*.sh`

---

## 版本计划

**0.2.1-bashoff**: Bash 归档版本
- 所有已迁移模块的 bash 文件归档
- 保留 plugins 和工具脚本
- 文档更新

---

## 验证清单

- [ ] `npm run architecture:check` ✅
- [ ] `npm run build` ✅
- [ ] `npm run typecheck` ✅
- [ ] `npm test` ✅
- [ ] 归档文件到 `archive/bash-legacy/`
- [ ] 更新文档
- [ ] 打 tag `v0.2.1-bashoff`
