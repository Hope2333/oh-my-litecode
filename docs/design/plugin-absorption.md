# 插件吸收计划：19 → OML / 原生 / 移除

> 判据三条：
> 1. **OpenCode 1.19 原生已取代** → 不吸收，从 config 移出（零损失）。
> 2. **OML 已内建替代** → 移出，功能走 OML 工具。
> 3. **真实空白且值得** → 吸收为 OML 能力（写进 BUDGET.md，给等量删除项）。
> 4. **宿主 UI/生态层** → 不吸收（OML 不做 TUI/弹窗/面板）。

## 一、立即移除（零损失）

| 插件 | 理由 |
|---|---|
| `@prevalentware/opencode-goal-plugin` | 在 1.19 全 hook 报错、零功能；goal 已由 `omo_admin action=goal (op=set/show/clear)` 接管 |
| `oh-my-openagent` | 已移除（本次 OML 接管的主体） |

## 二、OpenCode 1.19 原生已取代（不吸收）

| 插件 | 原生取代 |
|---|---|
| `opencode-checkpoints` (v1.0.0) | OpenCode 内建 checkpoints（`/undo`、session checkpoint） |
| `opencode-skill-distiller` (v0.2.0) | OpenCode 原生 skills 目录 + OML `omo_knowledge action=skill` 按需读取 |
| `opencode-browser` (v1.2.3) | 已有 `opencode-browser` MCP（Browser MCP）；OML 不重造浏览器自动化 |
| `opencode-token-monitor` (v0.5.0) | `omo_admin action=stats` + `omo measure`；生态遥测属 OML 反目标（telemetry:false） |
| `opencode-web-deepsearch` (v1.0.11) | `omo_knowledge action=web`（Gemini grounding） |
| `opencode-acp` (v1.14.16) | **已吸收**：`packages/core/src/compress/store.ts`。保留「模型自主决定压缩什么」+ `[[KEEP]]`/`[[REF]]` 标记 + 摘要块回溯；废弃其 nudge 状态机（宿主 compaction 已管）与外部 tokenizer（用 budget 估算）。走 `omo_admin action=compress_add/list/decompress`，摘要块注入 system 尾部 |
| `opencode-skeleton-pruner` (v0.1.0) | 文件读取返回骨架；属 opencode 核心 file-read 行为，插件层改不动且与渐进披露重叠 |
| `opencode-eslint-formatter` (v0.1.0) | opencode 原生 LSP/formatter 配置已覆盖（`lsp` 键） |

## 三、宿主 UI / 生态层（不吸收）

| 插件 | 理由 |
|---|---|
| `opencode-notify` (v0.3.1) | 系统弹窗；**保留**（OML 反目标：不做桌面 UI） |
| `opencode-subagent-magazine` (v1.5.2) | TUI 侧栏面板；已被 OML TaskStore + `omo_task action=status` 取代，面板本身是 TUI 层 |
| `opencode-visual-cache` (v1.6.2) | TUI 缓存命中率侧栏；纯 UI |
| `superpowers-zh` | **保留**（用户技能包，经 `omo_knowledge action=skill` 按需读取） |

## 四、值得吸收（OML 真实空白）

| 插件 | 空白 | OML 吸收形态 | 优先级 |
|---|---|---|---|
| `opencode-working-memory` (v1.6.9) | 跨会话持久记忆 + 热会话状态 | **已吸收**：`packages/core/src/memory/store.ts` → `<stateDir>/memory.json`；`omo_admin action=memory_add/list/forget/reinforce`；注入走 budget 的 memory 段（空库零成本）；护栏=去重/凭据脱敏/弱记忆衰减/硬上限 60。热会话态仍归 checkpoint | 已完成 |
| `opencode-dreams` (v0.1.5) | 从会话蒸馏「不再重复犯错」的经验 | **已吸收**：`packages/core/src/memory/dreams.ts`。确定性蒸馏（不调外部模型）：扫任务账本 failed 记录、按关键词聚类、出现≥2 次即候选反模式，`omo_admin action=dreams_distill`（`apply:true` 落库）。落成 `antipattern` 类型记忆 | 已完成 |
| `opencode-snippets` (v3.0.0) | hashtag 片段展开 | **已吸收（降级）**：片段= `snippet` 类型记忆，`memory_add kind=snippet` 存、`memory_list kind=snippet` 查、按需注入。不做输入层 hashtag 展开（TUI 层，反目标） | 已完成 |

## 执行

- 立即：从 config 移出 goal-plugin（第二节的 7 个 + 第三节的 3 个本就已移出或保留，见 BUDGET.md）。
- 保留：`opencode-notify`、`superpowers-zh`。
