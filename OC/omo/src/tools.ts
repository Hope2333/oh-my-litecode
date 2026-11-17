/**
 * OML 的 4 个工具网关 + 1 个兼容位。
 *
 * 折叠原则（用户要求）：按使用率与必要性分组，**网关内部用 action 分派**，
 * 而不是每个能力占一个独立 schema。9 个独立工具的 schema 常驻 system prompt；
 * 3 个网关的 schema 只有一层可选字段，实际注入量显著更低。
 *
 *  - omo_task      run / team / status / cancel / resume —— 任务与团队
 *  - omo_knowledge skill / skill_read / web —— 技能与外部检索
 *  - omo_admin     model / goal / status / checkpoint / handoff / mcp / memory / compress…
 *  - omo_mcp       tools / call / sync —— 按需拉起 MCP 服务器（宿主侧一律禁用）
 *  - skill         旧 OMO 兼容位（config.compat.skillTool）
 */
import { tool, type ToolContext } from "@opencode-ai/plugin"
import type {
  CompressBlock,
  CompressStore,
  EffectiveModel,
  Goal,
  McpCatalog,
  McpDef,
  MemoryStore,
  ModelOverrides,
  ModelTarget,
} from "@oml/core"
import {
  AGENT_IDS,
  connectMcp,
  enabledMcpIds,
  markMcpUsed,
  renderCallResult,
  renderMcpCatalog,
  setMcpEnabled,
  syncCatalog,
  canonicalAgent,
  runThirdUpgrade,
  canonicalCategory,
  formatStatusLine,
  type StatusLineInput,

  addTask,
  agentReadonly,
  attachMembers,
  concurrencyReason,
  contextSummary,
  addMemory,
  applyAntiPatterns,
  distillAntiPatterns,
  compressRange,
  decompressSource,
  listBlocks,
  totalSavedTokens,
  forgetMemory,
  reinforceMemory,
  topMemories,
  expire,
  isTerminal,
  readSources,
  scanSlop,
  summarizeSlop,
  selectSkills,
  triggerOf,
  setOverride,
  transition,
  CATEGORY_IDS,
  type BudgetReport,
  type OmlConfig,
  type SkillMeta,
  type SkillUsageMap,
  type TaskMember,
  type TaskRecord,
  type TaskStore,
} from "@oml/core"
import { mkdir, readFile, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { TaskClient } from "./client.ts"
import { searchWeb } from "./web.ts"

export interface HostStats {
  readonly startedAt: number
  readonly calls: Record<string, number>
}

export type HostState = {
  config: OmlConfig
  skills: SkillMeta[]
  usage: SkillUsageMap
  store: TaskStore
  directory: string
  client: TaskClient
  overrides: ModelOverrides
  stats: HostStats
  memory: MemoryStore
  compress: CompressStore
  /** sessionID → 最近一次用户文本，供 system.transform 选取技能。 */
  sessionText: Map<string, string>
  /** 会话里出现过图片/PDF 的 sessionID 集合（视觉路由用）。 */
  sessionImages: Set<string>
  /** sessionID → 会话标题（含隶属链），供子会话在自己的系统提示里看到「我是谁」。 */
  sessionTitles: Map<string, string>
  saveUsage(usage: SkillUsageMap): void
  saveTasks(store: TaskStore): void
  saveOverrides(next: ModelOverrides): void
  saveMemory(next: MemoryStore): void
  saveCompress(next: CompressStore): void
  measure(taskText?: string): BudgetReport
  modelFor(agentId?: string, categoryId?: string, explicit?: string): EffectiveModel
  getGoal(): Goal | null
  /** oml.json 的路径与原文（settings 动作展示用；找不到则 undefined） */
  settingsPath?: string
  settingsText?: string
  /** 宿主当前插件列表（upgrade 动作算 missing；宿主不给就 undefined → 只靠磁盘探测） */
  thirdPlugins?: string[]
  /** MCP 目录：全量登记、默认禁用，调用时才拉起进程 */
  mcpCatalog: McpCatalog
  saveMcpCatalog(next: McpCatalog): void
  /** 读宿主 opencode.json 的 mcp 段 */
  hostMcpDefs(): Promise<Record<string, McpDef>>
  /** 把目录的启用状态回写宿主配置（带备份） */
  writeHostMcp(catalog: McpCatalog): Promise<{ path: string; changed: string[] }>
  setGoal(text: string): Promise<Goal>
  clearGoal(): Promise<boolean>
  checkpoint(sessionId?: string): Promise<string>
}

/**
 * 网关的 action 槽位。
 *
 * 为什么单独数它：工具数会骗人。把 18 个能力塞进 1 个 `omo_admin` 的 enum，
 * 「工具数」变漂亮了，模型要读的分支并没有减少。A8 的计数单位是 action，不是 tool。
 */
export const TASK_ACTIONS = ["run", "team", "status", "cancel", "resume"] as const
export const KNOWLEDGE_ACTIONS = ["skill", "skill_read", "web"] as const
export const ADMIN_ACTIONS = [
  "model",
  "goal",
  "settings",
  "upgrade",
  "status",
  "checkpoint",
  "handoff",
  "slop_check",
  "team_list",
  "mcp",
  "memory",
  "dreams_distill",
  "compress_add",
  "compress_list",
  "decompress",
] as const

/** MCP 网关：宿主侧全部禁用，这里按需拉起子进程。 */
export const MCP_ACTIONS = ["tools", "call", "sync"] as const

export const ACTION_SLOTS = {
  omo_task: TASK_ACTIONS.length,
  omo_knowledge: KNOWLEDGE_ACTIONS.length,
  omo_admin: ADMIN_ACTIONS.length,
  omo_mcp: MCP_ACTIONS.length,
} as const

export const ACTION_TOTAL =
  ACTION_SLOTS.omo_task + ACTION_SLOTS.omo_knowledge + ACTION_SLOTS.omo_admin + ACTION_SLOTS.omo_mcp

/**
 * 同步 MCP 目录（admin 与 omo_mcp 共用一份策略）。
 *
 * 新增/定义变化一律降级为「禁用 + 待复核」：不替用户决定装了什么就该跑起来，
 * 也不静默删除消失的服务器。
 */
export async function syncMcpCatalog(state: HostState): Promise<string> {
  const defs = await state.hostMcpDefs()
  const r = syncCatalog(state.mcpCatalog, defs)
  state.saveMcpCatalog(r.catalog)
  return [
    `同步 ${Object.keys(defs).length} 个：新增 ${r.added.length}、变化 ${r.changed.length}、消失 ${r.gone.length}、未变 ${r.unchanged}`,
    ...(r.added.length === 0 ? [] : [`新增（已默认禁用，待复核）：${r.added.join(", ")}`]),
    ...(r.changed.length === 0 ? [] : [`定义变化（已降级禁用，待复核）：${r.changed.join(", ")}`]),
    ...(r.gone.length === 0 ? [] : [`从宿主配置消失：${r.gone.join(", ")}`]),
  ].join("\n")
}

const SKILL_READ_CAP = 20_000
const CATEGORY_SET: ReadonlySet<string> = new Set<string>(CATEGORY_IDS)

function allTasks(store: TaskStore): TaskRecord[] {
  return Object.values(store.tasks)
}

function brief(t: TaskRecord, sessionTitle?: string): Record<string, unknown> {
  return {
    id: t.id,
    kind: t.kind ?? "task",
    ...(sessionTitle === undefined ? {} : { title: sessionTitle }),
    parentId: t.parentId,
    status: t.status,
    category: t.category,
    agent: t.agent ?? null,
    model: t.model ?? null,
    attempts: t.attempts ?? 1,
    lastError: t.lastError ?? null,
    depth: t.depth,
    sessionId: t.sessionId ?? null,
    description: t.description.length > 120 ? `${t.description.slice(0, 120)}…` : t.description,
    members: t.members?.map((m) => ({ taskId: m.taskId, role: m.role, model: m.model ?? null })),
    error: t.error ?? null,
  }
}

/** "provider/model" → SDK 的 {providerID, modelID}；无斜杠视为不合法。 */
export function splitModel(model: string | null): { providerID: string; modelID: string } | null {
  if (model === null) return null
  const at = model.indexOf("/")
  if (at <= 0 || at === model.length - 1) return null
  return { providerID: model.slice(0, at), modelID: model.slice(at + 1) }
}

/** 只有这些错误值得换 fallback 模型重试；其余错误换模型不会变好。 */
function isModelError(message: string): boolean {
  return /model|not found|unknown model|unsupported|not available|no such model|overloaded|rate.?limit|429|50[234]|timeout|ECONNRESET|fetch failed/i.test(
    message,
  )
}

/** 从错误文本里抽 3 位失败码（TUI 折叠行要求：一般 3 位）。抽不到就 undefined，不编造。 */
function errorCode(err: string | undefined): string | undefined {
  if (err === undefined) return undefined
  const m = err.match(/\b([45]\d\d)\b/)
  return m?.[1]
}

/** 隶属链：从任务沿 parentId 一路上溯，根在前、自己在后，如 t1←t3←t5。断链即止（prune 可能删过父）。 */
function affiliationOf(store: TaskStore, task: TaskRecord): string {
  const ids = [task.id]
  let cur = task
  const seen = new Set<string>([task.id])
  while (cur.parentId !== null && !seen.has(cur.parentId)) {
    seen.add(cur.parentId)
    ids.unshift(cur.parentId)
    const parent = store.tasks[cur.parentId]
    if (parent === undefined) break
    cur = parent
  }
  return ids.join("←")
}

/** 会话标题：隶属链永远前置并保留（侧重），自定义名只替换描述段。
 *  形如 `omo t1←t5 · 出海报`。缺省也总是有名字，不会让会话裸奔进列表。 */
function sessionTitleOf(store: TaskStore, task: TaskRecord, custom?: string): string {
  const aff = affiliationOf(store, task)
  const label = custom !== undefined && custom.trim() !== "" ? custom.trim() : task.description.slice(0, 40)
  return `omo ${aff} · ${label}`
}

/** 让每个子会话知道自己的任务 id、隶属链与会话标题，再派任务时能带上 parentId（深度才真的可约束）。 */
function promptWithTaskContext(task: TaskRecord, prompt: string, aff: string, title: string): string {
  return `[oml-task ${task.id} depth=${task.depth}]\n本会话标题：${title}\n隶属链：${aff}\n若你需要再派子任务，请在 omo_task 参数里带 parentId: "${task.id}" 与 title（标题会自动带上完整隶属链）。\n\n${prompt}`
}

function runChild(
  state: HostState,
  task: TaskRecord,
  prompt: string,
  opts?: { resumeSessionId?: string; parentSessionId?: string; title?: string },
): Promise<{ ok: boolean; text: string; status?: StatusLineInput }> {
  return (async () => {
    const aff = affiliationOf(state.store, task)
    const title = sessionTitleOf(state.store, task, opts?.title)
    const created =
      opts?.resumeSessionId === undefined
        ? await state.client.createSession({
            ...(opts?.parentSessionId === undefined ? {} : { parentID: opts.parentSessionId }),
            title,
            directory: state.directory,
          })
        : { id: opts.resumeSessionId }
    // 记住本会话标题：子会话在自己的系统提示里会看到「我是谁」。
    state.sessionTitles.set(created.id, title)
    // resume 时可选改名：把刷新后的隶属链/标题写回宿主会话。
    if (opts?.resumeSessionId !== undefined && opts.title !== undefined) {
      await state.client.renameSession({ sessionId: created.id, title, directory: state.directory })
    }
    // 已在跑（续接同一会话）时不再迁移，否则会把 running → running 判成非法。
    if (task.status !== "running") {
      const running = transition(state.store, task.id, "running", { sessionId: created.id, now: Date.now() })
      if (!running.ok) return { ok: false, text: running.reason }
      state.store = running.store
      state.saveTasks(state.store)
    }

    const pick = state.modelFor(task.agent, task.category, task.model)
    // chain 里是「首选 + 各级 fallback」。只对「模型不可用」类错误换下一个，
    // 内容/权限/参数错误换模型不会变好，只会白烧两次钱。
    // chain 为空 = OML 没有意见（用户也没配模型）→ 不传 model，让 opencode 用它自己的默认值。
    // 这不是失败：宿主本来就有默认模型，OML 只在用户显式指定时才覆盖。
    const candidates = pick.chain.length === 0 ? (pick.model === null ? [null] : [pick.model]) : [...pick.chain]
    let res: { text: string; error?: string; tokens?: { input?: number; output?: number }; toolUses?: number } = { text: "" }
    const tried: string[] = []
    // 折叠状态行用的累计量：新增（下载侧）/ 累计读取 / 工具次数，跨模型链累加。
    let statNew = 0
    let statCum = 0
    let statTools = 0
    let statErr: string | undefined
    for (const candidate of candidates) {
      const model = candidate === null ? null : splitModel(candidate)
      const attempt = await state.client.promptSession({
        sessionId: created.id,
        ...(task.agent ? { agent: task.agent } : {}),
        ...(model === null ? {} : { model }),
        // 只给首选模型带 variant：回退模型未必有同一档位，强塞会变成「非模型错误」而不重试
        ...(pick.variant === undefined || model === null || candidate !== pick.model ? {} : { variant: pick.variant }),
        text: promptWithTaskContext(task, prompt, aff, title),
      })
      tried.push(`${candidate ?? "<宿主默认>"}${attempt.error === undefined ? "(✓)" : "(✗)"}`)
      res = attempt
      statNew += attempt.tokens?.output ?? 0
      statCum += attempt.tokens?.input ?? 0
      statTools += attempt.toolUses ?? 0
      if (attempt.error !== undefined) statErr = attempt.error
      if (attempt.error === undefined || !isModelError(attempt.error)) break
    }
    const failed = res.error !== undefined
    const done = transition(state.store, task.id, failed ? "failed" : "done", {
      now: Date.now(),
      ...(res.error === undefined ? { result: res.text } : { error: res.error }),
    })
    if (done.ok) {
      state.store = done.store
      state.saveTasks(state.store)
    }
    const tail = tried.length > 1 ? `\n\n（模型链：${tried.join(" → ")}）` : ""
    const status: StatusLineInput = {
      id: task.id,
      name: task.description.slice(0, 24),
      ...(task.agent === undefined ? {} : { agent: task.agent }),
      ...(statTools > 0 ? { toolUses: statTools } : {}),
      ...(statNew > 0 || statCum > 0 ? { newTokens: statNew, cumTokens: statCum } : {}),
      ...(failed ? { error: { ...(errorCode(statErr) === undefined ? {} : { code: errorCode(statErr) }) } } : {}),
    }
    return { ok: !failed, text: failed ? `${res.error ?? "未知错误"}${tail}` : res.text, status }
  })().catch((err: unknown) => {
    const message = err instanceof Error ? err.message : String(err)
    const failed = transition(state.store, task.id, "failed", { now: Date.now(), error: message })
    if (failed.ok) {
      state.store = failed.store
      state.saveTasks(state.store)
    }
    const status: StatusLineInput = {
      id: task.id,
      name: task.description.slice(0, 24),
      error: { ...(errorCode(message) === undefined ? {} : { code: errorCode(message) }) },
    }
    return { ok: false, text: message, status }
  })
}

function spawn(
  state: HostState,
  input: {
    description: string
    category: string
    agent?: string
    model?: string
    parentId?: string
    kind?: "task" | "team"
  },
): { ok: true; task: TaskRecord } | { ok: false; reason: string } {
  if (input.description.trim().length < 8) return { ok: false, reason: "任务描述过短（<8 字），请写清目标与验收标准" }
  // OMO 遗留名归一化：artistry→visual-engineering 等，路由黑洞清零（档位数不变）。
  const category = canonicalCategory(input.category)
  if (!CATEGORY_SET.has(category)) {
    return { ok: false, reason: `未知类别：${input.category}（可用：${CATEGORY_IDS.join(" / ")}；OMO 遗留名 artistry/unspecified-low/unspecified-high 会自动映射）` }
  }
  // 旧 agent 名走别名表（hephaestus→sisyphus-junior 等）；内置名（build/plan/general）
  // 原样放行，模型路由由 oml.json 的自由键 agents 承担。
  const agent = input.agent === undefined ? undefined : canonicalAgent(input.agent)
  const add = addTask(state.store, {
    description: input.description,
    category,
    ...(agent === undefined ? {} : { agent }),
    ...(input.model === undefined ? {} : { model: input.model }),
    ...(input.parentId === undefined ? {} : { parentId: input.parentId }),
    ...(input.kind === undefined ? {} : { kind: input.kind }),
    now: Date.now(),
    maxDepth: state.config.tasks?.maxDepth ?? 2,
  })
  if (!add.ok) return { ok: false, reason: add.reason }
  state.store = add.store
  state.saveTasks(state.store)
  return { ok: true, task: add.task }
}

export function buildTools(state: HostState): Record<string, ReturnType<typeof tool>> {
  const bump = (name: string): void => {
    state.stats.calls[name] = (state.stats.calls[name] ?? 0) + 1
  }

  const omoTask = tool({
    description:
      "任务与团队网关。action=run 派一个子任务（可 background）；team 派一组并行/串行成员并汇总；status 查账本；cancel 中止；resume 用 taskId 续接同一子会话。",
    args: {
      action: tool.schema.enum(TASK_ACTIONS),
      task: tool.schema.string().optional().describe("run/resume 的任务描述；team 时作为总目标"),
      title: tool.schema.string().optional().describe("会话标题：create 时给新子会话命名（缺省按任务描述生成，隶属链自动前置）；resume 时可选改名"),
      category: tool.schema.string().optional().describe("类别：quick/deep-low/deep-high/ultrabrain/visual-engineering/writing"),
      agent: tool.schema.string().optional().describe("指定执行者 agent id"),
      model: tool.schema.string().optional().describe("本次显式模型 provider/model（覆盖热分配）"),
      background: tool.schema.boolean().optional().describe("run 时 true = 立即返回任务 id"),
      taskId: tool.schema.string().optional().describe("resume/status/cancel 的目标任务 id"),
      all: tool.schema.boolean().optional().describe("status 时列出全部（默认只列未终结）"),
      parentId: tool.schema
        .string()
        .optional()
        .describe("父任务 id。递归派发时必须带，否则深度上限 p99 无效"),
      mode: tool.schema.enum(["parallel", "pipeline"]).optional().describe("team 的执行方式，默认 parallel"),
      members: tool.schema
        .array(
          tool.schema.object({
            role: tool.schema.string().describe("该成员的角色，如 impl / review / verify"),
            task: tool.schema.string().describe("该成员的具体任务"),
            agent: tool.schema.string().optional(),
            category: tool.schema.string().optional(),
            model: tool.schema.string().optional(),
          }),
        )
        .optional()
        .describe("team 成员（1-6 个）；用 team=<模板名> 时可省略"),
      team: tool.schema
        .string()
        .optional()
        .describe("团队模板名（oml.json 的 teams）；给了就从配置取成员、模式与工具约束"),
    },
    async execute(args, ctx: ToolContext) {
      bump(`task.${args.action}`)
      // watchdog（DSH 论文的 TTL 监督，分级 L1）：每次工具调用顺手扫一遍超时任务。
      // 只在真有 stale 时写盘，避免每次调用都改状态文件。
      const ttl = state.config.tasks?.ttlMs ?? 1_800_000
      const hasStale = Object.values(state.store.tasks).some(
        (t) => !isTerminal(t.status) && Date.now() - t.updatedAt > ttl,
      )
      if (hasStale) state.saveTasks(expire(state.store, Date.now(), ttl))
      if (args.action === "status") {
        const list = args.taskId !== undefined
          ? allTasks(state.store).filter((t) => t.id === args.taskId)
          : allTasks(state.store).filter((t) => args.all === true || !isTerminal(t.status))
        if (list.length === 0) return "没有匹配的任务。"
        // 折叠状态行：宿主 TUI 拿这个就能画「一行一子代理」，不用展开完整报告。
        const lines = list.map((t) =>
          formatStatusLine({
            id: t.id,
            name: t.description.slice(0, 24),
            ...(t.agent === undefined ? {} : { agent: t.agent }),
            ...(t.status === "failed" && t.error !== undefined ? { error: { ...(errorCode(t.error) === undefined ? {} : { code: errorCode(t.error) }) } } : {}),
          }),
        )
        // 单一 JSON：tasks 是账本视图，statusLines 是给宿主 TUI 折叠行用的紧凑视图。
        return JSON.stringify({
          tasks: list.map((t) => brief(t, t.sessionId === undefined ? undefined : state.sessionTitles.get(t.sessionId))),
          statusLines: lines,
        }, null, 2)
      }
      if (args.action === "cancel") {
        const id = args.taskId ?? ""
        if (id === "") return "需要 taskId"
        const t = state.store.tasks[id]
        if (t === undefined) return `没有任务 ${id}`
        if (t.sessionId !== undefined) await state.client.abortSession({ sessionId: t.sessionId })
        const r = transition(state.store, id, "cancelled", { now: Date.now() })
        if (!r.ok) return r.reason
        state.store = r.store
        state.saveTasks(state.store)
        return `已中止 ${id}`
      }
      if (args.action === "resume") {
        const id = args.taskId ?? ""
        const t = state.store.tasks[id]
        if (t === undefined) return `没有任务 ${id}`
        if (t.sessionId === undefined) return `任务 ${id} 没有子会话，无法续接；请改用 action=run`
        if (t.status === "running") return `任务 ${id} 仍在运行，先 action=status 或 action=cancel`
        if (t.status === "cancelled") return `任务 ${id} 已取消；取消是终态，请改用 action=run`
        // 同一任务原地复活：attempts+1、lastError 留痕、沿用原子会话（上下文不丢）。
        const resumed = transition(state.store, id, "running", { sessionId: t.sessionId, now: Date.now() })
        if (!resumed.ok) return resumed.reason
        state.store = resumed.store
        state.saveTasks(state.store)
        const out = await runChild(state, resumed.task, args.task ?? "继续", {
          resumeSessionId: t.sessionId,
          ...(args.title === undefined ? {} : { title: args.title }),
        })
        const line = out.status === undefined ? "" : `\n\n${formatStatusLine(out.status)}`
        return `续接 ${id}（第 ${resumed.task.attempts ?? 2} 次尝试）\n${out.text}${line}`
      }
      if (args.action === "team") {
        const profiles = state.config.teams ?? {}
        const profile = args.team === undefined ? undefined : profiles[args.team]
        if (args.team !== undefined && profile === undefined) {
          const names = Object.keys(profiles)
          return `没有团队模板 ${args.team}；可用：${names.length === 0 ? "（未配置 teams）" : names.join(", ")}`
        }
        const members = profile?.members ?? args.members ?? []
        const mode = args.mode ?? profile?.mode ?? "parallel"
        if (members.length === 0) return "team 需要 members[] 或 team=<模板名>"
        if (members.length > 6) return "team 成员上限 6"
        // 模板里声明的工具/MCP 是**约束**，写进每个成员的 brief，避免成员越界去用没配的工具。
        const policy = [
          profile?.tools !== undefined && profile.tools.length > 0 ? `只允许使用这些工具：${profile.tools.join(", ")}` : "",
          profile?.mcp !== undefined && profile.mcp.length > 0 ? `可用的 MCP：${profile.mcp.join(", ")}` : "",
        ]
          .filter((x) => x !== "")
          .join("；")
        // A4 单一写入者：并行成员里只要有两个可写者，就是两个代理同时改同一棵树。
        // 提示词里的纪律拦不住，必须在派发处拒绝。
        if (mode !== "pipeline") {
          const writers = members.filter((m) => !agentReadonly(canonicalAgent((m.agent ?? args.agent) ?? "sisyphus")))
          if (writers.length > 1) {
            return `拒绝：parallel 模式下 ${writers.length} 个可写成员（${writers
              .map((m) => m.role)
              .join("/")}）会同时改同一棵树。请改用 mode="pipeline" 串行，或把除第一个外的成员指定为只读 agent（oracle/librarian/explore/momus）。`
          }
        }
        const reason = concurrencyReason(state.store, state.config.tasks?.concurrency ?? 3)
        if (reason !== null) return reason
        const team = spawn(state, {
          description: args.task ?? (args.team === undefined ? "团队任务" : `团队任务（${args.team}）`),
          category: args.category ?? "deep-low",
          ...(args.agent === undefined ? {} : { agent: args.agent }),
          kind: "team",
        })
        if (!team.ok) return team.reason
        const teamId = team.task.id
        const started = transition(state.store, teamId, "running", { now: Date.now() })
        if (!started.ok) return started.reason
        state.store = started.store
        state.saveTasks(state.store)
        const limit = state.config.tasks?.concurrency ?? 3
        const results: Array<{ role: string; ok: boolean; text: string; status?: StatusLineInput }> = []
        const refs: Array<{ taskId: string; role: string; model?: string }> = []
        const runOne = async (m: (typeof members)[number]): Promise<void> => {
          const chosen = m.model ?? args.model
          const brief = m.task ?? profile?.members.find((x) => x.role === m.role)?.task ?? "完成你负责的部分"
          // 约束要进**提示词**才算数；只写在任务描述里，子会话看不到。
          const briefWithPolicy = policy === "" ? brief : `${brief}（${policy}）`
          const child = spawn(state, {
            description: `${m.role}: ${briefWithPolicy}`,
            category: m.category ?? args.category ?? "deep-low",
            ...(m.agent === undefined ? {} : { agent: m.agent }),
            ...(chosen === undefined ? {} : { model: chosen }),
            parentId: teamId,
          })
          if (!child.ok) {
            results.push({ role: m.role, ok: false, text: child.reason })
            return
          }
          refs.push({
            taskId: child.task.id,
            role: m.role,
            ...(chosen === undefined ? {} : { model: chosen }),
          })
          const out = await runChild(state, child.task, briefWithPolicy, {
            parentSessionId: ctx.sessionID,
            title: `${m.role} · ${child.task.description.slice(0, 24)}`,
          })
          const memberStatus =
            out.status === undefined
              ? undefined
              : { ...out.status, id: child.task.id, name: m.role, ...(m.agent === undefined ? {} : { agent: m.agent }) }
          results.push({ role: m.role, ok: out.ok, text: out.text, ...(memberStatus === undefined ? {} : { status: memberStatus }) })
        }
        if (mode === "pipeline") {
          for (const m of members) await runOne(m)
        } else {
          const queue = [...members]
          const workers = Array.from({ length: Math.min(limit, queue.length) }, async () => {
            for (;;) {
              const next = queue.shift()
              if (next === undefined) return
              await runOne(next)
            }
          })
          await Promise.all(workers)
        }
        state.store = attachMembers(state.store, teamId, refs)
        state.saveTasks(state.store)
        const summary = results
          .map((r) => {
            const head = `### ${r.role} ${r.ok ? "✓" : "✗"}`
            const body = r.text.length > 1200 ? `${r.text.slice(0, 1200)}…` : r.text
            const line = r.status === undefined ? "" : `\n${formatStatusLine(r.status)}`
            return `${head}\n${body}${line}`
          })
          .join("\n\n")
        const done = transition(state.store, teamId, results.every((r) => r.ok) ? "done" : "failed", {
          now: Date.now(),
          result: summary,
          ...(results.every((r) => r.ok) ? {} : { error: "部分成员失败" }),
        })
        if (done.ok) {
          state.store = done.store
          state.saveTasks(state.store)
        }
        return `团队 ${teamId} 完成 ${results.filter((r) => r.ok).length}/${results.length}\n\n${summary}`
      }

      // action = run
      const gate = concurrencyReason(state.store, state.config.tasks?.concurrency ?? 3)
      if (gate !== null) return gate
      if (args.background === true) {
        const created = spawn(state, {
          description: args.task ?? "",
          category: args.category ?? "deep-low",
          ...(args.agent === undefined ? {} : { agent: args.agent }),
          ...(args.model === undefined ? {} : { model: args.model }),
          ...(args.parentId === undefined ? {} : { parentId: args.parentId }),
        })
        if (!created.ok) return created.reason
        const task = created.task
        void runChild(state, task, args.task ?? "", {
          parentSessionId: ctx.sessionID,
          ...(args.title === undefined ? {} : { title: args.title }),
        })
        return `已派发 ${task.id}（后台，标题 ${sessionTitleOf(state.store, task, args.title)}）。用 action=status taskId=${task.id} 查看。`
      }
      const created = spawn(state, {
        description: args.task ?? "",
        category: args.category ?? "deep-low",
        ...(args.agent === undefined ? {} : { agent: args.agent }),
        ...(args.model === undefined ? {} : { model: args.model }),
        ...(args.parentId === undefined ? {} : { parentId: args.parentId }),
      })
      if (!created.ok) return created.reason
      const out = await runChild(state, created.task, args.task ?? "", {
        parentSessionId: ctx.sessionID,
        ...(args.title === undefined ? {} : { title: args.title }),
      })
      const line = out.status === undefined ? "" : `\n\n${formatStatusLine(out.status)}`
      return (out.ok ? out.text : `失败：${out.text}`) + line
    },
  })

  const omoKnowledge = tool({
    description:
      "知识与检索网关。skill 按任务检索技能（返回 name｜触发语）；skill_read 读某个技能正文；web 联网检索（Gemini grounding，需代理）。",
    args: {
      action: tool.schema.enum(KNOWLEDGE_ACTIONS),
      query: tool.schema.string().optional().describe("skill/web 的查询"),
      name: tool.schema.string().optional().describe("skill_read 的技能名"),
      limit: tool.schema.number().optional().describe("skill 返回条数（默认 8）/ web 来源数（默认 6，上限 12）"),
    },
    async execute(args) {
      bump(`knowledge.${args.action}`)
      if (args.action === "skill") {
        const q = (args.query ?? "").trim()
        if (q === "") return "需要 query"
        const picked = selectSkills(state.skills, q, {
          top: Math.min(Math.max(args.limit ?? 8, 1), 20),
          usage: state.usage,
        })
        if (picked.length === 0) return "没有匹配的技能。可换更具体的任务描述。"
        return picked.map((s) => `${s.name}｜${triggerOf(s.description)}｜${s.file}`).join("\n")
      }
      if (args.action === "skill_read") {
        const name = (args.name ?? "").trim()
        const found = state.skills.find((s) => s.name === name)
        if (found === undefined) return `没有技能 ${name}；先用 action=skill 检索`
        if (found.file === "<built-in>") {
          return `${name} 是 opencode 内置技能，正文不在磁盘上：请直接调用宿主的 skill 工具（工具名 skill，参数 {name: "${name}"}）。`
        }
        const text = await readFile(found.file, "utf8")
        return text.length > SKILL_READ_CAP ? `${text.slice(0, SKILL_READ_CAP)}\n…（已截断）` : text
      }
      const q = (args.query ?? "").trim()
      if (q.length < 2) return "拒绝：query 过短。"
      const cap = Math.min(Math.max(args.limit ?? 6, 1), 12)
      const res = await searchWeb(q, cap)
      return res.ok ? res.text : `检索失败：${res.error}`
    },
  })

  const omoAdmin = tool({
    description:
      "管理网关。model 查看/热分配子代理模型；goal 设看清目标；status 给出预算+上下文+统计+MCP 一览；checkpoint 落盘；handoff 输出交接摘要；mcp 管理 MCP 目录（show/sync/enable/disable）；memory 记忆（op=add/list/edit）。",
    args: {
      action: tool.schema.enum(ADMIN_ACTIONS),
      target: tool.schema.string().optional().describe("model set 的目标：agent:<id> / category:<id> / default；memory 的记忆 id；mcp 的服务器 id；slop_check 的扫描目录"),
      model: tool.schema.string().optional().describe("model set 的模型 provider/model；传空串表示清除该层"),
      text: tool.schema.string().optional().describe("goal_set 的目标文本；memory_add 的记忆正文；compress_add 的摘要"),
      kind: tool.schema.enum(["fact", "antipattern", "snippet"]).optional().describe("memory_add 的条目类型；memory_list 的过滤"),
      op: tool.schema
        .enum(["show", "set", "clear", "reinforce", "forget", "add", "list", "sync", "enable", "disable"])
        .optional()
        .describe("model：show/set；goal：set/show/clear（缺省 show）；memory：add/list/reinforce/forget；mcp：show/sync/enable/disable"),
      apply: tool.schema.boolean().optional().describe("dreams_distill：true 时把候选直接落库，否则只列候选"),
      taskText: tool.schema.string().optional().describe("measure 时用来重选技能的文本"),
      from: tool.schema.string().optional().describe("compress_add：被压缩区间起点消息 id"),
      to: tool.schema.string().optional().describe("compress_add：被压缩区间终点消息 id"),
      sources: tool.schema.record(tool.schema.string(), tool.schema.string()).optional().describe("compress_add：消息 id → 原文，供 KEEP 展开"),
      savedTokens: tool.schema.number().optional().describe("compress_add：估算节省的 token"),
      messageId: tool.schema.string().optional().describe("decompress：要回溯的原文消息 id"),
    },
    async execute(args) {
      bump(`admin.${args.action}`)
      switch (args.action) {
        case "model": {
          if (args.op !== "set") {
            const rows = ["# 生效模型"]
            for (const id of AGENT_IDS) {
              const pick = state.modelFor(id, undefined)
              rows.push(`${id}: ${pick.model ?? "(宿主默认)"} [${pick.source}]${pick.note === undefined ? "" : ` ${pick.note}`}`)
            }
            for (const c of CATEGORY_IDS) {
              const pick = state.modelFor(undefined, c)
              rows.push(`${c}: ${pick.model ?? "(宿主默认)"} [${pick.source}]`)
            }
            return rows.join("\n")
          }
          const target = (args.target ?? "").trim()
          if (target === "") return "需要 target（agent:<id> / category:<id> / default）"
          const value = args.model === undefined || args.model.trim() === "" ? null : args.model
          const r = setOverride(state.overrides, target as ModelTarget, value)
          if (!r.ok) return r.reason ?? "设置失败"
          state.overrides = r.overrides
          state.saveOverrides(r.overrides)
          return value === null ? `已清除 ${target} 的模型覆盖` : `已把 ${target} 热分配为 ${value}（对之后新建的子会话生效）`
        }
        case "goal": {
          // 三个旧动作（goal_set/show/clear）合并：op 缺省 = show（最常见）。
          const op = args.op ?? "show"
          if (op === "set") {
            const text = (args.text ?? "").trim()
            if (text === "") return "goal set 需要 text"
            return `目标已设为：${(await state.setGoal(text)).text}`
          }
          if (op === "clear") return (await state.clearGoal()) ? "目标已清除" : "当前没有目标"
          const goal = state.getGoal()
          return goal === null ? "当前没有目标" : goal.text
        }
        case "settings": {
          // OML settings（Neko Agent settings for <宿主 agent>）：读 oml.json 全量键
          // （含 language/third/permissions），给出路径与警告。改法：直接编辑 oml.json。
          const cfg = state.settingsText ?? "（未找到 oml.json；当前用内置默认 + 旧 OMO 兼容层）"
          return JSON.stringify({ path: state.settingsPath ?? "（内置默认）", config: cfg }, null, 2)
        }
        case "upgrade": {
          // 3rd systems 检查/升级（自动升级开关 = oml.json 的 third.autoUpgrade，默认 true）
          const out = await runThirdUpgrade({
            config: state.config,
            host: { name: "opencode" },
            currentPlugins: state.thirdPlugins,
          })
          return JSON.stringify(out.results, null, 2)
        }
        case "status": {
          const report = state.measure(args.taskText)
          const tasks = allTasks(state.store)
          const live = tasks.filter((t) => !isTerminal(t.status)).length
          const minutes = Math.max(1, Math.round((Date.now() - state.stats.startedAt) / 60000))
          const calls = Object.entries(state.stats.calls).sort((a, b) => b[1] - a[1])
          const mcpOn = enabledMcpIds(state.mcpCatalog)
          const review = Object.values(state.mcpCatalog.entries).filter((e) => e.needsReview && e.missing !== true)
          return [
            "## 注入预算",
            `- ${report.totalTokens}/${report.budget.limit} tok（${report.budget.status}）`,
            ...report.sections.map((s) => `- ${s.id}: ${s.tokens} tok / ${s.items} 项${s.truncated ? "（已截断）" : ""}`),
            "## 上下文",
            JSON.stringify(contextSummary(report, live, tasks.length)),
            "## 会话统计",
            `- ${minutes} 分钟，任务 ${tasks.length} 个（未终结 ${live}）`,
            ...calls.map(([k, v]) => `- ${k}: ${v}`),
            "## MCP",
            `- 启用 ${mcpOn.length}/${Object.keys(state.mcpCatalog.entries).length}${mcpOn.length === 0 ? "" : `：${mcpOn.join(", ")}`}`,
            ...(review.length === 0 ? [] : [`- 待复核 ${review.length} 个：${review.map((e) => e.id).join(", ")}（omo_admin action=mcp op=show）`]),
          ].join("\n")
        }
        case "checkpoint":
          return `检查点已写入：${await state.checkpoint()}`
        case "mcp": {
          const op = args.op ?? "show"
          if (op === "show") return renderMcpCatalog(state.mcpCatalog)
          if (op === "sync") return await syncMcpCatalog(state)
          if (op !== "enable" && op !== "disable") return "mcp 的 op 支持 show / sync / enable / disable"
          const target = args.target ?? ""
          if (target === "") return "mcp 需要 target=<服务器 id>"
          if (state.mcpCatalog.entries[target] === undefined) return `没有登记 [${target}]；先 op=sync`
          const next = setMcpEnabled(state.mcpCatalog, target, op === "enable")
          state.saveMcpCatalog(next)
          const written = await state.writeHostMcp(next)
          return `已${op === "enable" ? "启用" : "禁用"} [${target}]；宿主配置回写 ${written.changed.length} 项（${written.path}）。重启宿主后生效；本会话内用 omo_mcp action=call 可直接拉起。`
        }
        case "handoff": {
          const live = allTasks(state.store).filter((t) => !isTerminal(t.status))
          const done = allTasks(state.store)
            .filter((t) => t.status === "done")
            .slice(-8)
          const report = state.measure()
          return [
            "## 注入预算",
            `- ${report.totalTokens}/${report.budget.limit} tok（${report.budget.status}）`,
            "## 未终结",
            ...(live.length === 0 ? ["- 无"] : live.map((t) => `- ${t.id} ${t.description}`)),
            "## 最近完成",
            ...(done.length === 0 ? ["- 无"] : done.map((t) => `- ${t.id} ${t.description}`)),
            "## 恢复",
            "- 续接：omo_task action=resume taskId=<id>",
          ].join("\n")
        }

        case "memory": {
          const op = args.op ?? "list"
          if (op === "add") {
            const t = args.text ?? ""
            const kind = (args.kind ?? "fact") as "fact" | "antipattern" | "snippet"
            const r = addMemory(state.memory, t, Date.now(), kind)
            if (!r.ok) return r.reason
            state.saveMemory(r.store)
            return r.deduped
              ? `已有等价记忆 [${r.entry.id}]，已强化（hits=${r.entry.hits}）：${r.entry.text}`
              : `已记住 [${r.entry.id}]：${r.entry.text}`
          }
          if (op === "list") {
            const filter = args.kind as "fact" | "antipattern" | "snippet" | undefined
            const pool = filter ? topMemories(state.memory).filter((m) => m.kind === filter) : topMemories(state.memory)
            if (pool.length === 0) return "（暂无持久记忆）"
            return JSON.stringify(
              pool.map((m) => ({ id: m.id, kind: m.kind, text: m.text, hits: m.hits })),
              null,
              2,
            )
          }
          const id = args.target ?? ""
          if (op === "forget") return forgetMemory(state.memory, id) ? `已忘掉 [${id}]` : `没有记忆 [${id}]`
          if (op === "reinforce") return reinforceMemory(state.memory, id) ? `已强化 [${id}]` : `没有记忆 [${id}]`
          return "memory 的 op 支持 add / list / reinforce / forget"
        }
        case "dreams_distill": {
          const cands = distillAntiPatterns(state.store, state.memory)
          if (cands.length === 0) return "任务账本里没有可蒸馏的反复失败模式。"
          if (args.apply === true) {
            const r = applyAntiPatterns(state.memory, cands)
            state.saveMemory(r.store)
            return `已蒸馏 ${r.added} 条反模式（${r.deduped} 条去重强化）。`
          }
          return JSON.stringify(
            cands.map((c) => ({ pattern: c.pattern, occurrences: c.occurrences, rule: c.rule, sample: c.sampleError })),
            null,
            2,
          )
        }
        case "team_list": {
          const profiles = state.config.teams ?? {}
          const rows = Object.entries(profiles).map(([name, p]) => ({
            name,
            description: p.description,
            mode: p.mode ?? "parallel",
            members: p.members.map((m) => ({ role: m.role, agent: m.agent ?? null, category: m.category ?? null })),
            tools: p.tools ?? null,
            mcp: p.mcp ?? null,
          }))
          return rows.length === 0 ? "（未配置 teams；在 oml.json 的 teams 下声明）" : JSON.stringify(rows, null, 2)
        }
        case "slop_check": {
          const root = args.target ?? state.directory
          const files = await readSources(root)
          if (files.length === 0) return `在 ${root} 下没找到可扫描的源码`
          const findings = scanSlop(files)
          if (findings.length === 0) return `扫描 ${files.length} 个文件：未发现 slop`
          const head = findings.slice(0, 40).map((f) => `${f.path}:${f.line} [${f.rule}] ${f.evidence}`)
          return [`扫描 ${files.length} 个文件：${summarizeSlop(findings)}`, ...head, findings.length > 40 ? `…还有 ${findings.length - 40} 处` : ""].join("\n")
        }
        case "compress_add": {
          // 从最近对话文本取原文兜底；模型应通过 sources 传全被压缩消息。
          const from = args.from ?? ""
          const to = args.to ?? ""
          const summary = args.text ?? ""
          const sources = args.sources ?? {}
          if (from === "" || to === "") return "compress_add 需要 from/to（被压缩的消息 id 区间）"
          const r = compressRange(state.compress, {
            from,
            to,
            summary,
            sources,
            savedTokens: Math.max(0, Number(args.savedTokens ?? 0)),
          })
          if (!r.ok) return r.reason
          state.saveCompress(r.store)
          return `已压缩为块 [${r.block.id}]（原 ${from}–${to}，省约 ${r.block.savedTokens} tok）。后续用 [[KEEP:${from}]] 保留关键原文。`
        }
        case "compress_list": {
          const blocks = listBlocks(state.compress)
          if (blocks.length === 0) return "（暂无压缩块）"
          return JSON.stringify(
            blocks.map((b) => ({ id: b.id, range: `${b.from}–${b.to}`, saved: b.savedTokens, summary: b.summary.slice(0, 120) })),
            null,
            2,
          )
        }
        case "decompress": {
          const blockId = args.target ?? ""
          const block = state.compress.blocks[blockId]
          if (block === undefined) return `没有压缩块 [${blockId}]`
          const mid = args.messageId ?? ""
          if (mid !== "") {
            const src = decompressSource(block, mid)
            return src === undefined ? `块 [${blockId}] 里没有原文 ${mid}` : src
          }
          return block.summary
        }
      }
    },
  })

  const omoMcp = tool({
    description:
      "MCP 网关。所有服务器默认禁用、不进系统提示；用 tools 看某服务器的工具，用 call 现场拉起并调用（用完销毁）。启用/禁用用 omo_admin action=mcp。",
    args: {
      action: tool.schema.enum(MCP_ACTIONS),
      server: tool.schema.string().optional().describe("MCP 服务器 id（omo_admin action=mcp op=show 可看）"),
      tool: tool.schema.string().optional().describe("call 的工具名"),
      args: tool.schema.string().optional().describe('call 的参数 JSON 字符串，如 {"path":"a.png"}'),
    },
    async execute(input) {
      bump(`mcp.${input.action}`)
      if (input.action === "sync") return await syncMcpCatalog(state)

      const server = input.server ?? ""
      if (server === "") return "需要 server=<id>；先用 omo_admin action=mcp op=show 看目录"
      const entry = state.mcpCatalog.entries[server]
      if (entry === undefined) return `没有登记 [${server}]；先 omo_admin action=mcp op=sync`
      if (entry.missing === true) return `[${server}] 已从宿主配置移除`
      const defs = await state.hostMcpDefs()
      const def = defs[server]
      if (def === undefined) return `宿主配置里找不到 [${server}]；先 op=sync`
      if (!entry.enabled) {
        return `[${server}] 当前禁用。先 omo_admin action=mcp op=enable target=${server}（会回写宿主配置）；本会话可直接再调本工具。`
      }

      if (input.action === "tools") {
        const session = await connectMcp(server, def)
        try {
          const tools = await session.listTools()
          state.saveMcpCatalog(markMcpUsed(state.mcpCatalog, server, tools.map((t) => t.name)))
          return tools.length === 0
            ? `[${server}] 没有工具`
            : tools.map((t) => `- ${t.name}${t.description === undefined ? "" : `：${t.description}`}`).join("\n")
        } finally {
          await session.close()
        }
      }

      const toolName = input.tool ?? ""
      if (toolName === "") return "call 需要 tool=<工具名>"
      let parsed: unknown = {}
      const rawArgs = input.args ?? ""
      if (rawArgs.trim() !== "") {
        try {
          parsed = JSON.parse(rawArgs)
        } catch {
          return "args 不是合法 JSON"
        }
      }
      const session = await connectMcp(server, def)
      try {
        const result = await session.callTool(toolName, parsed)
        state.saveMcpCatalog(markMcpUsed(state.mcpCatalog, server))
        return renderCallResult(result).slice(0, 20_000)
      } catch (err) {
        return `MCP 调用失败：${err instanceof Error ? err.message : String(err)}`
      } finally {
        await session.close()
      }
    },
  })

  return {
    omo_task: omoTask,
    omo_knowledge: omoKnowledge,
    omo_admin: omoAdmin,
    omo_mcp: omoMcp,
  }
}

/** 从会话文本记录里取最近一条，供技能选取。 */
export function latestText(map: Map<string, string>, sessionId: string | undefined): string {
  if (sessionId) {
    const hit = map.get(sessionId)
    if (hit) return hit
  }
  let last = ""
  for (const v of map.values()) last = v
  return last
}
