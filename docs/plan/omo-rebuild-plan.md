# OMO 重建实施计划

> 配套设计：`docs/design/omo-rebuild.md`
> 运行环境：bun 1.4.2（本机 `/usr/bin/node` 损坏：缺 `libada.so.3`，全链路禁用裸 `node`）

## 阶段与任务

### P0 宪法层（由编排者独占写入，A4）
- [ ] `package.json`：bun workspaces（`packages/*`, `OC/omo`, `OC2/omo`）
- [ ] `tsconfig.base.json`：strict、ES2022、Bundler resolution、无 emit
- [ ] `BUDGET.md`：零增长账本（技能/hook/MCP/插件/依赖四项上限）
- [ ] `MODULES.md`：每个模块一行「消灭的矛盾」，写不出不合入
- [ ] `scripts/check.ts`：类型 + 单测 + 预算 + 结构 + 零增长 五道门
- 验证：`bun run check` 能在空实现上跑通并给出明确失败原因

### P1 契约层（编排者独占写入）
- [ ] `packages/core/src/contract.ts`：`PluginHost` / `SkillMeta` / `AgentSpec` / `ToolSpec` / `BudgetReport`
- [ ] `packages/core/src/index.ts`：稳定导出面
- 验证：`bun x tsc --noEmit` 通过

### P2 预算模块（并行单元 A）
- [ ] `packages/core/src/budget/estimate.ts`：CJK/ASCII 近似 token 计数
- [ ] `packages/core/src/budget/assemble.ts`：按段拼装，段优先级 `tools > identity > skillIndex > memory`
- [ ] `packages/core/src/budget/gate.ts`：超限截断 + 可见告警
- [ ] `packages/core/src/budget/gate.test.ts`
- 验证：8192 上限下，输入 20000 tok 的段被按优先级截断且告警写入

### P3 技能惰性索引（并行单元 B）
- [ ] `packages/core/src/skills/scan.ts`：扫描 4 个技能根，解析 frontmatter name/description
- [ ] `packages/core/src/skills/index-gen.ts`：生成 `name(触发语)` 索引，每条 ≤40 字，取 top-40
- [ ] `packages/core/src/skills/usage.ts`：`skill-usage.json` 读写、命中累加、连续 10 次零命中降级
- [ ] `packages/core/src/skills/*.test.ts`
- 验证：对真实 319 个 SKILL.md 生成索引 ≤1600 tok；零命中技能被降级

### P4 CLI（并行单元 C）
- [ ] `packages/cli/src/main.ts`：`omo measure|audit|slim|zhengfeng`
- [ ] `bench/prompt.ts`：空闲提示体积基准，输出 JSON
- [ ] `bench/startup.ts`：冷启动 p95
- 验证：`bun run omo measure` 输出设计文档 §7 的 JSON 形状

### P5 OC 前线（并行单元 D）
- [ ] `OC/omo/src/host.ts`：OpenCode 1.x `PluginHost` 实现（≤300 行）
- [ ] `OC/omo/src/index.ts`：插件入口，注册 8 个 hook 位置中的已实现者
- [ ] `OC/omo/package.json`
- 验证：在 OC 1.19.3 上加载不报错，`transformSystemPrompt` 生效

### P6 OC2 前线（并行单元 E）
- [ ] `OC2/omo/src/host.ts`：OpenCode 2.x 适配骨架 + TODO 标注差异点
- [ ] `OC2/omo/src/contract.test.ts`：契约一致性测试（两前线导出面必须相同）
- 验证：契约测试通过（不要求真实 OC2 运行）

### P7 端到端验收
- [ ] 真实跑通「派发子代理改一个文件」
- [ ] `omo measure` ≤8192 tok
- [ ] 与旧 OMO 的影子对比表

## 并行边界（A4 单一写入者）

| 单元 | 独占路径 | 禁止触碰 |
|---|---|---|
| 编排者 | 根配置、`contract.ts`、`index.ts`、`BUDGET.md`、`MODULES.md` | 各模块内部实现 |
| A | `packages/core/src/budget/**` | 其他任何路径 |
| B | `packages/core/src/skills/**` | 其他任何路径 |
| C | `packages/cli/**`, `bench/**` | 其他任何路径 |
| D | `OC/omo/**` | 其他任何路径 |
| E | `OC2/omo/**` | 其他任何路径 |

## 完成定义

`bun run check` 全绿；`omo measure` ≤8192 tok；OC 上端到端跑通一次委派。
