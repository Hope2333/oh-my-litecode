# TypeScript 迁移策略文档

**AI-LTC Lane**: shell-migration-research
**Stage**: 2 - Design
**Date**: 2026 年 3 月 26 日

---

## 1. 迁移原则

### 1.1 核心原则

| 原则 | 说明 | 示例 |
|------|------|------|
| **渐进式迁移** | 分阶段、分优先级迁移，保持向后兼容 | P0 -> P1 -> P2 |
| **功能对等** | TypeScript 实现必须覆盖 Shell 所有功能 | 100% 功能覆盖 |
| **测试先行** | 迁移前先有测试，确保功能一致 | TDD 方法 |
| **文档同步** | 迁移同时更新文档 | README, API docs |
| **可回滚** | 保留 Shell 脚本作为后备 | bin/oml.sh 兼容层 |

### 1.2 设计模式

| 模式 | 应用场景 | Shell -> TS 映射 |
|------|----------|-----------------|
| **Module Pattern** | 功能模块封装 | `source x.sh` -> `import x from 'x'` |
| **Singleton** | 全局管理器 | `GLOBAL_X` -> `class X { static instance }` |
| **Factory** | 对象创建 | `create_x()` -> `XFactory.create()` |
| **Strategy** | 算法替换 | `case $algo` -> `strategy.execute()` |
| **Observer** | 事件通知 | `trigger_hook()` -> `eventBus.emit()` |
| **Adapter** | 接口适配 | Shell 兼容层 -> `ShellAdapter` |

---

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │  CLI (oml)  │  │   Plugins   │  │   Scripts   │      │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘      │
│         │                │                │              │
├─────────┼────────────────┼────────────────┼──────────────┤
│         ▼                ▼                ▼              │
│  ┌─────────────────────────────────────────────────┐    │
│  │              Core Modules (@oml/core)            │    │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐   │    │
│  │  │Session │ │ Pool   │ │ Hooks  │ │Platform│   │    │
│  │  └────────┘ └────────┘ └────────┘ └────────┘   │    │
│  └─────────────────────────────────────────────────┘    │
│         │                │                │              │
├─────────┼────────────────┼────────────────┼──────────────┤
│         ▼                ▼                ▼              │
│  ┌─────────────────────────────────────────────────┐    │
│  │            Feature Modules (@oml/modules)        │    │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐   │    │
│  │  │ Cache  │ │ Error  │ │  I18n  │ │Switcher│   │    │
│  │  └────────┘ └────────┘ └────────┘ └────────┘   │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### 2.2 模块边界

| 模块 | 职责 | 对外接口 | 依赖 |
|------|------|----------|------|
| `@oml/core` | 核心功能 | SessionManager, HooksEngine | - |
| `@oml/cli` | CLI 接口 | Command classes | @oml/core, @oml/modules |
| `@oml/modules` | 功能扩展 | CacheManager, Translator | @oml/core |
| `@oml/plugins` | 插件系统 | Plugin interface | @oml/core |

---

## 3. 迁移策略分类

### 3.1 直接迁移 (Direct Migration)

**适用**: 功能简单、逻辑清晰的脚本

**步骤**:
1. 分析 Shell 函数签名
2. 设计 TypeScript 接口
3. 逐函数迁移
4. 编写单元测试
5. 验证功能一致

**示例**: `cache-manager.sh` -> `CacheManager`

```bash
# Shell
cache_set() {
    local key="$1"
    local value="$2"
    local ttl="${3:-3600}"
    # ...
}
```

```typescript
// TypeScript
class CacheManager {
  set(key: string, value: unknown, ttl: number = 3600): void {
    // ...
  }
}
```

### 3.2 重构迁移 (Refactoring Migration)

**适用**: 逻辑复杂、需要优化的脚本

**步骤**:
1. 分析现有逻辑
2. 识别设计问题
3. 设计改进方案
4. 重构实现
5. 回归测试

**示例**: `pool-manager.sh` -> `PoolManager` (重构)

### 3.3 替换迁移 (Replacement Migration)

**适用**: 已有 TypeScript 实现的功能

**步骤**:
1. 对比功能差异
2. 补充缺失功能
3. 更新调用方
4. 移除 Shell 脚本

**示例**: `session-manager.sh` -> `SessionManager` (已有 TS)

---

## 4. 错误处理策略

### 4.1 Shell vs TypeScript 错误处理对比

| 特性 | Shell | TypeScript |
|------|-------|------------|
| 错误检测 | `set -e`, `$?` | `try/catch`, `throw` |
| 错误类型 | 退出码 | Error 类 hierarchy |
| 错误传播 | 返回值 | Exception bubbling |
| 资源清理 | `trap` | `finally`, `using` |

### 4.2 错误处理模式

```typescript
// 模式 1: 自定义错误类
class SessionError extends Error {
  constructor(
    message: string,
    public code: string,
    public sessionId?: string
  ) {
    super(message);
  }
}

// 模式 2: Result 类型
type Result<T, E = Error> = 
  | { success: true; data: T }
  | { success: false; error: E };

// 模式 3: 错误边界
class SessionManager {
  async create(options: SessionOptions): Promise<Session> {
    try {
      // ...
    } catch (error) {
      if (error instanceof SessionExistsError) {
        // 处理特定错误
      }
      throw error;
    }
  }
}
```

---

## 5. 配置管理策略

### 5.1 Shell vs TypeScript 配置对比

| 特性 | Shell | TypeScript |
|------|-------|------------|
| 环境变量 | `$VAR` | `process.env.VAR` |
| 配置文件 | `.env`, `config.sh` | JSON, YAML |
| 默认值 | `${VAR:-default}` | 解构默认值 |
| 验证 | 手动检查 | Zod schema |

### 5.2 配置模式

```typescript
// 模式 1: Zod 验证
const ConfigSchema = z.object({
  sessionsDir: z.string().default('./sessions'),
  maxConnections: z.number().min(1).default(10),
});

type Config = z.infer<typeof ConfigSchema>;

// 模式 2: 配置类
class ConfigManager {
  private config: Config;
  
  get<T extends keyof Config>(key: T): Config[T] {
    return this.config[key];
  }
  
  async update<T extends keyof Config>(key: T, value: Config[T]): Promise<void> {
    // ...
  }
}
```

---

## 6. 测试策略

### 6.1 测试金字塔

```
           /\
          /  \
         / E2E \       端到端测试 (10%)
        /--------\
       /          \
      / Integration \   集成测试 (20%)
     /----------------\
    /                  \
   /     Unit Tests     \  单元测试 (70%)
  /----------------------\
```

### 6.2 测试框架

| 类型 | 框架 | 用途 |
|------|------|------|
| 单元测试 | Vitest | 模块测试 |
| 集成测试 | Vitest + mocks | 模块间测试 |
| E2E 测试 | Playwright | CLI 测试 |

### 6.3 测试覆盖率目标

| 模块类型 | 行覆盖率 | 分支覆盖率 | 函数覆盖率 |
|----------|----------|------------|------------|
| Core | 90% | 80% | 95% |
| Modules | 85% | 75% | 90% |
| Plugins | 80% | 70% | 85% |

---

## 7. 向后兼容策略

### 7.1 Shell 兼容层

```bash
#!/usr/bin/env bash
# bin/oml.sh - Shell 兼容层

OML_CLI="$(dirname "$0")/../packages/cli/dist/bin/oml.js"

if [[ ! -f "$OML_CLI" ]]; then
    echo "Error: OML CLI not found" >&2
    exit 1
fi

exec node "$OML_CLI" "$@"
```

### 7.2 API 版本控制

```typescript
// 版本化 API
class SessionManagerV1 {
  // 旧 API
  create(name?: string): Promise<Session> {
    // ...
  }
}

class SessionManagerV2 {
  // 新 API
  create(options: SessionCreateOptions): Promise<Session> {
    // ...
  }
}
```

---

## 8. 性能优化策略

### 8.1 性能对比维度

| 维度 | Shell | TypeScript | 优化空间 |
|------|-------|------------|----------|
| 启动时间 | ~50ms | ~100ms | - |
| 执行速度 | 基准 | 2-5x | + |
| 内存使用 | 低 | 中 | - |
| 并发能力 | 有限 | 强 | + |

### 8.2 优化技术

| 技术 | 适用场景 | 预期提升 |
|------|----------|----------|
| 缓存 | 重复计算 | 50-90% |
| 并行 | I/O 操作 | 2-8x |
| 懒加载 | 大模块 | 启动时间 50% |
| 批处理 | 批量操作 | 3-5x |

---

## 9. 迁移检查清单

### 9.1 迁移前

- [ ] 分析 Shell 脚本功能
- [ ] 设计 TypeScript 接口
- [ ] 编写测试用例
- [ ] 准备回滚方案

### 9.2 迁移中

- [ ] 实现 TypeScript 代码
- [ ] 运行单元测试
- [ ] 对比功能差异
- [ ] 更新文档

### 9.3 迁移后

- [ ] 运行集成测试
- [ ] 性能基准测试
- [ ] 代码审查
- [ ] 移除/归档 Shell 脚本

---

**Next Stage**: Stage 3 - 规划阶段，产出 `PRIORITY-MATRIX.md`
