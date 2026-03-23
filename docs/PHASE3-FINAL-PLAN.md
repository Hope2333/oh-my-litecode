# OML Phase 3 最终迁移计划

**版本**: 2.0 (修订版)
**日期**: 2026-03-23
**状态**: 已批准

---

## 📋 上游依赖确认

### 插件上游分析

| 插件 | 上游仓库 | 类型 | 迁移优先级 |
|------|---------|------|-----------|
| **context7 MCP** | `upstash/context7-mcp` | NPM 包 | P0 |
| **grep-app MCP** | **无 (本地实现)** | 本地逻辑 | P0 |
| **websearch** | `exa-labs/exa-py` | Python SDK | P1 |
| **qwen agent** | 无 (包装 qwen CLI) | 本地包装 | ❌ 不迁移 |
| **build agent** | 无 (系统命令) | 本地编排 | ❌ 不迁移 |
| **plan agent** | 无 (纯逻辑) | 本地逻辑 | P2 |

### grep-app 确认

```
grep-app MCP 是 OML 团队自主实现的本地 MCP 服务
- 无外部上游仓库
- 核心依赖：GNU grep, GNU find, Python 3
- MCP 工具：grep_search_intent, grep_regex, grep_count, grep_files_with_matches
- 模式：stdio (本地调用) / http (可选)
```

**结论**: grep-app 迁移无上游兼容风险，可安全迁移到 Python

---

## 🎯 修订后迁移计划

### Phase 3A - 核心 MCP (2 周)

#### 1. context7 MCP → TypeScript (3 天)

**目标**:
- 使用 `@modelcontextprotocol/sdk`
- 配置管理类型安全
- 自动处理上游更新

**文件结构**:
```
plugins/mcps/context7/
├── src/
│   ├── index.ts           # MCP 服务器入口
│   ├── config.ts          # 配置管理
│   └── modes/
│       ├── local.ts       # 本地模式 (npx)
│       └── remote.ts      # 远程模式 (API)
├── plugin.json            # 插件配置 (保留)
├── package.json           # NPM 依赖
└── tests/
    └── config.test.ts     # 配置测试
```

**依赖**:
```json
{
  "dependencies": {
    "@modelcontextprotocol/sdk": "^0.5.0",
    "@upstash/context7-mcp": "^1.2.0"
  }
}
```

**里程碑**:
- [ ] Day 1: 项目搭建，SDK 集成
- [ ] Day 2: 配置管理迁移
- [ ] Day 3: 测试 + 文档

---

#### 2. grep-app MCP → Python (5 天)

**目标**:
- 使用 Python 重写 grep/find 包装逻辑
- 实现 MCP stdio 协议
- 保持 100% 向后兼容

**文件结构**:
```
plugins/mcps/grep-app/
├── src/
│   ├── __init__.py
│   ├── main.py            # MCP 服务器入口
│   ├── search.py          # 搜索逻辑
│   ├── mcp_server.py      # MCP stdio 协议
│   └── utils.py           # 工具函数
├── plugin.json            # 插件配置 (保留)
├── requirements.txt       # Python 依赖
└── tests/
    ├── test_search.py     # 搜索测试
    └── test_mcp.py        # MCP 协议测试
```

**依赖**:
```txt
# requirements.txt
mcp>=0.5.0  # MCP SDK
pydantic>=2.0  # 数据验证
```

**核心实现**:
```python
# src/mcp_server.py
from mcp.server import Server
from .search import grep_search, grep_regex

server = Server("grep-app")

@server.tool("grep_search_intent")
async def search(query: str, path: str = ".", extensions: list[str] = None):
    """Natural language code search"""
    return await grep_search(query, path, extensions)

@server.tool("grep_regex")
async def regex(pattern: str, path: str = ".", exclude: list[str] = None):
    """Regex search in code files"""
    return await grep_regex(pattern, path, exclude)
```

**里程碑**:
- [ ] Day 1: 项目搭建，MCP SDK 集成
- [ ] Day 2-3: 搜索逻辑迁移 (grep/find 包装)
- [ ] Day 4: MCP 协议实现
- [ ] Day 5: 测试 + 文档

---

### Phase 3B - 功能 Agent (2 周)

#### 3. plan agent → Python (4 天)

**目标**:
- 依赖分析使用 networkx
- 计划导出支持 JSON/YAML
- 进度追踪可视化

**依赖**:
```txt
networkx>=3.0  # 图算法
pyyaml>=6.0    # YAML 导出
rich>=13.0     # 终端美化
```

**里程碑**:
- [ ] Day 1: 项目搭建
- [ ] Day 2-3: 依赖分析迁移
- [ ] Day 4: 测试 + 文档

---

#### 4. worker → TypeScript (2 天)

**目标**:
- 与 pool-manager 集成
- 使用 TypeScript 重写

**里程碑**:
- [ ] Day 1: 迁移
- [ ] Day 2: 测试

---

### Phase 3C - 可选增强 (1 周，可选)

#### 5. librarian → TypeScript (3 天)
- MCP 集成 (context7 + websearch)
- 文档检索优化

#### 6. scout/reviewer → Python (可选)
- 代码分析 (AST)
- 复杂度计算

---

## 📊 最终工作量评估

| 阶段 | 插件 | 工作量 | 优先级 |
|------|------|--------|--------|
| **3A** | context7 MCP | 3 天 | P0 |
| **3A** | grep-app MCP | 5 天 | P0 |
| **3B** | plan agent | 4 天 | P1 |
| **3B** | worker | 2 天 | P1 |
| **3C** | librarian | 3 天 | P2 (可选) |
| **3C** | scout/reviewer | 6 天 | P3 (可选) |
| **总计** | | **17 天** (核心) / **23 天** (完整) | |

---

## ⚠️ 风险评估

### 低风险 (可迁移)

| 插件 | 风险 | 理由 |
|------|------|------|
| context7 | 低 | 使用官方 SDK，上游稳定 |
| grep-app | 低 | 无上游，本地实现 |
| plan | 低 | 纯逻辑，无系统依赖 |

### 高风险 (不迁移)

| 插件 | 风险 | 理由 |
|------|------|------|
| qwen agent | 高 | 包装 qwen CLI，迁移无意义 |
| build agent | 高 | 系统命令编排，Bash 更合适 |

---

## ✅ 验收标准

### context7 MCP

- [ ] 配置管理类型安全
- [ ] local/remote 模式正常工作
- [ ] 通过所有 10+ 单元测试
- [ ] 文档完整

### grep-app MCP

- [ ] 所有搜索功能正常
- [ ] MCP stdio 协议兼容
- [ ] 性能不低于 Bash 版本
- [ ] 通过所有 15+ 单元测试

### plan agent

- [ ] 依赖分析正确
- [ ] 计划导出支持 JSON/YAML
- [ ] 通过所有 10+ 单元测试

---

## 📚 相关文档

- [PHASE3-DETAILED-ASSESSMENT.md](./PHASE3-DETAILED-ASSESSMENT.md) - 详细评估
- [MCP-UPSTREAM-STRATEGY.md](./MCP-UPSTREAM-STRATEGY.md) - 上游策略
- [MIGRATION-TS-PY.md](./MIGRATION-TS-PY.md) - 总体迁移评估

---

**批准人**: OML Team
**许可**: MIT License
