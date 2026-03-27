# OML TypeScript Packages

**Last Updated**: 2026-03-26  
**Status**: Evidence-Based Completion Tracking

---

## Packages

| Package | Description | Status | Evidence |
|---------|-------------|--------|----------|
| `@oml/core` | Core functionality | 🟡 Partial | ✅ utils, platform, session, plugin, hooks, fakehome, pool<br>⚠️ parity proof still incomplete |
| `@oml/cli` | CLI interface | 🟡 Partial | ✅ qwen/session/plugin/cloud/perf/tui wiring, package contract fixed<br>⚠️ chat, config, keys, mcp remain stubbed |
| `@oml/modules` | Feature modules | 🟡 Partial | ✅ backup, cache, cloud, conflict, error, i18n, perf, switchers, tui<br>⚠️ file logging still TODO |

### Status Legend

| Symbol | Meaning | Criteria |
|--------|---------|----------|
| ✅ Complete | 功能完整 | 100% 功能覆盖 + 测试覆盖 80%+ |
| 🟡 Partial | 部分实现 | 核心功能可用 + 部分占位 |
| 🔴 WIP | 进行中 | 实现中 |
| ⏳ Planned | 计划中 | 已规划未开始 |

---

## Quick Start

### Install Dependencies

```bash
npm install
```

### Build

```bash
npm run build
```

### Type Check

```bash
npm run typecheck
```

### Test

```bash
npm run test
```

## Package Structure

```
packages/
├── core/           # Core functionality
│   ├── src/
│   │   ├── utils/      ✅ Logger, Config
│   │   ├── platform/   ✅ Platform detection
│   │   ├── session/    ✅ Session management
│   │   ├── plugin/     ✅ Plugin loader
│   │   ├── hooks/      ✅ Hooks system
│   │   ├── fakehome/   ✅ Fakehome detection
│   │   └── pool/       ✅ Pool management
│   ├── tests/
│   │   ├── logger.test.ts    ✅ 4 tests
│   │   ├── platform.test.ts  ✅ 4 tests
│   │   ├── plugin.test.ts    ✅ 12 tests
│   │   ├── pool.test.ts      ✅ 13 tests
│   │   └── session.test.ts   ✅ 24 tests
│   └── package.json
│
├── cli/            # CLI interface
│   ├── src/
│   │   ├── commands/   ✅ qwen/plugin/cloud/perf/tui wiring
│   │   ├── ui/         ✅ tree menu
│   │   ├── input/      ⚠️ basic
│   │   └── bin/        ✅ oml entry point
│   ├── tests/
│   │   └── qwen-command.test.ts  ✅ 2 tests
│   └── package.json
│
└── modules/        # Additional modules
    ├── src/
    │   ├── backup/     ✅ Backup manager
    │   ├── cache/      ✅ Cache manager
    │   ├── cloud/      ✅ Cloud sync
    │   ├── conflict/   ✅ Conflict resolver
    │   ├── error/      ⚠️ Error reporter (no file logging)
    │   ├── i18n/       ✅ Translator
    │   ├── perf/       ✅ Perf monitor
    │   └── switchers/  ✅ Key/OAuth switchers
    ├── tests/
    │   ├── cloud.test.ts       ✅ 12 tests
    │   ├── perf.test.ts        ✅ 13 tests
    │   ├── integration.test.ts ✅ integration coverage
    │   └── smoke.test.ts       ✅ 1 test
    └── package.json
```

## Migration from Shell

To migrate from shell-based OML to TypeScript-based OML:

```bash
# Run migration tool
./scripts/migrate-to-ts.sh

# Use new CLI
./bin/oml.sh --help
```

## API Examples

### Core - Session Management

```typescript
import { SessionManager } from '@oml/core';

const manager = new SessionManager({ sessionsDir: './sessions' });

// Create session
const session = await manager.create({ name: 'my-session' });

// List sessions
const sessions = await manager.list({ limit: 10 });

// Delete session
await manager.delete(session.id);
```

### Core - Hooks

```typescript
import { registerHook, triggerHook } from '@oml/core';

// Register hook
registerHook('session:create', {
  name: 'my-hook',
  priority: 1,
  enabled: true,
  execute: async (context) => {
    console.log('Session created:', context.data);
  }
});

// Trigger hook
await triggerHook('session:create', { sessionId: '123' });
```

### Modules - Cache

```typescript
import { CacheManager } from '@oml/modules/cache';

const cache = new CacheManager({ maxSize: 100, ttl: 60000 });

cache.set('key', 'value');
const value = cache.get('key');
```

### Modules - I18n

```typescript
import { t, setLocale } from '@oml/modules/i18n';

setLocale('zh-CN');
const welcome = t('welcome'); // '欢迎'
```

## Known Gaps

| Module | Gap | Priority | Planned |
|--------|-----|----------|---------|
| `@oml/modules/error` | File logging | 🟡 P1 | Stage 2 |
| `@oml/cli` | chat/config/keys/mcp full impl | 🟡 P1 | Stage 2 |
| cross-package contract | keep deps/exports/imports aligned | 🔴 P0 | Continuous via `npm run architecture:check` |

## License

MIT
