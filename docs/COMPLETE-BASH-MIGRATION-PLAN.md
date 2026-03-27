# Complete Bash → TypeScript Migration Plan

**Date**: 2026-03-27  
**Target Version**: v0.3.0-allts  
**Goal**: 100% TypeScript, 0% Bash (except solve-android/)

---

## Current Status

| Type | Count | Target |
|------|-------|--------|
| Bash (.sh) | 166 | 0 (archive all) |
| TypeScript (.ts) | 3252 | Active |
| Python (.py) | 33 | Retained (tools) |

---

## Migration Categories

### Category 1: Core Modules (7 files) → `packages/core/src/`

| Bash File | TS Target | Priority |
|-----------|-----------|----------|
| `core/platform.sh` | `packages/core/src/platform/` | 🔴 P0 |
| `core/event-bus.sh` | `packages/core/src/events/` | 🔴 P0 |
| `core/task-registry.sh` | `packages/core/src/task/` | 🔴 P0 |
| `core/hooks-registry.sh` | `packages/core/src/hooks/` | 🟡 P1 |
| `core/hooks-dispatcher.sh` | `packages/core/src/hooks/` | 🟡 P1 |
| `core/hooks-engine.sh` | `packages/core/src/hooks/` | 🟡 P1 |
| `core/fakehome-fix.sh` | `packages/core/src/platform/` | 🟢 P2 |

### Category 2: Modules (7 files) → `packages/modules/src/`

| Bash File | TS Target | Priority |
|-----------|-----------|----------|
| `modules/cache-manager.sh` | `packages/modules/src/cache/` | 🟡 P1 |
| `modules/error-reporter.sh` | `packages/modules/src/error/` | 🟡 P1 |
| `modules/offline-mode.sh` | `packages/modules/src/offline/` | 🟢 P2 |
| `modules/parallel-downloader.sh` | `packages/modules/src/download/` | 🟢 P2 |
| `modules/startup-optimizer.sh` | `packages/modules/src/startup/` | 🟢 P2 |
| `modules/incremental-update.sh` | `packages/modules/src/update/` | 🟢 P2 |
| `modules/qwen-deploy.sh` | `packages/modules/src/deploy/` | 🟢 P2 |

### Category 3: Plugins (124 files) → `packages/plugins/`

#### Agents (27 files)
- build agent → `packages/plugins/agents/build/`
- plan agent → `packages/plugins/agents/plan/`
- qwen agent → `packages/plugins/agents/qwen/`
- qwen-key-switcher → `packages/plugins/agents/qwen-key-switcher/`
- qwen-oauth-switcher → `packages/plugins/agents/qwen-oauth-switcher/`

#### Subagents (39 files)
- librarian → `packages/plugins/subagents/librarian/`
- reviewer → `packages/plugins/subagents/reviewer/`
- scout → `packages/plugins/subagents/scout/`
- worker → `packages/plugins/subagents/worker/`
- architect/debugger/documenter/etc → `packages/plugins/subagents/`

#### MCPs (27 files)
- context7 → `packages/plugins/mcps/context7/`
- grep-app → `packages/plugins/mcps/grep-app/`
- websearch → `packages/plugins/mcps/websearch/`
- browser/calendar/database/etc → `packages/plugins/mcps/`

#### Skills (20 files)
- All skills → `packages/plugins/skills/`

#### Core Plugins (11 files)
- hooks-runtime → `packages/plugins/core/hooks-runtime/`

### Category 4: Tools (13 files) → `packages/tools/` or archive

| Bash File | Action | Reason |
|-----------|--------|--------|
| `lib/system-detect.sh` | Migrate to TS | Core utility |
| `lib/package-manager.sh` | Migrate to TS | Core utility |
| `lib/android-perms.sh` | Archive | Android-specific |
| `scripts/*.sh` (7) | Archive | Install scripts |
| `bin/*.sh` (3) | Migrate to TS | CLI entry points |

### Category 5: Tests & Benchmarks (10 files)

| Bash File | Action |
|-----------|--------|
| `tests/*.sh` (3) | Migrate to TS (vitest) |
| `benchmarks/*.sh` (6) | Migrate to TS |
| `tools/*.sh` (3) | Archive or migrate |

---

## Migration Strategy

### Phase 1: Core + Modules (14 files) - Current
- Migrate all core/ and modules/*.sh files
- Update imports and exports
- Verify with architecture:check

### Phase 2: Plugins Structure (124 files)
- Create `packages/plugins/` structure
- Migrate agents first (Qwen, build, plan)
- Migrate subagents (librarian, reviewer, scout, worker)
- Migrate MCPs
- Migrate skills

### Phase 3: Tools + Tests (23 files)
- Migrate lib/*.sh utilities
- Migrate bin/*.sh CLI entry points
- Migrate tests to vitest
- Archive install scripts

### Phase 4: Cleanup
- Remove all .sh files (except solve-android/)
- Update documentation
- Tag v0.3.0-allts

---

## Plugin Structure Standard

```
packages/plugins/
├── agents/
│   ├── <agent-name>/
│   │   ├── src/index.ts      # Main entry
│   │   ├── src/agent.ts      # Agent logic
│   │   ├── src/hooks/        # Hook implementations
│   │   ├── src/scripts/      # Lifecycle scripts
│   │   ├── tests/
│   │   └── plugin.json       # Plugin manifest
├── subagents/
├── mcps/
├── skills/
└── core/
```

---

## Verification Checklist

- [ ] All .sh files migrated or archived
- [ ] All plugins have plugin.json
- [ ] All tests pass (vitest)
- [ ] architecture:check passes
- [ ] Documentation updated
- [ ] Tag v0.3.0-allts created
