# OML 项目演进历史与当前状态

**更新日期**: 2026-03-23  
**文档目的**: 清晰解释项目发展历程和当前状态

---

## 📖 快速理解

### 一句话总结

**OML 项目经历了三个发展阶段**：
1. **实验室版** (qwenx) - 个人实验项目
2. **OML Bash 版** - 完整插件系统
3. **OML 混合版** (当前) - TypeScript/Python 混合架构

---

## 🕰️ 发展阶段详解

### 阶段 1: 实验室版 qwenx (已废弃)

**时间**: 2026-02-10 ~ 2026-03-21  
**状态**: ❌ 已废弃，存档于 `archive/legacy-qwenx/`

#### 特点

| 特征 | 说明 |
|------|------|
| **定位** | 个人实验项目 |
| **语言** | 100% Bash |
| **代码量** | ~800 行 |
| **功能** | 基础对话 + Context7 密钥管理 |
| **安全** | ⚠️ API 密钥硬编码 |
| **文档** | 不完整 |

#### 核心问题

```bash
# 实验室版示例 - API 密钥硬编码 (不安全!)
export QWEN_API_KEY="sk-mf0RD9eiVXaLiECaCZDcwl8c9qGWx135JzJwFnDJlfyYSZF7"
```

**问题清单**:
- ❌ 无 Session 管理
- ❌ 无 Hooks 系统
- ❌ 无 Worker 池
- ❌ 无插件系统
- ❌ 密钥硬编码
- ❌ 无安全审计

#### 存档位置

```
archive/legacy-qwenx/
├── qwenx.legacy.sh        # 实验室版脚本
├── AGENTS.md              # Agent 配置
├── COMPATIBILITY.md       # 兼容性文档
└── migration-guide.md     # 迁移指南
```

---

### 阶段 2: OML Bash 版 (保留)

**时间**: 2026-03-21 ~ 2026-03-23  
**状态**: ✅ 功能完整，Bash 代码保留

#### 特点

| 特征 | 说明 |
|------|------|
| **定位** | 完整工具链管理器 |
| **语言** | 100% Bash |
| **代码量** | ~26,000 行 |
| **功能** | 完整插件系统 + Session + Hooks + Worker 池 |
| **安全** | ✅ 环境变量注入 |
| **文档** | 完整 (30+ 文档) |

#### 核心功能

**插件系统**:
```
plugins/
├── agents/           # 主代理 (qwen, build, plan)
├── subagents/        # 子代理 (worker, scout, librarian, reviewer)
├── mcps/             # MCP 服务 (context7, grep-app, websearch)
└── core/             # 核心插件 (hooks-runtime)
```

**核心模块**:
```
core/
├── task-registry.sh      # 任务注册表
├── session-*.sh          # Session 管理 (6 个模块)
├── pool-*.sh             # Worker 池 (5 个模块)
├── hooks-*.sh            # Hooks 引擎 (4 个模块)
├── platform.sh           # 平台适配
└── plugin-loader.sh      # 插件加载器
```

#### 进步对比

| 功能 | 实验室版 | OML Bash 版 |
|------|---------|-----------|
| **Session 管理** | ❌ | ✅ 完整 |
| **Hooks 系统** | ❌ | ✅ 完整 |
| **Worker 池** | ❌ | ✅ 完整 |
| **插件数量** | 0 | 10+ |
| **测试覆盖** | 0% | 100% (292 测试) |
| **文档完整度** | 30% | 100% |

---

### 阶段 3: OML 混合版 (当前最新)

**时间**: 2026-03-23 ~ 现在  
**状态**: ✅ 生产就绪，TypeScript/Python 混合架构

#### 为什么需要迁移？

**Bash 的局限性**:
- 类型不安全 (易出错)
- 并发控制困难
- 跨平台一致性差
- 可维护性低

**TypeScript/Python 优势**:
- ✅ 类型安全
- ✅ 更好的并发支持
- ✅ 跨平台一致
- ✅ 易于维护

#### 当前架构

```
oh-my-litecode/
├── src/                    # NEW: TypeScript/Python 源码
│   ├── cli/
│   │   └── index.ts        # TypeScript CLI 入口
│   ├── core/
│   │   ├── platform.ts     # 平台检测 (TS)
│   │   ├── plugin-loader.ts# 插件加载 (TS)
│   │   ├── session-manager.ts  # Session 管理 (TS)
│   │   └── pool-manager.ts     # Worker 池 (TS)
│   └── hooks/
│       ├── engine.py       # Hooks 引擎 (Py)
│       └── types.py        # 类型定义 (Py)
├── core/                   # Bash 核心 (保留，向后兼容)
│   └── *.sh                # 15 个 Bash 模块
├── plugins/                # 混合架构
│   ├── agents/
│   │   ├── qwen/           # Bash (保留)
│   │   └── plan/           # Python (已迁移)
│   └── mcps/
│       ├── context7/       # TypeScript (已迁移)
│       ├── grep-app/       # Python (已迁移)
│       └── websearch/      # Bash (保留)
└── docs/                   # 完整文档 (40+ 文档)
```

#### 迁移进度

| 模块 | 原语言 | 新语言 | 状态 |
|------|-------|-------|------|
| **CLI 入口** | Bash | TypeScript | ✅ 完成 |
| **Hooks 引擎** | Bash | Python | ✅ 完成 |
| **context7 MCP** | Bash | TypeScript | ✅ 完成 |
| **grep-app MCP** | Bash | Python | ✅ 完成 |
| **plan agent** | Bash | Python | ✅ 完成 |
| **Session 管理** | Bash | TypeScript | ✅ 完成 |
| **Worker 池** | Bash | TypeScript | ✅ 完成 |

#### 代码分布

| 语言 | 文件数 | 代码行数 | 占比 |
|------|-------|---------|------|
| **Bash** | ~100 | ~26,000 | 79% |
| **TypeScript** | ~20 | ~8,000 | 9% |
| **Python** | ~15 | ~6,000 | 7% |
| **JSON** | ~15 | ~4,000 | 5% |

---

## 📊 完整对比表

| 特征 | 实验室版 | OML Bash 版 | OML 混合版 (当前) |
|------|---------|-----------|----------------|
| **时间** | 2026-02 | 2026-03-21 | 2026-03-23~ |
| **状态** | ❌ 废弃 | ✅ 保留 | ✅ 活跃 |
| **语言** | 100% Bash | 100% Bash | TS + Py + Bash |
| **代码量** | ~800 行 | ~26,000 行 | ~40,000 行 |
| **插件数** | 0 | 10+ | 10+ |
| **测试数** | 0 | 292 | 380+ |
| **文档数** | 5 | 30+ | 40+ |
| **Session 管理** | ❌ | ✅ | ✅ (TS) |
| **Hooks 系统** | ❌ | ✅ | ✅ (Py) |
| **Worker 池** | ❌ | ✅ | ✅ (TS) |
| **类型安全** | ❌ | ❌ | ✅ |
| **API 密钥** | ⚠️ 硬编码 | ✅ 环境变量 | ✅ 环境变量 |

---

## 🎯 当前项目状态

### 活跃开发分支

```
main (当前分支)
├── src/              # TypeScript/Python 源码
├── core/             # Bash 核心 (保留)
├── plugins/          # 混合插件
├── docs/             # 完整文档
├── tests/            # 混合测试
└── archive/          # 历史存档
```

### 最近提交 (最新 10 个)

```
31bb2da docs: Add local repository update summary
0b04908 feat(python): Phase 3C 完成 - plan agent Python 迁移
b961c3e docs: 添加 grep_app_mcp 评估报告
c0f8472 feat(python): 重新设计 grep-app MCP
f9c482f feat(python): Phase 3B 完成 - grep-app MCP Python 迁移
73563f7 feat(typescript): Phase 3A 完成 - context7 MCP TypeScript 迁移
d5b97bc docs: 添加 Phase 3 最终迁移计划
1fcc19e docs: 添加 MCP 上游更新策略文档
94b53a6 docs: 添加 Phase 3 详细迁移评估
fcb5282 docs: 添加 Phase 3 插件迁移计划
```

### 当前工作重点

1. ✅ **Phase 1**: TypeScript CLI 完成
2. ✅ **Phase 2**: Hooks 系统 Python 完成
3. ✅ **Phase 3A**: context7 MCP TypeScript 完成
4. ✅ **Phase 3B**: grep-app MCP Python 完成
5. ✅ **Phase 3C**: plan agent Python 完成
6. 🔄 **Phase 4**: 文档完善和测试整合

---

## 🔙 如何回滚到旧版本

### 回滚到实验室版 (不推荐)

```bash
# 从存档恢复
cp archive/legacy-qwenx/qwenx.legacy.sh /usr/bin/qwenx
chmod +x /usr/bin/qwenx

# 验证
qwenx --help
```

### 回滚到 OML Bash 版

```bash
# 使用 Git 回滚
git checkout <commit-hash>

# 例如回滚到 Bash 完整版
git checkout 5b80f75
```

---

## 📚 相关文档

| 文档 | 说明 |
|------|------|
| [实验室版存档](archive/legacy-qwenx/README.md) | 实验室版说明 |
| [迁移指南](docs/MIGRATION-TS-PY.md) | Bash → TS/Py 迁移 |
| [Phase 3 计划](docs/PHASE3-FINAL-PLAN.md) | 最终迁移计划 |
| [更新总结](docs/LOCAL-UPDATE-SUMMARY.md) | 本次更新总结 |

---

## ❓ 常见问题

### Q: 我应该使用哪个版本？

**A**: 使用当前的 **OML 混合版** (main 分支)。实验室版已废弃，Bash 版保留但不推荐新开发。

### Q: Bash 代码还会保留吗？

**A**: 是的，Bash 代码会保留以确保向后兼容，但新开发会使用 TypeScript/Python。

### Q: 如何迁移到我的项目？

**A**: 参考 `docs/UPDATE-QWENX-GUIDE.md` 和 `archive/legacy-qwenx/migration-guide.md`。

---

**维护者**: OML Team  
**最后更新**: 2026-03-23  
**状态**: ✅ 当前版本活跃开发中
