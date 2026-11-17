# OML v2 — 从「替换 OMO」到「接管宿主」

> v1 的目标是把提示预算砍下来（达成：116,302 → 31,258 tok，−73.1%）。v2 的目标是把 OMO 的**功能面**装进来，同时不把砍掉的东西加回去。
> 每项新增都在 `BUDGET.md` 的「删除/豁免记录」列给出了等量删除项。

## 1. 三网关：把 7 个细粒度工具折叠成 3 个

v1 的 7 个工具（`omo_task / omo_task_status / omo_task_cancel / omo_skill_search / omo_skill_read / omo_measure / omo_goal / omo_web_search`）各有独立的参数 schema。每个 schema 的字段说明都会进系统提示，是隐藏的固定成本。

v2 把它们按「谁在什么时候调用」收成三个动作网关：

| 网关 | 动作 | 取代的 v1 工具 |
|---|---|---|
| `omo_task` | `run / team / status / cancel / resume` | task*3 + todo/后台机制 |
| `omo_knowledge` | `skill / skill_read / web` | skill_search + skill_read + web_search |
| `omo_admin` | `model(op=show\|set) / goal(op=set\|show\|clear，缺省 show) / settings / upgrade / measure / context / checkpoint / stats / handoff / slop_check / team_list / memory_* / dreams_distill / compress_* / decompress` | 模型热分配 + goal + 上下文 + 记忆 + 诊断 |

`skill` 兼容位仍然存在（`config.compat.skillTool !== false` 时），包装 `omo_knowledge action=skill_read`，命中即记 usage。

判定：一个 schema 的字段说明进系统提示的成本是**每个工具一份**，动作网关把成本压到 3 份；功能没有丢，只是入口变了。

## 2. 模型热分配（`packages/core/src/models/overrides.ts`）

用户指出：OMO 的 `resolveModel` 硬编码了 deprecated 模型 id。v2 去掉全部硬编码，改为三层可热改的优先级：

```
explicit（本次调用的 model 参数）
  > overrides.agents["agent:<id>"]
  > overrides.categories["category:<id>"]
  > config.agents / config.categories（含 fallback 链）
  > overrides.default
  > config.models
  > none（返回 model: null，交给宿主默认）
```

`omo_admin action=model op=set target="agent:sisyphus" model="provider/model"` 立即写 `<stateDir>/model-overrides.json`，下一次派发生效，不需要重启。`model op=set model=""` 删掉该层。模型 id 校验为 `/^[\w.-]+\/[\w.:@-]+$/`，格式不对直接拒绝。

## 3. 团队（`omo_task action=team`）

- `mode=parallel`：`Math.min(并发上限, 队列长度)` 个 worker 拉同一个成员队列。
- `mode=pipeline`：串行。
- 成员 1–6，每个成员可独立指定 `agent / category / model`。
- 先查 `concurrencyReason`，拒绝时直接返回原因，不排队。
- 父任务 `kind=team`，成员记录在 `TaskRecord.members`，汇总格式 `### role ✓/✗`。

## 4. 上下文模块（`packages/core/src/context/module.ts`）

`CONTEXT_RULES` 是一段约 150 tok 的散文，默认展开注入 identity：什么时候收（写 checkpoint）、压缩时保留什么（路径/命令/错误原文/已否证的假设）、丢什么（重复日志、已落盘的产物）、什么时候换会话（handoff）。这是把「渐进式披露」写进提示词本身，而不是靠一个长技能文档。

## 5. Neko 三身份 + 五子代理

前台（`mode: all`，真机已验证 banner `> sisyphus · …` / `> prometheus · …` / `> atlas · …`）：

| 身份 | tier | tools | 职责 |
|---|---|---|---|
| sisyphus | primary | all | Ultraworker，编排不实现 |
| prometheus | primary | 只读集合 | Plan Builder，只写计划不改文件 |
| atlas | primary | all | Plan Executor，按计划执行，失败即停 |

子代理：sisyphus-junior / oracle / librarian / explore / momus。

Prometheus / Atlas / handoff 的行为都写在插件内置技能里（`OC/omo/skills/neko-*`），按需读取，不进常驻提示。

## 6. 对原版 OMO 的配置兼容与利用

`packages/core/src/compat/omo.ts`：
- 只读 `~/.config/opencode/oh-my-openagent.json`（本机是指向 `omo-config-bkps/default.json` 的符号链接，约 28KB）。
- `mapOmoConfig` 把 `agents[name].model / fallback_models / disabled` 映射成 OML 的 `config.agents`，`categories[name].model` 映射成 `config.categories`；未知顶层键计入 `ignoredKeys`。
- 支持带注释的 jsonc。文件不存在返回 `{found:false}`，不报错。
- 合并顺序 `{...omo, ...mine}`：OML 显式配置优先，OMO 只做兜底。

利用而不依赖：OMO 的模型分配习惯被读进来当默认值，但 OML 不导入它的代码，也不受它 5.1.34 里硬编码的 deprecated 模型影响。

## 7. 联网检索（`omo_knowledge action=web`）

Gemini `gemini-2.5-flash` + `google_search` grounding。直连 `generativelanguage.googleapis.com` 超时（curl 000），必须走 `http://127.0.0.1:7890`（403=可达）；`OML_HTTPS_PROXY=none` 可关。

## 8. 吞并矩阵：19 个插件

| 处置 | 插件 | OML 的替代 |
|---|---|---|
| 已废弃（在 1.19 全 hook 报错、零功能） | @prevalentware/opencode-goal-plugin | `omo_admin action=goal_*` |
| 已废弃（功能并入） | opencode-web-deepsearch | `omo_knowledge action=web` |
| 已废弃（功能并入） | opencode-working-memory | 上下文模块 + checkpoint |
| 已废弃（功能并入） | opencode-subagent-magazine | TaskStore 续接（resume 沿用原子会话） |
| 已废弃（功能并入） | opencode-skill-distiller | 技能选取（select.ts）+ `omo_knowledge action=skill` |
| 已废弃（功能并入） | opencode-token-monitor | `omo_admin action=measure/stats` |
| 已废弃（功能并入） | opencode-visual-cache | checkpoint 文件 |
| 保留 | opencode-notify | 系统通知，OML 不重造 |
| 保留 | superpowers-zh | 用户安装的技能包，由 `omo_knowledge action=skill` 按需读取 |
| 已移出（按需恢复） | opencode-acp / opencode-snippets / @xeaser/opencode-obsidian-sync / opencode-skeleton-pruner / @sffmc/cognition / opencode-browser / opencode-checkpoints / opencode-dreams / opencode-eslint-formatter / oh-my-openagent | 完整定义在 `~/.config/opencode/opencode-trimmed.json`，一行即可并回 |

## 9. 实测

```
bun test    123 pass / 0 fail
bun run check  7/7  tools=4/14 hooks=5/8 budget=2398
真机：sisyphus / prometheus / atlas 均 mode=all；omo_admin {"action":"measure"} 调用成功
```

## 10. 主动上下文裁剪（吸收 opencode-acp）

ACP 的洞见：上下文管理交给模型自己——给它一个 `compress` 工具，让它在合适的时机把消费过的消息区间提炼成自包含摘要，用 `[[KEEP:id]]` 标出必须原样保留的行（路径、命令、错误原文），用 `[[REF:id|说明]]` 做紧凑引用。原始消息落盘，可 `decompress` 回溯。

OML 的吸收（`packages/core/src/compress/store.ts`）：
- `omo_admin action=compress_add`：模型传 `from/to`（消息 id 区间）+ `summary`（含 KEEP/REF 标记）+ `sources`（id→原文）。KEEP 引用缺失原文时**拒绝**，防丢关键行。
- `omo_admin action=compress_list / decompress`：查块、回溯某条原文。
- 摘要块追加到 system 尾部（在 OMO_MARKER 之后），KEEP 展开为原文块、REF 折成一行 `[→ id: 说明]`。
- 与 8192 硬门的关系：compress 为主（主动、有损、保关键），硬门为兜底（被动截断）。两者叠加，而非二选一。

扬弃：ACP 的 nudge 状态机（nudgeFrequency/iterationNudgeThreshold/turnNudgeAnchors）依赖全量改写历史，OML 不做（宿主 compaction 已管），降级为 system 规则一句话；外部 `@anthropic-ai/tokenizer` 换成 budget 的估算，零依赖。
