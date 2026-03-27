# OML TypeScript 迁移研究计划

**AI-LTC Lane**: shell-migration-research
**Phase**: init -> execution
**Date**: 2026 年 3 月 26 日

---

## 1. 研究背景

### 1.1 现状分析

OML 项目已完成 TypeScript 核心框架搭建 (packages/core, packages/cli, packages/modules)，但仍有 **177 个 Shell 脚本** 需要迁移。

**现有 Shell 脚本分布**:
```
Total: 177 files
├── core/          19 files (P0 - 核心功能)
├── modules/       15 files (P0 - 功能模块)
├── plugins/      124 files (P1 - 插件系统)
├── tools/          3 files (P2 - 工具脚本)
└── scripts/        7 files (P2 - 部署脚本)
```

### 1.2 迁移必要性

| 原因 | 说明 |
|------|------|
| **类型安全** | TypeScript 提供静态类型检查，减少运行时错误 |
| **可维护性** | 模块化架构，更好的代码组织 |
| **可测试性** | 完善的单元测试框架支持 |
| **IDE 支持** | 更好的自动补全、重构工具 |
| **性能优化** | 编译优化，更好的执行效率 |

---

## 2. 研究目标

### 2.1 主要目标

1. **分析现有 Shell 脚本功能** - 理解每个脚本的职责和依赖
2. **设计 TypeScript 迁移方案** - 为每类脚本设计对应的 TS 实现
3. **制定迁移优先级** - 基于依赖关系和使用频率排序
4. **创建迁移指南** - 为后续执行提供详细步骤

### 2.2 交付物

| 文档 | 说明 | 优先级 |
|------|------|--------|
| `SHELL-ANALYSIS.md` | 177 个 Shell 脚本功能分析 | 🔴 P0 |
| `MIGRATION-STRATEGY.md` | 迁移策略和设计模式 | 🔴 P0 |
| `PRIORITY-MATRIX.md` | 迁移优先级矩阵 | 🔴 P0 |
| `API-MAPPING.md` | Shell -> TypeScript API 映射 | 🔴 P0 |
| `MIGRATION-GUIDE.md` | 详细迁移步骤指南 | 🟡 P1 |
| `TEST-STRATEGY.md` | 测试策略和覆盖率目标 | 🟡 P1 |

---

## 3. 研究方法论

### 3.1 分析阶段 (Execution Stage 1)

**方法**: 静态分析 + 功能归类

**步骤**:
1. 遍历所有 `.sh` 文件
2. 提取功能描述、输入输出、依赖关系
3. 归类到功能域 (session, pool, hooks, etc.)
4. 识别共享代码和重复逻辑

**产出**: `SHELL-ANALYSIS.md`

### 3.2 设计阶段 (Execution Stage 2)

**方法**: 架构设计 + 模式匹配

**步骤**:
1. 为每类功能设计 TypeScript 接口
2. 选择合适的设计模式
3. 定义模块边界和依赖关系
4. 设计错误处理策略

**产出**: `MIGRATION-STRATEGY.md`

### 3.3 规划阶段 (Execution Stage 3)

**方法**: 优先级排序 + 工作量估算

**步骤**:
1. 基于依赖关系排序
2. 基于使用频率排序
3. 估算每个模块迁移工作量
4. 制定里程碑和时间线

**产出**: `PRIORITY-MATRIX.md`

### 3.4 映射阶段 (Execution Stage 4)

**方法**: API 对照 + 示例代码

**步骤**:
1. Shell 函数 -> TypeScript 函数映射
2. Shell 变量 -> TypeScript 常量/配置映射
3. Shell 管道 -> TypeScript 流式处理映射
4. 提供迁移前后代码对照示例

**产出**: `API-MAPPING.md`

### 3.5 指南阶段 (Execution Stage 5)

**方法**: 步骤分解 + 最佳实践

**步骤**:
1. 编写逐步迁移指南
2. 提供检查清单
3. 记录常见问题和解决方案
4. 定义验收标准

**产出**: `MIGRATION-GUIDE.md`

---

## 4. 时间线

| 阶段 | 内容 | 预计时间 | 状态 |
|------|------|----------|------|
| Stage 1 | 分析阶段 | 2-3 天 | 📋 待开始 |
| Stage 2 | 设计阶段 | 2-3 天 | 📋 待开始 |
| Stage 3 | 规划阶段 | 1-2 天 | 📋 待开始 |
| Stage 4 | 映射阶段 | 2-3 天 | 📋 待开始 |
| Stage 5 | 指南阶段 | 1-2 天 | 📋 待开始 |

**总计**: 8-13 天

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Shell 脚本功能复杂 | 高 | 分阶段分析，先易后难 |
| 依赖关系复杂 | 中 | 创建依赖图，识别关键路径 |
| 边界情况遗漏 | 中 | 代码审查 + 测试验证 |
| 工作量估算偏差 | 低 | 预留 20% 缓冲时间 |

---

## 6. 成功标准

| 标准 | 衡量方式 |
|------|----------|
| 完整性 | 177 个脚本全部分析完毕 |
| 准确性 | 功能描述准确率 > 95% |
| 可用性 | 迁移指南可直接执行 |
| 可测试性 | 每个模块有明确验收标准 |

---

## 7. AI-LTC 状态流

```
init
  -> execution (Stage 1-5)
  -> review-gate (文档审查)
  -> checkpoint-closeout (研究完成)
  -> new lane (迁移执行)
```

---

## 8. 参考资源

### 8.1 现有 TypeScript 实现
- `packages/core/src/` - 核心模块参考
- `packages/cli/src/` - CLI 实现参考
- `packages/modules/src/` - 功能模块参考

### 8.2 Shell 脚本位置
- `core/*.sh` - 核心功能
- `modules/*.sh` - 功能模块
- `plugins/**/*.sh` - 插件系统

### 8.3 AI-LTC 框架
- `/home/miao/develop/AI-LTC/README.zh.md`
- `/home/miao/develop/AI-LTC/ARCHITECTURE-LAYERS.md`
- `/home/miao/develop/AI-LTC/STATE-FLOWS.md`

---

**Next Action**: 开始 Stage 1 - 分析阶段，产出 `SHELL-ANALYSIS.md`
