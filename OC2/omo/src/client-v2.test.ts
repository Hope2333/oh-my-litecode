/**
 * clientFromContext —— 基于真机 2.3.0 证据的 OC2 `ctx.session.*` 映射测试。
 *
 * 覆盖：构造不抛错；七方法各自映射到正确的 session 方法；返回体「直接 body」与
 * `{data:}` 两种外壳；能力缺失时在调用时才 informative throw（不伪装成功）；
 * 真机不存在的 messages/abort/delete 永不被调用。
 */
import { describe, expect, it } from "bun:test"
import { clientFromContext } from "./client-v2.ts"
import type { Oc2Context, V2SessionDomain } from "./v2-types.ts"

type Call = { name: string; input: Record<string, unknown> }

function fakeSession(opts: {
  calls: Call[]
  wrap?: boolean
  omit?: string[]
  overrides?: Record<string, (input: Record<string, unknown>) => Promise<unknown>>
}): V2SessionDomain {
  const { calls, wrap = false, omit = [], overrides = {} } = opts
  const ret = (value: unknown): unknown => (wrap ? { data: value } : value)
  const method = (name: string, result: unknown) => (input: Record<string, unknown>): Promise<unknown> => {
    calls.push({ name, input })
    return Promise.resolve(ret(result))
  }
  const session: Record<string, (input: Record<string, unknown>) => Promise<unknown>> = {
    create: method("create", { id: "new-1" }),
    update: method("update", {}),
    prompt: method("prompt", {
      parts: [{ type: "text", text: "pong" }],
      info: { tokens: { input: 3, output: 5 } },
    }),
    interrupt: method("interrupt", {}),
    get: method("get", { parts: [{ type: "text", text: "last answer" }], info: { role: "assistant" } }),
    list: method("list", [
      { id: "s1", title: "T", directory: "/d", parentID: "p", tokens: { cache: { read: 7 } } },
    ]),
    remove: method("remove", {}),
    // 真机没有的旧方法：若被调用立刻抛，证明映射走的是新方法。
    abort: () => Promise.reject(new Error("session.abort 不应被调用")),
    messages: () => Promise.reject(new Error("session.messages 不应被调用")),
    delete: () => Promise.reject(new Error("session.delete 不应被调用")),
  }
  for (const name of omit) delete session[name]
  Object.assign(session, overrides)
  return session as unknown as V2SessionDomain
}

function ctxWith(session: V2SessionDomain): Oc2Context {
  return { location: { directory: "/tmp" }, session } as unknown as Oc2Context
}

async function driveAll(client: ReturnType<typeof clientFromContext>): Promise<{
  created: { id: string }
  last: string
  list: ReturnType<ReturnType<typeof clientFromContext>["listSessions"]> extends Promise<infer L> ? L : never
}> {
  const created = await client.createSession({ title: "t", directory: "/d", parentID: "p" })
  await client.renameSession({ sessionId: "s1", title: "r", directory: "/d" })
  await client.promptSession({ sessionId: "s1", text: "ping" })
  await client.abortSession({ sessionId: "s1" })
  const last = await client.lastAssistantText({ sessionId: "s1" })
  const list = await client.listSessions()
  await client.deleteSession({ sessionId: "s1", directory: "/d" })
  return { created, last, list }
}

describe("clientFromContext（OC2 真机 2.3.0 ctx.session 映射）", () => {
  it("构造期不校验任何 session 方法：空 session / 无 session 都不抛", () => {
    expect(() => clientFromContext({ location: { directory: "/tmp" }, session: {} } as unknown as Oc2Context)).not.toThrow()
    expect(() => clientFromContext({ location: { directory: "/tmp" } } as unknown as Oc2Context)).not.toThrow()
  })

  it("七方法各自映射到正确的 session 方法，且返回值正确（直接 body）", async () => {
    const calls: Call[] = []
    const client = clientFromContext(ctxWith(fakeSession({ calls })))
    const { created, last, list } = await driveAll(client)

    expect(calls.map((c) => c.name)).toEqual([
      "create", "update", "prompt", "interrupt", "get", "list", "remove",
    ])
    expect(created).toEqual({ id: "new-1" })
    expect(last).toBe("last answer")
    expect(list[0]).toMatchObject({ id: "s1", title: "T", directory: "/d", parentID: "p", tokens: { cache: { read: 7 } } })

    // 需要 sessionID 的方法确实带上了 id；prompt 带上了 parts。
    for (const name of ["update", "prompt", "interrupt", "get", "remove"]) {
      const call = calls.find((c) => c.name === name)
      expect(call?.input["sessionID"] ?? call?.input["id"]).toBe("s1")
    }
    const promptCall = calls.find((c) => c.name === "prompt")
    expect(promptCall?.input["parts"]).toEqual([{ type: "text", text: "ping" }])
  })

  it("兼容 {data:X} 外壳：七方法返回值与直接 body 一致", async () => {
    const calls: Call[] = []
    const client = clientFromContext(ctxWith(fakeSession({ calls, wrap: true })))
    const { created, last, list } = await driveAll(client)
    expect(calls.map((c) => c.name)).toEqual([
      "create", "update", "prompt", "interrupt", "get", "list", "remove",
    ])
    expect(created).toEqual({ id: "new-1" })
    expect(last).toBe("last answer")
    expect(list[0]).toMatchObject({ id: "s1", title: "T" })
  })

  it("promptSession 把 token/tool 用量透传，遇 error 返回 {text:'',error}", async () => {
    const calls: Call[] = []
    let client = clientFromContext(ctxWith(fakeSession({ calls })))
    expect(await client.promptSession({ sessionId: "s1", text: "x" })).toMatchObject({
      text: "pong",
      tokens: { input: 3, output: 5 },
      toolUses: 0,
    })

    const errSession = fakeSession({
      calls,
      overrides: {
        prompt: () => Promise.resolve({ error: { message: "boom" } }),
      },
    })
    client = clientFromContext(ctxWith(errSession))
    expect(await client.promptSession({ sessionId: "s1", text: "x" })).toEqual({ text: "", error: "boom" })
  })

  it("lastAssistantText 兼容 V1 messages 数组形状（session.get 直接返回数组）", async () => {
    const calls: Call[] = []
    const session = fakeSession({
      calls,
      overrides: {
        get: (input: Record<string, unknown>) => {
          calls.push({ name: "get", input })
          return Promise.resolve([
            { info: { role: "user" }, parts: [{ type: "text", text: "q" }] },
            { info: { role: "assistant" }, parts: [{ type: "text", text: "a1" }, { type: "text", text: "a2" }] },
          ])
        },
      },
    })
    const text = await clientFromContext(ctxWith(session)).lastAssistantText({ sessionId: "s1" })
    expect(text).toBe("a1\na2")
    expect(calls.map((c) => c.name)).toEqual(["get"])
  })

  it("能力缺失时构造仍成功，只有调用对应方法才 informative throw", async () => {
    const omit = ["create", "update", "prompt", "interrupt", "get", "list", "remove"]
    const ctx = ctxWith(fakeSession({ calls: [], omit }))
    let client: ReturnType<typeof clientFromContext>
    expect(() => { client = clientFromContext(ctx) }).not.toThrow()
    // 上一行的赋值在箭头函数内，TS 可能认为未确定初始化；此处重新取一份供调用。
    client = clientFromContext(ctx)

    const cases: Array<{ name: string; run: () => Promise<unknown> }> = [
      { name: "create", run: () => client.createSession({ title: "t", directory: "/d" }) },
      { name: "update", run: () => client.renameSession({ sessionId: "s1", title: "r", directory: "/d" }) },
      { name: "prompt", run: () => client.promptSession({ sessionId: "s1", text: "x" }) },
      { name: "interrupt", run: () => client.abortSession({ sessionId: "s1" }) },
      { name: "get", run: () => client.lastAssistantText({ sessionId: "s1" }) },
      { name: "list", run: () => client.listSessions() },
      { name: "remove", run: () => client.deleteSession({ sessionId: "s1" }) },
    ]
    for (const { name, run } of cases) {
      await expect(run()).rejects.toThrow(new RegExp(`ctx\\.session\\.${name} 不可用`))
    }
  })

  it("ctx.session 整体缺失时，调用任何方法都 informative throw（非 TypeError）", async () => {
    const client = clientFromContext({ location: { directory: "/tmp" } } as unknown as Oc2Context)
    await expect(client.listSessions()).rejects.toThrow(/ctx\.session\..*不可用/)
  })
})
