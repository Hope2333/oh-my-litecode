# OMO 重建设计（OC / OC2）

> 版本 v0.1 · 2026-11-13 · 状态：已定（用户授权直接开工，跳过质询）
> 上游参考：https://github.com/Hope2333/oh-my-litecode （OML，MIT，v0.2.0-alpha）
> 被替代对象：oh-my-openagent 5.1.43（下称「旧 OMO」）

---

## 0. 一句话

用一个内核、两个前线（OC = OpenCode 1，OC2 = OpenCode 2），重建与 omo 兼容的编排层，把「注入量」从**与任务无关的全量**压缩到**与当前主要矛盾相关的最小集**。

---

## 1. 主要矛盾（实测，不是估计）

| 项 | 旧 OMO 实测 | 来源 |
|---|---|---|
| 会话系统提示 | **115.4K tokens（84% 上下文）** | 本会话实测 |
| 注册技能 | **319 个 SKILL.md**，全量描述进提示 | `.agents/skills` 203 / `.claude/skills` 71 / `.config/opencode/skills` 43 / cache 2 |
| SKILL.md 正文总量 | **2,001,615 字节** | 全量 `cat` 统计 |
| 插件产物 | dist **16MB**，单文件 `dist/index.js` **6.0MB** | `oh-my-openagent@5.1.43` |
| Hook | **60+ 个目录**（含 59 个 hook 实现 + 20 个 .d.ts 碎片） | `dist/hooks/` |
| MCP 常驻 | **8 个**，约 **150 个工具定义**常驻上下文 | `opencode.json` |
| 已装插件 | **19 个**，启动期 + 上下文双重收费 | `opencode.json` |
| 配置文件 | `opencode.json` 42,975 B + ~50 个 `.bak` 备份 | `~/.config/opencode` |

**矛盾表述**：系统的注入量与「用户此刻要解决的那一个问题」之间没有因果关系。
注入量由「装了什么」决定，而不是由「要做什么」决定。

由此派生的次生矛盾：

- **C1 技能通胀**：技能数量增长 → 提示线性增长 → 模型注意力被稀释 → 选择变差 → 用户装更多技能试图补救。
- **C2 Hook 官僚化**：60+ hook 互相补偿，任何一个删除都「怕出问题」，于是只增不减。
- **C3 抽象层叠**：20+ 子包中多数是为上一版抽象服务的抽象，删除需要先理解，理解成本高于重写。
- **C4 配置漂移（修正主义）**：~50 个 `.bak` 说明配置长期在打补丁而非收敛；spec 与实际行为已脱节。

---

## 2. 哲学 → 工程公理

用户指定路线：**马列毛主义（左、无产阶级革命派、反修—76 版）**。
下面不是修辞，是把该路线**操作化**为可测规则。每条公理必须能落成一条 CI 检查，否则不进本设计（这本身就是公理 A5 的要求）。

| # | 公理 | 来源概念 | 可测规则（CI 可执行） |
|---|---|---|---|
| A1 | **单一主要矛盾** | 主要矛盾 / 抓主要矛盾 | 任一时刻上下文中「活跃目标」≤ 1；非当前目标、非当前 agent、非命中技能**不得注入** |
| A2 | **具体问题具体分析** | 具体问题具体分析 | 禁止万能系统提示；prompt 由 (模型能力 × 任务类型) 矩阵拼装，同一模型的不同任务不得共用同一份大 prompt |
| A3 | **群众路线** | 从群众中来，到群众中去 | 技能注册表由**真实命中统计**驱动；冷启动白名单 ≤ 20；连续 N 次未命中的技能自动降级为「仅名字」 |
| A4 | **民主集中制** | 集中领导下的民主 | **单一写入者**：编排者独占写权限；子代理只读或隔离工作区写；禁止多中心并发写同一文件 |
| A5 | **反修** | 反修正主义 | 每个模块必须在 `MODULES.md` 写明「它消灭了哪个具体矛盾」；写不出的抽象**禁止合入**；已有抽象每季度复审一次，无证据即删 |
| A6 | **继续革命** | 无产阶级专政下继续革命 | 每 N 次会话产出「整风报告」：量化上下文开销、列出零命中技能/hook、给出删除建议；报告不是建议而是**待执行队列** |
| A7 | **自力更生** | 自力更生 | 零运行时外部依赖、零遥测、零云、**零 postinstall 网络下载**；单文件可离线跑 |
| A8 | **精兵简政** | 精兵简政 | Hook 硬上限 **8**、常驻 MCP 硬上限 **3**、插件硬上限 **5**；超限必须**先删后加** |
| A9 | **实践是检验真理的唯一标准** | 实践论 | 一切优化以 `bench/` 实测 token / 延迟为准；无基准数据的性能声明一律视为未验证 |
| A10 | **零增长（反和平演变）** | 反修—76 版的操作化 | 仓库维护 `BUDGET.md`；任何新增（技能/hook/工具/依赖）必须同时给出等量删除或书面豁免理由，否则 CI 拒绝 |

> 关于「76 版」：本设计把它读作**反修路线的连续性要求**——反对渐进膨胀、反对以「兼容」为名的永久妥协。A10 即其工程化形态。若用户对「76 版」另有具体文本指涉，只需替换 A10 的表述，其余公理不受影响。

---

## 3. 目标（硬指标，进 CI）

| 指标 | 旧 OMO | 目标 | 测量方式 |
|---|---|---|---|
| 空闲会话系统提示 | 115.4K tok | **≤ 8K tok** | `omo measure --json` |
| 技能描述注入 | 319 全量 | **≤ 40 条索引**（名字 + ≤40 字触发语） | 同上 |
| 技能正文加载 | 预注入 | **按需**（调用时才读 SKILL.md） | hook 计数 |
| Hook 数量 | 60+ | **≤ 8** | 目录计数 |
| 常驻 MCP | 8 | **≤ 3**（其余按项目 opt-in） | `omo audit` |
| 插件 dist | 16MB / 6MB 单文件 | **≤ 300KB**，可 tree-shake | `du` |
| 冷启动 p95 | 未测 | **≤ 100ms** | `bench/startup.ts` |
| 内核单测覆盖 | — | **≥ 80%** | `bun test --coverage` |
| 运行时依赖 | node 链路 | **bun 优先，node 兼容**（本机 node 已损坏） | 启动脚本 |

---

## 4. 非目标（明确不做）

- 不追求功能对齐旧 OMO 的 60+ hook。**兼容 = 配置与调用约定兼容，不是行为全等**。
- 不做 TUI 重写、不做 i18n 框架、不做云同步、不做 telemetry。
- 不做「万能 agent」。agent 只在被显式派发时存在，不常驻上下文。
- 不在第一阶段做 Rust/Go。**只有 bench 证明内核某路径 >20% 总耗时时才允许替换**（A9）。

---

## 5. 架构：一个内核，两个前线

```
~/Projects/OML/
├── packages/core/        # 内核：预算、索引、编排、契约（无平台 API）
│   ├── budget/           # 上下文预算：测量、拼装、门禁
│   ├── skills/           # 惰性技能索引：索引生成、命中统计、按需加载
│   ├── orchestrate/      # 单一写入者调度、子代理契约
│   ├── hooks/            # ≤8 个 hook 的注册与短路
│   └── contract/         # 与平台无关的 PluginHost 接口
├── packages/cli/         # omo measure / audit / slim / zhengfeng
├── OC/omo/               # 前线 1：OpenCode 1.x 适配（plugin 入口）
├── OC2/omo/              # 前线 2：OpenCode 2.x 适配（plugin 入口）
├── bench/                # 基准：提示体积、启动延迟、命中率
└── BUDGET.md             # 零增长账本（A10）
```

**民主集中制的落点**：`packages/core` 是唯一决策中心；`OC/omo` 与 `OC2/omo` 只做协议翻译，**不得包含业务逻辑**。二者共享内核，差异仅在 `PluginHost` 实现。

`PluginHost` 契约（平台无关，OC/OC2 各自实现）：

```ts
export interface PluginHost {
  onSessionStart(cb: () => Promise<void>): void
  onChatMessage(cb: (m: ChatMessage) => Promise<ChatMessage | void>): void
  transformSystemPrompt(cb: (p: SystemPrompt) => Promise<SystemPrompt>): void
  registerTool(t: ToolSpec): void
  registerAgent(a: AgentSpec): void
  readFile(p: string): Promise<string>
  listSkills(): Promise<SkillMeta[]>
}
```

内核只依赖 `PluginHost`。OC 与 OC2 各自把宿主 API 包成这 8 个方法。**适配层代码量目标各 ≤ 300 行。**

---

## 6. 模块表（A5：每个模块必须写明消灭的矛盾）

| 模块 | 消灭的具体矛盾 | 不做的后果 |
|---|---|---|
| `core/budget` | C1：注入量无因果 | 优化无从测量，回到「凭感觉精简」 |
| `core/skills` | C1 + C3：319 全量注入 | 提示线性膨胀，注意力稀释 |
| `core/orchestrate` | A4：多中心并发写 | 子代理互相覆盖，返工 |
| `core/hooks` | C2：60+ hook 互相补偿 | 删除任何一个都「怕出问题」 |
| `core/contract` | C3：抽象绑定单一平台 | OC2 适配要重写全部逻辑 |
| `cli` | A6 + A9：无度量、无整风 | 无法证明精简有效，无法阻止回涨 |

---

## 7. 核心机制一：上下文预算门禁

**问题**：旧 OMO 无法回答「这次会话注入了什么、为什么」。

**做法**：

1. `omo measure` 通过 `PluginHost` 收集三段来源：工具定义、系统提示段、技能索引，输出结构化报告：

```jsonc
{
  "totalTokens": 7920,
  "sections": [
    { "id": "tools",     "tokens": 3100, "items": 12 },
    { "id": "identity",  "tokens": 1800, "items": 1  },
    { "id": "skillIndex","tokens": 1400, "items": 38 },
    { "id": "memory",    "tokens": 1620, "items": 4  }
  ],
  "budget": { "limit": 8192, "used": 7920, "status": "pass" }
}
```

2. **门禁**：`transformSystemPrompt` 出口处强制检查；超预算则按优先级**截断**（`memory < skillIndex < identity < tools`），并写一行告警到 `~/.local/state/omo/budget.log`。
3. **不静默**：截断必须可见，否则就是新的修正主义（隐瞒矛盾）。

token 计数用字符级近似（CJK 1 char ≈ 1 token，ASCII 4 char ≈ 1 token），不引入 tokenizer 依赖（A7）。

---

## 8. 核心机制二：惰性技能索引

**问题**：319 个技能 × 平均 300 字描述 ≈ 25K+ tokens，且 90% 与本轮无关。

**做法**：

1. **索引 ≠ 全文**。注入的是：

```
skills[38]: blender-scene-craft(3d场景/穿模/打光) gsap-core(GSAP动画) ...
```

每条 ≤ 40 字，仅「名字 + 触发语」。全文留在磁盘。
2. **命中驱动**：`core/skills` 维护 `~/.local/state/omo/skill-usage.json`（name → hits, lastUsed）。索引按 hits 排序取前 40。
3. **按需加载**：模型调用 `skill` 工具时才 `readFile(SKILL.md)`，正文进对话而非系统提示。这正是 OpenCode 原生 `skill` 工具已有的语义，我们只是**不再预注入全量目录**。
4. **降级**：连续 10 次会话零命中 → 移出索引（仍可通过 `skill` 工具显式调用）。这是 A3「从群众中来」：没被群众用过的，不占用群众的位置。
5. **可解释**：`omo audit --skills` 输出「索引内 / 已降级 / 从未命中」三张表。

---

## 9. 核心机制三：Hook 预算

旧 OMO 的 60+ hook 中，大量是**补偿性 hook**（`*-guard`、`*-recovery`、`*-reminder`）。补偿性 hook 的存在说明上游行为不稳定；层叠补偿会让系统不可预测。

新内核只保留 8 个**不可补偿**的位置：

| # | hook | 唯一职责 | 对应公理 |
|---|---|---|---|
| 1 | `session-start` | 加载记忆 + 预算基线 | A1 |
| 2 | `prompt-transform` | 预算门禁 + 技能索引注入 | A1/A9 |
| 3 | `tool-gate` | 单一写入者校验 | A4 |
| 4 | `delegate` | 子代理派发与上下文裁剪 | A1/A4 |
| 5 | `compaction` | 压缩前保留目标与待办 | A6 |
| 6 | `retro` | 整风报告生成 | A6 |
| 7 | `guard` | 危险操作（写仓库外、删文件）拦截 | A4 |
| 8 | `notify` | 完成通知（可选，默认关） | — |

**规则**：新增第 9 个 hook 前，必须先证明「上述 8 个中某一个无法承担该职责」并写进 `MODULES.md`（A5 + A8）。

---

## 10. 验收（CI 门禁）

```bash
bun run check   # 依次执行：
# 1. 类型：bun x tsc --noEmit
# 2. 单测：bun test（内核覆盖 ≥80%）
# 3. 预算：bun run bench:prompt  → 空闲提示 ≤ 8192 tok，否则 exit 1
# 4. 结构：hook ≤8、常驻 MCP ≤3、插件 ≤5
# 5. 零增长：git diff 中新增项必须在 BUDGET.md 有对应删除或豁免
```

**完成定义**：`bun run check` 全绿 + `omo measure` 报告 ≤8K tok + 在 OC 上真实跑通一次「派发子代理改一个文件」的端到端流程。

---

## 11. 风险

| 风险 | 影响 | 对策 |
|---|---|---|
| OpenCode 插件 API 在 1.x/2.x 不一致 | OC2 适配返工 | `PluginHost` 契约先行；适配层 ≤300 行，可整体重写 |
| 惰性索引导致技能「想不起来用」 | 能力下降 | 保留 `skill` 工具显式调用；索引保留 top-40 而非 top-10；整风报告监控零命中率 |
| 本机 node 损坏（缺 `libada.so.3`） | 工具链不可用 | 全链路 bun；CI 脚本禁止裸 `node` |
| 过度精简砍掉真实需求 | 用户回退旧 OMO | 两套共存：新插件独立包名 `@oml/omo`，`opencode.json` 可随时切回 |
| 哲学表述被当成口号 | 设计与实现脱节 | A5：每个模块必须写「消灭哪个矛盾」，写不出不合入 |

---

## 12. 迁移路径（与旧 OMO 共存）

1. **共存期**：`@oml/omo` 与 `oh-my-openagent` 同时安装，但**只启用其一**（A1：单一主要矛盾）。
2. **影子模式**：`omo measure --against oh-my-openagent` 对比两者注入量，产出对比表。
3. **切换判据**：连续 5 次真实任务，新插件完成率不低于旧插件，且提示体积 ≤ 旧插件 10%。
4. **回退**：`omo switch legacy` 改回 `opencode.json` 的插件行，无需卸载。

---

## 13. 下一步

见 `docs/plan/omo-rebuild-plan.md`。
