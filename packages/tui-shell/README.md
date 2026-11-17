# OML TUI Shell (实验分支 B)

OML 自有的会话树 TUI 面板原型。目标：把 subagent 会话按 `parentID` 组织成树，
标题带隶属链，点击跳到任意会话（完整 session 功能），不依赖 A 的 fork 插件。

## 已验证（headless，可复现）
- `packages/tui-shell/src/tree.ts`：纯会话树模型，零外部依赖。处理孤儿/环/自环/dup/深度截断/排序。
- `packages/tui-shell/src/adapter.ts`：`api.state.session.get` 快照 → `SessionNode[]`，含幽灵裁剪。
- `packages/tui-shell/src/plugin.ts`：V1 TUI 注册外壳（slot + command + KV 累积 + 跳转），渲染器注入以便测试。
- 测试：`bun test packages/tui-shell/src/` → 26 pass / 0 fail。
- 语法：Bun.Transpiler 对 3 个 `.ts` 全部转换成功。

## 未验证（必须用户目视确认，不冒充完成）
- **真实 TUI 渲染**：本机无 TTY，OML 仓无 `solid-js` / `@opentui/solid` devDep。
  `plugin.ts` 默认导出的 `tui` 仍是占位描述符（`__omlTreePlaceholder`），不是真实 Solid 组件。
- **跳转副作用**：`api.route.navigate` 只在测试桩里验证调用形状，未在真宿主点击验证。
- 接入实验步骤（用户自行）：
  1. 在宿主 `~/.config/opencode/tui.jsonc` 临时注册本实验插件（需先把源码 bundle 成宿主可加载形态，
     或放 `file:` 路径 + 自带 solid 依赖）。
  2. 重启 opencode，观察侧栏是否出现 OML 会话树，标题是否带 `omo ·` 前缀与隶属链。
  3. 点条目确认跳到对应会话。
  4. 验证完撤销注册（避免和 A 的 fork 面板抢 slot）。

## 与 A 的关系
- A（master 分支 `a821fff`）fork 了 magazine + visual-cache 两插件并注册到 tui.jsonc，是已落地方案。
- B（本实验分支）只验证「OML 自己拥有树面板」的可行性，不改 A 的任何文件，不注册到宿主。
- 若 B 渲染验证通过，后续可考虑替换 A 的 magazine 面板；未通过则保留 A。

## 数据模型
会话 id 来自事件累积（V1 API 无 `session.list`），存 `oml_tui_shell.session_ids`（KV 前缀隔离，
不与 A 的 `oml_subagent_magazine` / `oml_cache_panel` 冲突）。父子关系来自 `session.get(sid).parentID`。
树算法见 `tree.ts`；标题格式由注入的 `labelFor` 决定（U1 的 `omo t1←t5 · <描述>` 已可对接）。

## 不做
- 不写 JSX 渲染成品（无 TTY 无法验证，写了也是未验证代码）。
- 不装 solid 依赖、不改宿主 tui.json(c)、不碰 A 的 fork。
