# @oml/omo-oc —— OpenCode 1.x 前线适配器

OMO 的 OpenCode 1.x 插件入口。它把平台无关的 `PluginHost` 契约（见
`packages/core/src/contract.ts`）实现为 OpenCode 的 Hooks，**只挂 2 个 hook
位**（设计 `docs/design/omo-rebuild.md` §9）：

| hook 位 | OpenCode 映射 | 职责 |
|---|---|---|
| session-start | `event`(`session.created`)，退化为首次 `chat.message` 去重 | 预算基线 |
| prompt-transform | `experimental.chat.system.transform` | 预算门禁 + 技能索引注入 |

预算、索引、技能扫描**全部委托 `@oml/core`**，适配层不含业务逻辑。

## 本机启用步骤

1. 确认依赖已安装（仓库根已声明 `@opencode-ai/plugin`，本包已依赖 `@oml/core`）：

   ```bash
   cd /home/miao/Projects/OML && bun install
   ```

2. 编辑 `~/.config/opencode/opencode.json`，在 `plugin` 数组中加入本包的
   入口路径（OpenCode 支持具名导出 `OmoPlugin` 与 default 导出两种）：

   ```json
   {
     "plugin": [
       "/home/miao/Projects/OML/OC/omo/src/index.ts"
     ]
   }
   ```

   若已有其它插件，把该路径追加进数组即可，不要覆盖。

3. 重启 OpenCode 使配置生效（运行中的会话仍用已加载的旧配置）。

4. 验证：新开一个会话，看 `~/.local/state/omo/budget.log` 是否在超预算时
   出现 `[budget]` 告警行；或临时把 `DEFAULT_BUDGET_TOKENS` 调小观察注入量。

## 回退

从 `plugin` 数组里删掉该路径即可，无需卸载（设计 §12 与旧 OMO 共存）。

## 开发

```bash
cd /home/miao/Projects/OML
bun test OC/omo                                  # 映射逻辑单测（假 Hooks）
bun ./node_modules/typescript/lib/tsc.js -p tsconfig.json --noEmit   # 类型
```

`src/host.ts` + `src/index.ts` 合计 ≤300 行；`src/host.test.ts` 用假 Hooks
对象测映射，不需要真实 OpenCode 进程。
