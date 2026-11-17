# OMO → OML 逐项对照

生成时间：2026-11-14T22:01:02.060Z　命令：`bun run bench:parity`

| 项目 | 原版 OMO | OML | 口径 |
|---|---|---|---|
| 首轮总提示 (tok) | 43,232 | **21,452** | 同一把尺子实测，−50.4% |
| 5 任务完成率 | 5/5 | **5/5** | docs/bench/task-ab.md；同模型同 fixture 实测 |
| 5 任务输入 (tok) | 534,573 | **227,632** | 真实任务累计，−57.4% |
| 5 任务平均步数 | 6.6 | **10.4** | 步数多＝多走了查技能/读正文/量预算 |
| OML 自身注入段 (tok) | — | **2,425** | `omo measure`：只统计 OML 拼装的四段，不是总提示 |
| 工具数 | 25 | **4** | inventory vs buildTools() |
| hook 职责位 | 57 | **5** | inventory vs hooks 键数 |
| agent | 11 | **8** | 其中前台 3 |
| category | 9 | **6** | inventory vs registry |
| 运行时依赖 | 3 + 12 optional | **0** | package.json |
| 产物体积 | 5.80 MB | **281 KB** | 源码 vs 打包产物；.d.ts 1679 → 0 |
| workspace | 34 | **3** | packages/core, packages/cli, OC/omo (+ OC2) |
| 首屏加载 | 未测 | **6.08 ms** | createHostCore 冷启动 |
| 常驻内存增量 | 未测 | **4.8 MB** | process.memoryUsage().rss 差值 |

## 首轮总提示：同一把尺子的 A/B

条件：`opencode/deepseek-v4.1-flash-free`、空项目 `/tmp/oml-ab/proj`、单轮提示词「只回复两个字：收到」、宿主配置 真实 ~/.config/opencode/opencode.json：2 个插件 + 4 个 MCP。
取数方法：opencode run --format json，取 step-finish.tokens.input（首轮）。测量时间：2026-11-14T14:25:00Z。

| 组 | OML | 外部技能扫描 | tokens.input | 说明 |
|---|---|---|---|---|
| A | 关 | 开 | **43,232** | 对照组：OML 关闭（plugin/omo.ts 临时改名） |
| B | 开 | 开 | **21,452** | 实验组：OML 开启 |
| C | 开 | 关 | **21,452** | OML 开启 + OPENCODE_DISABLE_EXTERNAL_SKILLS=1，与 B 完全相同 |
| D | 关 | 关 | **24,892** | OML 关闭 + 禁用外部技能：宿主底噪参考 |

结论：OML 使首轮总提示 43,232 → 21,452（−50.4%）。
C 与 B 完全相同，说明宿主注入的全量技能目录已被 OML 剥离——此时外部技能开关不再影响提示体积。
复现：`bash bench/ab.sh`。

## 真实任务 A/B：它到底会不会干活

模型 `bailing/Ling-3.0-flash`，5 个 fixture 任务，唯一变量是装 OML 还是装旧 OMO。验收脚本只判行为，不看实现。

| 任务 | OML | OML in tok | OMO | OMO in tok |
|---|---|---|---|---|
| 01-ndjson | ✓ | 25,083 | ✓ | 87,718 |
| 02-bugfix | ✓ | 71,953 | ✓ | 179,766 |
| 03-cache | ✓ | 50,492 | ✓ | 92,074 |
| 04-readme | ✓ | 52,771 | ✓ | 87,064 |
| 05-refactor | ✓ | 27,333 | ✓ | 87,951 |

完成率 5/5 vs 5/5；输入 token −57.4%；平均步数 10.4 vs 6.6（**多了**，不是少了）。
详细限定条件（单模型单次、任务规模小、长任务未覆盖）见 `docs/bench/task-ab.md`，此处不重复好消息。
复现：`bun bench/ab-task.ts --label oml` 与 `bun bench/ab-task.ts --label omo --config /tmp/omo-only.json`。

## 读法
- **总量**用首轮总提示（A/B 实测）；**OML 自身段**用 `omo measure`。两者不能混着说。
- OML 的 4 个工具与 5 个 hook 位都是条件装配的结果：配置里关掉哪个，计数就减一，`scripts/check.ts` 的 surface 门会当场验证。
- 原版 OMO 的「未测」项没有可信数字，不编。
