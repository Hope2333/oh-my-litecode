# OML Phase 3 插件迁移计划

**版本**: 0.1.0
**创建日期**: 2026-03-23
**状态**: 规划阶段

---

## 📋 执行摘要

Phase 3 目标是将现有 Bash 插件迁移到 TypeScript/Python 混合架构。

### 待迁移插件

| 插件 | 行数 | 复杂度 | 优先级 | 目标语言 |
|------|------|--------|--------|---------|
| `plugins/agents/qwen/` | 1358 | 高 | P0 | TypeScript |
| `plugins/mcps/context7/` | 984 | 高 | P0 | TypeScript |
| `plugins/mcps/grep-app/` | 2146 | 高 | P1 | Python |
| `plugins/agents/build/` | 1257 | 中 | P1 | Python |
| `plugins/agents/plan/` | 1737 | 中 | P2 | Python |
| `plugins/subagents/` | ~2500 | 中 | P2 | Python |

---

## 🎯 迁移原则

### 1. 保持接口兼容
- 插件 API 保持不变
- 支持渐进式迁移
- Bash/TS/Py 插件可共存

### 2. 平台适配
- Termux 和 GNU/Linux 同时支持
- 使用 platform.sh 检测
- 避免平台特定代码

### 3. 性能优先
- 使用 Bun 运行时 (3-5x 性能提升)
- Python 使用 asyncio
- 减少子进程调用

---

## 📁 目标架构

```
plugins/
├── agents/
│   ├── qwen/                    # TypeScript
│   │   ├── src/
│   │   │   ├── index.ts         # 主入口
│   │   │   ├── chat.ts          # 对话功能
│   │   │   ├── ctx7.ts          # Context7 集成
│   │   │   └── mcp.ts           # MCP 集成
│   │   ├── plugin.json          # 插件配置
│   │   └── package.json         # NPM 依赖
│   ├── build/                   # Python
│   │   ├── main.py
│   │   └── plugin.json
│   └── plan/                    # Python
│       ├── main.py
│       └── plugin.json
├── mcps/
│   ├── context7/                # TypeScript
│   │   ├── src/
│   │   │   ├── index.ts
│   │   │   └── mcp-server.ts
│   │   └── plugin.json
│   ├── grep-app/                # Python
│   │   ├── main.py
│   │   └── plugin.json
│   └── websearch/               # Python
│       ├── main.py
│       └── plugin.json
└── subagents/
    ├── worker/                  # TypeScript
    ├── scout/                   # Python
    ├── librarian/               # Python
    └── reviewer/                # Python
```

---

## 🔧 技术栈

### TypeScript 插件
- **运行时**: Bun 1.0+ 或 Node.js 20+
- **CLI 框架**: Commander.js
- **MCP SDK**: @modelcontextprotocol/sdk
- **测试**: Vitest

### Python 插件
- **版本**: Python 3.10+
- **异步**: asyncio + aiohttp
- **MCP**: mcp 库
- **测试**: pytest

---

## 📊 迁移工作量评估

### P0: 核心插件 (2-3 周)

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| qwen agent 迁移 | 5 天 | Phase 1, 2 |
| context7 MCP 迁移 | 4 天 | Phase 1 |
| 测试迁移 | 3 天 | 全部 |

**小计**: 12 工作日

### P1: 功能插件 (3-4 周)

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| grep-app MCP 迁移 | 5 天 | Phase 1 |
| build agent 迁移 | 4 天 | Phase 2 |
| plan agent 迁移 | 4 天 | Phase 2 |
| 测试迁移 | 4 天 | 全部 |

**小计**: 17 工作日

### P2: Subagents (2-3 周)

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| worker 迁移 | 3 天 | Phase 1 |
| scout 迁移 | 4 天 | Phase 1 |
| librarian 迁移 | 4 天 | Phase 1 |
| reviewer 迁移 | 4 天 | Phase 1 |
| 测试迁移 | 3 天 | 全部 |

**小计**: 18 工作日

### 总计

| 阶段 | 工作日 | 累计 |
|------|--------|------|
| P0 | 12 | 12 |
| P1 | 17 | 29 |
| P2 | 18 | 47 |

**总工作量**: 约 47 工作日 (~2.5 个月)

---

## 🧪 测试策略

### 单元测试
- 每个插件独立测试
- Mock 外部依赖
- 覆盖率目标：80%

### 集成测试
- 插件与 CLI 集成
- MCP 服务测试
- 跨平台测试

### E2E 测试
- 完整工作流测试
- 会话管理测试
- Hooks 触发测试

---

## 📈 里程碑

- [ ] **M1**: qwen agent 迁移完成 (Week 2)
- [ ] **M2**: context7 MCP 迁移完成 (Week 3)
- [ ] **M3**: grep-app MCP 迁移完成 (Week 5)
- [ ] **M4**: build/plan agent 迁移完成 (Week 7)
- [ ] **M5**: subagents 迁移完成 (Week 9)
- [ ] **M6**: 全面测试通过 (Week 10)

---

## 🔗 相关文档

- [MIGRATION-TS-PY.md](./MIGRATION-TS-PY.md) - 总体迁移评估
- [DEPLOYMENT-GUIDE.md](../DEPLOYMENT-GUIDE.md) - 部署指南

---

**维护者**: OML Team
**许可**: MIT License
