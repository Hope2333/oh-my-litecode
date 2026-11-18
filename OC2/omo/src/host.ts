/**
 * OC2（OpenCode 2.x）前线 —— 适配层。
 *
 * **不再返回空钩子**：形状差异收敛在 `dialect.ts`，实现直接委托 OC 前线的
 * `createOmoHost`。这样「两个前线」在 2.x 发布前是同一份实现 + 一层可替换的
 * 翻译，而不是一份实现 + 一份死代码。
 *
 * 为什么可以共用：上游探测显示 2.x 尚不存在，`dev` 通道的 hook 键集合与
 * 1.19.5 逐字相同（见 `dialect.ts` 的 OC2_DIFFS）。真正分歧出现时，只需让
 * `createOc2Host` 自己装配钩子，调用方零改动。
 *
 * 公理 A4：本文件只做协议翻译与委托，不含业务逻辑。目标 ≤120 行。
 */

import type { Hooks } from "@opencode-ai/plugin"
import { createHostCore, createOmoHost, type OmoHostOptions } from "../../../OC/omo/src/host.ts"
import type { TaskClient } from "../../../OC/omo/src/client.ts"
import { toV1Input } from "./dialect.ts"

const TASK_CLIENT_METHODS = [
  "createSession",
  "renameSession",
  "promptSession",
  "abortSession",
  "lastAssistantText",
  "listSessions",
  "deleteSession",
] as const

/** 鸭子类型判定：client 已经是 ctx-backed TaskClient（V2 setup 路径）。 */
function isTaskClient(value: unknown): value is TaskClient {
  if (value === null || typeof value !== "object") return false
  const obj = value as Record<string, unknown>
  return TASK_CLIENT_METHODS.every((name) => typeof obj[name] === "function")
}

/**
 * 创建 OC2 宿主。
 *
 * 两条路径，业务逻辑都只在 OC1 的 createHostCore（A4 单一写入者）：
 * - V1 `server()` 路径：SDK client → `createOmoHost`（内部经 sdkTaskClient 包装）。
 * - V2 `setup(ctx)` 路径：client 已是 ctx-backed TaskClient → 直接 `createHostCore`，
 *   避免被 `sdkTaskClient` 二次包装成调用 `client.session.*`（TaskClient 无此属性）。
 *
 * @param raw OC2 传给插件的 input（形状未定，故收 unknown 后校验）
 * @param options 与 OC 同名的宿主选项；真机上留空，测试里用来指定临时目录
 */
export async function createOc2Host(
  raw: unknown,
  options?: OmoHostOptions,
): Promise<Hooks> {
  const input = toV1Input(raw)
  const client: unknown = input.client
  if (isTaskClient(client)) {
    return createHostCore({ directory: input.directory, client }, options)
  }
  return createOmoHost(input, options)
}

export type { OmoHostOptions }
