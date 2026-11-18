/**
 * bridge.test.ts —— OC2 V1→V2 桥接器的结构化断言（用 fake ctx recorder）。
 *
 * 关注点：注册齐全 + 形状双向适配；业务逻辑本身由 OC1 测试覆盖（A4 单一写入者）。
 */
import { describe, it, expect } from "bun:test"
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import type { Hooks } from "@opencode-ai/plugin"
import { OMO_MARKER } from "../../../OC/omo/src/host.ts"
import { createOc2Host } from "./host.ts"
import { bridgeHooks, ALL_V2_TOOL_NAMES, BRIDGE_HOOK_MAP } from "./bridge.ts"
import type {
  Oc2Context,
  V2AgentDomain,
  V2EventDomain,
  V2EventStream,
  V2HookEvent,
  V2PermissionDomain,
  V2SessionDomain,
  V2ToolDomain,
  V2ToolRegistration,
} from "./v2-types.ts"

type StoredHandler = (event: unknown) => void | Promise<void>

interface Recorder {
  tools: V2ToolRegistration[]
  hooks: Array<{ name: string; handler: StoredHandler }>
  subscribes: Array<{ opts?: { signal?: AbortSignal } }>
  agentTransforms: number
  events: unknown[]
  unregistered: string[]
}

function fakeCtx(dir: string): { ctx: Oc2Context; rec: Recorder } {
  const rec: Recorder = {
    tools: [],
    hooks: [],
    subscribes: [],
    agentTransforms: 0,
    events: [],
    unregistered: [],
  }

  const tool: V2ToolDomain = {
    transform(editor) {
      editor({ add: (def) => rec.tools.push(def) })
      return () => undefined
    },
  }
  const session: V2SessionDomain = {
    hook(name, handler) {
      rec.hooks.push({ name, handler: handler as unknown as StoredHandler })
      return () => rec.unregistered.push(name)
    },
  }
  const permission: V2PermissionDomain = {
    hook(name, handler) {
      rec.hooks.push({ name, handler: handler as unknown as StoredHandler })
      return () => rec.unregistered.push(name)
    },
  }
  const agent: V2AgentDomain = {
    transform(editor) {
      rec.agentTransforms += 1
      editor({})
      return () => undefined
    },
  }
  const event: V2EventDomain = {
    subscribe(opts) {
      rec.subscribes.push({ opts })
      const stream: V2EventStream = {
        async *[Symbol.asyncIterator]() {
          yield { type: "session.idle", properties: { sessionID: "s1" } }
        },
      }
      return stream
    },
  }

  return {
    rec,
    ctx: { location: { directory: dir }, tool, session, permission, agent, event },
  }
}

/** 6 个假 V1 tool：execute 分别返回字符串 / {output} / 其它对象，验证归一。 */
function fakeHooks(events: unknown[]): Hooks {
  const make = (execute: (args: Record<string, unknown>) => Promise<unknown>) => ({
    description: "fake tool",
    args: {},
    execute,
  })
  const names = ALL_V2_TOOL_NAMES
  const byName: Record<string, ReturnType<typeof make>> = {
    [names[0]]: make(async () => "plain text"),
    [names[1]]: make(async () => ({ output: "from output" })),
    [names[2]]: make(async () => ({ title: "t", metadata: { m: 1 } })),
  }
  for (const name of names) {
    if (!(name in byName)) byName[name] = make(async () => "ok")
  }
  return {
    tool: byName,
    config: async () => undefined,
    "chat.message": async () => undefined,
    event: async (input: { event: unknown }) => { events.push(input) },
    "permission.ask": async (_input: unknown, output: { status: "ask" | "deny" | "allow" }) => { output.status = "allow" },
    "experimental.chat.system.transform": async () => undefined,
    "experimental.session.compacting": async () => undefined,
  } as unknown as Hooks
}

function withTemp(fn: (dir: string) => Promise<void>): Promise<void> {
  const dir = mkdtempSync(join(tmpdir(), "oc2-bridge-"))
  return fn(dir).finally(() => rmSync(dir, { recursive: true, force: true }))
}

function findHook(rec: Recorder, name: string): StoredHandler {
  const found = rec.hooks.find((h) => h.name === name)
  if (found === undefined) throw new Error(`未注册 hook: ${name}`)
  return found.handler
}

describe("OC2 bridgeHooks（理论映射）", () => {
  it("BRIDGE_HOOK_MAP 覆盖全部 7 个 V1 hook 位", () => {
    expect(Object.keys(BRIDGE_HOOK_MAP).sort()).toEqual(
      [
        "tool",
        "chat.message",
        "experimental.chat.system.transform",
        "experimental.session.compacting",
        "permission.ask",
        "event",
        "config",
      ].sort(),
    )
    expect(BRIDGE_HOOK_MAP["experimental.chat.system.transform"]).toContain("context")
  })

  it("(a) 6 个 tool 全注册，execute 归一为 {content}", async () => {
    await withTemp(async (dir) => {
      const { ctx, rec } = fakeCtx(dir)
      const fake = fakeHooks(rec.events)
      await bridgeHooks(ctx, fake)

      expect(rec.tools.map((t) => t.name).sort()).toEqual([...ALL_V2_TOOL_NAMES].sort())
      const byName = new Map(rec.tools.map((t) => [t.name, t]))
      const task = byName.get("omo_task")
      const knowledge = byName.get("omo_knowledge")
      const admin = byName.get("omo_admin")
      if (!task || !knowledge || !admin) throw new Error("工具缺失")

      expect(await task.execute({})).toEqual({ content: "plain text" })
      expect(await knowledge.execute({})).toEqual({ content: "from output" })
      expect(await admin.execute({})).toEqual({ content: JSON.stringify({ title: "t", metadata: { m: 1 } }) })
      // 每个注册都带 JSON Schema（理论：仅字段名）
      expect(rec.tools.every((t) => t.input && (t.input as Record<string, unknown>)["type"] === "object")).toBe(true)
    })
  })

  it("(b) system transform：V2 对象数组 → V1 string[] → 写回对象数组（marker 注入 + 技能剥离）", async () => {
    await withTemp(async (dir) => {
      mkdirSync(join(dir, "skills", "demo"), { recursive: true })
      writeFileSync(
        join(dir, "skills", "demo", "SKILL.md"),
        "---\nname: demo\ndescription: demo\n---\n# Demo\n",
      )
      const realHooks = await createOc2Host(
        { directory: dir, client: {} },
        { config: {}, skillRoots: [join(dir, "skills")], stateDir: join(dir, "state") },
      )
      const { ctx, rec } = fakeCtx(dir)
      await bridgeHooks(ctx, realHooks)

      const event: V2HookEvent = {
        sessionID: "s1",
        system: [
          { type: "text", text: "base system prompt" },
          { type: "text", text: "<available_skills><skill><name>demo</name></skill></available_skills>" },
        ],
      }
      await findHook(rec, "context")(event)

      expect(Array.isArray(event.system)).toBe(true)
      expect(event.system?.every((p) => p.type === "text" && typeof p.text === "string")).toBe(true)
      const texts = (event.system ?? []).map((p) => p.text)
      expect(texts.some((t) => t.includes(OMO_MARKER))).toBe(true)
      expect(texts.some((t) => t.includes("<available_skills>"))).toBe(false)
      expect(texts.some((t) => t.includes("base system prompt"))).toBe(true)

      // 防御分支：即便 V2 传的是 string[]，也应归一后再写回对象数组。
      const stringEvent = {
        sessionID: "s2",
        system: ["plain base"],
      }
      await findHook(rec, "context")(stringEvent as unknown as V2HookEvent)
      expect((stringEvent.system as unknown[]).every((p) => typeof p === "object" && p !== null)).toBe(true)
      expect((stringEvent.system as unknown as Array<{ text: string }>).some((p) => p.text.includes(OMO_MARKER))).toBe(true)
    })
  })

  it("(c) prompt / compaction / evaluate / config 都注册", async () => {
    await withTemp(async (dir) => {
      const { ctx, rec } = fakeCtx(dir)
      const fake = fakeHooks(rec.events)
      await bridgeHooks(ctx, fake)

      const names = rec.hooks.map((h) => h.name)
      expect(names.filter((n) => n === "prompt")).toHaveLength(1)
      expect(names.filter((n) => n === "context")).toHaveLength(1)
      expect(names.filter((n) => n === "compaction")).toHaveLength(1)
      expect(names.filter((n) => n === "evaluate")).toHaveLength(1)
      expect(rec.agentTransforms).toBe(1)

      // prompt 适配：V2 event → V1 (input, output)
      await findHook(rec, "prompt")({ sessionID: "s1", agent: "sisyphus", parts: [{ type: "text", text: "hi" }] })

      // compaction 适配：context 对象数组 → string[]，写回保持对象数组
      const compactEvent: V2HookEvent = { sessionID: "s1", context: [{ type: "text", text: "ctx" }] }
      await findHook(rec, "compaction")(compactEvent)
      expect(compactEvent.context?.every((p) => typeof p === "object" && p !== null)).toBe(true)

      // evaluate 适配：V1 改 output.status → V2 改 event.status
      const perm: { sessionID: string; status: "ask" | "deny" | "allow" } = { sessionID: "s1", status: "ask" }
      await findHook(rec, "evaluate")(perm)
      expect(perm.status).toBe("allow")
    })
  })

  it("(d) event.subscribe 被调用且 cleanup 存在并可注销", async () => {
    await withTemp(async (dir) => {
      const { ctx, rec } = fakeCtx(dir)
      const cleanup = await bridgeHooks(ctx, fakeHooks(rec.events))

      expect(rec.subscribes).toHaveLength(1)
      expect(rec.subscribes[0]?.opts?.signal).toBeInstanceOf(AbortSignal)
      expect(typeof cleanup).toBe("function")
      // 让后台 async 迭代消费掉 fake stream 的那一条事件
      await new Promise((resolve) => setTimeout(resolve, 0))
      expect(rec.events.length).toBeGreaterThanOrEqual(1)

      cleanup()
      expect(controllerAborted(rec.subscribes[0]?.opts?.signal)).toBe(true)
      expect(rec.unregistered).toContain("prompt")
    })
  })
})

function controllerAborted(signal: AbortSignal | undefined): boolean {
  return signal?.aborted === true
}
