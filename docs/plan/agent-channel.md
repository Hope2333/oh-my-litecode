# Plan: 代理间通信通道（选项2 / Unit4-6）

> Prometheus 格式。目标/证据/范围/步骤/回滚/风险/自检。

## 目标
让团队/多层子代理之间能横向通信、自推进，而不事事由主代理驱动；主代理只检查指导。交付：一个纯消息板内核 + 一个 `omo_channel` 工具 + team 子会话 prompt 注入通信指令，真机 PTY 可见、测试通过、预算诚实记账。

## 现状证据
- `OC/omo/src/tools.ts:657-766` team 分支：成员各自 `runChild`，结果汇总给主代理；成员之间零通信，全部由主代理汇总驱动。
- `OC/omo/src/tools.ts:272-275` `promptWithTaskContext` 只注入任务 id/隶属链/标题，无通信指令。
- 工具预算 `scripts/check.ts:138` `tools:14`，当前 6（tools.ts:557 `buildTools` 注册 omo_task/knowledge/admin/mcp + host.ts:435 skill）；action 26/26 已满 → 新能力不能塞进现有工具。
- `packages/core/src/skills/usage.ts:80` 原子写范式（tmp→rename + ENOENT 重建）；`paths.ts:17` `statePath()` 统一状态目录。
- 用户定性（m01933/49/52）：团队要成员间横向协作、自推进；原生子代理「能同时跑但不互通」。

## 范围
- 新增 `packages/core/src/channel/board.ts` + `board.test.ts`（纯逻辑/原子持久化）。
- 新增 `OC/omo/src/tools.ts` 中 `omo_channel` 工具（3 action：post/read/list）。
- 修改 `OC/omo/src/tools.ts` `promptWithTaskContext` + team 分支注入频道指令。
- 修改 `OC/omo/src/host.ts` hooks.tool 自动纳入（buildTools 返回对象即自动注册，无需手改 host）。
- 修改 `scripts/check.ts` action 上限 26→29（含新工具 3 action，诚实记账）+ `BUDGET.md` 记账 + `manifest.json` 刷新。
- **不碰**：`packages/tui-shell/**`（experiment 分支）、`packages/tui-plugins/**`、`OC/omo/src/host.ts` 的 hook 逻辑、任何 tui.json(c)、winston 外部依赖。

## 步骤
1. 纯内核 `channel/board.ts`：频道 = teamId；消息 `{id, channel, from(role), to(role|"*"), body, ts, kind:"msg"|"claim"|"result"}`；函数 `createBoard/post/read/list/prune`，原子写 `statePath("channels.json")` → 验收：`bun test packages/core/src/channel/` 0 fail。
2. `omo_channel` 工具：action enum `["post","read","list"]`；post 写消息；read 按 channel + since 游标读；list 列频道 → 验收：tools.test.ts 增用例；typecheck 干净。
3. prompt 注入：team 成员的 briefWithPolicy 追加「你在团队频道 <teamId>，先 omo_channel read 看队友进度，用 post 广播你的发现/认领，主动推进，不事事等主代理」；nested 子代理继承父频道 → 验收：promptWithTaskContext/team 测试断言注入文本存在。
4. 记账：check.ts action 上限 26→29（附理由），BUDGET.md 加行，manifest 刷新 → 验收：`bun run check` 7/7，zero-growth 变更 0。
5. 验收提交：`bun test` 全量 0 fail；typecheck 干净；check 7/7 → 提交 master。

## 依赖顺序
步骤1（纯内核）先于步骤2（工具调用内核）；步骤2/3 可并行但共用 tools.ts → 顺序执行；步骤4 依赖前面文件内容确定；步骤5 最后。

## 回滚
`git checkout master`（当前 543f6a0）；本计划所有改动在单个 commit，回滚 = `git reset --hard 543f6a0`（提交前）；提交后回滚 = `git revert <sha>`。B 实验分支 a3d5557 不受影响。

## 风险
- **预算门**：action 26→29 会让 `structure` 门失败，必须同步改 check.ts 上限并在 BUDGET.md 写明「新工具独立 3 action，非能力走私」——失败信号：`structure action 29/26`。
- **并发写**：多个 team 成员同时 post 到同一 channels.json → 用 usage.ts 同款 seq 临时名 + rename，仍可能丢写（最后写入覆盖）；缓解：post 为读改写，测试覆盖两次顺序 post 不丢；真并发窗口记为已知边界。
- **prompt 膨胀**：通信指令每轮注入占 token；控制为 1-2 行，预算门实测 <8192。

## 自检清单
- [x] 每条结论指到证据（路径:行号）
- [x] 每步有验收命令
- [x] 边界写明不碰什么
- [x] 回滚可执行（具体 sha）
- [x] 无「研究」伪装成实现
- [x] 规模与任务匹配（5 步）
