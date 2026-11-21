# ACP/压缩路由（v1 硬带 opencode-acp，v2/dsh/未来走 billion-context）

## 路由表（`packages/core/src/acp.ts` 是唯一真相源，doctor/install 查表）

| 宿主 | 版本 | 挂什么 | 理由 |
|---|---|---|---|
| opencode | 1.x（含版本未知） | `opencode-acp` | **v1 硬带**（既定策略）；宿主原生 ACP 生态，v1 有 opencode-acp 插件 |
| opencode | ≥2.x | `billion-context` | v2 尚无原生 ACP 插件；billion-context 是多宿主引擎 |
| dsh / dsh-codex | 任意 | `billion-context` | 用户既定路由；billion-context 自声明支持 20+ 宿主（含 deepseek-harness） |
| 其他未知宿主 | — | `billion-context` | 保守默认：它是通用引擎，未来宿主大概率在其宿主名单里 |

纯函数 `pickAcp(host)` + `majorOf(version)` + `hasAcpPlugin(plugins, plugin)`，7 个单测
（`packages/core/src/acp.test.ts`）。策略变更只改这一处并写理由。

## 与 OML 自身 `compress/store.ts` 的分工（公理 A8：把矛盾消灭说清楚）

| | 宿主 ACP 插件 | OML compress |
|---|---|---|
| 是什么 | **流式引擎**：在 agent 与模型 API 之间改写流，做前缀缓存友好的增量分层压缩 | **账本**：已消费区间折成 bN 块（KEEP/REF），供 handoff/恢复 |
| 管什么 | 会话能活多久（billion-context 实测：204,800 token 模型零窗口违规、8,584–12,049 调用的马拉松会话） | 交给人/下一个会话时给什么 |
| 归属 | 可随宿主换（v1 换 ACP，v2 换 bili） | 跟 OML 走，宿主无关 |

不重复造：OML **不做**流式压缩。宿主引擎负责「不爆窗口」，OML 账本负责「可交接」。

**权威关系**：上游 provider/harness 也会注入 ACP 压缩提示（"Compression Philosophy"），它只负责省 token，**不替代 OML 自带检查点**。曾发生 Windows 线误判"上游在管上下文"而删掉 85% 主动检查点的违纪删除。三层 ACP 的权威划分、根因与三重防护见 `context-authority.md`。

## 接入点

- `omo doctor`：`detectOpenCodeVersion()`（`opencode --version`）→ `pickAcp` → 打印
  「宿主 1.19.3 → 应带 opencode-acp（已在插件列表）」，缺了就进建议列表。
- `omo install --apply`：写 opencode.json 时**确保选定 ACP 插件在 plugin 列表里**
  （缺则补，这就是「v1 硬带」的落点）；从不删用户其他插件。
- GUI/非 TUI 场景：visual-cache / subagent-magazine 两插件「主要应对于 TUI，GUI 可
  按需不启动」——OML 不替宿主做这个判断，`oml.json` 的 `disabled_*` 键留给用户裁。

## billion-context 的事实底（2026-11-15 查）

`ranxianglei/billion-context`，7.4K★，TypeScript，MIT；论文《Model-Driven Incremental
Hierarchical Compression: Training-Free Multi-Generational Context Management for
Long-Lived Coding Agents》随仓库开源（v0.2）；4.5 个月生产研究：174,327 次调用、
18.76B 累计输入 token、204,800 上下文模型零违规。第三方基准：ContextBench #1
（0.3097 F1，比 full 省 58.3% 成本）、LongMemEval-S 79.20%（比最佳 RAG +16.6%）、
MemoryAgentBench 1.48M token TTL 存活率 100%。缓存健康度指标：95–97% 前缀命中。
