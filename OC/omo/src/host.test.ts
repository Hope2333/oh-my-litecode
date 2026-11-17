/**
 * 宿主测试：用假 TaskClient + 临时技能根 + 临时状态目录。
 * 不启动 OpenCode 进程，但走的是与线上同一条 createHostCore 路径。
 */
import { describe, test, expect, beforeEach, afterAll } from "bun:test"
import type { ToolContext } from "@opencode-ai/plugin"
import { mkdtemp, mkdir, writeFile, rm, readdir } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { createHostCore, OMO_MARKER } from "./host.ts"
import { resolveConfig } from "@oml/core"
import type { TaskClient } from "./client.ts"

type FakeClient = TaskClient & {
  created: string[]
  createdMeta: Array<{ parentID?: string; title: string }>
  renamed: Array<{ sessionId: string; title: string }>
  aborted: string[]
  prompts: Array<{ sessionId: string; agent?: string; model?: { providerID: string; modelID: string }; text: string }>
}

function fakeClient(opts: { hang?: boolean } = {}): FakeClient {
  const created: string[] = []
  const createdMeta: Array<{ parentID?: string; title: string }> = []
  const renamed: Array<{ sessionId: string; title: string }> = []
  const aborted: string[] = []
  const prompts: Array<{ sessionId: string; agent?: string; model?: { providerID: string; modelID: string }; text: string }> = []
  return {
    created,
    createdMeta,
    renamed,
    aborted,
    prompts,
    async createSession({ title, parentID }) {
      const id = `ses_${created.length + 1}_${title.length}`
      created.push(id)
      createdMeta.push({ title, ...(parentID === undefined ? {} : { parentID }) })
      return { id }
    },
    async renameSession({ sessionId, title }) {
      renamed.push({ sessionId, title })
    },
    async promptSession(input) {
      prompts.push({
        sessionId: input.sessionId,
        text: input.text,
        ...(input.agent === undefined ? {} : { agent: input.agent }),
        ...(input.model === undefined ? {} : { model: input.model }),
      })
      if (opts.hang === true) return new Promise<never>(() => {})
      return { text: "子会话完成" }
    },
    async abortSession({ sessionId }) {
      aborted.push(sessionId)
    },
    async lastAssistantText() {
      return ""
    },
  }
}

function toolCtx(sessionID = "ses_main"): ToolContext {
  return {
    sessionID,
    messageID: "msg_1",
    agent: "sisyphus",
    directory: "/tmp/oml-test",
    worktree: "/tmp/oml-test",
    abort: new AbortController().signal,
    metadata: () => {},
    ask: async () => {},
  }
}

const dirs: string[] = []
let dir = ""
let skillsRoot = ""
let stateDir = ""

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "omo-host-"))
  dirs.push(dir)
  skillsRoot = join(dir, "skills")
  stateDir = join(dir, "state")
  const one = join(skillsRoot, "frontend")
  await mkdir(one, { recursive: true })
  await writeFile(
    join(one, "SKILL.md"),
    "---\nname: frontend\ndescription: Build a landing page with layout and animation.\n---\n\n# frontend\n正文",
    "utf8",
  )
})

afterAll(async () => {
  // 落盘是 fire-and-forget；等所有后台写落地后再统一清理，避免与写操作竞态。
  await Bun.sleep(300)
  for (const d of dirs) await rm(d, { recursive: true, force: true })
})

describe("createHostCore", () => {
  test("system.transform 注入一段带标记的提示，且重复调用不重复注入", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    const output = { system: ["base prompt"] }
    await hooks["experimental.chat.system.transform"]!({ model: {} as never }, output)

    expect(output.system.length).toBe(2)
    expect(output.system[1]).toContain(OMO_MARKER)
    expect(output.system[1]).toContain("## 工作纪律")

    await hooks["experimental.chat.system.transform"]!({ model: {} as never }, output)
    expect(output.system.length).toBe(2)
  })

  test("聊天文本进入技能选取：命中任务后索引含 frontend", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    await hooks["chat.message"]!(
      { sessionID: "ses_main" },
      { message: {} as never, parts: [{ type: "text", text: "build a landing page" } as never] },
    )
    const output = { system: [] as string[] }
    await hooks["experimental.chat.system.transform"]!({ sessionID: "ses_main", model: {} as never }, output)
    expect(output.system[0]).toContain("frontend")
  })

  test("EigenFlux 主动提示：命中只读场景才注入，写操作带授权红线，可配置关闭", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    const run = async (text: string, config?: Record<string, unknown>): Promise<string> => {
      const h = config
        ? (await createHostCore({ directory: dir, client: fakeClient() }, { skillRoots: [skillsRoot], stateDir, config }))
        : hooks
      await h["chat.message"]!(
        { sessionID: "ses_ef" },
        { message: {} as never, parts: [{ type: "text", text } as never] },
      )
      const out = { system: [] as string[] }
      await h["experimental.chat.system.transform"]!({ sessionID: "ses_ef", model: {} as never }, out)
      return out.system[0] ?? ""
    }
    const readonly = await run("查一下最新的行业动态")
    expect(readonly).toContain("EigenFlux")
    expect(readonly).toContain("只读")
    const write = await run("把里程碑广播出去")
    expect(write).toContain("授权")
    const off = await run("查最新的行业动态", { eigenflux: { proactive: false } })
    expect(off).not.toContain("EigenFlux")
  })

  test("视觉路由：会话含图 + 当前模型不可见 → 注入一行提示；可视觉模型 → 不注入", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    // 1) 会话里出现一张图
    await hooks["chat.message"]!(
      { sessionID: "ses_img" },
      {
        message: {} as never,
        parts: [
          { type: "text", text: "看这张图" } as never,
          { type: "file", mime: "image/png", url: "data:image/png;base64,AAAA" } as never,
        ],
      },
    )
    // 2) 当前模型声明 image 不可见 → 有提示
    const out1 = { system: [] as string[] }
    await hooks["experimental.chat.system.transform"]!(
      { sessionID: "ses_img", model: { id: "deepseek-flash", capabilities: { input: { image: false, pdf: false } } } as never },
      out1,
    )
    expect(out1.system[0]).toContain("## 视觉")
    expect(out1.system[0]).toContain("multimodal-looker")
    // 3) 同一会话换视觉模型 → 不再提示（静态清单兜底）
    const out2 = { system: [] as string[] }
    await hooks["experimental.chat.system.transform"]!(
      { sessionID: "ses_img", model: { id: "agnes-3.0-flash", capabilities: { input: { image: false, pdf: false } } } as never },
      out2,
    )
    expect(out2.system[0]).not.toContain("## 视觉")
    // 4) capabilities 声明 image 可见（即便不在静态清单）→ 不提示
    const out3 = { system: [] as string[] }
    await hooks["experimental.chat.system.transform"]!(
      { sessionID: "ses_img", model: { id: "some-future-vlm", capabilities: { input: { image: true, pdf: true } } } as never },
      out3,
    )
    expect(out3.system[0]).not.toContain("## 视觉")
    // 5) 无图会话不受影响
    const out4 = { system: [] as string[] }
    await hooks["experimental.chat.system.transform"]!(
      { sessionID: "ses_plain", model: { id: "deepseek-flash", capabilities: { input: { image: false, pdf: false } } } as never },
      out4,
    )
    expect(out4.system[0]).not.toContain("## 视觉")
  })

  test("注册 4 个网关 + 1 个兼容位，旧 OMO 的工具名一个都没有", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir, config: {} },
    )
    const names = Object.keys(hooks.tool ?? {}).sort()
    expect(names).toEqual(["omo_admin", "omo_knowledge", "omo_mcp", "omo_task", "skill"])
  })

  test("omo_admin action=status 报告上限 8192 且 totalTokens 为正", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    const out = await hooks.tool!["omo_admin"]!.execute({ action: "status" }, toolCtx())
    const text = typeof out === "string" ? out : out.output
    // status 现在是人读+JSON 混合：预算行在前，上下文段是 JSON 片段
    expect(text).toContain("8192 tok")
    expect(text).toMatch(/## 注入预算\n- \d+\/8192 tok（pass|truncated|fail）/)
  })

  test("omo_task run 拒绝过短描述，也拒绝未知类别", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    const short = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "改一下", category: "quick" },
      toolCtx(),
    )
    expect(String(short)).toContain("过短")

    const bad = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "把落地页的布局改成两栏并加动效", category: "no-such-category" },
      toolCtx(),
    )
    expect(String(bad)).toContain("未知类别")
  })

  test("OMO 遗留类别名归一化：artistry→visual-engineering（路由黑洞清零）", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    const out = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "出一版海报与版式方案，含字体与配色", category: "artistry" },
      toolCtx(),
    )
    expect(String(out)).not.toContain("未知类别")
    // saveTasks 是 fire-and-forget（host.ts），给它一个事件循环周期
    await Bun.sleep(50)
    const tasks = JSON.parse(await Bun.file(join(stateDir, "tasks.json")).text()) as {
      tasks: Record<string, { category: string }>
    }
    const mine = Object.values(tasks.tasks).filter((t) => t.category === "visual-engineering")
    expect(mine.length).toBeGreaterThan(0)
    expect(Object.values(tasks.tasks).some((t) => t.category === "artistry")).toBe(false)
  })

  test("OMO 遗留 agent 名走别名表：hephaestus→sisyphus-junior", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    const out = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "把长任务的重试与退避逻辑实现完", category: "deep-low", agent: "hephaestus" },
      toolCtx(),
    )
    expect(String(out)).toContain("子会话完成")
    expect(client.prompts[0]?.agent).toBe("sisyphus-junior")
  })

  test("宿主内置 agent 名原样放行（build/plan/general，路由由 oml.json 自由键承担）", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    const out = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "把工具函数的单元测试补齐并跑绿", category: "quick", agent: "build" },
      toolCtx(),
    )
    expect(String(out)).toContain("子会话完成")
    expect(client.prompts[0]?.agent).toBe("build")
  })

  test("权限钩子：默认全放行（主代理 + omo_task 子会话不被 Permission required 打断）", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    expect(hooks["permission.ask"]).toBeTypeOf("function")
    const output = { status: "ask" as "ask" | "deny" | "allow" }
    await hooks["permission.ask"]!({
      id: "p1",
      type: "bash",
      sessionID: "ses_x",
      messageID: "m1",
      title: "bash",
      metadata: {},
      time: { created: 0 },
    } as never, output)
    expect(output.status).toBe("allow")
  })

  test("permissions=false 时不注册权限钩子（回宿主每次询问）", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir, config: { permissions: false } },
    )
    expect(hooks["permission.ask"]).toBeUndefined()
  })

  test("未映射的未知类别仍拒绝，且提示里列出别名映射", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    const bad = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "把落地页的布局改成两栏并加动效", category: "no-such-category" },
      toolCtx(),
    )
    const text = String(bad)
    expect(text).toContain("未知类别")
    expect(text).toContain("artistry")
  })

  test("omo_task 前台派发会建子会话、跑完并置 done", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    const out = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "统计仓库里所有的 TODO 注释并归类", category: "quick" },
      toolCtx(),
    )
    const text = typeof out === "string" ? out : out.output
    expect(text).toContain("子会话完成")
    expect(client.created.length).toBe(1)

    const status = await hooks.tool!["omo_task"]!.execute({ action: "status", all: true }, toolCtx())
    const parsed = JSON.parse(typeof status === "string" ? status : status.output).tasks as Array<{ status: string }>
    expect(parsed[0]?.status).toBe("done")
  })

  test("会话命名：新子会话默认带隶属链标题，parentID = 调用方会话", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "统计仓库里所有的 TODO 注释并归类", category: "quick" },
      toolCtx("ses_main_caller"),
    )
    expect(client.createdMeta.length).toBe(1)
    const meta = client.createdMeta[0]!
    expect(meta.parentID).toBe("ses_main_caller") // 树状嵌套：子会话挂在调用方会话下
    expect(meta.title).toContain("omo t1")          // 有名字，不裸奔
    expect(meta.title).toContain("TODO")            // 含描述
    // 子会话自己的系统提示里能看到身份
    const sid = client.created[0]!
    const out = { system: [] as string[] }
    await hooks["experimental.chat.system.transform"]!({ sessionID: sid, model: {} as never }, out)
    expect(out.system.some((s) => s.includes(`本会话标题：${meta.title}`))).toBe(true)
  })

  test("会话命名：自定义 title 进入标题，隶属链仍前置保留", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "统计仓库里所有的 TODO 注释并归类", category: "quick", title: "我的自定义名" },
      toolCtx(),
    )
    const meta = client.createdMeta[0]!
    expect(meta.title).toContain("omo t1")
    expect(meta.title).toContain("我的自定义名")
    expect(meta.title.indexOf("omo t1")).toBeLessThan(meta.title.indexOf("我的自定义名")) // 隶属链前置侧重
  })

  test("resume 可选改名：带 title 时对已有子会话调 session.update", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    const first = await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "统计仓库里所有的 TODO 注释并归类", category: "quick" },
      toolCtx(),
    )
    expect(String(first)).toContain("子会话完成")
    const id = client.created[0]!
    await hooks.tool!["omo_task"]!.execute(
      { action: "resume", taskId: "t1", task: "继续", title: "改名后续接" },
      toolCtx(),
    )
    expect(client.created.length).toBe(1) // 续接不新建会话
    expect(client.renamed.length).toBe(1)
    expect(client.renamed[0]!.sessionId).toBe(id)
    expect(client.renamed[0]!.title).toContain("改名后续接")
  })

  test("status 输出每个任务带 title 与 parentId 隶属信息", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir },
    )
    await hooks.tool!["omo_task"]!.execute(
      { action: "run", task: "统计仓库里所有的 TODO 注释并归类", category: "quick", title: "带标题的任务" },
      toolCtx(),
    )
    const status = await hooks.tool!["omo_task"]!.execute({ action: "status", all: true }, toolCtx())
    const parsed = JSON.parse(typeof status === "string" ? status : status.output).tasks as Array<{ title?: string; parentId: string | null }>
    expect(parsed[0]?.title).toContain("带标题的任务")
    expect(parsed[0]?.parentId).toBeNull()
  })

  test("omo_knowledge skill 命中，skill_read 读到正文并计数", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    const found = await hooks.tool!["omo_knowledge"]!.execute({ action: "skill", query: "landing page" }, toolCtx())
    expect(String(found)).toContain("frontend")

    const body = await hooks.tool!["omo_knowledge"]!.execute({ action: "skill_read", name: "frontend" }, toolCtx())
    expect(String(body)).toContain("# frontend")
  })
})

async function adminTools() {
  const hooks = await createHostCore(
    { directory: dir, client: fakeClient() },
    { skillRoots: [skillsRoot], stateDir },
  )
  const t = hooks["tool"]?.["omo_admin"] as unknown as { execute: (args: unknown, ctx: unknown) => Promise<string | { output: string }> }
  if (t === undefined) throw new Error("omo_admin 未注册")
  return t
}

describe("omo_admin 新动作（goal 合并 / settings / upgrade）", () => {
  test("goal：op=set 设、缺省 show、op=clear 清", async () => {
    const admin = await adminTools()
    const set = await admin.execute({ action: "goal", op: "set", text: "把预算压到 8K 以内" }, toolCtx())
    expect(typeof set === "string" ? set : set.output).toContain("目标已设为")
    const show = await admin.execute({ action: "goal" }, toolCtx())
    expect(typeof show === "string" ? show : show.output).toContain("把预算压到 8K 以内")
    const clear = await admin.execute({ action: "goal", op: "clear" }, toolCtx())
    expect(typeof clear === "string" ? clear : clear.output).toContain("目标已清除")
  })

  test("settings：返回 oml.json 面板 JSON（路径 + 配置）", async () => {
    const admin = await adminTools()
    const out = await admin.execute({ action: "settings" }, toolCtx())
    const text = typeof out === "string" ? out : out.output
    const parsed = JSON.parse(text) as { path: string; config: unknown }
    expect(typeof parsed.path).toBe("string")
    expect(parsed.config !== undefined).toBe(true)
  })

  test("upgrade：返回 3rd systems 结果 JSON（离线/不触发也不炸）", async () => {
    const admin = await adminTools()
    const out = await admin.execute({ action: "upgrade" }, toolCtx())
    const parsed = JSON.parse(typeof out === "string" ? out : out.output) as Array<{ system: string }>
    expect(parsed.map((r) => r.system)).toContain("opencode-visual-cache")
  })
})

describe("滚动检查点", () => {
  test("每轮用户发言后落一次盘，不依赖模型自觉", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    await hooks["chat.message"]!(
      { sessionID: "ses_r" },
      { message: {} as never, parts: [{ type: "text", text: "帮我修 03-cache 的缓存" } as never] },
    )
    // 落盘是 fire-and-forget，给它一个事件循环周期
    await Bun.sleep(30)

    const files = await readdir(join(stateDir, "checkpoints"))
    expect(files.length).toBeGreaterThan(0)
    const body = await Bun.file(join(stateDir, "checkpoints", files[0]!)).text()
    expect(body).toContain("ses_r")
  })
})

describe("主动上下文控制", () => {
  test("占用过 85% 时自动写检查点并在提示里留下路径", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      // limit 压到 200：任何注入都会过线
      { config: { budget: { limit: 200 } }, skillRoots: [skillsRoot], stateDir },
    )
    const output = { system: ["base prompt"] }
    await hooks["experimental.chat.system.transform"]!({ model: {} as never }, output)

    expect(output.system[1]).toContain("<auto-checkpoint")
    const files = await readdir(join(stateDir, "checkpoints"))
    expect(files.length).toBeGreaterThan(0)
  })

  test("宿主压缩时把权威事实交给它，而不是让它自己总结", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir },
    )
    const out = { context: [] as string[] }
    await hooks["experimental.session.compacting"]!({ sessionID: "ses_x" }, out)

    expect(out.context.length).toBe(1)
    expect(out.context[0]).toContain("<omo-compaction>")
    expect(out.context[0]).toContain("压缩时必须保留")
  })

  test("disabled_hooks 关掉 compaction 后不接管", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      {
        config: {
          skills: { maxIndex: 40 },
          tasks: { concurrency: 3, maxDepth: 2, ttlMs: 60_000 },
          budget: { limit: 8192 },
          disabled_hooks: ["compaction"],
        },
        skillRoots: [skillsRoot],
        stateDir,
      },
    )
    expect(hooks["experimental.session.compacting"]).toBeUndefined()
  })
})

describe("配置开关", () => {
  const base = { skills: { maxIndex: 40 }, tasks: { concurrency: 3, maxDepth: 2, ttlMs: 60_000 }, budget: { limit: 8192 } }

  test("compat.taskAlias 追加 task 工具，且与 omo_task 同实现", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { config: { ...base, compat: { taskAlias: true } }, skillRoots: [skillsRoot], stateDir },
    )
    const tools = hooks.tool ?? {}
    expect(Object.keys(tools).length).toBe(6)
    expect(tools["task"]).toBe(tools["omo_task"])
  })

  test("disabled_tools 移除指定工具", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { config: { ...base, disabled_tools: ["omo_admin"] }, skillRoots: [skillsRoot], stateDir },
    )
    expect(hooks.tool?.["omo_admin"]).toBeUndefined()
    expect(hooks.tool?.["omo_task"]).toBeDefined()
  })

  test("disabled_hooks 关掉 system.transform 后不注入", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { config: { ...base, disabled_hooks: ["system.transform"] }, skillRoots: [skillsRoot], stateDir },
    )
    expect(hooks["experimental.chat.system.transform"]).toBeUndefined()
    const hooks2 = await createHostCore(
      { directory: dir, client: fakeClient() },
      { config: { ...base, disabled_hooks: ["event"] }, skillRoots: [skillsRoot], stateDir },
    )
    expect(hooks2.event).toBeUndefined()
    expect(hooks2["experimental.chat.system.transform"]).toBeDefined()
  })

  test("disabled_agents 不注册对应 agent", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { config: { ...base, disabled_agents: ["momus", "explore"] }, skillRoots: [skillsRoot], stateDir },
    )
    const cfg: { agent?: Record<string, unknown> } = {}
    await hooks.config!(cfg as never)
    // 内置 4 个 agent 也会被显式覆盖（为了关掉原生 skill 工具），故一并出现。
    expect(Object.keys(cfg.agent ?? {}).sort()).toEqual([
      "atlas",
      "build",
      "general",
      "librarian",
      "oracle",
      "plan",
      "prometheus",
      "sisyphus",
      "sisyphus-junior",
    ])
  })

  test("config 钩子设 default_agent=sisyphus、注入 OMO 颜色，且顺序 S-P-A 在前", async () => {
    const hooks = await createHostCore({ directory: dir, client: fakeClient() }, { skillRoots: [skillsRoot], stateDir })
    const cfg: Record<string, unknown> = {}
    await hooks.config!(cfg as never)
    expect(cfg["default_agent"]).toBe("sisyphus")
    const agents = cfg["agent"] as Record<string, { color?: string }>
    expect(agents["sisyphus"]?.color).toBe("#00CED1")
    expect(agents["prometheus"]?.color).toBe("#FF5722")
    expect(agents["atlas"]?.color).toBe("#10B981")
    expect(agents["sisyphus-junior"]?.color).toBe("#20B2AA")
    const ids = Object.keys(agents)
    expect(ids.slice(0, 3)).toEqual(["sisyphus", "prometheus", "atlas"])
  })

  test("disabled_skills 从索引里剔除", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { config: { ...base, disabled_skills: ["frontend"] }, skillRoots: [skillsRoot], stateDir },
    )
    const output = { system: [] as string[] }
    await hooks["experimental.chat.system.transform"]!({ model: {} as never }, output)
    expect(output.system[0]).not.toContain("frontend")
  })
})

describe("任务续接", () => {
  test("action=resume 原地复活同一任务、attempts+1、沿用同一子会话", async () => {
    const client = fakeClient()
    const hooks = await createHostCore({ directory: dir, client }, { skillRoots: [skillsRoot], stateDir })
    const task = hooks.tool!["omo_task"]!
    await task.execute(
      { action: "run", task: "先做第一件事，比如读一遍仓库结构", category: "quick" },
      toolCtx(),
    )
    expect(client.created.length).toBe(1)

    const list = async (): Promise<
      Array<{ id: string; sessionId: string | null; attempts?: number; status?: string; model?: string | null }>
    > => {
      const raw = await task.execute({ action: "status", all: true }, toolCtx())
      return JSON.parse(typeof raw === "string" ? raw : raw.output) .tasks as Array<{
        id: string
        sessionId: string | null
        attempts?: number
        status?: string
        model?: string | null
      }>
    }
    const before = await list()
    const first = before[0]
    expect(first).toBeDefined()
    const firstId = first?.id ?? ""
    expect(first?.sessionId).not.toBeNull()

    const second = await task.execute({ action: "resume", taskId: firstId, task: "继续收尾" }, toolCtx())
    const text = typeof second === "string" ? second : second.output
    expect(text).toContain("续接")
    expect(client.created.length).toBe(1) // 没有新建会话

    const after = await list()
    // 不再新增任务记录：同一条任务从 done 回到 done，attempts 递增
    expect(after.length).toBe(before.length)
    const same = after.find((t) => t.id === firstId)
    expect(same).toBeDefined()
    expect(same?.sessionId).toBe(first?.sessionId ?? "")
    expect(same?.attempts).toBe(2)
    expect(same?.status).toBe("done")
  })

  test("model 真的透传到子会话（账本不再静默丢弃）", async () => {
    const client = fakeClient()
    const hooks = await createHostCore({ directory: dir, client }, { skillRoots: [skillsRoot], stateDir })
    const task = hooks.tool!["omo_task"]!
    await task.execute(
      { action: "run", task: "用指定模型跑一个任务看看", category: "quick", model: "acme/m1" },
      toolCtx(),
    )
    expect(client.prompts[0]?.model).toEqual({ providerID: "acme", modelID: "m1" })

    const raw = await task.execute({ action: "status", all: true }, toolCtx())
    const rows = JSON.parse(typeof raw === "string" ? raw : raw.output).tasks as Array<{ model?: string | null }>
    expect(rows[0]?.model).toBe("acme/m1")
  })

  test("team 任务会走 pending→running→终态，不再卡在 pending", async () => {
    const client = fakeClient()
    const hooks = await createHostCore({ directory: dir, client }, { skillRoots: [skillsRoot], stateDir })
    const task = hooks.tool!["omo_task"]!
    const out = await task.execute(
      {
        action: "team",
        task: "串行做两件互不依赖的事",
        category: "quick",
        mode: "pipeline",
        members: [
          { role: "impl", task: "实现甲部分" },
          { role: "verify", task: "验证乙部分" },
        ],
      },
      toolCtx(),
    )
    expect(typeof out === "string" ? out : out.output).toContain("团队")

    const raw = await task.execute({ action: "status", all: true }, toolCtx())
    const rows = JSON.parse(typeof raw === "string" ? raw : raw.output).tasks as Array<{
      id: string
      kind?: string
      status?: string
      members?: unknown[]
    }>
    const team = rows.find((r) => r.kind === "team")
    expect(team).toBeDefined()
    expect(team?.status).toBe("done")
    expect(team?.members?.length).toBe(2)
  })

  test("团队模板：team=<名字> 从配置取成员、模式与工具约束", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      {
        skillRoots: [skillsRoot],
        stateDir,
        config: {
          teams: {
            review: {
              description: "只读评审队",
              mode: "pipeline",
              members: [
                { role: "scan", agent: "explore", task: "扫描风险点" },
                { role: "judge", agent: "momus", task: "给出结论" },
              ],
              tools: ["read", "grep", "glob"],
              mcp: ["codegraph"],
            },
          },
        },
      },
    )
    const task = hooks.tool!["omo_task"]!
    const out = await task.execute({ action: "team", team: "review", category: "quick" }, toolCtx())
    expect(typeof out === "string" ? out : out.output).toContain("团队")
    // TUI 折叠状态行：每个成员结果带一行机器可读状态（↳ 开头）
    expect(typeof out === "string" ? out : out.output).toContain("↳")

    // 约束写进了成员 brief：子会话提示词里应能看到工具与 MCP 的白名单
    expect(client.prompts.some((p) => p.text.includes("只允许使用这些工具") && p.text.includes("codegraph"))).toBe(true)
    // 模板里的 task 生效
    expect(client.prompts.some((p) => p.text.includes("扫描风险点"))).toBe(true)

    const listed = await hooks.tool!["omo_admin"]!.execute({ action: "team_list" }, toolCtx())
    expect(typeof listed === "string" ? listed : listed.output).toContain("review")
  })

  test("未知团队模板给出可用名单而不是静默失败", async () => {
    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir, config: { teams: { a: { description: "d", members: [{ role: "r" }] } } } },
    )
    const out = await hooks.tool!["omo_task"]!.execute({ action: "team", team: "nope" }, toolCtx())
    const text = typeof out === "string" ? out : out.output
    expect(text).toContain("没有团队模板 nope")
    expect(text).toContain("a")
  })

  test("A4：parallel 出现两个可写成员时直接拒绝", async () => {
    const client = fakeClient()
    const hooks = await createHostCore({ directory: dir, client }, { skillRoots: [skillsRoot], stateDir })
    const task = hooks.tool!["omo_task"]!
    const out = await task.execute(
      {
        action: "team",
        task: "两个写者同时改树",
        category: "quick",
        mode: "parallel",
        members: [
          { role: "a", task: "改甲文件" },
          { role: "b", task: "改乙文件" },
        ],
      },
      toolCtx(),
    )
    expect(typeof out === "string" ? out : out.output).toContain("拒绝")
    expect(client.created.length).toBe(0)
  })

  test("A4：parallel + 只读协作者时放行", async () => {
    const client = fakeClient()
    const hooks = await createHostCore({ directory: dir, client }, { skillRoots: [skillsRoot], stateDir })
    const task = hooks.tool!["omo_task"]!
    const out = await task.execute(
      {
        action: "team",
        task: "一个写者加一个只读评审",
        category: "quick",
        mode: "parallel",
        members: [
          { role: "impl", task: "实现功能" },
          { role: "review", task: "只读审查", agent: "oracle" },
        ],
      },
      toolCtx(),
    )
    expect(typeof out === "string" ? out : out.output).toContain("团队")
  })

  test("并发上限对 run（含 background）同样生效", async () => {
    const client = fakeClient({ hang: true })
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir, config: resolveConfig({ tasks: { concurrency: 1 } }) },
    )
    const task = hooks.tool!["omo_task"]!
    const first = await task.execute(
      { action: "run", task: "第一件足够长的任务描述", category: "quick", background: true },
      toolCtx(),
    )
    expect(typeof first === "string" ? first : first.output).toContain("已派发")
    await Bun.sleep(20)
    const second = await task.execute(
      { action: "run", task: "第二件足够长的任务描述", category: "quick", background: true },
      toolCtx(),
    )
    expect(typeof second === "string" ? second : second.output).toContain("并发已达上限")
  })

  test("深度上限对带 parentId 的递归派发生效", async () => {
    const client = fakeClient()
    const hooks = await createHostCore(
      { directory: dir, client },
      { skillRoots: [skillsRoot], stateDir, config: resolveConfig({ tasks: { maxDepth: 0 } }) },
    )
    const task = hooks.tool!["omo_task"]!
    const out = await task.execute(
      { action: "run", task: "带父任务的子任务描述", category: "quick", parentId: "t404" },
      toolCtx(),
    )
    expect(typeof out === "string" ? out : out.output).toContain("不存在")
  })
})

describe("watchdog（TTL 回收，DSH 论文 L1）", () => {
  test("status 调用会先把超时任务标 failed，而不是一直挂着", async () => {
    const stale = {
      version: 1,
      tasks: {
        t1: {
          id: "t1",
          depth: 0,
          description: "一个已经超时、没人管的子任务",
          category: "quick",
          status: "running",
          createdAt: 0,
          updatedAt: 0,
        },
      },
    }
    await mkdir(stateDir, { recursive: true })
    await writeFile(join(stateDir, "tasks.json"), JSON.stringify(stale), "utf8")

    const hooks = await createHostCore(
      { directory: dir, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir, config: { tasks: { ttlMs: 1000 } } },
    )
    const call = hooks["tool"]?.["omo_task"] as unknown as {
      execute: (a: unknown, c: unknown) => Promise<string | { output: string }>
    }
    const raw = await call.execute({ action: "status", all: true }, {})
    const text = typeof raw === "string" ? raw : raw.output

    expect(text).toContain("failed")
    expect(text).toContain("超时")
  })
})

describe("MCP 网关（全量登记、默认禁用、按需拉起）", () => {
  const SERVER = `
const respond = (id, result) => process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\\n")
const dec = new TextDecoder(); let buf = ""
for await (const chunk of Bun.stdin.stream()) {
  buf += dec.decode(chunk)
  let i = buf.indexOf("\\n")
  while (i !== -1) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1); i = buf.indexOf("\\n")
    if (line === "") continue
    const msg = JSON.parse(line)
    if (msg.method === "initialize") respond(msg.id, { protocolVersion: "2024-11-05", capabilities: {}, serverInfo: { name: "fake", version: "1" } })
    else if (msg.method === "tools/list") respond(msg.id, { tools: [{ name: "echo", description: "回显" }] })
    else if (msg.method === "tools/call") respond(msg.id, { content: [{ type: "text", text: String(msg.params.arguments.text) }] })
    else if (msg.id !== undefined) respond(msg.id, {})
  }
}
`
  test("sync → enable → tools → call → disable", async () => {
    const work = await mkdtemp(join(tmpdir(), "oml-mcpgw-"))
    dirs.push(work)
    const serverPath = join(work, "server.ts")
    await writeFile(serverPath, SERVER, "utf8")
    const hostConfigPath = join(work, "opencode.json")
    await writeFile(hostConfigPath, JSON.stringify({ mcp: { fake: { command: ["bun", serverPath], enabled: false } } }), "utf8")

    const def = { command: ["bun", serverPath], enabled: false }
    const hooks = await createHostCore(
      { directory: work, client: fakeClient() },
      { skillRoots: [skillsRoot], stateDir: join(work, "state"), mcpDefs: { fake: def }, hostConfigPath },
    )
    const admin = hooks.tool!["omo_admin"]!
    const mcp = hooks.tool!["omo_mcp"]!

    const synced = await admin.execute({ action: "mcp", op: "sync" }, toolCtx())
    expect(typeof synced === "string" ? synced : synced.output).toContain("同步 1 个")

    const shown = await admin.execute({ action: "mcp", op: "show" }, toolCtx())
    expect(typeof shown === "string" ? shown : shown.output).toContain("待复核")

    // 未启用时拒绝调用
    const refused = await mcp.execute({ action: "call", server: "fake", tool: "echo", args: '{"text":"hi"}' }, toolCtx())
    expect(typeof refused === "string" ? refused : refused.output).toContain("当前禁用")

    const enabled = await admin.execute({ action: "mcp", op: "enable", target: "fake" }, toolCtx())
    expect(typeof enabled === "string" ? enabled : enabled.output).toContain("已启用")
    const written = JSON.parse(await Bun.file(hostConfigPath).text()) as { mcp: Record<string, { enabled?: boolean }> }
    expect(written.mcp["fake"]?.enabled).toBe(true)

    const listed = await mcp.execute({ action: "tools", server: "fake" }, toolCtx())
    expect(typeof listed === "string" ? listed : listed.output).toContain("echo")

    const called = await mcp.execute({ action: "call", server: "fake", tool: "echo", args: '{"text":"你好"}' }, toolCtx())
    expect(typeof called === "string" ? called : called.output).toBe("你好")

    const disabled = await admin.execute({ action: "mcp", op: "disable", target: "fake" }, toolCtx())
    expect(typeof disabled === "string" ? disabled : disabled.output).toContain("已禁用")
    const after = JSON.parse(await Bun.file(hostConfigPath).text()) as { mcp: Record<string, { enabled?: boolean }> }
    expect(after.mcp["fake"]?.enabled).toBe(false)
  })
})
