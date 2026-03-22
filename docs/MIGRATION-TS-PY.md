# OML Bash → TypeScript/Python 迁移评估

**版本**: 0.1.0
**创建日期**: 2026-03-23
**状态**: 评估阶段

---

## 📋 执行摘要

OML 当前以 Bash 为主要实现语言，但为了长期可维护性、类型安全和跨平台一致性，计划逐步迁移到 **TypeScript + Python** 混合架构。

### 当前状态

| 指标 | 数值 |
|------|------|
| **总代码行数** | ~67,000 行 |
| **Bash 文件数** | ~100+ |
| **核心模块** | 15 个 (全部 Bash) |
| **插件** | 10 个 (全部 Bash) |
| **测试覆盖** | 100% (Bash 测试) |

### 迁移目标

| 阶段 | 目标 | 时间线 |
|------|------|--------|
| **Phase 1** | 核心 CLI 迁移 (oml 命令) | 2-3 周 |
| **Phase 2** | 核心模块迁移 (platform, plugin-loader) | 3-4 周 |
| **Phase 3** | 插件迁移 (agents, mcps) | 4-6 周 |
| **Phase 4** | 高级功能迁移 (pool, session, hooks) | 6-8 周 |

---

## 🎯 迁移原则

### 1. 渐进式迁移
- 不破坏现有功能
- 保持向后兼容
- 可以混合运行 (Bash + TS/Py)

### 2. 平台优先
- Termux 和 GNU/Linux 必须同时支持
- 避免平台特定代码污染
- 使用平台抽象层

### 3. 类型安全
- TypeScript 严格模式
- Python 类型注解
- 运行时类型检查

### 4. 测试驱动
- 迁移前：现有测试通过
- 迁移中：测试同步更新
- 迁移后：测试覆盖不降低

---

## 📁 模块迁移优先级

### P0 - 核心 CLI (优先迁移)

| 文件 | 行数 | 复杂度 | 优先级 | 目标语言 |
|------|------|--------|--------|---------|
| `oml` | 918 | 高 | P0 | TypeScript |
| `core/platform.sh` | 429 | 中 | P0 | TypeScript |
| `core/plugin-loader.sh` | 503 | 中 | P0 | TypeScript |

**理由**: 
- 核心入口点，影响所有功能
- 平台检测逻辑复杂，需要类型安全
- 迁移后可立即提升用户体验

### P1 - 会话和 Worker 管理

| 文件 | 行数 | 复杂度 | 优先级 | 目标语言 |
|------|------|--------|--------|---------|
| `core/session-manager.sh` | 998 | 高 | P1 | TypeScript |
| `core/session-storage.sh` | 1021 | 高 | P1 | TypeScript |
| `core/pool-manager.sh` | 1269 | 高 | P1 | TypeScript |
| `core/pool-concurrency.sh` | 1083 | 高 | P1 | TypeScript |

**理由**:
- 状态管理复杂，需要强类型
- 并发控制需要更好的抽象
- 会话数据需要持久化

### P2 - Hooks 系统

| 文件 | 行数 | 复杂度 | 优先级 | 目标语言 |
|------|------|--------|--------|---------|
| `core/hooks-engine.sh` | 752 | 高 | P2 | Python |
| `core/hooks-dispatcher.sh` | 594 | 中 | P2 | Python |
| `core/hooks-registry.sh` | 780 | 中 | P2 | Python |
| `core/event-bus.sh` | 625 | 中 | P2 | Python |

**理由**:
- 事件驱动架构适合 Python
- 需要动态脚本能力
- 与 AI 工具集成紧密

### P3 - Agent 插件

| 插件 | 行数 | 复杂度 | 优先级 | 目标语言 |
|------|------|--------|--------|---------|
| `plugins/agents/qwen/` | 1358 | 高 | P3 | TypeScript |
| `plugins/agents/build/` | 1257 | 中 | P3 | Python |
| `plugins/agents/plan/` | 1737 | 中 | P3 | Python |

**理由**:
- qwen 需要与 Qwen Code 原生集成
- build/plan 需要系统脚本能力

### P4 - Subagent 插件

| 插件 | 行数 | 复杂度 | 优先级 | 目标语言 |
|------|------|--------|--------|---------|
| `plugins/subagents/worker/` | 349 | 低 | P4 | TypeScript |
| `plugins/subagents/scout/` | 527 | 中 | P4 | Python |
| `plugins/subagents/librarian/` | 703 | 中 | P4 | Python |
| `plugins/subagents/reviewer/` | 893 | 中 | P4 | Python |

**理由**:
- worker 简单，可先用 TS
- scout/librarian/reviewer 需要代码分析能力

### P5 - MCP 插件

| 插件 | 行数 | 复杂度 | 优先级 | 目标语言 |
|------|------|--------|--------|---------|
| `plugins/mcps/context7/` | 984 | 高 | P5 | TypeScript |
| `plugins/mcps/grep-app/` | 2146 | 高 | P5 | Python |
| `plugins/mcps/websearch/` | 246 | 中 | P5 | Python |

**理由**:
- context7 需要与 MCP SDK 集成
- grep-app/websearch 需要网络/搜索能力

---

## 🏗️ 目标架构

### 目录结构

```
oh-my-litecode/
├── bin/                          # 编译后的可执行文件
│   ├── oml                       # TypeScript CLI
│   └── oml-hooks                 # Python hooks runner
├── src/
│   ├── cli/                      # TypeScript CLI
│   │   ├── index.ts
│   │   ├── commands/
│   │   │   ├── build.ts
│   │   │   ├── plugins.ts
│   │   │   ├── worker.ts
│   │   │   └── mcps.ts
│   │   └── platform.ts
│   ├── core/                     # TypeScript 核心
│   │   ├── plugin-loader.ts
│   │   ├── session-manager.ts
│   │   └── pool-manager.ts
│   └── hooks/                    # Python hooks
│       ├── engine.py
│       ├── dispatcher.py
│       └── event_bus.py
├── plugins/                      # 迁移后的插件
│   ├── agents/
│   │   ├── qwen/                 # TypeScript
│   │   └── build/                # Python
│   └── mcps/
│       └── context7/             # TypeScript
├── legacy/                       # 旧 Bash 代码 (保留兼容)
│   ├── oml.bash
│   └── core/
├── tests/
│   ├── unit/                     # 单元测试
│   ├── integration/              # 集成测试
│   └── e2e/                      # 端到端测试
├── package.json                  # TypeScript 依赖
├── requirements.txt              # Python 依赖
└── tsconfig.json                 # TypeScript 配置
```

### 技术栈

#### TypeScript
- **运行时**: Node.js 20+ / Bun 1.0+
- **类型检查**: TypeScript 5.0+ 严格模式
- **CLI 框架**: Commander.js 或 Cliffy (Deno)
- **测试**: Vitest 或 Jest
- **打包**: esbuild 或 pkg

#### Python
- **版本**: Python 3.10+
- **类型检查**: mypy + pydantic
- **事件系统**: asyncio + aioevents
- **测试**: pytest + pytest-asyncio
- **打包**: PyInstaller 或 uv

### 通信协议

#### Bash ↔ TypeScript
```bash
# 通过子进程调用
node bin/oml platform detect
```

#### TypeScript ↔ Python
```typescript
// 通过 stdio 协议
const result = await spawn('python', ['src/hooks/engine.py', event]);
```

#### 插件接口
```typescript
interface Plugin {
  name: string;
  version: string;
  type: 'agent' | 'subagent' | 'mcp' | 'skill';
  main: string;  // .ts, .py, or .sh
  platforms: Array<'termux' | 'gnu-linux'>;
  
  // 生命周期钩子
  onInstall?(): Promise<void>;
  onEnable?(): Promise<void>;
  onDisable?(): Promise<void>;
  onUninstall?(): Promise<void>;
  
  // 命令处理
  commands?: Record<string, (...args: string[]) => Promise<void>>;
}
```

---

## 📊 迁移工作量评估

### Phase 1: 核心 CLI (2-3 周)

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| TypeScript 项目搭建 | 2 天 | - |
| oml 命令迁移 | 5 天 | - |
| platform.sh 迁移 | 3 天 | oml |
| 测试迁移 | 3 天 | oml, platform |
| 文档更新 | 2 天 | 全部 |

**小计**: 15 工作日

### Phase 2: 核心模块 (3-4 周)

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| plugin-loader 迁移 | 4 天 | Phase 1 |
| session-manager 迁移 | 5 天 | Phase 1 |
| pool-manager 迁移 | 5 天 | Phase 1 |
| 并发控制迁移 | 4 天 | pool-manager |
| 测试迁移 | 5 天 | 全部 |

**小计**: 23 工作日

### Phase 3: Hooks 系统 (3-4 周)

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| Python 项目搭建 | 2 天 | - |
| event-bus 迁移 | 3 天 | Phase 1 |
| hooks-engine 迁移 | 5 天 | event-bus |
| hooks-dispatcher 迁移 | 4 天 | hooks-engine |
| hooks-registry 迁移 | 3 天 | hooks-engine |
| 测试迁移 | 5 天 | 全部 |

**小计**: 22 工作日

### Phase 4: 插件迁移 (4-6 周)

| 任务 | 工作量 | 依赖 |
|------|--------|------|
| qwen agent 迁移 | 5 天 | Phase 1, 2 |
| build/plan agent 迁移 | 5 天 | Phase 3 |
| subagents 迁移 | 8 天 | Phase 1, 2 |
| mcps 迁移 | 8 天 | Phase 1, 2 |
| 测试迁移 | 5 天 | 全部 |

**小计**: 31 工作日

### 总计

| 阶段 | 工作日 | 累计 |
|------|--------|------|
| Phase 1 | 15 | 15 |
| Phase 2 | 23 | 38 |
| Phase 3 | 22 | 60 |
| Phase 4 | 31 | 91 |

**总工作量**: 约 91 工作日 (~4.5 个月)

---

## ⚠️ 风险与缓解

### 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| TypeScript 性能不如 Bash | 中 | 低 | 使用 Bun 运行时，性能提升 3-5x |
| Python 启动慢 | 低 | 中 | 使用常驻进程 + stdio 协议 |
| 平台兼容性回归 | 高 | 中 | 双平台 CI/CD，每次提交测试 |
| 迁移期间功能停滞 | 中 | 低 | 保持 Bash 版本维护 |

### 管理风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| 工作量估计不足 | 高 | 中 | 每阶段结束重新评估 |
| 团队技能不足 | 中 | 低 | 提前培训 TS/Py |
| 用户需求变化 | 中 | 中 | 保持架构灵活性 |

---

## 🧪 测试策略

### 测试金字塔

```
        /\
       /  \      E2E Tests (10%)
      /----\     - 完整工作流
     /      \    - 跨平台测试
    /--------\   
   /          \  Integration Tests (30%)
  /------------\ - 模块间接口
 /              \- 插件集成
/----------------\ 
|                | Unit Tests (60%)
|                | - 纯函数
|________________| - 工具函数
```

### 测试框架

#### TypeScript
```json
{
  "devDependencies": {
    "vitest": "^1.0.0",
    "@vitest/coverage-v8": "^1.0.0",
    "tsx": "^4.0.0"
  }
}
```

#### Python
```txt
# requirements-dev.txt
pytest>=7.0.0
pytest-asyncio>=0.21.0
pytest-cov>=4.0.0
mypy>=1.0.0
```

### 测试覆盖率目标

| 模块 | 目标覆盖率 |
|------|----------|
| CLI | 90% |
| Core | 95% |
| Hooks | 85% |
| Plugins | 80% |

---

## 📈 迁移进度追踪

### 里程碑

- [ ] **M1**: TypeScript 项目搭建完成 (Week 1)
- [ ] **M2**: oml 命令迁移完成 (Week 3)
- [ ] **M3**: 核心模块迁移完成 (Week 7)
- [ ] **M4**: Hooks 系统迁移完成 (Week 11)
- [ ] **M5**: 插件迁移完成 (Week 17)
- [ ] **M6**: 全面测试通过 (Week 18)

### 每周检查点

| 周次 | 目标 | 完成标准 |
|------|------|---------|
| W1 | TS 项目搭建 | package.json, tsconfig.json, 基础 CI |
| W2 | oml 命令 50% | build, plugins 命令迁移 |
| W3 | oml 命令 100% | 所有命令迁移，测试通过 |
| W4 | platform 迁移 | 平台检测 100% 测试通过 |
| W5 | plugin-loader 迁移 | 插件加载 100% 测试通过 |
| ... | ... | ... |

---

## 🔧 开发环境 setup

### TypeScript

```bash
# 安装依赖
cd oh-my-litecode
npm install

# 开发模式
npm run dev

# 构建
npm run build

# 测试
npm test
```

### Python

```bash
# 创建虚拟环境
python -m venv .venv
source .venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 运行 hooks
python src/hooks/engine.py post_install
```

### 混合运行

```bash
# Bash 调用 TypeScript
./oml.ts platform detect

# TypeScript 调用 Python
node bin/oml hooks trigger post_install

# Python 调用 Bash
subprocess.run(['bash', '-c', 'source legacy/core/platform.sh && oml_platform_detect'])
```

---

## 📚 参考资源

### TypeScript
- [TypeScript 官方文档](https://www.typescriptlang.org/docs/)
- [Node.js CLI 最佳实践](https://clig.dev/)
- [Bun 运行时](https://bun.sh/)

### Python
- [Python 类型注解](https://docs.python.org/3/library/typing.html)
- [asyncio](https://docs.python.org/3/library/asyncio.html)
- [pydantic](https://docs.pydantic.dev/)

### 架构
- [CLI 设计原则](https://clig.dev/)
- [十二要素应用](https://12factor.net/)
- [事件驱动架构](https://www.eventdriven.io/)

---

## 📝 决策日志

### 2026-03-23: 初始评估

**决策**: 采用 TypeScript + Python 混合架构

**理由**:
1. TypeScript 提供类型安全，适合 CLI 和核心逻辑
2. Python 适合事件处理和 AI 集成
3. 保持 Bash 兼容，渐进式迁移

**反对意见**:
- 增加技术栈复杂度
- 需要团队学习成本

**缓解**:
- 提供详细文档和培训
- 保持向后兼容

---

**维护者**: OML Team
**许可**: MIT License
