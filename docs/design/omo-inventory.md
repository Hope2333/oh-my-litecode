# OMO 功能面清册（实测）

对象：`oh-my-openagent@5.1.43`（本机已安装，`~/.cache/opencode/packages/oh-my-openagent@5.1.43/node_modules/oh-my-openagent`）
测量时间：2026-11-13
方法：只读 `.d.ts` 契约 + `package.json` + 目录结构，不反编译 6MB 单文件 bundle。

## 0. 体量

| 指标 | 实测值 | 来源 |
|---|---|---|
| 单文件 bundle | 6,083,548 B (5.8 MiB) | `ls -l dist/index.js` |
| 类型声明 | 1,679 个 `.d.ts` | `find dist -name '*.d.ts' \| wc -l` |
| monorepo workspaces | 34 | `package.json` |
| 运行时依赖 | 3 deps + 12 optional | `package.json` |
| `dist/hooks` 目录 | 56 + `shared` | `ls dist/hooks` |
| `dist/features` 目录 | 24 | `ls dist/features` |
| 配置 schema 文件 | 35 | `ls dist/config/schema/*.d.ts` |
| 内置技能 | 18 个，354,195 B 正文 | `dist/skills/*/SKILL.md` |
| 内置 locale | 12（README 亦 12 语言） | `dist/locales`, 根 README.* |

## 1. Agent（11 个，`config/schema/agent-names.d.ts`）

`sisyphus` `sisyphus-junior` `hephaestus` `atlas` `prometheus` `oracle` `librarian` `explore` `metis` `momus` `multimodal-looker`

可覆写集合额外含 `build` `plan` `OpenCode-Builder`（`OverridableAgentNameSchema`）。

每个 agent 的 prompt 按模型分叉：`sisyphus-junior/` 下有 `kimi-k2-6` `kimi-k2-7` `kimi-k3` `gpt` `gpt-5-4` `gpt-5-5` `gemini` `glm-5-2` `default` 9 个变体；`sisyphus/` 下 `kimi-k2-6` 等；另有 `sisyphus-dynamic-prompt-{builder,role,execution,exploration}.d.ts` 做运行时拼装。

## 2. Category（9 个，`config/schema/categories.d.ts` + 运行时）

`quick` `deep-low` `deep-high` `ultrabrain` `visual-engineering` `artistry` `writing` `unspecified-low` `unspecified-high`

每 category 的 schema 支持 `model` `models[]`（含 reasoning/variant/temperature/top_p/maxTokens/thinking）`fallback_models`。

## 3. Hook（57 个，`config/schema/hooks.d.ts` 的 `HookNameSchema`）

```
agent-usage-reminder            anthropic-context-window-limit-recovery
ast-grep-sg-provision           atlas
auto-slash-command              auto-update-checker
background-notification         bash-file-read-guard
category-skill-reminder         claude-code-hooks
comment-checker                 compaction-context-injector
compaction-todo-preserver       delegate-task-retry
directory-agents-injector       directory-readme-injector
edit-error-recovery             empty-task-response-detector
fsync-skip-warning              goal
hashline-read-enhancer          hephaestus-agents-md-injector
interactive-bash-session        json-error-recovery
keyword-detector                legacy-plugin-toast
model-fallback                  monitor-status-injector
native-edition-nudge            no-hephaestus-non-gpt
no-sisyphus-gpt                 non-interactive-env
notepad-write-guard             plan-format-validator
preemptive-compaction           prometheus-md-only
question-label-truncator        read-image-resizer
rules-injector                  runtime-fallback
session-notification            sisyphus-junior-notepad
startup-toast                   stop-continuation-guard
task-resume-info                tasks-todowrite-disabler
team-tool-gating                think-mode
todo-continuation-enforcer      todo-description-override
tool-output-truncator           tool-pair-validator
ulw-execute                     unstable-agent-babysitter
webfetch-redirect-guard         write-existing-file-guard
```

另有 `team-mode-status-injector` `team-mailbox-injector` `team-session-events` 与 feature 内注入器，未进 HookName 枚举。

## 4. Tool（OMO 自有，非 MCP）

契约见 `create-tools.d.ts` → `ToolsRecord`。实测出现于 bundle：

- 编排：`task`、`background_output`、`background_cancel`、`background_task`
- 上下文：`compress`、`decompress`、`search_context`、`acp_status`、`acp_context_recap`
- 技能：`skill`
- 会话：`session_list` `session_read` `session_search` `session_info` `session_write`（部分为插件/内置）
- LSP：`lsp_diagnostics` `lsp_find_references` `lsp_goto_definition` `lsp_prepare_rename` `lsp_rename` `lsp_symbols` `lsp_status` `lsp_format` `lsp_install_decision`
- 待办：`todowrite` `todoread`
- goal 系列来自独立插件 `@prevalentware/opencode-goal-plugin`，不属 OMO

## 5. Command（6 个，`config/schema/commands.d.ts`）

`goal` `hyperplan` `refactor` `remove-ai-slops` `stop-continuation` `ulw-execute`

## 6. Config（`config/schema/oh-my-opencode-config.d.ts` 顶层键）

```
$schema  new_task_system_enabled  default_run_agent  agent_order  agent_definitions
disabled_mcps  disabled_agents  disabled_skills  disabled_hooks  disabled_commands
disabled_tools  disabled_providers  mcp_env_allowlist  hashline_edit  telemetry
model_fallback  agents{...per-agent models[]/fallback/...}
```

35 个 schema 文件覆盖：`background-task`（11 个并发/超时旋钮 + circuitBreaker）`team-mode` `tmux` `tui` `openclaw` `ralph-loop` `monitor` `notification` `websearch` `skills` `i18n` `git-master` `claude-code` `comment-checker` `browser-automation` `model-capabilities` `fallback-models` `runtime-fallback` `goal` `dynamic-context-pruning` `experimental` `babysitting` `default-mode` `keyword-detector` `hashline` `hooks`。

## 7. 本机宿主现状（OMO 运行的上下文）

| 项 | 实测 |
|---|---|
| 已装插件 | 19 |
| MCP server | 8（fuck-u-code, time-complexity, blender-mcp, codegraph, krita, computer-use, unreal-engine, ocr-tools） |
| `opencode.json` | 42,975 B，另有 ~50 个 `.bak-*` |
| 会话系统提示 | **115.4K tokens（占上下文 84%）** |
| 全机唯一技能 | **291**（`SKILL.md` 正文合计 2,001,615 B） |
| 技能目录来源 | `~/.agents/skills` 203、`~/.claude/skills` 71、`~/.config/opencode/skills` 43、`~/.cache/opencode/skills` 2（含嵌套 vendored 重复） |

## 8. 浪费的结构性来源（诊断，不是抱怨）

1. **注入由「装了什么都」决定**：系统提示里 291 条技能目录 + ~15K tokens 行为指令 + 8 个 MCP 的 ~150 个工具定义，与被问的问题无关。
2. **状态机重复**：后台任务是 `background-agent`；续跑有 `boulder-state`；循环有 `ralph-loop`；再续跑有 `run-continuation-state`；再加 `task-resume-info` `task-toast-manager` `task-reminder`。六处各记一份状态。
3. **守卫层自我增殖**：57 个 hook 里至少 20 个是「模型做错了事之后去修」的 guard/recovery（`*-guard` `*-recovery` `*-validator` `*-babysitter` `*-detector`）。它们的共同前提是「工具契约不可靠」。把契约修好，这一层整体失去存在理由。
4. **模型特化分叉**：同一 agent 按 9 个模型写 9 份 prompt。模型换代即产生 9 份技术债。
5. **兼容层叠加**：claude-code 加载器 4 个、codex/senpi/openclaw 各一套、team-mode 一套、tmux 一套、TUI 一套。这些服务于「别的 harness」，不是 OpenCode 用户的矛盾。
6. **营销与自更新**：`native-edition-nudge` `legacy-plugin-toast` `startup-toast` `auto-update-checker` 在运行时向用户提示自身。这是插件对用户的单向广播，不是功能。

## 9. 结论（进入扬弃判定的依据）

OMO 的**真实价值**集中在四件事：多模型 agent 编排、后台并行任务、技能按需加载、上下文预算控制。
其余 80% 的代码量服务于：自保（guard）、自我宣传（nudge/toast）、兼容他人（claude-code/codex/openclaw）、以及未收敛的实验分支（team/tmux/ulw/ralph）。

判定表见 `omo-sublation.md`。
