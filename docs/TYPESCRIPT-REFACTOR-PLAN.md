# OML TypeScript 重构计划

将所有 Shell 脚本重构为 TypeScript 实现，基于 Qwen Code 官方架构设计。

---

## 一、重构目标

### 1.1 为什么要重构为 TypeScript

**Shell 脚本的局限性**:
- 类型不安全，容易出错
- 难以维护和测试
- 缺乏模块化支持
- 错误处理复杂
- 跨平台兼容性差

**TypeScript 的优势**:
- 静态类型检查
- 更好的 IDE 支持
- 模块化架构
- 完善的错误处理
- 跨平台一致行为
- 与 Qwen Code 官方架构对齐

### 1.2 重构原则

1. **保持向后兼容**: 保留 shell 脚本作为兼容层
2. **渐进式重构**: 按模块优先级逐步迁移
3. **测试覆盖**: 每个模块都有完整的单元测试
4. **文档同步**: 重构同时更新文档

---

## 二、当前 Shell 脚本统计

| 分类 | 数量 | 优先级 |
|------|------|--------|
| **核心模块 (core/)** | 19 | 🔴 P0 |
| **Lib 库 (lib/)** | 3 | 🟡 P1 |
| **功能模块 (modules/)** | 15 | 🟡 P1 |
| **插件 (plugins/)** | 124 | 🟢 P2 |
| **脚本 (scripts/)** | 6 | 🟢 P2 |
| **Bin 工具 (bin/)** | 2 | 🔴 P0 |
| **测试 (tests/)** | 3 | 🟡 P1 |
| **Benchmarks** | 5 | 🟢 P2 |
| **总计** | **177** | - |

---

## 三、核心模块重构设计

### 3.1 项目结构

```
packages/
├── core/                      # 核心包
│   ├── src/
│   │   ├── index.ts           # 主入口
│   │   ├── platform/          # 平台检测
│   │   │   ├── index.ts
│   │   │   ├── detector.ts    # 平台检测
│   │   │   ├── types.ts       # 类型定义
│   │   │   └── adapter.ts     # 平台适配
│   │   ├── session/           # 会话管理
│   │   │   ├── index.ts
│   │   │   ├── manager.ts     # 会话管理器
│   │   │   ├── storage.ts     # 会话存储
│   │   │   ├── diff.ts        # 会话 diff
│   │   │   ├── fork.ts        # 会话 fork
│   │   │   ├── search.ts      # 会话搜索
│   │   │   └── types.ts
│   │   ├── pool/              # 连接池管理
│   │   │   ├── index.ts
│   │   │   ├── manager.ts     # 池管理器
│   │   │   ├── queue.ts       # 队列管理
│   │   │   ├── concurrency.ts # 并发控制
│   │   │   ├── monitor.ts     # 监控
│   │   │   ├── recovery.ts    # 恢复机制
│   │   │   └── types.ts
│   │   ├── hooks/             # Hooks 系统
│   │   │   ├── index.ts
│   │   │   ├── engine.ts      # Hooks 引擎
│   │   │   ├── dispatcher.ts  # 分发器
│   │   │   ├── registry.ts    # 注册表
│   │   │   ├── event-bus.ts   # 事件总线
│   │   │   └── types.ts
│   │   ├── plugin/            # 插件系统
│   │   │   ├── index.ts
│   │   │   ├── loader.ts      # 插件加载
│   │   │   └── types.ts
│   │   ├── fakehome/          # Fakehome 管理
│   │   │   ├── index.ts
│   │   │   ├── detector.ts    # 嵌套检测
│   │   │   ├── fixer.ts       # 修复器
│   │   │   └── cleaner.ts     # 清理器
│   │   └── utils/             # 工具函数
│   │       ├── index.ts
│   │       ├── logger.ts      # 日志
│   │       ├── config.ts      # 配置
│   │       └── helpers.ts     # 辅助函数
│   ├── tests/
│   │   ├── platform/
│   │   ├── session/
│   │   ├── pool/
│   │   ├── hooks/
│   │   └── fakehome/
│   ├── package.json
│   └── tsconfig.json
│
├── cli/                       # CLI 包
│   ├── src/
│   │   ├── index.ts
│   │   ├── commands/          # 命令处理
│   │   │   ├── qwen.ts        # Qwen 控制器
│   │   │   ├── session.ts     # 会话命令
│   │   │   ├── config.ts      # 配置命令
│   │   │   ├── keys.ts        # 密钥管理
│   │   │   └── mcp.ts         # MCP 管理
│   │   ├── ui/                # UI 渲染
│   │   │   ├── index.ts
│   │   │   ├── tree-menu.ts   # 树形菜单
│   │   │   └── colors.ts      # 颜色主题
│   │   └── input/             # 输入处理
│   ├── package.json
│   └── tsconfig.json
│
├── modules/                   # 功能模块
│   ├── src/
│   │   ├── cache-manager.ts
│   │   ├── cloud-sync.ts
│   │   ├── error-reporter.ts
│   │   ├── i18n.ts
│   │   ├── perf-monitor.ts
│   │   └── ...
│   ├── package.json
│   └── tsconfig.json
│
└── plugins/                   # 插件系统
    ├── qwen/                  # Qwen 插件
    ├── qwen-key-switcher/     # Key 切换器
    ├── qwen-oauth-switcher/   # OAuth 切换器
    └── ...
```

### 3.2 核心模块详细设计

#### platform (平台检测)

**原 shell 脚本**: `core/platform.sh`

**TypeScript 实现**:
```typescript
// packages/core/src/platform/detector.ts

export type PlatformType = 
  | 'termux' 
  | 'arch' 
  | 'manjaro' 
  | 'endeavouros'
  | 'debian'
  | 'ubuntu'
  | 'fedora'
  | 'rhel'
  | 'opensuse'
  | 'alpine'
  | 'macos'
  | 'windows';

export interface PlatformInfo {
  type: PlatformType;
  arch: string;
  homeDir: string;
  isFakeHome: boolean;
  fakeHomeOriginal?: string;
}

export class PlatformDetector {
  async detect(): Promise<PlatformInfo> {
    // 平台检测逻辑
  }

  async fixFakeHomeNesting(): Promise<void> {
    // Fakehome 嵌套修复
  }
}
```

---

#### session (会话管理)

**原 shell 脚本**: 
- `core/session-manager.sh`
- `core/session-storage.sh`
- `core/session-diff.sh`
- `core/session-fork.sh`
- `core/session-search.sh`
- `core/session-share.sh`

**TypeScript 实现**:
```typescript
// packages/core/src/session/manager.ts

export interface Session {
  id: string;
  name?: string;
  status: 'active' | 'inactive' | 'archived';
  createdAt: Date;
  updatedAt: Date;
  messages: Message[];
  metadata: Record<string, unknown>;
}

export interface Message {
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
  metadata?: Record<string, unknown>;
}

export class SessionManager {
  private storage: SessionStorage;

  async create(name?: string): Promise<Session>;
  async resume(id?: string): Promise<Session>;
  async switch(id: string): Promise<void>;
  async list(limit?: number): Promise<Session[]>;
  async delete(id: string): Promise<void>;
  async export(id: string, format: 'json' | 'md'): Promise<string>;
  async import(file: string): Promise<Session>;
  async fork(id: string, name?: string): Promise<Session>;
  async search(query: string): Promise<Session[]>;
  diff(sessionId1: string, sessionId2: string): Promise<SessionDiff>;
  share(id: string, options: ShareOptions): Promise<string>;
}
```

---

#### pool (连接池管理)

**原 shell 脚本**:
- `core/pool-manager.sh`
- `core/pool-queue.sh`
- `core/pool-concurrency.sh`
- `core/pool-monitor.sh`
- `core/pool-recovery.sh`

**TypeScript 实现**:
```typescript
// packages/core/src/pool/manager.ts

export interface PoolConfig {
  maxConnections: number;
  minConnections: number;
  idleTimeout: number;
  acquireTimeout: number;
}

export interface PoolStats {
  active: number;
  idle: number;
  waiting: number;
  total: number;
}

export class PoolManager<T> {
  constructor(config: PoolConfig);

  async acquire(): Promise<T>;
  async release(resource: T): Promise<void>;
  async destroy(resource: T): Promise<void>;
  getStats(): PoolStats;
  async drain(): Promise<void>;
}

// 并发控制
export class ConcurrencyController {
  constructor(maxConcurrency: number);

  async execute<T>(task: () => Promise<T>): Promise<T>;
  async executeAll<T>(tasks: Array<() => Promise<T>>): Promise<T[]>;
}

// 监控
export class PoolMonitor {
  constructor(pool: PoolManager<unknown>);

  startMonitoring(interval: number): void;
  stopMonitoring(): void;
  getMetrics(): PoolMetrics;
}
```

---

#### hooks (Hooks 系统)

**原 shell 脚本**:
- `core/hooks-engine.sh`
- `core/hooks-dispatcher.sh`
- `core/hooks-registry.sh`
- `core/event-bus.sh`

**TypeScript 实现**:
```typescript
// packages/core/src/hooks/engine.ts

export type HookEvent = 
  | 'session:create'
  | 'session:delete'
  | 'prompt:submit'
  | 'tool:pre-use'
  | 'tool:post-use'
  | 'response:receive'
  | 'session:stop';

export interface HookContext {
  event: HookEvent;
  data: Record<string, unknown>;
  timestamp: Date;
}

export interface HookHandler {
  name: string;
  priority: number;
  execute: (context: HookContext) => Promise<void>;
}

export class HooksEngine {
  private registry: HooksRegistry;
  private dispatcher: HooksDispatcher;
  private eventBus: EventBus;

  register(handler: HookHandler): void;
  unregister(name: string): void;
  async trigger(event: HookEvent, data: Record<string, unknown>): Promise<void>;
  enable(name: string): void;
  disable(name: string): void;
}

// 事件总线
export class EventBus {
  on(event: string, handler: (data: unknown) => void): void;
  off(event: string, handler: (data: unknown) => void): void;
  emit(event: string, data: unknown): void;
}
```

---

#### fakehome (Fakehome 管理)

**原 shell 脚本**: `core/fakehome-fix.sh`, `scripts/cleanup-fakehome.sh`

**TypeScript 实现**:
```typescript
// packages/core/src/fakehome/detector.ts

export interface FakeHomeResult {
  isNested: boolean;
  currentHome: string;
  realHome?: string;
  nestedPaths: string[];
}

export class FakeHomeDetector {
  async detect(): Promise<FakeHomeResult> {
    // 检测嵌套 fakehome
  }
}

// packages/core/src/fakehome/fixer.ts

export class FakeHomeFixer {
  async fix(): Promise<void> {
    // 修复嵌套 fakehome
  }

  async restoreHome(): Promise<void> {
    // 恢复真实 HOME
  }
}

// packages/core/src/fakehome/cleaner.ts

export class FakeHomeCleaner {
  async clean(baseDir: string): Promise<CleanResult> {
    // 清理嵌套 fakehome
  }

  async mergeNested(source: string, target: string): Promise<void> {
    // 合并嵌套数据
  }
}
```

---

## 四、CLI 包设计

### 4.1 Qwen 控制器

**原 shell 脚本**: `plugins/agents/qwen/main.sh`

**TypeScript 实现**:
```typescript
// packages/cli/src/commands/qwen.ts

export class QwenController {
  async chat(query: string, options: ChatOptions): Promise<void>;
  async session(): Promise<void>;
  async config(): Promise<void>;
  async keys(): Promise<void>;
  async mcp(): Promise<void>;
  async extensions(): Promise<void>;
  async migrate(): Promise<void>;
}

// 会话管理子命令
export class SessionCommand {
  async list(limit: number): Promise<void>;
  async show(id: string): Promise<void>;
  async switch(id: string): Promise<void>;
  async create(name?: string): Promise<void>;
  async delete(id: string): Promise<void>;
  async export(id: string, format: string): Promise<void>;
  async import(file: string): Promise<void>;
}

// 配置管理子命令
export class ConfigCommand {
  async show(scope: string): Promise<void>;
  async edit(): Promise<void>;
  async reset(): Promise<void>;
  async backup(): Promise<void>;
}

// 密钥管理子命令
export class KeysCommand {
  async list(): Promise<void>;
  async add(key: string, alias: string): Promise<void>;
  async remove(alias: string): Promise<void>;
  async rotate(): Promise<void>;
  async current(): Promise<void>;
}
```

### 4.2 树形菜单帮助系统

```typescript
// packages/cli/src/ui/tree-menu.ts

export interface MenuNode {
  name: string;
  description: string;
  children?: MenuNode[];
  action?: () => Promise<void>;
}

export class TreeMenu {
  private nodes: MenuNode[];

  constructor(nodes: MenuNode[]);

  render(): void;
  navigate(direction: 'up' | 'down' | 'enter' | 'back'): void;
  select(index: number): void;
}

// 帮助系统
export class HelpSystem {
  showMainHelp(): void;
  showCommandHelp(command: string): void;
  showSubcommandHelp(command: string, subcommand: string): void;
}
```

---

## 五、模块重构映射

| 原 Shell 脚本 | TypeScript 模块 | 优先级 |
|--------------|----------------|--------|
| `core/platform.sh` | `packages/core/src/platform/` | 🔴 P0 |
| `core/session-*.sh` | `packages/core/src/session/` | 🔴 P0 |
| `core/pool-*.sh` | `packages/core/src/pool/` | 🔴 P0 |
| `core/hooks-*.sh` | `packages/core/src/hooks/` | 🔴 P0 |
| `core/fakehome-fix.sh` | `packages/core/src/fakehome/` | 🔴 P0 |
| `core/plugin-loader.sh` | `packages/core/src/plugin/` | 🟡 P1 |
| `core/event-bus.sh` | `packages/core/src/hooks/event-bus.ts` | 🟡 P1 |
| `lib/system-detect.sh` | `packages/core/src/platform/detector.ts` | 🟡 P1 |
| `lib/package-manager.sh` | `packages/modules/src/package-manager.ts` | 🟡 P1 |
| `modules/cache-manager.sh` | `packages/modules/src/cache-manager.ts` | 🟡 P1 |
| `modules/cloud-sync.sh` | `packages/modules/src/cloud-sync.ts` | 🟡 P1 |
| `modules/error-reporter.sh` | `packages/modules/src/error-reporter.ts` | 🟡 P1 |
| `modules/i18n.sh` | `packages/modules/src/i18n.ts` | 🟡 P1 |
| `modules/perf-monitor.sh` | `packages/modules/src/perf-monitor.ts` | 🟡 P1 |
| `bin/oml-install.sh` | `packages/cli/src/install.ts` | 🔴 P0 |
| `bin/oml-update.sh` | `packages/cli/src/update.ts` | 🔴 P0 |
| `plugins/agents/qwen/main.sh` | `packages/plugins/qwen/` | 🟡 P1 |
| `plugins/agents/qwen/scripts/session.sh` | `packages/plugins/qwen/src/session.ts` | 🟡 P1 |

---

## 六、依赖配置

### 6.1 package.json (根)

```json
{
  "name": "oh-my-litecode",
  "version": "0.2.0",
  "private": true,
  "workspaces": [
    "packages/*"
  ],
  "scripts": {
    "build": "turbo run build",
    "dev": "turbo run dev",
    "test": "turbo run test",
    "lint": "turbo run lint",
    "typecheck": "turbo run typecheck"
  },
  "devDependencies": {
    "turbo": "^2.0.0",
    "typescript": "^5.4.0",
    "vitest": "^1.0.0",
    "eslint": "^8.0.0",
    "@types/node": "^20.0.0"
  }
}
```

### 6.2 packages/core/package.json

```json
{
  "name": "@oml/core",
  "version": "0.2.0",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  },
  "scripts": {
    "build": "tsc",
    "dev": "tsc --watch",
    "test": "vitest",
    "lint": "eslint src/"
  },
  "dependencies": {
    "zod": "^3.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "^5.4.0",
    "vitest": "^1.0.0"
  }
}
```

### 6.3 tsconfig.json (根)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "lib": ["ES2022"],
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "./dist",
    "rootDir": "./src"
  }
}
```

---

## 七、实施计划

### 阶段 1: 核心基础设施 (2 周) 🔴

**目标**: 实现核心包的基础设施

- [ ] 项目结构搭建
- [ ] TypeScript 配置
- [ ] 构建系统配置 (Turbo)
- [ ] 测试框架配置 (Vitest)
- [ ] 日志系统
- [ ] 配置系统

**交付物**:
- `packages/core` 基础框架
- 构建和测试流程

### 阶段 2: 核心模块重构 (4 周) 🔴

**目标**: 重构核心模块

- [ ] Platform 模块
- [ ] Session 模块
- [ ] Pool 模块
- [ ] Hooks 模块
- [ ] Fakehome 模块

**交付物**:
- `packages/core` 完整功能
- 单元测试覆盖 > 80%

### 阶段 3: CLI 包实现 (3 周) 🟡

**目标**: 实现 CLI 控制器

- [ ] Qwen 控制器
- [ ] 会话命令
- [ ] 配置命令
- [ ] 密钥管理
- [ ] 树形菜单帮助系统

**交付物**:
- `packages/cli` 完整功能
- 命令行界面

### 阶段 4: 模块和插件 (4 周) 🟡

**目标**: 重构功能模块和插件

- [ ] 缓存管理
- [ ] 云同步
- [ ] 错误报告
- [ ] i18n
- [ ] Qwen 插件
- [ ] Key 切换器
- [ ] OAuth 切换器

**交付物**:
- `packages/modules` 功能模块
- `packages/plugins` 插件系统

### 阶段 5: 兼容层和迁移 (2 周) 🟢

**目标**: 创建兼容层，支持渐进式迁移

- [ ] Shell 兼容层
- [ ] 迁移工具
- [ ] 文档更新

**交付物**:
- 向后兼容的 shell 脚本
- 迁移指南

---

## 八、测试策略

### 8.1 单元测试

```typescript
// packages/core/tests/session/manager.test.ts

import { describe, it, expect, beforeEach } from 'vitest';
import { SessionManager } from '../../src/session/manager';

describe('SessionManager', () => {
  let manager: SessionManager;

  beforeEach(() => {
    manager = new SessionManager();
  });

  it('should create a new session', async () => {
    const session = await manager.create('test-session');
    expect(session.name).toBe('test-session');
    expect(session.status).toBe('active');
  });

  it('should list sessions', async () => {
    await manager.create('session-1');
    await manager.create('session-2');
    
    const sessions = await manager.list();
    expect(sessions).toHaveLength(2);
  });

  it('should delete a session', async () => {
    const session = await manager.create('to-delete');
    await manager.delete(session.id);
    
    const sessions = await manager.list();
    expect(sessions).not.toContainEqual(
      expect.objectContaining({ id: session.id })
    );
  });
});
```

### 8.2 集成测试

```typescript
// packages/core/tests/integration/session-flow.test.ts

import { describe, it, expect } from 'vitest';
import { SessionManager } from '../../src/session/manager';
import { HooksEngine } from '../../src/hooks/engine';

describe('Session Flow Integration', () => {
  it('should trigger hooks during session lifecycle', async () => {
    const sessionManager = new SessionManager();
    const hooksEngine = new HooksEngine();
    
    let hookCalled = false;
    hooksEngine.register({
      name: 'test-hook',
      priority: 1,
      execute: async (context) => {
        if (context.event === 'session:create') {
          hookCalled = true;
        }
      }
    });

    await sessionManager.create('test');
    expect(hookCalled).toBe(true);
  });
});
```

---

## 九、迁移指南

### 9.1 从 Shell 迁移到 TypeScript

**Shell 脚本**:
```bash
#!/bin/bash
qwen_session_create() {
    local name="$1"
    local session_id="qwen-session-$(date +%s)-$$-${RANDOM}"
    
    local session_data=$(python3 -c "
import json
print(json.dumps({
    'session_id': '${session_id}',
    'name': '${name}',
    'status': 'active',
    'created_at': '$(date -Iseconds)'
}))
")
    
    echo "$session_data" > "${QWEN_SESSION_DIR}/${session_id}.json"
}
```

**TypeScript 实现**:
```typescript
async create(name?: string): Promise<Session> {
  const session: Session = {
    id: `qwen-session-${Date.now()}-${process.pid}`,
    name,
    status: 'active',
    createdAt: new Date(),
    updatedAt: new Date(),
    messages: [],
    metadata: {}
  };

  await this.storage.save(session);
  await this.hooks.trigger('session:create', { session });
  
  return session;
}
```

### 9.2 兼容性处理

```bash
#!/bin/bash
# 兼容层：调用 TypeScript 实现
oml() {
    local cmd="$1"
    shift
    
    # 使用 TypeScript 实现
    node /path/to/packages/cli/dist/index.js "$cmd" "$@"
}
```

---

## 十、参考资源

### 官方文档
- [Qwen Code 架构](https://qwenlm.github.io/qwen-code-docs/zh/developers/architecture/)
- [Qwen Code 工具](https://qwenlm.github.io/qwen-code-docs/en/developers/tools/introduction/)
- [Qwen Code 扩展](https://qwenlm.github.io/qwen-code-docs/en/users/extension/introduction/)

### TypeScript 资源
- [TypeScript 官方文档](https://www.typescriptlang.org/docs/)
- [Node.js TypeScript 最佳实践](https://github.com/microsoft/TypeScript-Node-Starter)

### 构建工具
- [Turborepo](https://turbo.build/repo/docs)
- [Vitest](https://vitest.dev/)

---

**文档更新时间**: 2026 年 3 月 26 日
**总脚本数**: 177 个
**预计重构时间**: 15 周
