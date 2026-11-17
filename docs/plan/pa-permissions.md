# PA 权限与会话所有权 — 实现计划（Prometheus 格式）

## 目标
补上 OML 相对原版 OMO 的权限短板：修 /dev 类访问被 PA 拦截；建立会话所有权账本；分级会话操作（读放行、删/改写走 PA）；PA 携带工作说明；对高价值未明归属会话（Read 100M tok+ / Turn 16+）删除前强制说明。

## 现状证据
- 权限钩子 `OC/omo/src/host.ts:538-542` 只 `permission.ask → allow`，不覆盖配置层 `external_directory`（/dev 被拦的根因）。
- 原版 OMO 在 config 钩子注入 `params.config.permission = { webfetch:"allow", external_directory:"allow", ... }`（`oh-my-opencode@4.19.4 dist/index.js:163166`），插件内即可绕过 → 学它。
- SDK `Session`（live 4096 实测）有 `tokens.cache.read`（100M+）、`time`、`directory`、`parentID`，无 owner/turn 字段。
- action 预算 26/26 满（`tools.ts ACTION_SLOTS` + BUDGET.md 读值）。
- 会话 token 数据来自 `session.list` 的 `tokens` 字段，无需额外 API。

## 范围
新：packages/core/src/permission/{ownership.ts,pa.ts}；配套测试。
改：host.ts（config 注入 + 工具接线 + 待批提示）、client.ts（session.list/delete 窄接口）、tools.ts（omo_admin 加 pa action op）、contract/config/schema（配置键）、BUDGET/MODULES/manifest。
不碰：原版 OMO 插件、宿主 opencode.json（用 config 钩子注入，不改文件）、fork 的 TUI 插件、A/B 分支。

## 步骤
1. **配置层权限注入**：host.ts 的 config 钩子里注入 `permission.external_directory="allow"`、`webfetch="allow"`（学 OMO），带开关 `config.permissions.allowExternal !== false`。验收：host.test 断言注入值。
2. **所有权账本** `permission/ownership.ts`：`SessionOwner{id,owner:"oml"|"human"|"unknown",parentID,directory,createdAt,detail}`；`load/save`（原子写，复用 usage 模式）；`classify(session, ownIds)`：本 OML 建=oml，root 且非本 OML=human/unknown，子会话继承父。验收：归属判定测试。
3. **PA 队列** `permission/pa.ts`：`PaRequest{id,sessionId,op:"delete"|"write"|...,reason,resources,status:"pending"|"approved"|"denied",createdAt}`；`add/list/approve/deny/expire`；高价值检测 `isHighValue(session)` = cache.read≥100M 或 turn≥16；`needsJustification(req,session)`。验收：队列状态机 + 高价值判定测试。
4. **工具接线**：client.ts 加 `listSessions`/`deleteSession`；tools.ts `omo_admin` 加 `pa` action（op=request/list/approve/deny）——为守 action 预算，把 compress 三 action 合并成 `compress(op=add/list/decompress)` 净 −2，加 pa +1，总 25/26。验收：ACTION_TOTAL≤26、check structure 通过。
5. **待批提示**：host.ts system.transform 尾部，若有 pending PA 注入 `## 待批权限` 段（含 sessionId + reason + 高价值警告）。验收：host.test 命中注入。
6. **删除硬边界**：PA approve 后可删；high-value 未明归属会话的 request 必须带非空 reason（否则拒绝）；human/unknown 会话删除前必须 PA。
7. 全量验收 typecheck/test/check/manifest + 提交。

## 依赖顺序
1(config) 独立；2(账本)→3(PA 用账本)→4(工具)→5(提示)；6 依赖 3+4。
## 回滚
`git reset --hard <基线commit>`（提交后即有一个干净 commit 可回退）。
## 风险
- action 预算：compress 合并需同步改 docs + 任何引用（已 grep，仅 docs，无 agent 提示词硬引用）。
- 高价值 turn≥16 需要 messages 计数（list 无 turn 字段）→ 用 cache.read≥100M 为主判据，turn 作为可选增强（避免额外 N 次 API）。
- config 钩子注入是否被 1.19.5 接受需实测（原版同法已验证可行）。
