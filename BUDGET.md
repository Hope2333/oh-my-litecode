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
| 工具数量 | 14 | 5（omo_task / omo_knowledge / omo_admin / omo_mcp / skill 兼容位） | 旧 OMO ~25 个工具；v2 把 7 个细粒度工具折叠成 3 网关，v3 加 MCP 网关（换来宿主 4 个 MCP 的工具 schema 全部不进提示） |
| 网关 action 槽位 | 26 | 26（omo_task 5 / omo_knowledge 3 / omo_admin 15 / omo_mcp 3） | **真实复杂度货币**：折叠工具不减少模型要读的分支，所以按 action 计数；加一个必须删一个。2026-11-14 加 `slop_check`+`team_list`(+2)、并把 `model_show`/`model_set` 合并为 `model`(+op)(−1)、`memory_forget`/`memory_reinforce` 合并为 `memory_edit`(−1)，净 0。2026-11-16 加 `mcp`(+1) 与 omo_mcp 3 槽，同时把 `measure`/`context`/`stats` 合并为 `status`(−2)、`memory_add`/`memory_list`/`memory_edit` 合并为 `memory`(+op)(−2)，净 0 |
| 常驻 MCP | 3 | 0（OML 自身） | 宿主现存 8 个属被改造对象 |
| 启用插件 | 5 | 1（OML 自身） | 宿主现仅 2 个（opencode-notify / superpowers-zh）；其余见 docs/design/plugin-absorption.md |
| 内核运行时依赖 | 0 | 0 | 只用 node: 内建 + @opencode-ai/plugin 的类型 |
| 适配层行数（OC） | 300 | host+index 295（全目录含 client/tools/web 共 1804 行） | 300 只约束「入口+宿主装配」，业务逻辑在 client/tools/web 三个职责文件 |
| 适配层行数（OC2） | 300 | 骨架 | — |
| TUI 外壳（B 实验分支） | — | 6 新增文件（packages/tui-shell/ 下 panel.tsx/deploy.ts/*.test.ts/*.d.ts） | 实验分支 experiment/oml-tui-shell，非默认导出、不进宿主提示/工具面/预算；纯可视化与测试代码，零注入成本，故书面豁免 A10 |

## 当前实测（2026-11-13）

```
bun run check
PASS types / tests(177) / budget(2422) / host(889) / surface(4 工具,6 hook) / structure(action 26/26) / zero-growth
真实技能根：292 个 SKILL.md → 索引 40 条，注入段 959 tok
```

## 豁免格式

```
- YYYY-MM-DD | 新增项 | 等量删除项 / 豁免理由 | 批准人
- 2026-11-18 | B 路线 TUI 外壳 6 文件（packages/tui-shell/） | 实验分支，非默认导出；纯可视化/测试代码，零 token/hook/tool/action 注入成本，不影响任何受约束货币 | 用户（B 路线授权）
```
