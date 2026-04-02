# OML 插件 SDK 指南

**Version**: 1.0  
**Date**: 2026-04-01

---

## 快速开始

### 1. 创建插件目录

```bash
mkdir -p packages/plugins/agents/my-agent/src
mkdir -p packages/plugins/agents/my-agent/tests
```

### 2. 创建类型定义

```typescript
// src/types.ts
export interface MyAgentConfig {
  apiKey: string;
  enabled: boolean;
}

export interface MyAgentResult {
  success: boolean;
  output?: string;
  error?: string;
}
```

### 3. 创建 Agent 类

```typescript
// src/agent.ts
export class MyAgent {
  public readonly name = 'my-agent';
  public readonly version = '1.0.0';
  
  private config: MyAgentConfig;
  private initialized: boolean;

  constructor() {
    this.initialized = false;
    this.config = { apiKey: '', enabled: true };
  }

  async initialize(config: Record<string, unknown>): Promise<void> {
    this.config = { ...this.config, ...config };
    this.initialized = true;
  }

  async shutdown(): Promise<void> {
    this.initialized = false;
  }

  async process(message: AgentMessage): Promise<AgentResponse> {
    if (!this.initialized) {
      return { success: false, error: 'Not initialized' };
    }
    // 处理逻辑
    return { success: true, content: 'Result' };
  }
}
```

### 4. 创建导出

```typescript
// src/index.ts
export { MyAgent } from './agent.js';
export type { MyAgentConfig, MyAgentResult } from './types.js';
```

### 5. 创建配置

```json
// package.json
{
  "name": "@oml/plugin-my-agent",
  "version": "1.0.0",
  "type": "module",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "test": "vitest run"
  },
  "dependencies": {
    "@oml/core": "^0.3.0"
  }
}
```

```json
// plugin.json
{
  "name": "my-agent",
  "version": "1.0.0",
  "type": "agent",
  "description": "My custom agent",
  "main": "dist/index.js",
  "license": "MIT"
}
```

### 6. 创建测试

```typescript
// tests/agent.test.ts
import { describe, it, expect } from 'vitest';
import { MyAgent } from '../src/agent.js';

describe('MyAgent', () => {
  it('should have correct name', () => {
    const agent = new MyAgent();
    expect(agent.name).toBe('my-agent');
  });

  it('should initialize', async () => {
    const agent = new MyAgent();
    await agent.initialize({});
    // Test initialization
  });
});
```

---

## API 参考

### Agent 接口

```typescript
interface Agent {
  name: string;
  version: string;
  initialize(config: Record<string, unknown>): Promise<void>;
  shutdown(): Promise<void>;
  process(message: AgentMessage): Promise<AgentResponse>;
}
```

### AgentMessage

```typescript
interface AgentMessage {
  id: string;
  type: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
}
```

### AgentResponse

```typescript
interface AgentResponse {
  success: boolean;
  content?: string;
  error?: string;
}
```

---

## 最佳实践

1. **类型安全**: 使用 TypeScript 严格模式
2. **测试覆盖**: 至少 80% 覆盖率
3. **文档**: 提供 README.md
4. **错误处理**: 妥善处理所有错误情况
5. **配置**: 支持环境变量和配置文件

---

## 示例

查看现有插件示例：
- `packages/plugins/agents/qwen/` - 完整 Agent 示例
- `packages/plugins/mcps/context7/` - MCP 示例
- `packages/plugins/skills/code-review/` - Skill 示例

---

## 支持

如有问题，请查看文档或提交 issue。
