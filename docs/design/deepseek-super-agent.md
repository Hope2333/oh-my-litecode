# DeepSeek Super Agent vs Neko OML（对照记档）

> 用户判断（原话）：「DeepSeek Super Agent（论文）与我前面设想的 Neko Agent 十分近似，
> 但我这个依赖于插件，即使是后面会出独立的东西。」本文把这个判断落成证据。

## 对象

`deepseek-ai/dsh-superagent-prototype`（23.1K★，MIT，TS，2026-10/11 发布）。
官方定位：**研究原型，非 DeepSeek 官方产品**；自述「可能是研究代码，风格不一致，
使用前先审阅」。设计文章《Exploring Super-agent Design: Towards a More Autonomous
Agent System》中的部分设计「是未来方向，原型未实现」。

## 它是什么

- **主动式编码代理**，绑定 DeepSeek Harness（dsh）发行，监听 GitHub（可选 Feishu）：
  被 @ → 开工单 → 自己的会话+目录里干活 → 回贴（如 PR）→ 面板只露出「需要人」的事。
- **router-worker**：一个 router 对用户，worker 在隔离会话里执行；社区 fork 描述的
  watchdog（重启卡死的 worker）与 ledger（不丢 issue/task/session）是其特征件。
- 哲学（docs/000，原文要点）：**「拿走尽可能少的人类注意力，给出尽可能多的价值」**；
  每个消息/通知/设置/文档段都要「给的价值 > 消耗的注意力，否则删掉」；
  默认值替代设置、行为用 prompt 不用设置、面板只展示需要人的事。

## 近似点（为什么用户说「十分近似」）

| 维度 | dsh-superagent | Neko OML | 判定 |
|---|---|---|---|
| 架构 | router（对用户）+ worker（隔离会话） | sisyphus（编排）+ omo_task run/team（隔离会话） | **同构** |
| 注意力经济 | 哲学核心：少打断、只在有价值时说话 | 预算门 8192 tok：只在有余量时注入；技能索引 40 条 | **同构**（一个管人类注意力，一个管上下文注意力，原理同源） |
| 任务账本 | ledger 不丢任务/session | tasks.json 状态机 + 滚动检查点 | **同构** |
| 看门狗 | watchdog 重启卡死 worker | （**未实现**：任务超时/卡死检测） | **OML 缺这块** |
| 主动模式 | 规则允许时主动开工（先记录后放行） | （未实现：OML 是被动的） | **OML 缺这块** |
| 面板 | Web 面板只露「需要人」 | `omo doctor/handoff`（文本） | 部分近似 |

## 差异点（Neko 的不同走法，别被「近似」冲掉）

1. **宿主依赖**：dsh 绑定 DeepSeek Harness 发行；Neko 是**任意宿主**上的插件层
   （OpenCode 1.x/2.x、dsh、未来 codex），经 ACP 路由表挂压缩引擎。
   → 用户判断的「依赖于插件，即使后面会出独立的东西」= 路线选择：先寄生宿主，
   独立运行时（rs/go）是后续阶段，不是前提。
2. **质量纪律**：dsh 自认「研究代码、风格不一致」；OML 是 194 测试 + 7 道门 +
   零增长账本 + 逐模块「消灭的矛盾」——dsh 的哲学文档管人类注意力，OML 的
   公理管**工程注意力**（谁写得出删除理由才准新增）。
3. **范围**：dsh 是「一个 GitHub 仓 + 团队注意力」；OML 是「单用户的上下文/资源预算」。
   两者的「少打扰」指向不同稀缺资源（人的注意力 vs 模型上下文），机制同构。

## 可吸收（判 F 级以下，不做就写进债）

- **watchdog**：task 超 TTL 未终结 → 自动 cancel + 记账（OML 已有 ttlMs，缺执行者）。
- **主动模式**：`omo_admin action=goal` 已有目标位，缺「规则允许的主动开工」（先记录后放行的两段制
  正好对应 OML 的 dry-run 习惯）。
- **面板**：`omo doctor` 的 facts 已含大部分，缺「只露需要人」的过滤视图。

## 结论

近似是真的（router-worker + 注意力经济 + 账本 + watchdog）。Neko 的差异在
**可移植性（插件化 → 未来独立）** 与 **删除纪律**。dsh 给 OML 的两个真缺口：
watchdog 与主动模式。两者都记在 `docs/design/omo-v2.md` 的待办里（不做不删，
但写明白为什么不现在做：watchdog 需要宿主级定时，插件层只能做会话内 TTL，
主动模式需要 GitHub/飞书 source，超出当前单用户范围）。

## 分级结合（2026-11-15 定为三级）

| 级别 | DSH 机制 | OML 的对应实现 | 状态 |
|---|---|---|---|
| L1 | 任务账本 | `TaskStore`（单一状态机 + 并发上限 + 深度限制） | 已实现 |
| L1 | TTL 监督（watchdog） | `expire()` 在每次工具调用与 `session.idle` 触发，超时任务标 `failed` 并留 `error` | 已实现（本轮） |
| L1 | 注意力经济 | `omo_admin stats/context/handoff`、`status` 折叠行、后台任务 | 已实现 |
| L1 | 经验沉淀 | `memory` + `dreams` + `omo share` 经验包 | 已实现 |
| L2 | router-worker（真实子会话路由） | `team` + `omo_task run` 已能派活；策略层需要宿主的子会话生命周期回调 | 待上游 |
| L2 | 跨模型评审 / judge | `team` 成员可各带 `model`；只在用户显式要求时用，不做默认 pipeline | 按需可组合 |
| L3 | 独立控制实体（自主编排器） | **不做**：本仓是插件层，不造第二运行时 | 见下节边界 |
| L3 | 13-agent review pipeline / inquirer 安装器 | 与 A8（精兵简政）冲突，重且不可解释 | 不做 |

## 上游边界：NekoAgent 控制实体不在本仓

判断（用户，2026-11-15）：真正的 NekoAgent 控制实体只会在上游出现，现在实现**过早**。

因此 OML 的定位是**无状态方法论层**：提示词 + 技能 + 账本 + 命令。
宿主换了就能搬，不持有会话生命周期。判据很硬：

> 如果一个能力必须持有会话生命周期才成立，它就不属于 OML。

当上游真的出现控制实体时，OML 交付的是它的世界观、纪律与经验包（`oml.json` + `skills/` +
`omo share`），而不是它的替代品。这也是为什么 `docs/design/oc2-status.md` 里的适配层
只有 33 行——协议翻译，不是第二个实现。
