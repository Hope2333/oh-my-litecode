# Plugins Bash → TypeScript 迁移技术参考

**Version**: 1.0  
**Date**: 2026-03-27  
**Target**: v0.4.0-plugins-ts

---

## 1. 现有架构分析

### 1.1 PluginLoader 现有能力

**位置**: `packages/core/src/plugin/`

**类型定义**:
```typescript
type PluginType = 'agent' | 'subagent' | 'mcp' | 'skill';
type PluginStatus = 'enabled' | 'disabled' | 'installed';

interface Plugin {
  name: string;
  type: PluginType;
  version: string;
  description: string;
  author?: string;
  status: PluginStatus;
  path: string;
  mainScript?: string;
  dependencies?: string[];
  config?: Record<string, unknown>;
}
```

**核心方法**:
- `list(type?)` - 列出插件
- `loadPlugin(name, type?)` - 加载插件
- `install(options)` - 安装插件
- `enable(name)` / `disable(name)` - 启用/禁用
- `run(name, options)` - 运行插件
- `create(options)` - 创建插件模板
- `uninstall(name)` - 卸载插件

### 1.2 归档的 Bash 插件结构

**Agents (5 个)**:
```
plugins/agents/
├── build/
│   ├── main.sh              # 主入口
│   ├── hooks/               # Hooks 实现
│   ├── scripts/             # 生命周期脚本
│   ├── tests/               # 测试
│   └── plugin.json          # 插件清单
├── plan/
└── qwen/
```

**Subagents (11 个)**:
```
plugins/subagents/
├── librarian/
│   ├── main.sh
│   ├── lib/                 # 库函数
│   └── plugin.json
├── reviewer/
├── scout/
└── worker/
```

**MCPs (14 个)**:
```
plugins/mcps/
├── context7/
│   ├── main.sh
│   ├── src/index.ts         # 已有 TS 实现
│   └── plugin.json
├── grep-app/
│   ├── main.sh
│   ├── src/grep_app_mcp/    # Python MCP
│   └── plugin.json
└── websearch/
```

**Skills (20 个)**:
```
plugins/skills/
├── code-review/
│   ├── main.sh
│   └── plugin.json
└── ...
```

---

## 2. TypeScript 插件规范

### 2.1 标准目录结构

```
packages/plugins/
├── agents/
│   └── <agent-name>/
│       ├── src/
│       │   ├── index.ts         # 导出 Agent 类
│       │   ├── agent.ts         # Agent 核心逻辑
│       │   ├── hooks/           # Hooks 实现
│       │   └── types.ts         # 类型定义
│       ├── tests/
│       │   ├── agent.test.ts
│       │   └── hooks.test.ts
│       ├── plugin.json          # 插件清单 (保留)
│       ├── package.json         # NPM 包配置
│       └── README.md
├── subagents/
├── mcps/
├── skills/
└── core/
```

### 2.2 Plugin Manifest (plugin.json)

```json
{
  "name": "qwen",
  "type": "agent",
  "version": "1.0.0",
  "description": "Qwen AI agent",
  "author": "OML Team",
  "main": "dist/index.js",
  "scripts": {
    "post-install": "scripts/post-install.sh",
    "pre-uninstall": "scripts/pre-uninstall.sh"
  },
  "dependencies": [],
  "config": {
    "apiKey": "",
    "model": "qwen-plus"
  }
}
```

### 2.3 Agent 接口规范

```typescript
// packages/plugins/src/types.ts
export interface Agent {
  name: string;
  version: string;
  
  // 生命周期
  initialize(config: Record<string, unknown>): Promise<void>;
  shutdown(): Promise<void>;
  
  // 核心功能
  process(message: AgentMessage): Promise<AgentResponse>;
  
  // Hooks
  getHooks(): AgentHooks;
}

export interface AgentMessage {
  id: string;
  type: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
}

export interface AgentResponse {
  success: boolean;
  content?: string;
  error?: string;
}

export interface AgentHooks {
  preProcess?: (message: AgentMessage) => Promise<void>;
  postProcess?: (response: AgentResponse) => Promise<void>;
}
```

---

## 3. 迁移策略

### 3.1 优先级分类

| 优先级 | 插件 | 原因 | 工时 |
|--------|------|------|------|
| 🔴 P0 | qwen | 核心 Agent，使用频率最高 | 3 天 |
| 🔴 P0 | build | 构建自动化 | 2 天 |
| 🔴 P0 | plan | 任务规划 | 2 天 |
| 🟡 P1 | librarian/reviewer/scout/worker | 核心 Subagents | 4 天 |
| 🟡 P1 | context7/grep-app/websearch | 常用 MCPs | 4 天 |
| 🟢 P2 | 其他 MCPs | 低频使用 | 3 天 |
| 🟢 P2 | Skills | 工具类 | 3 天 |

### 3.2 迁移步骤

**每个插件**:
1. 创建目录结构 `packages/plugins/<type>/<name>/`
2. 复制 `plugin.json` 并更新 `main` 字段
3. 分析 `main.sh` 功能，创建 `src/agent.ts`
4. 迁移 hooks 到 `src/hooks/`
5. 创建 `src/index.ts` 导出
6. 编写测试 `tests/*.test.ts`
7. 更新 `package.json`
8. 验证：build + test
9. 归档旧 bash 文件

### 3.3 依赖处理

**内部依赖**:
```json
{
  "dependencies": {
    "@oml/core": "^0.2.0",
    "@oml/modules": "^0.2.0"
  }
}
```

**外部依赖**:
- 使用 npm/yarn 管理
- 避免原生模块 (Termux 兼容性)

---

## 4. 测试规范

### 4.1 Vitest 配置

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    coverage: {
      provider: 'v8',
      threshold: { lines: 80, functions: 80, branches: 80 },
    },
  },
});
```

### 4.2 测试模板

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { QwenAgent } from '../src/agent';

describe('QwenAgent', () => {
  let agent: QwenAgent;

  beforeEach(async () => {
    agent = new QwenAgent();
    await agent.initialize({ apiKey: 'test-key' });
  });

  it('should process user message', async () => {
    const response = await agent.process({
      id: '1',
      type: 'user',
      content: 'Hello',
      timestamp: new Date(),
    });
    
    expect(response.success).toBe(true);
    expect(response.content).toBeDefined();
  });
});
```

---

## 5. 合规要求

### 5.1 API 密钥管理

- 使用 `OAuthSwitcher` 或 `KeySwitcher`
- 不硬编码密钥
- 支持多密钥轮换

### 5.2 用户确认

- OAuth fallback 需要 `QWEN_OAUTH_CONFIRMED=1`
- 显示警告信息

### 5.3 官方 API 优先

- 优先使用官方 API
- 避免消费型网页端点

---

## 6. 验证清单

- [ ] 目录结构符合规范
- [ ] `plugin.json` 更新
- [ ] `package.json` 配置正确
- [ ] 所有功能迁移完成
- [ ] 测试覆盖 > 80%
- [ ] `npm run build` 通过
- [ ] `npm run typecheck` 通过
- [ ] `npm test` 通过
- [ ] 文档更新
- [ ] 旧 bash 文件归档

---

## 7. 参考资源

- [PluginLoader API](../packages/core/src/plugin/)
- [现有插件结构](../archive/bash-legacy/plugins/)
- [MCP 架构文档](./mcp/)
