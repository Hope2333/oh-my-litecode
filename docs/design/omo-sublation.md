# OML 扬弃判定表

依据：`docs/design/omo-rebuild.md` 十条公理；`omo-inventory.md` 实测清册。
判据三条，缺一即废除：
1. **它消灭谁的矛盾？** 说不出具体矛盾的，是繁琐哲学。
2. **它是否把责任推给了「事后修补」？** 是，则矛盾在工具契约，不在调用方。
3. **它能否被一个更少状态的机制替代？** 能，则原机制废除。

标记：**保留**=概念成立、由 OML 重写；**替代**=概念成立但机制更换；**废除**=概念不成立。

---

## 一、Agent：11 → 8

> **修订（2026-11-14）**：本表初稿判 `atlas`/`prometheus` 废除。用户随后明确要求保留
> 「Neko 三身份」：Ultraworker（sisyphus）/ Plan Builder（prometheus）/ Plan Executor（atlas），
> 并让后两者可由技能激活扮演。故最终为 **11 → 8**：3 个前台 + 5 个子代理。
> 判据变化：`prometheus` 的「只写 md」不再靠 hook 事后拦截，而是**工具白名单**（根本拿不到写工具）。

| 原 agent | 判定 | 消灭的矛盾 / 理由 | OML 形态 |
|---|---|---|---|
| `sisyphus` | 保留 | 需要「一个编排者，不亲自写代码」的角色 | 声明式对象，prompt ≤1.2K tok |
| `sisyphus-junior` | 保留 | 需要「拿到明确 brief 就干活」的执行者 | 单一变体；模型在 category 里选，不写 9 份 prompt |
| `oracle` | 保留 | 需要「只读、高推理、给方向」的顾问 | 只读工具白名单 |
| `librarian` | 保留 | 需要「查外部文档/他人实现」 | 同上 |
| `explore` | 保留 | 需要「并行 grep 本仓库」 | 同上 |
| `momus` | 保留 | 需要「写计划后有人挑刺」 | 同上 |
| `metis` | 替代 | 「预规划顾问」与 momus 同属审阅位，二者只差时机 | 合入 `momus` 的 `--pre` 模式 |
| `hephaestus` | 废除 | GPT-only 的 sisyphus-junior 副本。矛盾是「某模型写代码更强」，不是「需要一个新角色」 | 由 category 的 model 字段解决 |
| `atlas` | 保留 | 用户要求「计划执行」成为独立身份：执行者不该有规划权，否则会边做边改计划 | 前台代理，全工具，按 plan 文件执行 |
| `prometheus` | 保留 | 用户要求「先分解再执行」可被显式调用；且规划者必须无写权限 | 前台代理，只读工具白名单（拿不到 edit/write） |
| `multimodal-looker` | 废除 | 看图能力应是 `read` 的属性，不是独立 agent | `read` 直接吃图片 |

**模型特化分叉全废**：`sisyphus-junior/{kimi-k2-6,kimi-k2-7,kimi-k3,gpt,gpt-5-4,gpt-5-5,gemini,glm-5-2}` 9 份、`sisyphus/{...}` 多份、`momus-gpt-5-6` 等。理由：prompt 与模型版本的组合是乘法，模型一换代全部作废。OML 只保留**一个** prompt 文本，模型差异放在 `model` 字段与 temperature。

## 二、Category：9 → 6

| 原 | 判定 | 理由 |
|---|---|---|
| `quick` | 保留 | 单文件改动 |
| `deep-low` | 保留 | 默认深度执行 |
| `deep-high` | 保留 | 决策无法由证据裁定时升级 |
| `ultrabrain` | 保留 | 纯推理交付 |
| `visual-engineering` | 保留 | 域专用模型确有差异 |
| `writing` | 保留 | 同上 |
| `artistry` | 废除 | 与 `ultrabrain` 的差别是修辞，不是模型或工具差异 |
| `unspecified-low` | 废除 | 与 `quick` 同义 |
| `unspecified-high` | 废除 | 与 `deep-low` 同义 |

9 → 6，且**不引入 `-low/-high` 后缀的语义空洞**。

## 三、Hook：57 → 6

### 3.1 实现态（5 个，这是代码里真实注册的键）

| Hook | 职责 | 替代的原 hook |
|---|---|---|
| `config` | 读配置 + 注册 agent + 设默认代理（原「session-start」的加载职责并到这里，宿主启动时本就会调它） | `startup-toast` `auto-update-checker` `directory-agents-injector` |
| `chat.message` | 记录最近用户文本，供技能相关性选条 | `auto-slash-command` |
| `event` | `session.idle` → 清理终态任务；`session.deleted` → 清会话缓存 | `background-notification` `todo-continuation-enforcer` |
| `experimental.chat.system.transform` | **唯一**拼装点：剥离宿主全量技能目录 → 按预算注入 | `rules-injector` `directory-readme-injector` `hephaestus-agents-md-injector` |
| `tool` | 注册 4 个工具（3 网关 + skill 兼容位） | 旧 OMO 的 ~25 个工具 |

> 初稿列的 `compaction` / `idle` / `tool-output` 未单独注册：压缩前的摘要由 `omo_admin action=compress_add`
> 显式记录（模型自己决定压什么），task 续跑由 `omo_task action=resume` 显式触发。
> 理由：这两个动作需要「判断」，塞进 hook 自动跑等于把判断交给正则。**未实现的不写进已实现表。**

### 3.2 废除（51 个）

**A. 守卫/修复类（矛盾在工具契约，不在调用方）——18 个**

| Hook | 它想修什么 | 为什么废除 |
|---|---|---|
| `write-existing-file-guard` | 模型覆盖未读文件 | 由 `write` 工具自身拒绝并返回「先 read」——契约内解决 |
| `bash-file-read-guard` | 用 bash 读文件 | 工具描述已说明；再拦是重复约束 |
| `notepad-write-guard` | 写 notepad 路径 | notepad 机制本身废除 |
| `tasks-todowrite-disabler` | 两套 todo 冲突 | 两套 todo 本身废除（只留一套） |
| `tool-pair-validator` | tool_call/tool_result 不配对 | 协议层问题，hook 修不了 |
| `json-error-recovery` | 模型输出坏 JSON | 工具参数由 schema 校验，失败会重试 |
| `edit-error-recovery` | 编辑失败 | `edit` 返回真实 diff 错误即可 |
| `empty-task-response-detector` | 子代理空回复 | 由 `task` 返回值契约保证非空 |
| `question-label-truncator` | 标签过长 | UI 截断是 UI 的事 |
| `fsync-skip-warning` | 用户跳过 fsync | 无受众 |
| `webfetch-redirect-guard` | 重定向 | `webfetch` 自身处理 |
| `comment-checker` | 注释过多 | 由 `remove-ai-slops` 技能按需做，不常驻 |
| `delegate-task-retry` | 委派失败重试 | `task` 内部一次重试足够 |
| `unstable-agent-babysitter` | 子代理不稳 | 状态机问题，见 tasks 统一 |
| `tool-pair-validator` 等 | — | 同上 |
| `interactive-bash-session` | tmux 会话 | tmux 机制废除 |
| `non-interactive-env` | 非交互环境适配 | 环境探测应一次性，不每轮 hook |
| `plan-format-validator` | 计划格式 | 计划写入时校验一次 |
| `prometheus-md-only` | 规划者只写 md | 权限白名单 |

**B. 提示型「唠叨」（把 prompt 当补丁）——8 个**

`agent-usage-reminder` `category-skill-reminder` `task-reminder` `task-resume-info` `keyword-detector` `think-mode` `todo-description-override` `ulw-execute`

理由：靠周期性往对话里塞提醒来纠正行为，是**用注入解决指令不清**。指令写清一次即可；写不清，塞十次也没用。`keyword-detector` 尤其：用关键词猜意图并强制技能，误判成本高于收益。

**C. 模型策略型（应在定义处解决）——5 个**

`no-sisyphus-gpt` `no-hephaestus-non-gpt` `model-fallback` `runtime-fallback` `hashline-read-enhancer`

`no-*-gpt` 是「某模型不许配某 agent」——写在 agent 的 `model` 字段即可。两层 fallback（静态 + 运行时）合并为一层：模型不可用 → 下一个候选，一次。`hashline` 的行哈希增强在 opencode 原生 read/edit 已有行号后无增量价值。

**D. 兼容/移植层（服务于别的 harness）——6 个**

`claude-code-hooks` `atlas` `monitor-status-injector` `ast-grep-sg-provision` `legacy-plugin-toast` `native-edition-nudge`

**E. 团队/多人模式——4 个**

`team-tool-gating` `team-mode-status-injector` `team-mailbox-injector` `team-session-events`

理由：单机单用户的主要矛盾是「上下文与注意力」，不是「多个 agent 互相发邮件」。team-mode 的 4 个 hook + `features/team-mode` 整套是**未收敛的实验分支**。

**F. 通知/外观/自更新——4 个**

`session-notification` `startup-toast` `auto-update-checker` `question-label-truncator`（已计入 A）

**G. 备份状态机——2 个**

`sissyphus-junior-notepad` `ulw-execute`（已计入 B）

> 合计 18+8+5+6+4+4+2 = 47，另有 4 个仅存在于 `dist/hooks` 而未入枚举（team 三件、session-notification 系）。57 个枚举项 + 4 个未枚举 → **保留 6 个职责位，废除 55 项**。

## 四、Command：6 → 4

| 原 | 判定 | 理由 |
|---|---|---|
| `goal` | 保留 | 长任务的持久目标 |
| `stop-continuation` | 保留 | 用户必须能一键停机（安全阀） |
| `refactor` | 替代 | 是技能，不是命令；由 `skill(refactor)` 调用 |
| `remove-ai-slops` | 替代 | 同上 |
| `hyperplan` | 废除 | 依赖 team-mode |
| `ulw-execute` | 废除 | 与 `task` + todo 重复的第三套执行器 |

新增（OMO 缺而实际每日用）：`handoff`（交接摘要）、`measure`、`audit`、`slim`、`zhengfeng`（整风）。

## 五、Tool：收敛为 4 组

| 组 | OML 工具 | 替代原 |
|---|---|---|
| 编排 | `task`（同步/后台同一入口，`background: bool`） | `task` + `background_task` + `background_output` + `background_cancel` |
| 上下文 | `compress` `decompress` `search_context` | 原 5 个 ACP 工具中保留 3 个 |
| 技能 | `skill`（按名加载正文） | 同 |
| 检索 | `lsp_*`（8 个） | 同 |

废除 `session_write` `session_replay*` `acp_context_recap` `todoread`（todowrite 返回全量即读）。
`background_output` 的职责并入 `task(id)`：同一工具按 id 取结果，少一个工具定义 = 少一份 schema 注入。

## 六、Package：34 → 3

| 原 workspace（抽样） | 判定 |
|---|---|
| `rules-engine` `prompts-core` `model-core` `omo-config-core` `skills-loader-core` `agents-md-core` | 合并进 `@oml/core` |
| `background-agent` `boulder-state` `run-continuation-state` `isolation-core` | 合并进 `@oml/core/src/tasks` |
| `delegate-core` `team-core` `tmux-core` `senpi-*`(6) `omo-codex` `omo-senpi` `openclaw-core` `claude-code-compat-core` `telemetry-core` `shared-skills` `ast-grep-mcp` `git-bash-mcp` `mcp-stdio-core` `mcp-client-core` `lsp-core` `comment-checker-core` `hashline-core` `memory-core` `utils` | 废除或合入 |

结果：`@oml/core` + `@oml/cli` + `OC/omo`（`OC2/omo` 复用 core）。**34 → 3 个可发布单元。**

## 七、Config：35 个 schema 文件 → 1 个

保留的键（15 个）：`agents` `categories` `skills{roots,maxIndex}` `tasks{concurrency,maxDepth,ttlMs}` `budget{limit}` `disabled_{agents,skills,tools,hooks}` `telemetry`(恒 false) `$schema`。

废除的 21 组：`team-mode` `tmux` `tui` `openclaw` `ralph-loop` `monitor` `notification` `i18n` `claude-code` `comment-checker` `browser-automation` `model-capabilities` `fallback-models` `runtime-fallback` `dynamic-context-pruning` `experimental` `babysitting` `default-mode` `keyword-detector` `hashline` `hooks`（逐 hook 开关——hook 只剩 6 个，无需开关）。

`background-task` 的 11 个旋钮 → 3 个（`concurrency` `maxDepth` `ttlMs`）。理由：`staleTimeoutMs` `messageStalenessTimeoutMs` `sessionGoneTimeoutMs` `taskCleanupDelayMs` `syncPollTimeoutMs` `maxToolCalls` `circuitBreaker.*` 是对同一件事（任务何时算死）的 7 种猜测。

## 八、替代性进化（原 OMO 没有的）

| 进化 | 内容 | 消灭的矛盾 |
|---|---|---|
| **技能按需检索** | 索引只注入「名字 + 触发词」，正文由 `skill(name)` 拉取；相关性由任务文本打分排序，只取 top-40 | 291 条全文目录（约 60K tok）与「本轮只需要 1 个技能」的矛盾 |
| **预算闸门** | 组装前估算，超限按优先级尾部截断，`status: pass/truncated/fail` 可观测 | 「不知道注入了多少」 |
| **整风报告** | `zhengfeng` 扫描常驻足迹并生成整改清单 | 插件只增不减 |
| **零增长账本** | `BUDGET.md` + 结构门 | 每次加功能都无人负责删 |
| **单一任务状态机** | 一个 JSON 状态文件，`pending/running/done/failed/cancelled` | 六处各记一份状态 |
| **契约测试** | `contract.test.ts` 断言两个前端导出面一致 | OC/OC2 漂移 |

## 九、判定后的账

| 维度 | OMO | OML | 变化 |
|---|---|---|---|
| Agent | 11 | 6 | −45% |
| Category | 9 | 6 | −33% |
| Hook 职责位 | 57 | 6 | **−89%** |
| Command | 6 | 4(+5 新) | — |
| Tool 定义 | ~25 | ~14 | −44% |
| Workspace | 34 | 3 | −91% |
| Config schema 文件 | 35 | 1 | −97% |
| 系统提示（空闲） | 115.4K tok | 目标 ≤8,192 tok | **−93%** |

**没有一项是因为「看起来复杂」被删的**：每一项都写明它原本想消灭的矛盾，以及该矛盾转由谁承担。
