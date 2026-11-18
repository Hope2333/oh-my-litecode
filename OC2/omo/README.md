# OC2/omo —— OpenCode 2.x 前线（V2 兼容插件，真机加载已验证）

## 现状（2026-11-18）

**已按官方 V1→V2 迁移文档把 OC2 前线升级为结构性完整的 V2 插件，覆盖 OC1 全部能力（7 hook + 6 tool）。已在隔离的真实 `@opencode/cli` 2.3.0 上验证：插件加载成功、setup 走完、5 个 hook 注册调用全部执行（见 `docs/bench/oc2-realmachine-2026-11-18.md`）。但 TaskClient 的 7 个 session RPC 方法尚未在真实会话中触发（本机模型不可用），仍是按真机 ctx 形状写的映射。**

真机证据（隔离的 `@opencode/cli` 2.3.0 ELF，生产 1.19.3 未动）：

- 旧的函数导出在 2.3.0 被拒：`Plugin must export a default definition with an id and an effect or setup function`。
- 最小对象导出 `{id, effect}` 在同版加载成功 → **默认导出必须是对象**（现已采用 `{id, setup, server}`）。
- V2 配置键 `plugin`→`plugins`、**本地插件路径必须是目录**（指向 `.ts` 文件会得到 `configured plugin path must be a directory` 而静默不加载）。
- hook 改为 `ctx.*.hook/transform` 领域方法。这是整套插件 API 更换，不是改 hook 键能修的方言差异。
- **真实 setup ctx 没有 `ctx.client`**：原 `clientFromContext` 依赖它导致 setup 抛错、插件加载失败。已改为从 `ctx.session.*`（1 参 RPC 包装：`create/update/prompt/get/list/remove/interrupt`）构建 TaskClient；修复后真机 setup 走完，`tool.transform` + `session.prompt/context/compaction` + `permission.evaluate` 五个注册调用全部执行，返回 cleanup 函数。

本机 node 损坏（`/usr/bin/node` 缺 `libada.so.3`）、npm 不可达，`@opencode/plugin` 2.x 装不上，故新代码**不 import 真实 2.x 类型**，改用 `src/v2-types.ts` 里的本地 structural interface。方法缺失或返回形状无法归一时 informative throw，**禁止空 catch / any / ts-ignore**，不伪装成功。

## 架构（A4 单一写入者 / 纯翻译层）

业务逻辑只在 OC1 的 `createHostCore`（`/OC/omo/src/host.ts`），OC2 不含任何 OML 业务逻辑：

```
V2 setup(ctx)
  └─ clientFromContext(ctx)       // ctx.client.session.* → OC1 的 TaskClient（理论映射）
  └─ createOc2Host({directory, client})
       └─ client 已是 TaskClient → createHostCore(...)（避免 sdkTaskClient 二次包装）
       └─ V1 server() 路径        → createOmoHost(...)（SDK client 正常包装）
  └─ bridgeHooks(ctx, hooks)      // 7 hook + 6 tool 注册到 V2 domain + 形状双向适配
V1 server(input)                  // 1.18.29+ 双形态兼容，仍返回 V1 Hooks
```

## 官方 V1→V2 映射表（已实现，均为理论映射）

| V1（OC1 Hooks） | V2 注册位（bridge.ts） | 形状适配 / 备注 |
|---|---|---|
| `default` 导出函数 | `Plugin.define({id:'oml.oc2', setup(ctx)})` 对象 + `server()` | 对象形态真机 2.3.0 已确认；`server()` 为 V1 兼容 |
| `tool`（6 个 OML 工具） | `ctx.tool.transform(editor => editor.add({name, description, input, execute}))` | V1 zod args → JSON Schema（仅字段名，类型待确认）；execute 返回 `string`/`{output}` → `{content:string}` |
| `chat.message` | `ctx.session.hook("prompt", …)` | V2 event 的 sessionID/messageID/agent/model/variant/parts → V1 `(input, output)` |
| `experimental.chat.system.transform` | `ctx.session.hook("context", …)` | **双向适配**：V2 `event.system` = `{type:"text",text}[]` → V1 `string[]` → 调 V1 hook（注入 OMO_MARKER、剥离宿主技能目录）→ 结果写回对象数组 |
| `experimental.session.compacting` | `ctx.session.hook("compaction", …)` | `event.context` 对象数组 ↔ `string[]`，写回保持输入形状 |
| `permission.ask` | `ctx.permission.hook("evaluate", …)` | V1 改 `output.status` → V2 改 `event.status` |
| `event` | `ctx.event.subscribe({signal})` 异步迭代 | V2 event → V1 `{event}`；cleanup = `AbortController.abort()` |
| `config` | `ctx.agent.transform(…)`（尽力） | **config 的 `permission` / `default_agent` 部分 V2 无对应全局对象，理论映射**：仅消费 agent 部分，其余只记 `console.debug`，不抛不伪装 |
| `dispose` | `setup` 返回的合并 cleanup 函数 | 各 domain 注册返回的 cleanup + event abort 合并 |

6 个工具名（权威集合见 `ALL_V2_TOOL_NAMES`）：`omo_task`、`omo_knowledge`、`omo_admin`、`omo_mcp`、`omo_channel`、`skill`。

## 文件

| 文件 | 职责 |
|---|---|
| `src/v2-types.ts` | V2 domain/session/tool/permission/event/storage 的最小 structural interface；`Plugin.define` 恒等助手；`Oc2Context` |
| `src/client-v2.ts` | `clientFromContext(ctx): TaskClient`，7 方法映射到真机确认的 `ctx.session.*`（create/update/prompt/get/list/remove/interrupt）；方法缺失或形状无法归一才 informative throw |
| `src/bridge.ts` | `bridgeHooks(ctx, hooks, options?)`：7 hook + 6 tool 注册、形状双向适配、cleanup；导出 `BRIDGE_HOOK_MAP` / `ALL_V2_TOOL_NAMES` |
| `src/host.ts` | `createOc2Host(raw, options?)`：V1 SDK client → `createOmoHost`；V2 TaskClient → `createHostCore` 直通 |
| `src/index.ts` | default = `{id:'oml.oc2', setup, server}`；保留具名导出 `createOmoHost` / `createOc2Host` |
| `src/dialect.ts` | `toV1Input(raw)` 校验 directory/client（OC2-DIFF 探测数据保留） |
| `src/contract.test.ts` | OC2 default 对象形状（只导出 default）+ 两前线工具能力等价 |
| `src/client-v2.test.ts` | 假 ctx.session 覆盖 7 方法映射、两种返回外壳、构造不抛、缺失方法调用才抛 |
| `src/bridge.test.ts` | fake ctx recorder：6 tool 注册与 `{content}` 归一、system 双向适配、prompt/compaction/evaluate/config 注册、event 订阅与 cleanup |
| `src/host.test.ts` | 沿用 OC1 的 7 hook + 6 tool + OMO_MARKER 注入 / 技能剥离断言 |

## 验证状态

### 真机 2.3.0 已确认（加载探针，见 docs/bench/oc2-realmachine-2026-11-18.md）
- default 对象导出 `{id,setup,server}` 被正确加载（marker 读到 `id:'oml.oc2'`）。
- 本地插件路径须为目录（含 package.json + index.ts），指向 .ts 文件静默不加载。
- setup 走完、返回 cleanup 函数；5 个注册调用真实执行：`tool.transform`、`session.prompt`、`session.context`、`session.compaction`、`permission.evaluate`。
- 真实 ctx 无 `ctx.client`；`ctx.session.*` 是 1 参 RPC 包装（create/update/prompt/get/list/remove/interrupt，无 messages/abort/delete）。已据此修 clientFromContext。

### 仍未验证（不可宣称可用）
| 项 | 为什么未验证 / 验证所需 |
|---|---|
| 7 个 session RPC 的请求/返回形状 | 真机模型不可用（openai/gpt-6.2-sol region error），子会话 create/prompt 未在真实会话中触发；写法兼容 `{data:X}` 与直接 body 两种外壳，须在可用模型上跑一遍 |
| `event.system` 形状 | 计划按 `{type:"text",text}[]` 适配；bridge 同时兼容字符串元素，待真实会话触发 context hook 确认 |
| `config` 的 `permission` / `default_agent` | V2 无全局 config 对象，这部分**不映射**，只记 debug；需确认是否有替代 domain |
| tool schema | V1 zod → V2 JSON Schema 仅还原字段名，字段类型未转换 |
| cleanup 语义 | 真机确认返回 cleanup 函数，但 domain 注册 unregister / subscribe signal 是否真正停止流未触发验证 |
| `Plugin.define` 运行时身份 | 本地恒等助手；真机应替换为官方实现，调用方零改动 |

## 验证方式

```bash
cd /home/miao/Projects/OML
bun ./node_modules/typescript/lib/tsc.js -p tsconfig.json --noEmit   # 必须零报错（/usr/bin/node 损坏，用 bun 跑 tsc）
bun test OC2/omo/                                                   # 19 pass / 0 fail
bun test                                                            # 全量 0 fail
git status --short                                                  # 确认只碰 OC2/omo/** 与 docs/plan
```

契约测试：OC 前线未实现时相关断言 skip 并打印原因，不 fail。真机可用后按「未验证清单」逐条收紧 `v2-types.ts`、把 informative throw 替换为真实映射，内核 `@oml/core` 与 OC1 生产路径零改动。
