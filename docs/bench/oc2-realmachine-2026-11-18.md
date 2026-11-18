# OC2 V2.3.0 真机探测证据（2026-11-18）

> 真机：`/tmp/oc2-bin/@opencode-cli-linux-x64/package/bin/opencode`（opencode v2.3.0，Bun 编译自包含 ELF）。
> 隔离配置：`OPENCODE_CONFIG_DIR=/tmp/oc2-verify` + `OPENCODE_TEST_HOME=/tmp/oc2-verify/home`。
> 模型不可用（openai/gpt-6.2-sol region error）不影响插件加载测试——插件 setup 在 session 启动前发生。

## 加载机制（真机确认）
- 配置 `opencode.json` 的 `plugin` 键被归一化为 `plugins`（debug config 证实）。
- **本地插件路径必须是目录，不能是 .ts 文件**：直接指 `file:///.../index.ts` → 日志 WARN `configured plugin path must be a directory`，插件不加载。
- 目录需 `package.json`（`{"type":"module","exports":"./index.ts"}`）+ `index.ts`，配置指目录 `file:///.../oml-plugin-dir` → 日志 `loading plugin id=... entrypoint=file:///.../index.ts`，成功。
- 插件 default 导出 `{id, setup, server}` 对象：真机 marker 读到 `{keys:["default"], id:"oml.oc2", hasSetup:true, hasServer:true}`（v2-types 的 Plugin.define 恒等助手返回对象正确）。

## 关键缺陷（真机确认，必须修）
**`ctx.client` 不存在**。原 clientFromContext 读 `ctx.client` 立即抛 informative throw → setup 失败 → 日志 `failed to load plugin plugin.id=oml.oc2 cause=... ctx.client 签名待真机确认 —— 上下文未提供 client`。

## 真实 ctx 形状（真机 dump，setup ctx 的 keys）
```
app, location{directory,workspaceID,project}, options, agent{get,list,transform,reload},
aisdk{hook}, command{list,transform,reload}, credential{activate}, event{subscribe},
experimental{terminal,generate,artifact}, generate{text}, model{list,default,transform,reload},
provider{list,get,transform,reload}, integration{...}, mcp{list,transform,reload},
permission{hook,list,get,reply,assert}, plugin{list}, reference{...}, rpc(fn),
skill{list,transform,reload}, storage{get,set,remove,scan}, tool{reload,list,transform,hook},
vcs{...}, websearch{...}, worktree{...}, session{...}, shell{hook}
```
`hasClient: false`。

## ctx.session 真实方法（真机 dump）
keys: `hook, list, create, get, remove, switchAgent, switchModel, prompt, generate, command, compact, synthetic, interrupt, update, move, wait, context, instructions`
- `create/prompt/list/get/remove/update` 都是 **1 参 RPC 包装**：`(i)=>...` 内部 zod decode，返回解码后的 body（无 `{data:}` 外壳）。
- `hook(o,s,t)` 3 参；`messages` **不存在**（undefined）；`abort` 不存在（有 `interrupt`）；`delete` 不存在（有 `remove`）。
- `update` 存在（rename 可行）。

## ctx 其它 domain 真实签名
- `tool.transform(fn)`：fn 收到编辑器 `{list,get,namespace,add,update,...}`；`tool.hook(name,handler)` 2 参。
- `command.transform(fn)`：编辑器 `{add,...}`；`command.list/reload`。
- `agent.transform(fn)`：`transform(s)=>o.transform(t=>s(t))`；`agent.get/list/reload`。
- `permission.hook(name,handler)` 2 参；`permission.list/get/reply/assert`。
- `event.subscribe(handler)`。

## 修复方向
clientFromContext 改为从 `ctx.session.*` 构建 TaskClient：create→session.create、prompt→session.prompt、list→session.list、rename→session.update、delete→session.remove、abort→session.interrupt（或降级 no-op + 注释）、lastAssistantText→session.get（从返回体取 parts/text）。注意 V2 方法 1 参 + 返回解码 body（非 {data:}），要兼容两种形状。
