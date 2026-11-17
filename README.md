# OML / omo

用马列毛主义（左、无产阶级革命派、反修—76 版）的组织原则重建 OpenCode 编排层。
目标不是「功能更多」，而是**注入量只与当前主要矛盾相关**。

- 设计：`docs/design/omo-rebuild.md`
- 计划：`docs/plan/omo-rebuild-plan.md`
- 预算账本：`BUDGET.md`
- 模块存在理由：`MODULES.md`

## 结构

```
packages/core   内核（平台无关）：预算 / 惰性技能索引 / 编排 / hook / 契约
packages/cli    omo measure | audit | slim | zhengfeng | skills | tasks | config
OC/omo          前线 1：OpenCode 1.x 适配
OC2/omo         前线 2：OpenCode 2.x 适配
bench           提示体积与启动延迟基准
```

## 证据：它不是「看起来更小」，是量出来的

三个独立维度，各有可复现命令，且**口径不同、不许混着说**：

| 维度 | 数字 | 命令 | 口径 |
|---|---|---|---|
| 首轮总提示 | 43,232 → **21,452**（−50.4%） | `bash bench/ab.sh` | 同一宿主同一模型，装/不装 OML |
| 5 个真实任务 | 完成率 **5/5 vs 5/5**，输入 tok **−57.4%**，步数 +58% | `bun bench/ab-task.ts --label oml` | 同模型同 fixture，唯一变量是插件 |
| OML 自身注入段 | **2,422 tok** | `bun run omo measure` | 只统计 OML 拼的四段，**不是总提示** |

结论只能这么说：**OML 把系统变小了，并且在 5 个短任务上与旧 OMO 打平、成本低一半。**
不能说「总提示 116K 降到 2.4K」——那是两把尺子混用，旧文档已作废（见 `docs/bench/parity.md` 的口径列）。

限定条件写在 `docs/bench/task-ab.md`：单模型、单次跑、任务规模 30–60 秒，长任务与中断恢复尚未对照测量。

## 接入 OpenCode 1.x

```ts
// ~/.config/opencode/plugin/omo.ts
export { default } from "file:///home/miao/Projects/OML/OC/omo/src/index.ts"
```

插件只挂 4 个 hook 位（`event` / `chat.message` / `experimental.chat.system.transform` / `tool`），
系统提示只在 `system.transform` 一处注入，并带 `<!-- omo:system -->` 标记防重复。

## 开发

```bash
bun install
bun run check         # 7 道门：类型/单测/预算/宿主注入/插件面/结构/零增长
bun run bench:host    # 宿主实际注入段体积（--real 用真实技能根）
bun run omo measure   # 查看当前注入量
bun run omo skills 落地页   # 按任务检索技能
bun run omo tasks --all     # 任务账本
bun run omo config          # 生效配置及来源
```

> 本机 `/usr/bin/node` 已损坏（缺 `libada.so.3`）。全链路使用 bun，禁止裸 `node`。
