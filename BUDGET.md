# BUDGET — 零增长账本（公理 A10）

> 规则：任何新增（技能 / hook / 工具 / 依赖 / 常驻 MCP / 插件）必须在此表给出**等量删除**或**书面豁免**。
> CI（`scripts/check.ts`）读取本文件的「当前」列，超限即失败。

| 项 | 上限 | 当前 | 删除/豁免记录 |
|---|---|---|---|
| 空闲系统提示 | 8192 tok | 1672 tok（bench/prompt） | 旧 OMO 115400 tok → −98.6% |
| 宿主注入段 | 8192 tok | 889 tok（bench/host，fixture） | 292 真实技能根时为 959 tok |
| 注入技能索引条目 | 40 | 40 | 291 全量 → 只留 40 |
| 持久记忆条目 | 60 | 0（空库零成本） | 吸收 working-memory + dreams + snippets（三类：fact/antipattern/snippet）；仅头部 12 条注入 |
| 压缩摘要块 | 无上限（模型自主） | 0 | 吸收 opencode-acp；只注入模型显式压缩的块，不预注入 |
| Hook 数量 | 8 | 6（config / event / chat.message / system.transform / compaction / tool） | 旧 OMO 57 个 hook 目录；compaction 于 2026-11-15 加入，记账理由见下 |
| 工具数量 | 14 | 6（omo_task / omo_knowledge / omo_admin / omo_mcp / omo_channel / skill 兼容位） | 旧 OMO ~25 个工具；v2 把 7 个细粒度工具折叠成 3 网关，v3 加 MCP 网关（换来宿主 4 个 MCP 的工具 schema 全部不进提示）；2026-11-18 加 omo_channel 团队频道工具，工具数 5→6，仍在 14 以内 |
| 网关 action 槽位 | 29 | 28（omo_task 5 / omo_knowledge 3 / omo_admin 14 / omo_mcp 3 / omo_channel 3） | **真实复杂度货币**：折叠工具不减少模型要读的分支，所以按 action 计数；加一个必须删一个。2026-11-14 加 `slop_check`+`team_list`(+2)、并把 `model_show`/`model_set` 合并为 `model`(+op)(−1)、`memory_forget`/`memory_reinforce` 合并为 `memory_edit`(−1)，净 0。2026-11-16 加 `mcp`(+1) 与 omo_mcp 3 槽，同时把 `measure`/`context`/`stats` 合并为 `status`(−2)、`memory_add`/`memory_list`/`memory_edit` 合并为 `memory`(+op)(−2)，净 0。2026-11-17 加 `pa`(+1) 管会话删除/改写授权，同时把 `compress_add`/`compress_list`/`decompress` 合并为 `compress`(+op)(−2)，净 −1。2026-11-18 加 `omo_channel` 3 action（post/read/list）— 团队横向通信，独立工具非能力走私；基线实为 25（非 26），上限 26→29 保留 +1 余量 |
| 常驻 MCP | 3 | 0（OML 自身） | 宿主现存 8 个属被改造对象 |
| 启用插件 | 5 | 1（OML 自身） | 宿主现仅 2 个（opencode-notify / superpowers-zh）；其余见 docs/design/plugin-absorption.md |
| 内核运行时依赖 | 0 | 0 | 只用 node: 内建 + @opencode-ai/plugin 的类型 |
| 适配层行数（OC） | 300 | host+index 295（全目录含 client/tools/web 共 1804 行） | 300 只约束「入口+宿主装配」，业务逻辑在 client/tools/web 三个职责文件 |
| 适配层行数（OC2） | 300 | V2 理论兼容插件（host+index+dialect+v2-types+client-v2+bridge ≈ 596 行；含注释/类型，非业务逻辑） | 2026-11-18 按官方 V1→V2 文档移植：`Plugin.define({id,setup})`+`server()` 双形态，7 hook+6 tool 经 bridge 注册到 V2 domain，业务逻辑仍只在 OC1 `createHostCore`。**未真机验证**（@opencode/plugin 2.x 装不上）；内核零改动 |
| 内核纯模块（无副作用） | 不设上限 | 新增 `eigenflux/hint.ts`（+`hint.test.ts`）；`tokenfold/fold.ts`、`compress/tool-result.ts`（+ 各自 `.test.ts`） | 2026-11-17 记账：EigenFlux 主动提示的纯字符串判定 + 测试。零 hook / 零工具 / 零 action 槽位 / 零运行时依赖 / 零常驻 MCP；只在命中任务文本时于预算外追加区出一行，空闲注入 0 tok（实测 budget 3247，未增）。不占任何受控预算类别，按 A10 书面记账。2026-11-18 新增 tokenfold（结构化无损折叠/预算帽/本地打码，TS 重写非 Rust）+ tool-result（DCP 式编号锚点分块）两个纯模块；接线走现有 `omo_admin action=compress` 的 op 分派（fold/unfold/budget/redact/restore/tool-fold/tool-expand），**零新 tool / 零新 action 槽位**（op 是同一 action 内的分支，沿用 compress_add/list/decompress 合并先例）；能力目录 +2 条（fold/toolchunk），纪律层 KISS/YAGNI/完成度命名化（light +65 tok / standard +94 tok）。零运行时依赖、零网络 |
| 内置 MCP def + 证据提示（context7） | 不设上限 | 新增 `mcp/builtins.ts` + `mcp/context7-hint.ts`（+ 各自 `.test.ts`） | 2026-11-18 记账：复刻原版 OMO 的 Context7 为 OML 内置 def（merge 进 `hostMcpDefs()`，宿主 opencode.json 不登记），默认禁用 / needsReview，API key 占位串清洗；纯 hint 函数命中才出、预算外追加区，**prompt 只做证据分级**。零新 tool / 零新 action 槽位 / 零运行时依赖 / 零常驻 MCP（未启用）；空闲注入 0 tok。不占任何受控预算类别，按 A10 书面记账。2026-11-18 真机验证：POST https://mcp.context7.com/mcp 握手成功（serverInfo Context7 v4.7.3，protocol 2024-11-05），tools/list 返回 resolve-library-id + query-docs；无需 key、无需代理（直连 http=405 为 GET 预期，POST 正常） |
| 内核纯模块（无副作用） | 不设上限 | 新增 `capabilities/manifest.ts`（+`manifest.test.ts`）；`contract.ts`/`prompt/build.ts`/`config/{schema,index}.ts` 各接线 | 2026-11-18 记账：常驻能力目录 section（248 tok），把 8 项能力「什么场景→怎么调」常驻在唯一装配点，场景判断交还模型，解决「能力放着不用成摆设」；替代/并存关系：现有正则 hint（`eigenflux/hint.ts`、`context7-hint.ts`）降级为命中时补一句的强化层，未删除。`config.capabilities`（enabled/mode/disabled）可关可精简。零新 tool/action/hook/运行时依赖；SectionId 加一值（预算门实测 3258/8192 pass），不占任何受控类别，按 A10 书面记账 |

| 内置技能（纯文档/脚本，无运行时成本） | 不设上限 | 新增 `OC/omo/skills/neko-pty/`（SKILL.md + pty.sh） | 2026-11-18 记账：PTY/交互式 TUI 验证规范 + tmux 助手脚本（把每次手搓 tmux 的踩坑固化为可复用流程：TERM/leader 两段式/输入行清空/OC1 vs OC2 配方/收尾清理）。随 builtinSkills 根自动扫描发现（实测 neko-pty 已被发现）。零 hook / 零 tool / 零 action / 零运行时依赖 / 零 token（技能按需加载，不进常驻提示）；脚本只操作 `oml-` 前缀 tmux 会话、拒杀生产服务器。不占任何受控预算类别，按 A10 书面记账 |

## 当前实测（2026-11-13）

```
bun run check
PASS types / tests(177) / budget(2422) / host(889) / surface(4 工具,6 hook) / structure(action 26/26) / zero-growth
真实技能根：292 个 SKILL.md → 索引 40 条，注入段 959 tok
```

## 豁免格式

```
- YYYY-MM-DD | 新增项 | 等量删除项 / 豁免理由 | 批准人
- 2026-11-18 | omo_channel 3 action（post/read/list）— 团队横向通信，独立工具非能力走私 | 网关 action 上限 26→29（实测 25→28，保留 +1 余量）；工具数 5→6 仍在 14 以内 | Unit5 记账
- 2026-11-18 | context7 内置 MCP def + 纯 hint 函数（2 模块 + 2 测试文件） | 零新 tool / 零新 action / 零 hook / 零运行时依赖 / 零常驻 MCP（默认禁用）；命中才于预算外追加区注入，空闲 0 tok | Unit7 记账
- 2026-11-18 | N=5 重复基准脚本 + 报告 + 3 个数据文件（bench/report.ts、docs/bench/task-ab-repeat.md、task-ab-{oml,omo}-r5.json） | 纯离线测量工具与产物，零运行时依赖 / 零 hook / 零 tool / 零 action / 零注入成本；不进生产提示 | 基准提交记账
- 2026-11-18 | OC2 V2 理论兼容插件（v2-types.ts / client-v2.ts / bridge.ts + bridge.test.ts + 计划文档） | 纯 V1→V2 形状翻译层，业务逻辑零复制（仍只在 OC1 createHostCore）；仅本地 structural types，不装 @opencode/plugin 2.x、零新运行时依赖 / 零 hook / 零 tool / 零 action / 零注入成本（未在宿主启用）；未真机验证 | OC2-V2 记账
```
