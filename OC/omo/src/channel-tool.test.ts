/**
 * omo_channel 工具接线测试。
 * 用临时 OML_STATE_DIR + 临时状态目录，绝不污染真实状态；假 TaskClient 记录子会话 prompt 以验证注入。
 */
import { describe, test, expect, beforeEach, afterAll } from "bun:test"
import type { ToolContext } from "@opencode-ai/plugin"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { createHostCore } from "./host.ts"
import { loadBoard } from "@oml/core/channel/board.ts"
import type { TaskClient } from "./client.ts"

type FakeClient = TaskClient & {
  prompts: Array<{ sessionId: string; text: string }>
}

function fakeClient(): FakeClient {
  const prompts: Array<{ sessionId: string; text: string }> = []
  return {
    prompts,
    async createSession({ title }) {
      return { id: `ses_${prompts.length + 1}_${title.length}` }
    },
    async renameSession() {},
    async promptSession(input) {
      prompts.push({ sessionId: input.sessionId, text: input.text })
      return { text: "子会话完成" }
    },
    async abortSession() {},
    async lastAssistantText() {
      return ""
    },
    async listSessions() {
      return []
    },
    async deleteSession() {},
  }
}

function toolCtx(sessionID = "ses_main"): ToolContext {
  return {
    sessionID,
    messageID: "msg_1",
    agent: "sisyphus",
    directory: "/tmp/oml-channel-test",
    worktree: "/tmp/oml-channel-test",
    abort: new AbortController().signal,
    metadata: () => {},
    ask: async () => {},
  }
}

function textOf(v: unknown): string {
  if (typeof v === "string") return v
  if (typeof v === "object" && v !== null && "output" in v) return String((v as { output: unknown }).output)
  return String(v)
}

const savedStateDir = process.env["OML_STATE_DIR"]
const dirs: string[] = []
let dir = ""
let stateDir = ""

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "omo-channel-"))
  dirs.push(dir)
  stateDir = join(dir, "state")
  process.env["OML_STATE_DIR"] = stateDir
})

afterAll(async () => {
  if (savedStateDir === undefined) delete process.env["OML_STATE_DIR"]
  else process.env["OML_STATE_DIR"] = savedStateDir
  await Bun.sleep(100)
  for (const d of dirs) await rm(d, { recursive: true, force: true })
})

async function setup(): Promise<{
  hooks: Awaited<ReturnType<typeof createHostCore>>
  client: FakeClient
}> {
  const client = fakeClient()
  const hooks = await createHostCore({ directory: dir, client }, { skillRoots: [], stateDir })
  return { hooks, client }
}

describe("omo_channel", () => {
  test("post → read 往返：消息落进临时频道，to 过滤生效", async () => {
    const { hooks } = await setup()
    const ch = hooks.tool!["omo_channel"]!
    const posted = textOf(
      await ch.execute(
        { action: "post", channel: "team-t1", from: "impl", to: "*", body: "发现 A" },
        toolCtx(),
      ),
    )
    expect(posted).toContain("已发到 team-t1")
    await ch.execute(
      { action: "post", channel: "team-t1", from: "review", to: "impl", body: "认领 B" },
      toolCtx(),
    )

    const all = textOf(await ch.execute({ action: "read", channel: "team-t1" }, toolCtx()))
    expect(all).toContain("impl→*")
    expect(all).toContain("发现 A")
    expect(all).toContain("review→impl")
    expect(all).toContain("认领 B")

    const toImpl = textOf(
      await ch.execute({ action: "read", channel: "team-t1", to: "impl" }, toolCtx()),
    )
    expect(toImpl).toContain("发现 A")
    expect(toImpl).toContain("认领 B")

    const toReview = textOf(
      await ch.execute({ action: "read", channel: "team-t1", to: "review" }, toolCtx()),
    )
    expect(toReview).toContain("发现 A")
    expect(toReview).not.toContain("认领 B")

    const board = await loadBoard()
    expect(board.channels["team-t1"]?.length).toBe(2)
  })

  test("list 列出所有频道", async () => {
    const { hooks } = await setup()
    const ch = hooks.tool!["omo_channel"]!
    await ch.execute({ action: "post", channel: "team-z", from: "a", body: "m1" }, toolCtx())
    await ch.execute({ action: "post", channel: "team-a", from: "b", body: "m2" }, toolCtx())
    const listed = textOf(await ch.execute({ action: "list", channel: "" }, toolCtx()))
    expect(listed).toContain("team-z")
    expect(listed).toContain("team-a")
  })

  test("team 成员的 prompt 注入 teamId 频道与通信指令", async () => {
    const { hooks, client } = await setup()
    const out = textOf(
      await hooks.tool!["omo_task"]!.execute(
        { action: "team", task: "验证团队频道注入通信指令", members: [{ role: "impl", task: "完成实现部分并广播发现" }] },
        toolCtx(),
      ),
    )
    const m = /团队 (t\w+) 完成/.exec(out)
    expect(m).not.toBeNull()
    const teamId = m![1]!
    const injected = client.prompts.find((p) => p.text.includes(`你在团队频道 ${teamId}`))
    expect(injected).toBeDefined()
    expect(injected!.text).toContain("omo_channel read")
    expect(injected!.text).toContain("omo_channel post")
    expect(injected!.text).toContain("主动推进")
  })

  test("nested run 继承父 team 频道；无 team 祖先不注入", async () => {
    const { hooks, client } = await setup()
    const teamOut = textOf(
      await hooks.tool!["omo_task"]!.execute(
        { action: "team", task: "验证子代理继承团队频道", members: [{ role: "impl", task: "做一个子任务并广播进度" }] },
        toolCtx(),
      ),
    )
    const teamId = /团队 (t\w+) 完成/.exec(teamOut)![1]!

    await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "嵌套子代理继承频道", parentId: teamId },
      toolCtx(),
    )
    expect(client.prompts.at(-1)!.text).toContain(`你在团队频道 ${teamId}`)

    await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "独立子代理不注入频道" },
      toolCtx(),
    )
    expect(client.prompts.at(-1)!.text).not.toContain("你在团队频道")
  })
})
