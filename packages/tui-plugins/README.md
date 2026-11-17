# OML TUI 插件 fork（A 路线）

用户决策（2026-11-17，走 A）：把 `opencode-subagent-magazine` 与 `opencode-visual-cache`
两个 TUI 侧栏插件 fork 进 OML 仓，纳入维护枝，复活 subagent 树面板 + 完整 session 跳转。
B（OML 自有 TUI 外壳）作为实验分支，A 之后再谈。

## 为什么 fork

- 上游插件的 `subagent_magazine.session_data` 是 2026-11-12 TUI「Session not found」
  幽灵会话残留的源头；隶属判定全靠宿主 `SessionLike.parentID`。
- OML 需要可控的 KV 命名空间 + 可审计的补丁，而不是随 npm 升级漂移的黑盒。

## fork 形态（重要）

仓库 `bundle/tui.js` 是**上游原样 prebuilt bundle**（只读基线，来自本机运行版本）。
`patch.ts` 是纯函数补丁（`patchMagazine` / `patchVisualCache`）。
`sync.ts` 做：`读 bundle/tui.js → apply patch → verify → 写 live cache dist/tui.js`。

- **不改** slot `id` / npm 名 → `~/.config/opencode/tui.json` 与宿主 loader 原样认得；
  `third.test.ts` 的名字断言、`third.ts` 的升级命令都不动。
- `.gitignore` 已忽略 `dist/`，故 bundle 放在 `bundle/`（纳入版本控制）。
- 上游升级后需重新 `cp` 一份 bundle 并跑测试调整补丁锚点（`sync.ts --check` 会报锚点漂移）。

## 补丁内容

| 插件 | 变更 |
|---|---|
| magazine | `KV_PREFIX` → `oml_subagent_magazine`；tui 入口注入「仅迁移用户设置、不迁 session_data」块；toast 标 fork；clearedIds / id 原样 |
| visual-cache | `KV_PREFIX`（3 处）+ `.session` key → `oml_cache_panel`；id / API key 逻辑原样 |

running 版本 magazine 1.5.2 / visual-cache 1.6.2 **无 dbSync 开关**（那是缓存里 1.7.x 才有的），
故不做 dbSync 默认关。

## 使用

```bash
bun packages/tui-plugins/sync.ts --check   # 只校验补丁可落地 + 目标当前状态，不写盘
bun packages/tui-plugins/sync.ts            # 应用到 live cache（写前自动备份 .oml-orig）
bun packages/tui-plugins/sync.ts --revert   # 从 .oml-orig 还原上游
```

写盘后需**重启 opencode** 才加载新 bundle。TUI 真实渲染本机无 TTY 无法自动验证，
需用户目视确认：侧栏出现 subagent 树 + cache 面板，且标题带隶属链（`omo t1←t5 · ...`，U1 已做）。
