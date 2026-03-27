# TypeScript 迁移指南

**AI-LTC Lane**: shell-migration-research  
**Stage**: 5 - Guide  
**Date**: 2026-03-26  
**Version**: 1.0

---

## 1. 迁移前准备

### 1.1 环境检查清单

- [ ] Node.js 20+ 已安装
- [ ] npm 10+ 已安装
- [ ] 项目依赖已安装 (`npm install`)
- [ ] 构建验证通过 (`npm run build`)
- [ ] 类型检查通过 (`npm run typecheck`)
- [ ] 测试验证通过 (`npm run test`)

### 1.2 工具准备

| 工具 | 用途 | 安装命令 |
|------|------|----------|
| Node.js 20+ | TypeScript 运行环境 | `nvm install 20` |
| Vitest | 单元测试框架 | `npm install -D vitest` |
| ESLint | 代码检查 | `npm install -D eslint` |

### 1.3 知识准备

| 知识点 | 重要度 | 参考资料 |
|--------|--------|----------|
| TypeScript 基础 | 🔴 高 | https://www.typescriptlang.org/docs/ |
| Shell 基础 | 🔴 高 | 现有 shell 脚本 |
| 设计模式 | 🟡 中 | `MIGRATION-STRATEGY.md` |
| API 映射 | 🔴 高 | `API-MAPPING.md` |

---

## 2. 迁移步骤详解

### 2.1 分析阶段

**目标**: 理解 Shell 脚本功能

**步骤**:
1. 阅读 Shell 脚本头部注释
2. 提取函数列表和参数
3. 识别依赖关系
4. 记录边界情况

**模板**:
```markdown
## 脚本分析：xxx.sh

### 功能描述
(一句话描述)

### 输入参数
- $1: 参数 1 说明
- $2: 参数 2 说明

### 输出
- stdout: 输出说明
- exit code: 退出码说明

### 依赖
- 外部命令：command1, command2
- 环境变量：$VAR1, $VAR2
- 其他脚本：source xxx.sh

### 边界情况
- 空参数处理
- 错误处理
```

### 2.2 设计阶段

**目标**: 设计 TypeScript 接口

**步骤**:
1. 定义类型接口
2. 设计类/函数签名
3. 设计错误处理
4. 设计配置管理

**示例**:
```typescript
// 类型定义
interface SessionOptions {
  name?: string;
  metadata?: Record<string, unknown>;
}

// 类设计
class SessionManager {
  constructor(options: SessionManagerOptions);
  create(options?: SessionOptions): Promise<Session>;
  resume(id?: string): Promise<Session>;
  // ...
}
```

### 2.3 实现阶段

**目标**: 编写 TypeScript 代码

**步骤**:
1. 创建模块文件
2. 实现类型定义
3. 实现核心逻辑
4. 添加 JSDoc 注释

**示例**:
```typescript
/**
 * Session Manager
 * 
 * Manages session lifecycle operations.
 */
export class SessionManager {
  /**
   * Create a new session
   * @param options - Session creation options
   * @returns The created session
   */
  async create(options?: SessionOptions): Promise<Session> {
    // Implementation
  }
}
```

### 2.4 测试阶段

**目标**: 编写单元测试

**步骤**:
1. 创建测试文件
2. 编写测试用例
3. 运行测试验证
4. 修复测试失败

**示例**:
```typescript
import { describe, it, expect } from 'vitest';
import { SessionManager } from '../session-manager';

describe('SessionManager', () => {
  it('should create a new session', async () => {
    const manager = new SessionManager({ sessionsDir: './sessions' });
    const session = await manager.create({ name: 'test' });
    expect(session.name).toBe('test');
  });
});
```

### 2.5 验证阶段

**目标**: 验证功能一致性

**步骤**:
1. 对比 Shell 和 TS 输出
2. 运行集成测试
3. 性能基准测试
4. 代码审查

**检查清单**:
- [ ] 功能覆盖 100%
- [ ] 测试覆盖 80%+
- [ ] 性能无明显下降
- [ ] 代码审查通过

### 2.6 归档阶段

**目标**: 归档 Shell 脚本

**步骤**:
1. 更新 `packages/README.md` 状态
2. 在 Shell 脚本头部添加 deprecated 注释
3. 更新迁移进度文档
4. 提交归档 commit

**Deprecated 注释模板**:
```bash
#!/usr/bin/env bash
# DEPRECATED: This script has been migrated to TypeScript.
# Use: packages/core/src/session/manager.ts instead.
# Archive Date: 2026-03-26
```

---

## 3. 常见问题

### Q1: Shell 数组如何映射？

**Shell**:
```bash
array=("a" "b" "c")
for item in "${array[@]}"; do
  echo "$item"
done
```

**TypeScript**:
```typescript
const array = ['a', 'b', 'c'];
for (const item of array) {
  console.log(item);
}
```

### Q2: Shell 关联数组如何映射？

**Shell**:
```bash
declare -A map
map["key"]="value"
echo "${map["key"]}"
```

**TypeScript**:
```typescript
const map = new Map<string, string>();
map.set('key', 'value');
console.log(map.get('key'));
```

### Q3: Shell trap 如何映射？

**Shell**:
```bash
trap 'cleanup' EXIT
```

**TypeScript**:
```typescript
try {
  // main logic
} finally {
  await cleanup();
}
```

### Q4: Shell 管道如何映射？

**Shell**:
```bash
cat file | grep pattern | wc -l
```

**TypeScript**:
```typescript
const content = await fs.readFile(file, 'utf-8');
const lines = content.split('\n').filter(line => pattern.test(line));
console.log(lines.length);
```

---

## 4. 最佳实践

### 4.1 代码组织

```typescript
// 推荐：按功能域组织
src/
├── session/
│   ├── types.ts
│   ├── manager.ts
│   ├── storage.ts
│   └── index.ts
└── ...
```

### 4.2 错误处理

```typescript
// 推荐：自定义错误类
class SessionError extends Error {
  constructor(
    message: string,
    public code: string,
    public sessionId?: string
  ) {
    super(message);
  }
}
```

### 4.3 配置管理

```typescript
// 推荐：Zod 验证
const ConfigSchema = z.object({
  sessionsDir: z.string().default('./sessions'),
});
type Config = z.infer<typeof ConfigSchema>;
```

### 4.4 测试组织

```typescript
// 推荐：测试文件与源码对应
src/
├── session/
│   └── manager.ts
tests/
├── session/
│   └── manager.test.ts
```

---

## 5. 迁移进度追踪

### 5.1 进度模板

```markdown
## 迁移进度 - 2026-03-26

### 已完成
- [x] session-manager.sh -> SessionManager (80%)
- [x] platform.sh -> PlatformDetector (100%)

### 进行中
- [ ] pool-manager.sh -> PoolManager (30%)

### 待开始
- [ ] hooks-engine.sh -> HooksEngine
```

### 5.2 度量指标

| 指标 | 目标 | 当前 |
|------|------|------|
| Shell 脚本迁移数 | 177 | 0 |
| 测试覆盖率 | 80%+ | 15% |
| 构建时间 | < 5min | 4.5s |
| 类型错误 | 0 | 0 |

---

## 6. 参考资源

### 6.1 内部文档

| 文档 | 说明 |
|------|------|
| `SHELL-ANALYSIS.md` | Shell 脚本功能分析 |
| `MIGRATION-STRATEGY.md` | 迁移策略 |
| `API-MAPPING.md` | API 映射 |
| `MIGRATION-CONSTITUTION.md` | 迁移宪法 |

### 6.2 外部资源

| 资源 | 链接 |
|------|------|
| TypeScript 官方文档 | https://www.typescriptlang.org/docs/ |
| Vitest 文档 | https://vitest.dev/ |
| Zod 文档 | https://zod.dev/ |

---

## 7. 变更日志

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0 | 2026-03-26 | 初始版本 |

---

**Next**: 开始 P0 核心功能迁移
