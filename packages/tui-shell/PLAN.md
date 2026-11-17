# B 计划：OML 自有 TUI 外壳（实验分支 experiment/oml-tui-shell）

## 目标
在 A（fork 两插件）之外，验证「OML 自己拥有会话树 TUI 面板」是否可行：
把 subagent 会话按 parentID 组织成树，标题带隶属链，点击可跳到任意会话（完整 session 功能）。

## 现状证据
- V1 TUI API：宿主 1.19.x 经 `~/.config/opencode/tui.json(c)` 的 `plugin` 数组加载 TUI 面板；
  `tui = async (api) => { api.slots.register({order, slots:{sidebar_content(ctx,input){...}}}); api.command?.register(...) }`
  （fork bundle `packages/tui-plugins/subagent-magazine/bundle/tui.js:2411-2461`）。
- 树数据源：无 `session.list` API；面板靠事件累积 session_id，再用 `api.state.session.get(sid)?.parentID`
  判定父子（`bundle/tui.js:488-490`）。会话对象有 `parentID`/`agent`/`status`，标题由调用方给。
- 跳转：`api.route.navigate("session",{sessionID})`（`bundle/tui.js:2247`）。
- solid-js / @opentui/solid 只在插件缓存目录，OML 仓无这两个 devDep；本机无 TTY → 渲染无法自动验证。

## 范围
- 建：`packages/tui-shell/src/{tree,adapter}.ts`（纯逻辑，零外部依赖，Bun 可测）、
  `tree.test.ts`、`plugin.ts`（V1 外壳，Bun.Transpiler 语法校验）、`README.md`。
- 不碰：`packages/tui-plugins/**`（A 的 fork）、`OC/omo/**`、`packages/core/**`、任何 tui.json(c)（不注册到宿主，避免和 A 抢 slot）。
- 不装 solid 依赖、不写 JSX 渲染成品（无 TTY 无法验证，写了也是未验证代码）。

## 步骤
1. tree.ts：flat sessions→带隶属链的树（环/孤儿/dedupe/maxDepth 处理）→ 验收 `bun test tree.test.ts`。
2. adapter.ts：`api.state.session.get` 快照 → SessionNode[] → 验收测试覆盖。
3. plugin.ts：V1 外壳骨架，纯逻辑调用 tree.ts，渲染层留最小已知接口 + 明确 TODO → 验收 Bun.Transpiler 语法合法。
4. README：声明已验证/未验证边界与接入实验步骤。
5. 全量 `bun test` + `typecheck` + `check 7/7` + manifest + 提交到实验分支。

## 依赖顺序
tree → adapter → plugin → docs；每步独立验收，失败续接同会话。

## 回滚
`git checkout master`（B 仅在实验分支，A 在 master 完好）。

## 风险
渲染层无 TTY 不可验证 —— 步骤 3 只保证语法与纯逻辑正确，真实副作用需用户重启 opencode 后目视确认；
README 明确标注「未验证」，不冒充已完成。

## 自检
- [x] 每条结论带路径证据
- [x] 每步有验收命令
- [x] 边界写清「不碰什么」
- [x] 回滚可执行
- [x] 未把研究伪装成实现
- [x] 规模与实验分支匹配
