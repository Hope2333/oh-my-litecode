/**
 * OC2（OpenCode 2.x）V1→V2 桥接器。
 *
 * 把 OC1 `createHostCore` 返回的 7 个 V1 hook + 6 个 tool 注册到 V2 `ctx` 的
 * domain API 上。本文件**只做形状翻译**，不含任何 OML 业务逻辑（A4 单一写入者）。
 * 所有 V2 调用都是理论映射，未真机验证；签名缺失/不确定处抛 informative throw，
 * 绝不空 catch / any / ts-ignore。
 */
import type { Hooks, ToolContext } from "@opencode-ai/plugin"
import type {
  Oc2Context,
  V2Cleanup,
  V2HookEvent,
  V2PermissionEvent,
  V2Registration,
  V2SystemPart,
  V2ToolContext,
  V2ToolRegistration,
} from "./v2-types.ts"

type V1Tool = NonNullable<Hooks["tool"]>[string]

/** 6 个 OML 工具名（测试与契约断言的权威集合）。 */
export const ALL_V2_TOOL_NAMES = [
  "omo_task",
  "omo_knowledge",
  "omo_admin",
  "omo_mcp",
  "omo_channel",
  "skill",
] as const

/** V1 hook → V2 注册位的映射表（供测试断言，亦作文档）。 */
export const BRIDGE_HOOK_MAP = {
  tool: "ctx.tool.transform(editor => editor.add(...))",
  "chat.message": "ctx.session.hook('prompt', ...)",
  "experimental.chat.system.transform": "ctx.session.hook('context', ...)",
  "experimental.session.compacting": "ctx.session.hook('compaction', ...)",
  "permission.ask": "ctx.permission.hook('evaluate', ...)",
  event: "ctx.event.subscribe({ signal })",
  config: "ctx.agent.transform(...)",
} as const

export interface BridgeOptions {
  /** 记录理论映射/无法安全应用项的回调；缺省 console.debug。 */
  log?: (message: string) => void
}

function requireDomain<T>(value: T | undefined, name: string): T {
  if (value === undefined) {
    throw new Error(`OC2 理论插件：ctx.${name} 签名待真机确认 —— domain 缺失，无法完成 V1→V2 注册（未伪装成功）`)
  }
  return value
}

/** V1 ToolContext 由 V2 工具上下文投影；缺省值不伪造业务语义，仅满足形状。 */
function toV1ToolContext(pluginCtx: Oc2Context, v2: V2ToolContext | undefined): ToolContext {
  const directory = v2?.directory ?? v2?.worktree ?? pluginCtx.location.directory
  return {
    sessionID: v2?.sessionID ?? "",
    messageID: v2?.messageID ?? "",
    agent: v2?.agent ?? "",
    directory,
    worktree: v2?.worktree ?? directory,
    abort: v2?.abort ?? new AbortController().signal,
    metadata: v2?.metadata ?? (() => undefined),
    ask: v2?.ask ?? (async () => undefined),
  }
}

/** V1 execute 返回 string | {output} → V2 要求的 `{content:string}`。 */
function normalizeToolResult(result: unknown): { content: string } {
  if (typeof result === "string") return { content: result }
  if (result !== null && typeof result === "object") {
    const obj = result as Record<string, unknown>
    if ("output" in obj) {
      const out = obj["output"]
      if (typeof out === "string") return { content: out }
      const serializedOut = JSON.stringify(out)
      return { content: typeof serializedOut === "string" ? serializedOut : "" }
    }
  }
  const serialized = JSON.stringify(result)
  return { content: typeof serialized === "string" ? serialized : "" }
}

/** V1 tool 的 zod args → V2 JSON Schema（理论：只还原字段名，类型待真机确认）。 */
function jsonSchemaFor(def: V1Tool): Record<string, unknown> {
  const properties: Record<string, unknown> = {}
  const args = def.args
  if (args !== null && typeof args === "object") {
    for (const key of Object.keys(args)) properties[key] = {}
  }
  return {
    type: "object",
    description: def.description,
    properties,
    "x-oml-theoretical": "V1 zod args → V2 JSON Schema 仅还原字段名，字段类型待真机确认",
  }
}

/** V2 `event.system` 对象数组 → V1 string[]。 */
function systemPartsToStrings(parts: V2SystemPart[] | string[] | undefined): string[] {
  if (!Array.isArray(parts)) return []
  return parts.map((p) => {
    if (typeof p === "string") return p
    return typeof p.text === "string" ? p.text : ""
  })
}

/** V1 string[] → V2 `{type:"text",text}[]`（system 写回固定用对象数组）。 */
function stringsToSystemParts(strings: string[]): V2SystemPart[] {
  return strings.map((text) => ({ type: "text", text }))
}

/** compaction 的 context 写回：保持输入形状（V2 可能是 string[] 或对象数组）。 */
function writeBackContext(original: V2SystemPart[] | string[] | undefined, next: string[]): V2SystemPart[] | string[] {
  const first = Array.isArray(original) ? original[0] : undefined
  if (typeof first === "string") return next
  return stringsToSystemParts(next)
}

/**
 * 把 V1 hooks 注册到 V2 ctx。
 *
 * @returns 合并后的 cleanup 函数：调用后 abort 事件订阅并注销各 domain hook。
 */
export async function bridgeHooks(ctx: Oc2Context, hooks: Hooks, options: BridgeOptions = {}): Promise<V2Cleanup> {
  const cleanups: V2Cleanup[] = []
  const log = options.log ?? ((message: string) => console.debug(message))
  const collect = async (reg: V2Registration): Promise<void> => {
    const value = await reg
    if (typeof value === "function") cleanups.push(value)
  }

  // ── 6 个 tool：ctx.tool.transform ────────────────────────────────────
  const toolDomain = requireDomain(ctx.tool, "tool")
  const v1Tools = hooks.tool ?? {}
  await collect(
    toolDomain.transform((editor) => {
      for (const [name, def] of Object.entries(v1Tools)) {
        const registration: V2ToolRegistration = {
          name,
          description: def.description,
          input: jsonSchemaFor(def),
          async execute(args, v2ctx) {
            const result = await def.execute(args, toV1ToolContext(ctx, v2ctx))
            return normalizeToolResult(result)
          },
        }
        editor.add(registration)
      }
    }),
  )

  // ── session.hook × 3：prompt / context / compaction ───────────────────
  const session = requireDomain(ctx.session, "session")

  if (hooks["chat.message"]) {
    const v1 = hooks["chat.message"]
    await collect(
      session.hook("prompt", (event: V2HookEvent) => {
        const input = {
          sessionID: event.sessionID ?? "",
          ...(event.agent ? { agent: event.agent } : {}),
          ...(event.messageID ? { messageID: event.messageID } : {}),
          ...(event.model ? { model: event.model } : {}),
          ...(event.variant ? { variant: event.variant } : {}),
        } as unknown as Parameters<typeof v1>[0]
        const output = {
          message: event.message,
          parts: event.parts ?? [],
        } as unknown as Parameters<typeof v1>[1]
        return v1(input, output)
      }),
    )
  }

  if (hooks["experimental.chat.system.transform"]) {
    const v1 = hooks["experimental.chat.system.transform"]
    await collect(
      session.hook("context", (event: V2HookEvent) => {
        // V2 event.system = {type,text}[] → V1 string[] → V1 hook（注入 marker / 剥离技能）→ 写回对象数组。
        const strings = systemPartsToStrings(event.system)
        const output = { system: strings }
        const input = {
          sessionID: event.sessionID,
          model: event.model,
        } as unknown as Parameters<typeof v1>[0]
        return Promise.resolve(v1(input, output)).then(() => {
          event.system = stringsToSystemParts(output.system)
        })
      }),
    )
  }

  if (hooks["experimental.session.compacting"]) {
    const v1 = hooks["experimental.session.compacting"]
    await collect(
      session.hook("compaction", (event: V2HookEvent) => {
        const strings = systemPartsToStrings(event.context)
        const output = { context: strings, ...(event.prompt !== undefined ? { prompt: event.prompt } : {}) }
        const input = { sessionID: event.sessionID ?? "" } as unknown as Parameters<typeof v1>[0]
        return Promise.resolve(v1(input, output)).then(() => {
          event.context = writeBackContext(event.context, output.context)
        })
      }),
    )
  }

  // ── permission.ask：ctx.permission.hook("evaluate") ──────────────────
  const permission = requireDomain(ctx.permission, "permission")
  if (hooks["permission.ask"]) {
    const v1 = hooks["permission.ask"]
    await collect(
      permission.hook("evaluate", (event: V2PermissionEvent) => {
        const output = { status: event.status }
        const input = { ...event } as unknown as Parameters<typeof v1>[0]
        // V1 改 output.status，V2 改 event.status —— 双向对齐。
        return Promise.resolve(v1(input, output)).then(() => {
          event.status = output.status
        })
      }),
    )
  }

  // ── event：ctx.event.subscribe({signal}) 异步迭代 ─────────────────────
  if (hooks.event) {
    const v1 = hooks.event
    const eventDomain = requireDomain(ctx.event, "event")
    const controller = new AbortController()
    const stream = await eventDomain.subscribe({ signal: controller.signal })
    void (async () => {
      for await (const ev of stream) {
        if (controller.signal.aborted) break
        const input = { event: ev } as unknown as Parameters<typeof v1>[0]
        await v1(input)
      }
    })().catch((err: unknown) => {
      log(`[OC2] event 订阅循环异常（理论插件）：${err instanceof Error ? err.message : String(err)}`)
    })
    cleanups.push(() => controller.abort())
  }

  // ── config：V2 无全局 config，尽力映射到 ctx.agent.transform ──────────
  // 注意：config 的权限（cfg.permission）与 default_agent 部分 V2 无对应全局对象，
  // 属理论映射 —— 仅 agent 部分被消费，其余只记录、不抛、不伪装成功。
  if (hooks.config) {
    const v1 = hooks.config
    try {
      const agent = requireDomain(ctx.agent, "agent")
      await collect(
        agent.transform((agents) => {
          const cfg = { agent: agents } as unknown as Parameters<typeof v1>[0]
          return Promise.resolve(v1(cfg)).then(() => {
            const applied = (cfg as Record<string, unknown>)["agent"]
            if (applied !== null && typeof applied === "object") {
              for (const [key, value] of Object.entries(applied as Record<string, unknown>)) agents[key] = value
            }
          })
        }),
      )
    } catch (err) {
      log(
        `[OC2] config→ctx.agent.transform 理论映射未应用（权限/default_agent 部分 V2 无对应全局对象）：` +
          `${err instanceof Error ? err.message : String(err)}`,
      )
    }
  }

  return () => {
    for (const cleanup of cleanups) cleanup()
  }
}
