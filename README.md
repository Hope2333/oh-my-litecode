# Oh-My-Litecode (OML)

**Version: 0.2.0-alpha**

A unified AI-assisted development orchestrator with AI-LTC Brain/Body architecture integration.

## Overview

OML is a TypeScript monorepo providing:
- **Plugin system** — agent, subagent, MCP, and skill loading
- **Session management** — create, fork, search, export/import sessions
- **Hooks engine** — event-driven lifecycle with 14+ hook events
- **Worker pool** — parallel task execution with error recovery
- **AI-LTC Bridge** — Brain/Body integration with state machine, memory sync, and platform adapters

## Architecture

| Layer | Framework | Role |
|-------|-----------|------|
| **Brain** | [AI-LTC](https://github.com/Hope2333/AI-LTC) | State machine, memory, error recovery, cross-repo sync |
| **Body** | OML (this repo) | Plugin loading, MCP gateway, session management, worker pool, hooks |
| **Bridge** | `@oml/bridge` | State transition → hook mapping, platform adapters, memory sync |

## Packages

| Package | Description | Status |
|---------|-------------|--------|
| `@oml/core` | Core engine: hooks, session, plugin, pool, platform | ✅ Complete |
| `@oml/cli` | Commander-based CLI with all OML commands | ✅ Complete |
| `@oml/modules` | Backup, cache, cloud, conflict, error, i18n, perf, TUI | ✅ Complete |
| `@oml/bridge` | AI-LTC Bridge: adapters, memory, context, error tracking | ✅ Complete |

## Bridge (Phase 1-4 Complete)

### Phase 1: Bridge Foundation
- `OmlBridge` class — state file watcher, phase transition → hook triggering
- EventMapper — 8 AI-LTC state → OML hook mappings
- VersionSync — version compatibility checking with drift detection
- 7 new bridge HookEvents in `@oml/core/hooks`

### Phase 2: Platform Adapters
- `PlatformAdapter` interface + `AdapterRegistry`
- `OpenCodeAdapter` — reads/writes `.ai/state.json`, forwards events via hooks
- `ClaudeCodeAdapter` — reads/writes `.ai/claude-state.json`, logs events

### Phase 3: Memory & Context Integration
- `MemorySync` — in-memory entry store with add/query/export/import
- `ContextManager` — generates context summaries, escalation detection
- `ErrorTracker` — pattern tracking with occurrence counts and recovery

### Phase 4: Automation & CI
- 130 unit + integration tests (9 test files)
- `scripts/check-bridge-version.mjs` — standalone version compatibility check
- `scripts/deploy-bridge.sh` — install/update/health check
- Bridge version check integrated into `npm run architecture:check`

## Quick Start

```bash
# Install dependencies
npm install

# Build all packages
npm run build

# Run tests
npm test

# Type check
npm run typecheck

# Architecture contract check
npm run architecture:check

# CLI
npx oml --help
npx oml bridge status
npx oml bridge info
npx oml qwen chat
```

## AI-LTC Bridge CLI

```bash
# Check bridge status
npx oml bridge status

# Show bridge configuration
npx oml bridge info

# Test bridge functionality
npx oml bridge test

# Start watching for AI-LTC state changes
npx oml bridge start
```

## Event Mapping

| AI-LTC Transition | OML Hook |
|-------------------|----------|
| `INIT → EXECUTION` | `bridge:execution:start` |
| `HANDOFF_READY → EXECUTION` | `bridge:execution:start` |
| `EXECUTION → REVIEW` | `bridge:review:start` |
| `REVIEW → OPTIMIZER` | `bridge:optimize:start` |
| `OPTIMIZER → CHECKPOINT` | `bridge:checkpoint:create` |
| `REVIEW → EXECUTION` | `bridge:blocked:resolve` |
| `EXECUTION → CHECKPOINT` | `bridge:done:notify` |
| `Any → BLOCKED` | `bridge:blocked:notify` |

## Environment Policy

- OML is **not Termux-only**.
- Execution priority:
  1. **Termux** as first-class citizen (primary validation path)
  2. **GNU/Linux** as secondary supported environment
- No other OS targets are considered unless explicitly required.

## Cross-CLI Adapters

OML provides adapters for all major AI coding CLI tools. Each adapter connects to OML Core's shared logic layer.

| CLI | Adapter Dir | Extension Format | Status |
|-----|------------|-----------------|--------|
| OpenCode | `opencode/` | oh-my-openagent.json + Plugin SDK | ✅ Full (OMO) |
| Qwen Code | `qwen/` | qwen-extension.json + QWEN.md | 🔄 Partial |
| Gemini CLI | `gemini/` | gemini-extension.json + GEMINI.md | 🔄 Partial |
| Claude Code | `claude/` | claude-plugin.json + Skills | 📋 Entry |
| Aider | `aider/` | .aider.conf.yaml + Commands | 📋 Entry |
| Codex CLI | `codex/` | TBD | 📋 Entry |

**Architecture**: See [docs/CROSS-CLI-ADAPTER-ARCHITECTURE.md](docs/CROSS-CLI-ADAPTER-ARCHITECTURE.md)
**OML Core Spec**: See [docs/OML-CORE-SPEC.md](docs/OML-CORE-SPEC.md)
**AI-LTC Integration**: See [.ai/modernization/oml-ai-ltc-integration.md](.ai/modernization/oml-ai-ltc-integration.md)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Upstream Projects

- [OpenCode](https://github.com/anomalyco/opencode) - MIT License
- [Bun](https://github.com/oven-sh/bun) - MIT License
- [bun-termux-loader](https://github.com/kaan-escober/bun-termux-loader) - MIT License

## Archive

本仓库包含历史版本存档于 `archive/` 目录：

- **[archive/legacy-qwenx/](archive/legacy-qwenx/)** - 实验室版 qwenx (已废弃)
  - **状态**: ❌ 已废弃，不推荐新开发
  - **用途**: 历史参考、迁移指南
  - **推荐**: 使用 [0.1.0](https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0) 版本
  - **详情**: [archive/ARCHIVE-MANIFEST.md](archive/ARCHIVE-MANIFEST.md)

## Version Tags

| 版本 | 语言 | 状态 | 推荐 |
|------|------|------|------|
| **[0.2.0-alpha](https://github.com/Hope2333/oh-my-litecode/releases/tag/0.2.0-alpha)** | 100% TypeScript | ✅ 当前 | ⭐⭐⭐⭐⭐ |
| **[0.1.0](https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0)** | TS + Py + Bash | ✅ 保留 | ⭐⭐⭐⭐ |
| **[0.1.0-bash](https://github.com/Hope2333/oh-my-litecode/releases/tag/0.1.0-bash)** | 100% Bash | ✅ 保留 | ⭐⭐⭐ |
| **legacy-qwenx** | 100% Bash | ❌ 废弃 | ❌ |

**详情**: [docs/TAGS.md](docs/TAGS.md)
