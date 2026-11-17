# OC2 前线状态（2026-11-15）

## 结论

| 项目 | 状态 | 证据 |
|---|---|---|
| OC2 适配层 | **已去骨架化**，委托 OC 前线实现 | `OC2/omo/src/host.ts`（33 行） |
| OC2 真机加载 | **通过**（在现存唯一运行时 1.19.3 上） | 下节实测 |
| OpenCode 2.x 真机 | **不可测：尚未发布** | npm dist-tags 探测 |

## 上游探测（为什么 2.x 不可测）

```
opencode-ai       dist-tags: latest=1.19.5  dev=0.0.0-dev-202611092046
                             beta=0.0.0-beta-19271  next=0.0.0-next-17444
@opencode-ai/plugin dist-tags: latest=1.19.5  dev=0.0.0-dev-202611092046
```

**不存在 2.x 版本线**。把 `dev` 通道的 `dist/index.d.ts` 拉下来 diff，14 个 hook 键与 1.19.5 逐字相同：

```
chat.headers / chat.message / chat.params / command.execute.before
experimental.chat.messages.transform / experimental.chat.system.transform
experimental.compaction.autocontinue / experimental.session.compacting
experimental.text.complete / permission.ask / shell.env / tool.definition
tool.execute.after / tool.execute.before
```

因此「OC2 适配」当前的正确形态不是另写一套实现，而是**一层可替换的方言翻译**：
`dialect.ts` 里的 6 条 DIFF（键名、system 载荷、工具注册方式、PluginInput 字段、
压缩载荷、导出契约），每条都写了「若 2.x 变了改哪里」与「怎么验」。

## 真机实测（把宿主插件指向 OC2 入口，跑完即恢复）

```bash
# ~/.config/opencode/plugin/omo.ts 临时改为
export { default } from "file:///home/miao/Projects/OML/OC2/omo/src/index.ts"

opencode run --model bailing/Ling-3.0-flash --agent sisyphus \
  --dir /tmp/oml-smoke "调用 omo_admin action=stats，原样回传它的返回值"
```

输出：

```
TOOL omo_admin -> 本次会话 1 分钟，任务 0 个（未终结 0）| admin.stats: 1
in=22934   （OC 前线同场景 23,019，差 0.4%，属噪声）
插件加载错误：0
```

跑完已把 `omo.ts` 恢复为 OC 前线（`cp /tmp/omo.ts.oc1`）。

## 测试

`bun test OC2` → 6 pass：缺 `directory` / `client` 立刻抛错；装配出的钩子键与 OC
同构（6 个）；工具表恰为 `omo_admin/omo_knowledge/omo_task/skill`；系统提示被接管
（有 `<!-- omo:system -->`，且宿主 `<available_skills>` 被剥离）。

## 2.x 发布后的动作（唯一待办）

1. `bun add @opencode-ai/plugin@<2.x>` 后跑 `bun test OC2`：失败的那条即 DIFF 现场。
2. 按 `dialect.ts` 的 6 条 DIFF 逐条改翻译，**不要碰 `packages/core`**。
3. 若 DIFF-3（工具注册改命令式）成立，`host.ts` 会从 33 行长到 ~80 行，仍在 120 行预算内。
