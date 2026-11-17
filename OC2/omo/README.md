# OC2/omo —— OpenCode 2.x 前线适配层（骨架）

## 现状

**骨架阶段，未在 OC2 真机验证。** OC2 的插件 API（`@opencode-ai/plugin` 2.x）
尚未在本机安装，因此本目录**不 import** `@opencode-ai/plugin`，只依赖
`host.ts` 内定义的结构性最小接口 `Oc2HooksLike`（鸭子类型）。

实现遵循 A4（民主集中制）：本目录只做**协议翻译** —— 把 OC2 的 hook 形状
翻译成内核 `PluginHost`（`packages/core/src/contract.ts`），**不含业务逻辑**。
预算 / 技能索引 / 编排全在 `@oml/core`。代码量目标 ≤300 行（`host.ts` +
`index.ts`）。

## 文件

| 文件 | 职责 |
|---|---|
| `src/host.ts` | `Oc2HooksLike` 结构接口 + `createOmoHost(hooks): PluginHost` |
| `src/index.ts` | 导出与 OC 前线同名同形的 `OmoPlugin`、`createOmoHost` |
| `src/contract.test.ts` | 断言 OC 与 OC2 两前线导出面一致 |

## 已知 / 预期差异点（OC1 → OC2）

详见 `src/host.ts` 头部 `// OC2-DIFF:` 注释。摘要：

1. **hook 键名**：`experimental.chat.system.transform` 可能去掉
   `experimental.` 前缀 → 验证：真机 dump hook 键集合。
2. **system 载荷**：`output.system` 可能由 `string[]` 改为 `string`
   → 验证：真机打印 `typeof output.system`。
3. **tool 注册**：`hooks.tool` 映射可能改为命令式 `registerTool()`
   → 验证：查 OC2 的 `Hooks` / `Plugin` 类型是否仍有 `tool?` 字段。
4. **Plugin 入口签名**：`PluginInput` 字段可能变化
   → 验证：读 OC2 发布的 `Plugin` / `PluginInput` 定义。

## 验证方式

```bash
cd /home/miao/Projects/OML
bun test OC2/omo                                    # 契约测试
bun ./node_modules/typescript/lib/tsc.js -p tsconfig.json --noEmit   # 零报错
```

- 契约测试：`OC/omo` 未实现时 `test.skip` 并打印原因，不 fail。
- OC2 发布后：按 `OC2-DIFF` 逐条在真机核实，把 `Oc2HooksLike` 收紧为
  真实类型、把占位实现替换为真实映射，内核零改动。

## 未验证假设

| 假设 | 验证所需 |
|---|---|
| OC2 仍有 `event` / `chat.message` / system-transform hook | OC2 真机 + 官方 `.d.ts` |
| `chat.message` 的 `output.parts` 含可写 `text` 段 | 真机触发并回填 |
| `hooks.tool[name].execute` 的返回/异常约定 | OC2 工具定义文档 |
| OC2 是否暴露 agent 注册通道（config 回调？） | OC2 `config` hook 形状 |
| 技能目录根由宿主提供还是 config | OC2 文件系统 API |
