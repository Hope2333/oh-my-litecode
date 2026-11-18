/**
 * OC1 → OC2 协议方言。
 *
 * 这是两个前线之间**唯一**允许有分歧的地方（A4：单一写入者）。适配层只做
 * 形状翻译，不含业务逻辑：预算、索引、编排、任务账本全在 `@oml/core`。
 *
 * ## 真机结论更新（2026-11-18，推翻下方旧假设）
 *
 * 2.x **已经发布**：`@opencode/cli` 2.3.0（独立 ELF，下载到 /tmp/oc2-bin 隔离测试，
 * 生产 /usr/bin/opencode 1.19.3 未动）。原「不存在 2.x / 恒等映射」假设被真机证伪：
 * V1 插件函数导出在 2.x 上直接被拒，日志原文：
 *   `Plugin must export a default definition with an id and an effect or setup
 *    function. (cause: SchemaError(Expected object at ["default"]))`
 * 对象导出（id+setup/effect）、配置键 `plugin`→`plugins`、本地路径必须是目录、
 * hook 从「返回 hook 映射」改成 `ctx.session.hook("context")`/`ctx.tool.transform(...)`
 * 等领域方法（官方文档 opencode.ai/docs/build/plugins/migrate-v1）。真机对照：
 * 函数导出的 omo.ts 加载失败；最小对象导出插件加载成功（无 "failed to load"）。
 *
 * **因此当前 toV1Input 恒等映射在 2.x 真机不可用**：这不是改 hook 键能修的，
 * 而是整套插件 API 换了。完整 V2 适配是独立任务（见 README「V2 移植待办」），
 * 未做前 OC2 前线只能保证 1.x 语义 + 契约测试，不能宣称 2.x 可用。
 *
 * 下方 6 条 DIFF 保留为历史探针记录（发布前写的「怎么验」），其中 DIFF-6 已被
 * 真机证实发生（且方向相反：不是「允许对象导出」而是「必须对象导出」）。
 */

import type { PluginInput } from "@opencode-ai/plugin"

/** 已知分歧点（发布前探针）。DIFF-6 已由 2.3.0 真机证实，且方向与预测相反。 */
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
    topic: "插件模块导出契约【2.3.0 真机已证实】",
    current: "每个运行时导出都必须是函数（否则整插件被丢弃）",
    observed: "2.x 要求 default 导对象 {id, setup|effect}；函数导出被拒并报 SchemaError at [\"default\"]。方向与此条发布前预测相反。",
    fix: "改 index.ts 为 Plugin.define({id:'oml.oc2', setup}) 对象导出；但 V2 的 ctx 领域 API 与 V1 返回 hook 映射不同，整套适配是独立任务，未做。",
    verify: "2.3.0 真机：函数导出 omo.ts 报 'Plugin must export a default definition with an id'；最小对象导出插件加载成功（无 failed to load）",
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
