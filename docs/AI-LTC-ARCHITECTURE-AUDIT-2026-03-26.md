# OML AI-LTC 架构审查与长期规划

**日期**: 2026-03-26  
**范围**: `/home/miao/develop/oh-my-litecode`  
**参照**: AI-LTC v1 四层架构、A-B-O 生命周期、relay/runtime 分层规则

## 1. 审查结论

当前仓库的核心问题不是“缺少设计”，而是三层事实不同步：

1. **治理层不完整**  
   已复制 prompt、template 和 `.ai/` 运行态，但缺少 `AGENTS.md`、`.ai/README.md`、`docs/ai-relay.md`、`docs/ai-collaboration.md`、`docs/ai-workbench.md` 这些最小 relay surface，导致 AI-LTC 在本仓库是“半部署”状态。

2. **实现层完成度被文档高估**  
   `packages/README.md` 把 `@oml/core`、`@oml/cli`、`@oml/modules` 标为 complete，但 `packages/core/src/pool/index.ts` 仍是 placeholder，`packages/cli/src/commands/qwen.ts` 存在多个 coming soon，占位远多于“完成”。

3. **验证层策略与路线图冲突**  
   路线图把测试完善排在后续阶段，但仓库当前已把 `npm test` 作为工程门禁；同时 `packages/cli`、`packages/modules` 原本没有测试文件，导致 test gate 先于功能成熟而失败。

4. **迁移边界不清晰**  
   根目录仍保留大量 shell 实现，`src/` 与 `packages/` 两套 TypeScript 结构并存，缺少明确的“谁是未来主线、谁是过渡兼容层”的边界说明。

## 2. 关键发现

### High

- **AI-LTC 协议入口缺失**  
  证据：仓库原先没有根 `AGENTS.md`，也缺少 `docs/ai-relay.md`、`docs/ai-collaboration.md`、`.ai/README.md`。  
  影响：AI 在进入仓库时没有统一 read order，runtime state 与 stable docs 之间缺少权威入口。

- **测试门禁为假失败而非真实质量门禁**  
  证据：`npm test` 失败原因为 `packages/cli` 和 `packages/modules` 没有测试文件。  
  影响：当前红灯不能区分“实现回归”和“治理缺口”，降低审查信号质量。

- **“完成”叙事与实际实现不符**  
  证据：`packages/README.md` 标 complete，但 `packages/core/src/pool/index.ts`、`packages/cli/src/commands/qwen.ts`、`packages/modules/src/error/reporter.ts` 仍有明显占位逻辑。  
  影响：长期规划会被错误基线污染，导致路线图失真。

### Medium

- **AI-LTC resolver 字段不完全符合 v1 期望**  
  当前 config 缺少 `human_summary_language` 和 `human_input_language_policy`，且治理文档未明确本仓库如何解析 active lane。

- **迁移资产分散**  
  `src/`、`packages/`、旧 shell 目录同时存在，但没有单一迁移宪法文档说明优先级和淘汰顺序。

## 3. 架构优化决策

### 决策 A: 把 OML 明确定义为“双轨迁移仓库”

- **Track 1**: legacy shell 作为功能基线和兼容层
- **Track 2**: `packages/*` 作为未来主线
- **约束**: 在 core parity 未完成前，不再把 TypeScript 包标记为 complete

### 决策 B: 把 AI-LTC 治理骨架视为强依赖，而不是附属文档

- `AGENTS.md`、`.ai/README.md`、`docs/ai-relay.md`、`docs/ai-collaboration.md`、`docs/ai-workbench.md` 必须齐套
- `.ai/` 负责 live state，`docs/` 负责稳定协议和人类入口

### 决策 C: 把验证分成三层

- **Layer V0**: build/typecheck 必须绿
- **Layer V1**: 每个 workspace 至少一个 smoke test，避免空套件假失败
- **Layer V2**: 核心 parity 模块建立行为测试，再谈覆盖率指标

### 决策 D: 路线图从“全量迁移”改成“价值切片迁移”

- 先做治理和 proof path
- 再做 `core` 的 parity slice
- 然后做 CLI 契约和模块边界
- 最后再进入大规模 plugin / shell 迁移

## 4. 分阶段长期规划

### 0 到 7 天: Stabilize

- 补齐 AI-LTC 治理骨架和 ignore 规则
- 让 `build`、`typecheck`、`test` 成为可信信号
- 明确 `src/` 与 `packages/` 的地位，停止“完成”叙事漂移

### 2 到 4 周: Core Parity

- 以 `platform`、`session`、`hooks` 为第一批 parity slice
- `pool` 不再占位暴露为“已完成模块”，需要单独列为 P1
- 为 session、hooks、cache、translator 建立行为测试

### 1 到 2 个月: Contract Consolidation

- 为 CLI 命令建立稳定 contract：哪些是真实可用，哪些仍是 stub
- 将 `src/` 目录转为 bridge notes 或明确废弃
- 为 shell 与 TypeScript 之间建立 adapter/compat 层，而不是并行漂移

### 1 个季度: Selective Migration

- 只迁移高复用、高稳定价值的 shell 能力
- 对 plugins 和 MCP 采用“边界先行、实现后补”的策略
- 对每个迁移批次给出 parity 证据，而不是继续扩张文档规模

## 5. 本次已执行优化

- 补齐本仓库缺失的 AI-LTC 治理入口文件
- 将 `.ai/`、`.omx/`、`AGENTS.md` 纳入本地状态忽略
- 为 `packages/cli` 与 `packages/modules` 增加最小 smoke tests
- 在 resolver config 中补充 AI-LTC v1 语言字段

## 6. 对 AI-LTC 的反哺建议

从 OML 这次审查看，AI-LTC 还应强化三件事：

1. **部分部署识别**  
   目标仓库最容易复制 prompt/template，却漏掉 relay surface。bootstrap checklist 应明确把这些文件列为“缺一不可”的最小集合。

2. **兼容已有配置模型**  
   真实项目可能已经存在自己的 config schema。AI-LTC init 需要强调“兼容扩展”而不是强制替换。

3. **治理完成度先于执行完成度**  
   如果 protocol layer 没齐，就不应宣称 init 已完成，更不应进入 execution 叙事。

## 7. 推荐下一步

1. 以 `platform + session + hooks` 为第一批 parity lane，暂停扩大 CLI/插件表面面积。
2. 把 `packages/README.md` 的状态从 complete 改成 evidence-based status。
3. 新开一轮专门的“迁移边界收敛”审查，决定 `src/` 是否保留为 bridge 层。
