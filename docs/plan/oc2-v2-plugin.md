# Plan: OC2 V2 理论兼容插件（按官方文档移植，进度对齐 OC1）

> Prometheus 格式。目标/证据/范围/步骤/回滚/风险/自检。
> 用户指令（m02145）：「oc1插件明显进度领先。依照开发者文档和官方文档制作oc2理论兼容插件（在实际投产并实机测试前一直为理论插件），先完成达到进度同步」。

## 目标
按官方 V1→V2 迁移文档，把 OC2 前线从「恒等映射的骨架」升级为**结构性完整的 V2 理论兼容插件**：覆盖 OC1 全部 7 hook + 6 tool，API 形状为 `Plugin.define({id, setup(ctx)})`。实机投产前一律标注「理论插件、未真机验证」。业务逻辑仍只在 OC1 `createHostCore`，OC2 只做 V1→V2 形状翻译（A4 单一写入者）。

## 现状证据（路径:行）
- `OC2/omo/src/index.ts:11` default 是 V1 函数导出 → 2.3.0 真机被拒（README/ dialect.ts DIFF-6）。
- `OC2/omo/src/host.ts:25-31` `createOc2Host` 把 unknown input 校验后委托 `createOmoHost`（返回 V1 `Hooks`）。
- `OC/omo/src/host.ts:203-205` `createOmoHost` → `createHostCore({directory, client})`，`:457-705` 返回 7 hook（`tool`/`config`/`chat.message`/`event`/`permission.ask`/`experimental.chat.system.transform`/`experimental.session.compacting`）+ 6 tool。
- `OC/omo/src/host.ts:120-124` `HostInput` 只要 `{directory, client:TaskClient}` → 可用 ctx-backed client 满足，业务逻辑零复制。
- 官方文档 opencode.ai/docs/build/plugins/migrate-v1（本次已抓取）：
  - 入口 `Plugin.define({id, setup(ctx)})`；可同时导出 `server()` 兼容 V1（1.18.29+）。
  - `chat.message`→`ctx.session.hook("prompt")`；`experimental.chat.system.transform`→`ctx.session.hook("context")` 改 `event.system`（V2 是 `{type:"text",text}[]`）；`experimental.session.compacting`→`ctx.session.hook("compaction")`；`permission.ask`→`ctx.permission.hook("evaluate")` 改 `event.status`；`event`→`ctx.event.subscribe()`；`tool` map→`ctx.tool.transform(editor=>editor.add(...))`（JSON Schema input + 返回 `{content}`）；`config`→各域 transform（V2 无全局 config）；`$`→自带进程 API。
  - `ctx.location.directory`/`ctx.options`/`ctx.storage`/cleanup 函数。
- `@opencode/plugin` 2.x 本机装不上（node 损坏 libada.so.3、npm 不可达）→ V2 类型用本地 structural types，不 import 该包。

## 范围
- 改 `OC2/omo/src/index.ts`：default 改 V2 定义对象（`Plugin.define({id:'oml.oc2', setup})` + `server()` V1 兼容）。
- 新增 `OC2/omo/src/v2-types.ts`：官方 V2 context/domain/event 的本地最小 structural types + `Plugin.define` 恒等助手（不依赖 @opencode/plugin）。
- 新增 `OC2/omo/src/client-v2.ts`：ctx-backed `TaskClient`，把 OML 工具需要的会话操作映射到 V2 domain 方法（理论映射，签名待真机确认处写 informative throw，不用空 catch / any）。
- 新增 `OC2/omo/src/bridge.ts`：`bridgeHooks(ctx, hooks)` 把 7 V1 hook + 6 tool 注册到 V2 ctx；含 V1↔V2 事件/system 形状适配。
- 更新 `OC2/omo/src/contract.test.ts`（OC2 default 现为 V2 对象 + server()；OC 仍 V1 函数，断言两前线能力等价而非导出同形）、`OC2/omo/src/host.test.ts`、`OC2/omo/README.md`（理论插件状态 + 完整映射表 + 未验证清单）。
- 新增 `OC2/omo/src/bridge.test.ts`：fake ctx recorder 断言 7 hook + 6 tool 全注册、事件/system 适配正确。
- 根 `BUDGET.md`/`manifest.json`/`check.ts` 由我（主代理）在子代理交付后统一记账，**子代理不许碰**。
- **不碰**：`OC/**`（OC1 生产路径）、`packages/**`、`tui.json(c)`、任何配置实际启用 OC2。

## 步骤
1. v2-types.ts + client-v2.ts → 验收：typecheck 干净。
2. bridge.ts（7 hook + 6 tool 注册 + 形状适配）→ 验收：bridge.test.ts 0 fail。
3. index.ts 改 V2 定义 + 更新 contract/host 测试 → 验收：OC2 测试 0 fail、全量 0 fail。
4. README 更新（理论状态 + 映射表 + 未验证清单）→ 验收：文档与代码一致。
5. 主代理统一记账 + 全量验收 + 提交 master。

## 依赖顺序
1→2→3→4→5 顺序（client 和 bridge 被 index 依赖；测试跟随实现）。

## 回滚
提交前：`git checkout -- OC2/omo/` + 删除新增文件；提交后：`git revert <sha>`。OC1 生产路径零改动，随时可独立回滚。

## 风险
- **V2 ctx 签名无法真机验证**：所有 domain 方法调用是理论映射 → 用 informative throw + 注释标注，README 明确「未真机验证」，绝不宣称可用。
- **V2 `event.system` 是对象数组 `{type,text}[]`**（非 V1 string[]）→ 适配需双向转换，bridge.test.ts 覆盖。
- **V2 无全局 config hook**：OC1 的 config 逻辑（agents/权限/default_agent）映射到 `ctx.agent.transform` + `ctx.permission.hook("evaluate")`；这是「迁移目的地非精确重命名」，标为理论。
- **tool args schema**：V1 用 tool.schema（zod-like），V2 用 JSON Schema → 理论插件用显式 JSON Schema 描述 6 工具输入（基于 V1 args），execute 包装返回 `{content}`。
- **契约测试 bases on V1 形状**：OC2 default 从函数变对象后必须同步改断言，否则 fail。

## 自检清单
- [x] 每条结论指到证据（路径:行 / 官方文档）
- [x] 每步有验收命令
- [x] 边界写明不碰什么（OC/**、packages/**、配置启用）
- [x] 回滚可执行
- [x] 无「研究」伪装成实现
- [x] 规模匹配（5 步 + 主代理记账）
