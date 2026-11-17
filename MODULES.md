# MODULES — 每个模块必须回答「消灭了哪个矛盾」（公理 A5）

> 写不出「消灭的矛盾」的抽象，**禁止合入**。
> 每季度复审一次：无证据支撑的抽象删除。

| 模块 | 路径 | 消灭的具体矛盾 | 证据（bench / 测试） |
|---|---|---|---|
| contract | `packages/core/src/contract.ts` | 抽象绑定单一平台 → OC2 适配要重写全部逻辑 | 两前线导出面一致性测试 |
| budget/estimate | `packages/core/src/budget/estimate.ts` | 注入量不可度量 | 与真实 tokenizer 偏差 ≤15% |
| budget/assemble | `packages/core/src/budget/assemble.ts` | 拼装顺序不可解释 | 段优先级测试 |
| budget/gate | `packages/core/src/budget/gate.ts` | 超预算静默失败 | 截断 + 告警测试 |
| skills/scan | `packages/core/src/skills/scan.ts` | 技能发现依赖隐式目录约定 | 4 根扫描测试 |
| skills/index-gen | `packages/core/src/skills/index-gen.ts` | 319 全量描述注入 | 索引 ≤1600 tok |
| skills/usage | `packages/core/src/skills/usage.ts` | 冷技能永久占用上下文 | 连续 10 次零命中降级测试 |
| cli | `packages/cli/src/main.ts` | 无度量、无整风 → 无法阻止回涨 | `omo measure` 输出契约 |
| paths | `packages/core/src/paths.ts` | 状态散落在旧 OMO 目录，升级即丢 | 单点 `OML_STATE_DIR` + 旧目录只读回落 |
| config | `packages/core/src/config/index.ts` | 35 个 schema 文件各说各话 | 1 个 `oml.json`，未知键只告警 |
| agents/registry | `packages/core/src/agents/registry.ts` | 11 个 agent × 9 模型 prompt 矩阵 = 99 份提示 | 6 agent / 6 类别，模型零内置 |
| prompt/build | `packages/core/src/prompt/build.ts` | 4 个注入器各塞一段，总量无人知晓 | 单一拼装点 + 段级计数 |
| tasks/store | `packages/core/src/tasks/store.ts` | 后台任务黑箱、递归派发爆炸 | 状态机 + 深度/并发上限 + 原子落盘 |
| skills/select | `packages/core/src/skills/select.ts` | 全量目录与任务无关 | 按任务检索 top-N，无命中回退 |
| OC 前线 | `OC/omo/src/{host,tools,client}.ts` | 内核耦合平台 API；57 hook 分散注入 | 4 hook 位 / 6 工具 / 3 文件分责：`host`(接线) `tools`(能力) `client`(SDK 收敛) |
| OC2 前线 | `OC2/omo/src/` | 版本升级需重写内核 | 契约测试通过 |
| OC2 前线 | `OC2/omo/src/` | 版本升级需重写内核 | 契约测试通过 |

## packages/cli/src/commands/host.ts

- **职责**：`omo doctor`（宿主足迹诊断：OML 注入 / 技能数 / MCP / 插件 / 外部技能扫描 / 旧 OMO 残留）与 `omo install`（写插件入口、移除旧 OMO 条目、补 oml.json；默认 dry-run，`--apply` 才落盘）。
- **消灭的矛盾**：C1 的宿主侧延伸——只量 OML 自身注入，会把「大头在宿主」这个事实掩盖掉。
- **实测成本常数**（2026-11-13，opencode 1.19.3，单一变量开关法）：底噪 7,811 / 外部技能 20,329 / claude 技能 2,657 / 18 个插件 18,800 / MCP 估算 27,000 tok。换环境必须重测。

### packages/core/src/compat/omo.ts
| 项 | 说明 |
|---|---|
| 职责 | 读原版 OMO 配置（`~/.config/opencode/oh-my-openagent.json`，可能是符号链接），把 `agents.*.model/fallback_models/disabled` 与 `categories.*.model` 翻译成 OML 配置 |
| 消灭的矛盾 | 换插件就丢模型绑定；用户要在两份配置里各写一遍 |
| 关键接口 | `mapOmoConfig(raw)` / `loadOmoCompat(paths?)`；支持 jsonc（行注释、尾逗号）；未知顶层键进 `ignoredKeys` 而非报错 |
| 优先级 | `agents: {...omo, ...mine}` —— OML 显式配置覆盖 OMO |

### packages/core/src/agents/registry.ts（8 个身份）
| tier | id | 定位 |
|---|---|---|
| primary | `sisyphus` | Neko Ultraworker：编排，不实现 |
| primary | `prometheus` | Plan Builder：只读，只写计划 |
| primary | `atlas` | Plan Executor：按计划执行，失败即停 |
| subagent | `sisyphus-junior` / `oracle` / `librarian` / `explore` / `momus` | 执行 / 顾问 / 检索 / 仓库检索 / 评审 |
- `tier` 决定 `mode`：primary→`all`（前台可见），subagent→`subagent`。**旧实现只给 sisyphus 设 all，导致其余 agent 一律回退到 build。**
- `playbook` 指向插件内置技能（`neko-*`），实现渐进式披露：身份提示词只有几行，流程在技能里按需加载。

### packages/cli/src/commands/session.ts
| 命令 | 作用 |
|---|---|
| `omo stop` | 所有未终结任务 → cancelled（账本保留），再 prune 到 200 条 |
| `omo handoff [--print]` | 生成 ≤80 行交接文档（预算分段 / 未终结任务 / 末 8 条完成 / 恢复入口 / `[未验证]` 待补项） |

## `packages/core/src/acp.ts` + `docs/design/acp-routing.md`
- **消灭的矛盾**：宿主侧长会话压缩「该装哪个 ACP 插件」靠记忆、各宿主各维护一份。
- 路由表（纯函数，7 测试）：OpenCode v1 → `opencode-acp`（硬带）；v2 / dsh / dsh-codex / 未来宿主 →
  `ranxianglei/billion-context`（多宿主模型驱动分层压缩）。改策略只改这一处。
- 与 OML 自身 `compress/store.ts` 分工：宿主 ACP = 流式引擎（管会话活多久）；OML compress = 交接账本（管交给下一会话什么）。不重复造。
- 接入点：`omo doctor` 探测宿主版本查表并检查插件就位；`omo install --apply` 缺了就补进 opencode.json。

## `packages/core/src/tasks/status-line.ts` + `docs/design/tui-fold.md`
- **消灭的矛盾**：子代理状态「要么全展开报告，要么没有」——TUI 折叠行没有机器可读内容源。
- `formatStatusLine`：一行一子代理（任务名 / ↳ 最近工具+命令头 / ×N 工具次数 / ↓新增 K / ✏累计 K/M / 出错 ✗3 位失败码）。
- 接入：`omo_task` run/resume/team/status 四动作结果带折叠行；status 返回单一 JSON `{tasks, statusLines}`。
- 边界：折叠 UI 与重试倒计时属宿主 TUI（插件层拿不到宿主定时器）；宿主不透传 tokens 时显示 `—`，不造假。

## `packages/core/src/third.ts` + `packages/cli/src/commands/third.ts`（3rd systems）
- **消灭的矛盾**：三方组件（ACP 引擎 + TUI 件）该装哪些/什么版本/要不要升级，散落各宿主配置无单一事实源。
- 注册表 `THIRD_SYSTEMS`（opencode-visual-cache / opencode-subagent-magazine，用户决策内置）+ ACP 路由（acp.ts）；
  台账 `<stateDir>/third.json`；`planThirds` 纯函数算「该装什么、缺什么」。
- 自动升级**默认开**（oml.json 第 18 键 `third.autoUpgrade`）：host 在 session.start 24h 节流 fire-and-forget 检查
  （`opencode plugin <name>` 重装取最新）；失败只告警不伤会话。
- CLI：`omo settings`（OML settings 面板：18 键现值/来源/缺省）+ `omo upgrade [--dry-run]`。
- 已知保守处：宿主缓存的 `@latest` 目录版本判不出新旧 → 不触发升级（宁可漏报不误装）。

## `packages/cli/src/commands/third.ts` 之外的 omo_admin 变化
- goal 三动作合并为 `goal(op=set|show|clear)`（槽位净 0：-2+2）；新增 `settings`（读 oml.json 面板）与
  `upgrade`（3rd systems 检查/升级）。action 槽位仍 26/26。

## `packages/core/src/prompt/worldview.ts`（世界观层）
- **消灭的矛盾**：方法论只存在于聊天记录里，换个会话就丢；或者反过来，把口号当证据。
- `WORLDVIEW_LIGHT`（八条）/ `WORLDVIEW_FULL`（+阶段论/统一战线/不给的判断权）；`worldviewBlock(level)`。
- 默认注入 identity（`worldview: "light"`），可 `off`；计入 8192 预算。反修=防资本/防现代修正主义蛊惑/敢质疑，不写成「模块须写删除理由」（那条属工作纪律）。

## `packages/core/src/federation/bundle.ts` + `cli/commands/share.ts`（经验包）
- **消灭的矛盾**：经验锁在单机 memory/compress 里，换机重踩。
- `createBundle/parseBundle/mergeBundle/renderBundle`；本地优先合并（同 id 冲突不覆盖，记忆 jaccard 0.75 去重，导入条目 `X<n>` + hits 归零）。
- CLI `omo share export|import [--dry-run]`；**零网络**，传输由调用方决定。

## 分级结合 DSH 论文（`docs/design/deepseek-super-agent.md`）
- L1 已实现：账本、TTL watchdog（`expire` 挂到每次工具调用 + `session.idle`）、注意力经济、经验沉淀。
- L2 待上游：router-worker 策略、跨模型 judge（按需）。L3 不做：独立控制实体、13-agent pipeline。
- 硬边界：需要持有会话生命周期的能力不放进 OML（上游 NekoAgent 控制实体出现后再议）。

## packages/core/src/mcp/

- `catalog.ts` — MCP 目录：全量登记、默认禁用、指纹（type/command/url/env/headers，值转字符串）、
  自检（新增/变化→待复核，消失→missing）、`suggestMcp`、`applyMcpToHost` 回写。
  消灭的矛盾：宿主把每个 MCP 的工具 schema 无条件注入（4 个约 9.5K tok）。
- `client.ts` — 最小 MCP 客户端（stdio + streamable-HTTP），只实现
  initialize / notifications-initialized / tools/list / tools/call；握手失败立刻 close，不留孤儿进程。
  消灭的矛盾：「禁用 MCP 要重启宿主」——把服务器变成按需子进程。
- `packages/cli/src/commands/mcp.ts` — `omo mcp list|sync|enable|disable`，与
  `omo_admin action=mcp` 共用同一策略；回写宿主配置前备份 `.bak-mcp-<ts>`。

## `OC/omo/src/host.ts`（视觉路由）

- 会话 part 含 `image` 或 `file`（`image/*`、`application/pdf`）→ `sessionImages` 记会话；
  `experimental.chat.system.transform` 在现有块之后、救援行之前追加一行 `## 视觉`：
  当前模型 `capabilities.input.image/pdf` 为假、且不在 `VISION_MODEL_IDS` → 提示
  `omo_admin action=model op=set target=agent:<agent> model=<视觉模型>` 换模型，
  或 `omo_task` 派 multimodal-looker。无图/可视觉模型时 0 注入。
- `VISION_MODEL_IDS`（2026-11-17 纯色探针实测）：agnes-3.0-flash、sensenova-6.8-flash
  及其变体；kimi-k3 吞图、glm-5.3 超时、gemini-omni-* 上游 503，均不入表。
