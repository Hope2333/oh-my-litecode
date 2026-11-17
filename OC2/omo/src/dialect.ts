/**
 * OC1 → OC2 协议方言。
 *
 * 这是两个前线之间**唯一**允许有分歧的地方（A4：单一写入者）。适配层只做
 * 形状翻译，不含业务逻辑：预算、索引、编排、任务账本全在 `@oml/core`。
 *
 * 上游探测结论（2026-11-15，`registry.npmjs.org/-/package/@opencode-ai/plugin/dist-tags`）：
 *   latest = 1.19.5   dev = 0.0.0-dev-202611092046   beta = 0.0.0-beta-19271
 * **不存在 2.x 版本线**；`dev` 通道的 `dist/index.d.ts` 里 14 个 hook 键与 1.19.5
 * 逐字相同（含 `experimental.chat.system.transform`、`experimental.session.compacting`、
 * `tool`）。因此当前翻译是恒等映射，而下面每条 DIFF 都留了「发布后怎么验」。
 *
 * 一旦 2.x 出现，只改本文件 + 跑 `bun test OC2`，内核与 OC 前线不动。
 */

import type { PluginInput } from "@opencode-ai/plugin"

/** 已知分歧点。当前全部未发生（2.x 未发布），保留以说明「改哪里、怎么验」。 */
export const OC2_DIFFS = [
  {
    id: "DIFF-1",
    topic: "系统提示 hook 的键名",
    current: "experimental.chat.system.transform",
    ifChanged: "去掉 experimental. 前缀 → 在 toV1Input 之后重命名 hook 键",
    verify: "在 2.x 真机打印 Object.keys(hooks)，确认键名集合",
  },
  {
    id: "DIFF-2",
    topic: "system 载荷形状",
    current: "output.system: string[]",
    ifChanged: "若变成 string → system.transform 包装层 join/拆分",
    verify: "真机 typeof output.system",
  },
  {
    id: "DIFF-3",
    topic: "工具注册方式",
    current: "hooks.tool 映射（键名=工具名）",
    ifChanged: "若改命令式 registerTool → 在 host.ts 里换注册路径",
    verify: "读 2.x Hooks 接口是否仍有 tool 字段",
  },
  {
    id: "DIFF-4",
    topic: "PluginInput 字段",
    current: "directory / client / worktree / serverUrl / $",
    ifChanged: "缺 directory 或 client 时映射到等价字段",
    verify: "真机打印 Object.keys(input)",
  },
  {
    id: "DIFF-5",
    topic: "压缩 hook 载荷",
    current: "output.context: string[]",
    ifChanged: "若变单字符串 → push 改拼接",
    verify: "真机触发压缩，看 output 类型",
  },
  {
    id: "DIFF-6",
    topic: "插件模块导出契约",
    current: "每个运行时导出都必须是函数（否则整插件被丢弃）",
    ifChanged: "若 2.x 允许对象导出 → 可省掉 index.ts 的三行转发",
    verify: "故意多导出一个常量，看 2.x 是否报 Plugin export is not a function",
  },
] as const

/**
 * 把 OC2 的输入翻译成 OC1 的 `PluginInput`。
 *
 * 现在 2.x 未发布，形状一致，函数只做**校验**：缺 `directory` 或 `client` 就
 * 立刻抛错，而不是带着半个上下文跑起来——那种失败会推迟到第一次派任务时，
 * 排查成本高一个量级。
 */
export function toV1Input(raw: unknown): PluginInput {
  if (typeof raw !== "object" || raw === null) {
    throw new Error("OC2 适配层：插件输入不是对象")
  }
  const input = raw as Record<string, unknown>
  const directory = input["directory"]
  if (typeof directory !== "string" || directory === "") {
    throw new Error("OC2 适配层：输入缺少 directory（见 OC2_DIFFS/DIFF-4）")
  }
  const client = input["client"]
  if (typeof client !== "object" || client === null) {
    throw new Error("OC2 适配层：输入缺少 client（见 OC2_DIFFS/DIFF-4）")
  }
  return input as unknown as PluginInput
}
