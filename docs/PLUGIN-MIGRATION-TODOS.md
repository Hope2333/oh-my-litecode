# Plugins Migration - Deep Execution TODOS

**Lane**: plugins-migration  
**Phase**: Execution  
**Target**: v0.4.0-plugins-ts

---

## Phase 1: P0 Agents (3 plugins, 7 days)

### TUI-001: Qwen Agent Migration (3 days)

**Files**:
- `archive/bash-legacy/plugins/agents/qwen/main.sh` (42KB)
- `archive/bash-legacy/plugins/agents/qwen/hooks/` (4 hooks)
- `archive/bash-legacy/plugins/agents/qwen/plugin.json`

**Tasks**:
- [ ] Create `packages/plugins/agents/qwen/` structure
- [ ] Copy and update `plugin.json`
- [ ] Analyze `main.sh` - identify core functions
- [ ] Create `src/types.ts` - Qwen-specific types
- [ ] Create `src/agent.ts` - QwenAgent class
- [ ] Migrate hooks:
  - [ ] `hooks/prompt-scan.sh` → `src/hooks/prompt-scan.ts`
  - [ ] `hooks/result-cache.sh` → `src/hooks/result-cache.ts`
  - [ ] `hooks/session-summary.sh` → `src/hooks/session-summary.ts`
  - [ ] `hooks/tool-permission.sh` → `src/hooks/tool-permission.ts`
- [ ] Create `src/index.ts` - exports
- [ ] Create `tests/agent.test.ts`
- [ ] Create `tests/hooks.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test
- [ ] Update documentation

**Acceptance**:
- All main.sh functions migrated
- All hooks migrated
- Tests pass (>80% coverage)
- `oml plugin run qwen` works

---

### TUI-002: Build Agent Migration (2 days)

**Files**:
- `archive/bash-legacy/plugins/agents/build/main.sh`
- `archive/bash-legacy/plugins/agents/build/hooks/` (2 hooks)

**Tasks**:
- [ ] Create `packages/plugins/agents/build/` structure
- [ ] Copy and update `plugin.json`
- [ ] Create `src/agent.ts` - BuildAgent class
- [ ] Migrate hooks:
  - [ ] `hooks/build-logger.sh` → `src/hooks/build-logger.ts`
  - [ ] `hooks/build-notification.sh` → `src/hooks/build-notification.ts`
- [ ] Create `src/index.ts`
- [ ] Create `tests/agent.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test

---

### TUI-003: Plan Agent Migration (2 days)

**Files**:
- `archive/bash-legacy/plugins/agents/plan/main.sh`
- `archive/bash-legacy/plugins/agents/plan/hooks/` (2 hooks)

**Tasks**:
- [ ] Create `packages/plugins/agents/plan/` structure
- [ ] Copy and update `plugin.json`
- [ ] Create `src/agent.ts` - PlanAgent class
- [ ] Migrate hooks:
  - [ ] `hooks/plan-notification.sh` → `src/hooks/plan-notification.ts`
  - [ ] `hooks/plan-tracker.sh` → `src/hooks/plan-tracker.ts`
- [ ] Create `src/index.ts`
- [ ] Create `tests/agent.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test

---

## Phase 2: P1 Subagents (4 plugins, 4 days)

### TUI-004: Librarian Subagent (1 day)

**Files**:
- `archive/bash-legacy/plugins/subagents/librarian/main.sh`
- `archive/bash-legacy/plugins/subagents/librarian/lib/` (5 libs)

**Tasks**:
- [ ] Create `packages/plugins/subagents/librarian/` structure
- [ ] Create `src/agent.ts` - LibrarianAgent class
- [ ] Migrate libs:
  - [ ] `lib/compile.sh` → `src/lib/compile.ts`
  - [ ] `lib/context7.sh` → `src/lib/context7.ts`
  - [ ] `lib/results.sh` → `src/lib/results.ts`
  - [ ] `lib/utils.sh` → `src/lib/utils.ts`
  - [ ] `lib/websearch.sh` → `src/lib/websearch.ts`
- [ ] Create `src/index.ts`
- [ ] Create `tests/agent.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test

---

### TUI-005: Reviewer Subagent (1 day)

**Files**:
- `archive/bash-legacy/plugins/subagents/reviewer/main.sh`
- `archive/bash-legacy/plugins/subagents/reviewer/lib/` (6 libs)

**Tasks**:
- [ ] Create `packages/plugins/subagents/reviewer/` structure
- [ ] Create `src/agent.ts` - ReviewerAgent class
- [ ] Migrate libs (best-practices, performance, report, security, style, utils)
- [ ] Create `src/index.ts`
- [ ] Create `tests/agent.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test

---

### TUI-006: Scout Subagent (1 day)

**Files**:
- `archive/bash-legacy/plugins/subagents/scout/main.sh`
- `archive/bash-legacy/plugins/subagents/scout/lib/` (5 libs)

**Tasks**:
- [ ] Create `packages/plugins/subagents/scout/` structure
- [ ] Create `src/agent.ts` - ScoutAgent class
- [ ] Migrate libs (complexity, deps, stats, tree, utils)
- [ ] Create `src/index.ts`
- [ ] Create `tests/agent.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test

---

### TUI-007: Worker Subagent (1 day)

**Files**:
- `archive/bash-legacy/plugins/subagents/worker/main.sh`

**Tasks**:
- [ ] Create `packages/plugins/subagents/worker/` structure
- [ ] Create `src/agent.ts` - WorkerAgent class
- [ ] Create `src/index.ts`
- [ ] Create `tests/agent.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test

---

## Phase 3: P1 MCPs (3 plugins, 4 days)

### TUI-008: Context7 MCP (1 day)

**Note**: Already has TypeScript implementation!

**Files**:
- `archive/bash-legacy/plugins/mcps/context7/src/index.ts` (existing)

**Tasks**:
- [ ] Move to `packages/plugins/mcps/context7/`
- [ ] Update `plugin.json`
- [ ] Update `package.json`
- [ ] Verify tests pass
- [ ] Update documentation

---

### TUI-009: Grep-App MCP (2 days)

**Note**: Python MCP - keep as-is or wrap in TS

**Files**:
- `archive/bash-legacy/plugins/mcps/grep-app/`

**Tasks**:
- [ ] Decide: Keep Python or migrate to TS
- [ ] If keep: Create TS wrapper
- [ ] If migrate: Create `src/agent.ts`
- [ ] Update `plugin.json`
- [ ] Create `package.json`
- [ ] Run tests

---

### TUI-010: Websearch MCP (1 day)

**Files**:
- `archive/bash-legacy/plugins/mcps/websearch/main.sh`

**Tasks**:
- [ ] Create `packages/plugins/mcps/websearch/` structure
- [ ] Create `src/agent.ts` - WebsearchAgent class
- [ ] Create `src/index.ts`
- [ ] Create `tests/agent.test.ts`
- [ ] Create `package.json`
- [ ] Run build + test

---

## Phase 4: P2 Plugins (Remaining, 6 days)

### TUI-011: Other MCPs (2 days)

**Plugins**: browser, calendar, database, email, filesystem, git, news, notification, translation, weather

**Tasks**:
- [ ] Create standard structure for each
- [ ] Migrate main functionality
- [ ] Create tests
- [ ] Run build + test

---

### TUI-012: Skills (2 days)

**Plugins**: 20 skill plugins

**Tasks**:
- [ ] Create standard structure
- [ ] Migrate each skill
- [ ] Create tests
- [ ] Run build + test

---

### TUI-013: Other Subagents (2 days)

**Plugins**: architect, debugger, documenter, optimizer, researcher, security-auditor, tester, translator

**Tasks**:
- [ ] Create standard structure
- [ ] Migrate each subagent
- [ ] Create tests
- [ ] Run build + test

---

## Phase 5: Cleanup (2 days)

### TUI-014: Documentation (1 day)

**Tasks**:
- [ ] Update `docs/PLUGIN-MIGRATION-REFERENCE.md`
- [ ] Create plugin SDK documentation
- [ ] Update usage guide
- [ ] Create migration guide for plugin developers

---

### TUI-015: Final Verification (1 day)

**Tasks**:
- [ ] Run full test suite
- [ ] Verify all plugins load correctly
- [ ] Test plugin commands: `oml plugin list/install/run`
- [ ] Create release notes
- [ ] Tag v0.4.0-plugins-ts

---

## Progress Tracking

| Phase | Tasks | Completed | In Progress | Pending |
|-------|-------|-----------|-------------|---------|
| Phase 1: P0 Agents | 3 | 0 | 0 | 3 |
| Phase 2: P1 Subagents | 4 | 0 | 0 | 4 |
| Phase 3: P1 MCPs | 3 | 0 | 0 | 3 |
| Phase 4: P2 Plugins | 3 | 0 | 0 | 3 |
| Phase 5: Cleanup | 2 | 0 | 0 | 2 |
| **Total** | **15** | **0** | **0** | **15** |

---

## Blockers

| ID | Description | Status | Resolution |
|----|-------------|--------|------------|
| B001 | Need to analyze main.sh for each plugin | Pending | Manual review required |
| B002 | Python MCPs migration strategy | Pending | Decision needed |
| B003 | Plugin hooks interface design | Pending | Design review |

---

## Notes

- Start with Qwen agent (highest priority)
- Reuse patterns across similar plugins
- Keep bash scripts for post-install/pre-uninstall
- Archive old bash files after successful migration
