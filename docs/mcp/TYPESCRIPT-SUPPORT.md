# MCP TypeScript 支持方案 | TypeScript Support Guide

> **版本**: 1.0.0 | **标签**: [GENERIC] [TYPESCRIPT]

---

## 📋 概述

本文档描述如何在 Qwen Code 递归子代理架构中使用 TypeScript，包括编译、运行和与 Bash 脚本互操作。

### 为什么支持 TypeScript

1. **类型安全** - 编译时检查，减少运行时错误
2. **更好的 IDE 支持** - 自动补全、重构工具
3. **代码复用** - 与 Qwen Code 核心共享类型定义
4. **可维护性** - 大型项目更易维护

### 运行环境

```
┌─────────────────────────────────────────────────────────────┐
│                    TypeScript 运行环境                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  Bun        │    │  Node.js    │    │  Deno       │     │
│  │  (推荐)     │    │  (兼容)     │    │  (可选)     │     │
│  ├─────────────┤    ├─────────────┤    ├─────────────┤     │
│  │ • 内置 TS   │    │ • ts-node   │    │ • 原生 TS   │     │
│  │ • 快速启动  │    │ • 广泛支持  │    │ • 安全沙箱  │     │
│  │ • 低内存    │    │ • 成熟生态  │    │ • 新特性    │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 环境配置

### 1. 使用 Bun（推荐）

**安装**:
```bash
# Termux 安装 Bun
curl -fsSL https://bun.sh/install | bash

# 验证安装
bun --version
```

**项目初始化**:
```bash
cd ~/.oml/core
bun init

# 安装依赖
bun add commander chalk
bun add -d typescript @types/node @types/bun
```

**tsconfig.json**:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "types": ["bun-types"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

---

### 2. 使用 Node.js + ts-node

**安装**:
```bash
# 安装 ts-node
npm install -g ts-node typescript

# 验证安装
ts-node --version
```

**tsconfig.json**:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "outDir": "./dist",
    "rootDir": "./src"
  }
}
```

---

## 📝 示例代码

### 1. 会话 ID 生成器（TypeScript 版本）

**文件**: `~/.oml/core/src/session_id.ts`

```typescript
#!/usr/bin/env bun
// 会话 ID 生成器

import { randomBytes } from 'crypto';

/**
 * 生成 22 字符 Base64URL 编码的会话 ID
 * @returns 会话 ID 字符串
 */
export function generateSessionId(): string {
  // 生成 16 字节随机数
  const random = randomBytes(16);
  
  // Base64 编码
  const base64 = random.toString('base64');
  
  // Base64URL 转换
  const base64url = base64
    .replace(/\+/g, '_')
    .replace(/\//g, '.')
    .replace(/=/g, '');
  
  // 截断到 22 字符
  return base64url.substring(0, 22);
}

/**
 * 验证会话 ID 格式
 * @param id 会话 ID
 * @returns 是否有效
 */
export function validateSessionId(id: string): boolean {
  // 22 字符，只包含 Base64URL 字符
  const regex = /^[A-Za-z0-9_.]{22}$/;
  return regex.test(id);
}

// CLI 入口
if (import.meta.main) {
  const id = generateSessionId();
  console.log(`Generated session ID: ${id}`);
  console.log(`Valid: ${validateSessionId(id)}`);
}
```

**运行**:
```bash
# 直接运行（Bun）
bun run ~/.oml/core/src/session_id.ts

# 或使用 ts-node
ts-node ~/.oml/core/src/session_id.ts
```

---

### 2. 上下文管理器（TypeScript 版本）

**文件**: `~/.oml/core/src/context_manager.ts`

```typescript
#!/usr/bin/env bun
// 上下文管理器

import { mkdir, writeFile, readFile, stat } from 'fs/promises';
import { createGzip, createGunzip } from 'zlib';
import { pipeline } from 'stream/promises';
import { createReadStream, createWriteStream } from 'fs';

/**
 * 上下文配置
 */
export interface ContextConfig {
  maxActiveTokens: number;
  maxSummaryTokens: number;
  outputMaxLines: number;
}

/**
 * 会话摘要
 */
export interface SessionSummary {
  type: 'session_summary';
  generated_at: string;
  total_messages: number;
  latest_messages: any[];
  key_decisions: string[];
  files_modified: string[];
  tools_used: string[];
  truncated: boolean;
}

/**
 * 上下文管理器类
 */
export class ContextManager {
  private config: ContextConfig;
  private baseDir: string;

  constructor(config: Partial<ContextConfig> = {}) {
    this.config = {
      maxActiveTokens: config.maxActiveTokens ?? 4000,
      maxSummaryTokens: config.maxSummaryTokens ?? 2000,
      outputMaxLines: config.outputMaxLines ?? 500,
    };
    
    this.baseDir = process.env.CTX_MGR_DIR || `${process.env.HOME}/.oml/context`;
  }

  /**
   * 初始化目录
   */
  async init(): Promise<void> {
    await mkdir(`${this.baseDir}/active`, { recursive: true });
    await mkdir(`${this.baseDir}/archive`, { recursive: true });
    await mkdir(`${this.baseDir}/summaries`, { recursive: true });
  }

  /**
   * 估算 Token 数
   */
  estimateTokens(text: string): number {
    return Math.ceil(text.length / 3);
  }

  /**
   * 保存活跃上下文
   */
  async saveActive(sessionId: string, data: string): Promise<'full' | 'summary'> {
    const tokenCount = this.estimateTokens(data);
    const filePath = `${this.baseDir}/active/${sessionId}.json`;

    if (tokenCount > this.config.maxActiveTokens) {
      // 生成摘要
      const summary = await this.generateSummary(data);
      await writeFile(filePath, JSON.stringify(summary, null, 2), 'utf-8');
      return 'summary';
    } else {
      await writeFile(filePath, data, 'utf-8');
      return 'full';
    }
  }

  /**
   * 加载活跃上下文
   */
  async loadActive(sessionId: string): Promise<string | null> {
    const filePath = `${this.baseDir}/active/${sessionId}.json`;
    try {
      return await readFile(filePath, 'utf-8');
    } catch {
      return null;
    }
  }

  /**
   * 归档会话
   */
  async archiveSession(sessionId: string, fullContext: string): Promise<void> {
    const archivePath = `${this.baseDir}/archive/${sessionId}.json.gz`;
    
    // 压缩存储
    await pipeline(
      createReadStream(fullContext, 'utf-8'),
      createGzip(),
      createWriteStream(archivePath)
    );

    // 生成摘要
    const summary = await this.generateSummary(fullContext);
    await writeFile(
      `${this.baseDir}/summaries/${sessionId}.json`,
      JSON.stringify(summary, null, 2),
      'utf-8'
    );
  }

  /**
   * 从归档加载
   */
  async loadArchive(sessionId: string, full: boolean = false): Promise<string | null> {
    const archivePath = `${this.baseDir}/archive/${sessionId}.json.gz`;
    
    try {
      if (full) {
        // 解压完整内容
        const chunks: Buffer[] = [];
        await pipeline(
          createReadStream(archivePath),
          createGunzip(),
          async (source) => {
            for await (const chunk of source) {
              chunks.push(chunk);
            }
          }
        );
        return Buffer.concat(chunks).toString('utf-8');
      } else {
        // 加载摘要
        const summaryPath = `${this.baseDir}/summaries/${sessionId}.json`;
        return await readFile(summaryPath, 'utf-8');
      }
    } catch {
      return null;
    }
  }

  /**
   * 生成摘要
   */
  private async generateSummary(data: string): Promise<SessionSummary> {
    // 简化实现
    return {
      type: 'session_summary',
      generated_at: new Date().toISOString(),
      total_messages: 0,
      latest_messages: [],
      key_decisions: [],
      files_modified: [],
      tools_used: [],
      truncated: false,
    };
  }

  /**
   * 截断输出
   */
  truncateOutput(output: string): string {
    const lines = output.split('\n');
    if (lines.length <= this.config.outputMaxLines) {
      return output;
    }

    const headLines = Math.floor(this.config.outputMaxLines * 2 / 3);
    const tailLines = this.config.outputMaxLines - headLines;

    const head = lines.slice(0, headLines).join('\n');
    const tail = lines.slice(-tailLines).join('\n');
    const omitted = lines.length - this.config.outputMaxLines;

    return `${head}\n\n...[truncated: ${omitted} lines omitted]...\n\n${tail}`;
  }
}

// CLI 入口
if (import.meta.main) {
  const manager = new ContextManager();
  await manager.init();
  console.log('Context manager initialized');
}
```

---

### 3. 类型定义文件

**文件**: `~/.oml/core/src/types.ts`

```typescript
/**
 * 会话状态
 */
export type SessionStatus = 'active' | 'completed' | 'failed' | 'cancelled';

/**
 * 会话元数据
 */
export interface SessionMetadata {
  id: string;
  name: string;
  status: SessionStatus;
  created_at: string;
  updated_at: string;
  parent_id?: string;
  depth: number;
  agent_name?: string;
  task_name?: string;
}

/**
 * 环境变量
 */
export interface SessionEnv {
  QWEN_SESSION_ID: string;
  QWEN_PARENT_SESSION: string;
  QWEN_SESSION_DEPTH: number;
  QWEN_AGENT_NAME?: string;
  QWEN_TASK_NAME?: string;
}

/**
 * MCP 配置
 */
export interface MCPConfig {
  servers: Array<{
    name: string;
    url?: string;
    protocol: string;
    enabled: boolean;
  }>;
  allowed: string[];
}

/**
 * 工具结果
 */
export interface ToolResult {
  content: Array<{
    type: 'text' | 'image';
    text?: string;
    data?: string;
    mimeType?: string;
  }>;
  isError?: boolean;
}

/**
 * 审计日志条目
 */
export interface AuditLogEntry {
  timestamp: string;
  event_type: 'CREATE' | 'READ' | 'UPDATE' | 'DELETE' | 'FORK';
  session_id: string;
  operation: string;
  user_id: string;
  pid: number;
  ppid: number;
  prev_hash: string;
  entry_hash: string;
}
```

---

## 🔗 与 Bash 脚本互操作

### 1. Bash 调用 TypeScript

**文件**: `~/.oml/core/session_id.sh`

```bash
#!/data/data/com.termux/files/usr/bin/bash
# Bash 包装器调用 TypeScript

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 使用 Bun 运行
bun run "${SCRIPT_DIR}/src/session_id.ts" "$@"
```

### 2. TypeScript 调用 Bash

```typescript
// 在 TypeScript 中执行 Bash 命令
import { $ } from 'bun';

// 执行 Bash 命令
const result = await $`ls -la`.text();
console.log(result);

// 设置环境变量
process.env.QWEN_SESSION_ID = generateSessionId();
```

---

## 📊 性能对比

| 运行方式 | 启动时间 | 内存占用 | 推荐场景 |
|----------|----------|----------|----------|
| Bash | ~10ms | ~5MB | 简单脚本 |
| Bun + TS | ~50ms | ~20MB | 中等复杂度 |
| Node + ts-node | ~100ms | ~30MB | 大型项目 |

---

## 🔗 相关文档

- [会话管理](./SESSION-MANAGEMENT.md) - Bash 版本实现
- [上下文优化](./CONTEXT-OPTIMIZATION.md) - 三层架构
- [架构优化](./ARCHITECTURE-OPTIMIZATION.md) - 实施路线图

---

*最后更新：2026-03-22 | 维护者：Oh My LiteCode Team*
