/**
 * OpenCode 1.x 宿主：把 OML 的纯函数内核接到一条真实插件上。
 *
 * 扬弃对象：旧 OMO 用 57 个 hook 位分别注入。这里只有 3 个 hook 位 + 6 个工具，
 * 注入只发生在 system.transform 一处，因此「最终提示有多大」永远可计量。
 */
import { tool, type Hooks, type PluginInput } from "@opencode-ai/plugin"
import {
  EMPTY_OVERRIDES,
  effectiveModel,
  loadGoal,
  loadMcpCatalog,
  applyMcpToHost,
  saveMcpCatalog as persistMcpCatalog,
  syncCatalog,
  type McpCatalog,
  type McpDef,
  loadOverrides,
  saveGoal,
  saveOverrides,
  clearGoal,
  type Goal,
  type ModelOverrides,
  loadMemory,
  saveMemory,
  renderMemories,
  addMemory,
  forgetMemory,
  reinforceMemory,
  topMemories,
  type MemoryStore,
  loadCompress,
  saveCompress,
  renderAllBlocks,
  type CompressStore,
  autoCheckDue,
  loadThirdLedger,
  runThirdUpgrade} from "@oml/core"
import {
  buildSystemPrompt,
  COMPACTION_RULES,
  defaultSkillRoots,
  stripSkillCatalog,
  gate,
  loadTasks,
  loadOmoCompat,
  loadUsage,
  expire,
  isTerminal,
  parseConfigText,
  resolveModel,
  resolveConfig,
  pruneTerminal,
  recordHit,
  recordMisses,
  eigenfluxHint,
  loadOwnership,
  saveOwnership,
  loadPa,
  savePa,
  pendingPa,
  registerOmlSession,
  saveTasks,
  saveUsage,
  scanSkills,
  statePath,
  DEFAULT_BUDGET_TOKENS,
  AGENTS,
  type BudgetReport,
  type OmlConfig,
  type SkillMeta,
  type OmoCompatResult,
  type SkillUsageMap,
  type TaskStore,
} from "@oml/core"
import { mkdir, readFile, writeFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { sdkTaskClient, type TaskClient } from "./client.ts"
import { buildTools, latestText, type HostState } from "./tools.ts"

export const OMO_MARKER = "<!-- omo:system -->"

/**
 * 视觉模型清单（模型 id，不含 provider 前缀）。
 * 依据 2026-11-17 对 8100 网关的纯色 PNG 探针：
 *   agnes-3.0-flash      红→红色 / 蓝→蓝色（真视觉）
 *   sensenova-6.8-flash  红→红色
 *   kimi-k3              吞图不回话（不可靠，不入表）
 *   glm-5.3              120s 超时（不入表）
 *   gemini-omni-*        名义视觉，当时 503（先入表，可用性是运行时问题）
 */
export const VISION_MODEL_IDS = new Set([
  "agnes-3.0-flash",
  "sensenova-6.8-flash",
  "sensenova-6.8-flash-lite",
  "gemini-omni-1.1-flash",
  "gemini-omni-1.2-flash",
  "gemini-omni-flash-preview",
])

export type AgentId = "sisyphus" | "sisyphus-junior" | "oracle" | "librarian" | "explore" | "momus"

export type OmoHostOptions = {
  config?: OmlConfig
  skillRoots?: string[]
  agentId?: AgentId
  /** 状态目录；默认 OML 状态根。测试注入临时目录以免污染真实状态。 */
  stateDir?: string
  /** 是否注册名为 task 的兼容工具（默认关；关闭旧 OMO 后再开，避免同名工具互撞）。 */
  taskAlias?: boolean
  /** 直接给定 MCP 定义（测试注入；默认从宿主 opencode.json 读）。 */
  mcpDefs?: Record<string, McpDef>
  /** 宿主配置路径（回写 enabled 用；测试注入临时文件，默认真实配置）。 */
  hostConfigPath?: string
}

/** 宿主真正需要的东西，比 PluginInput 窄，因此可以在测试里直接造。 */
export type HostInput = {
  directory: string
  client: TaskClient
}

async function readConfigFile(path: string): Promise<string | undefined> {
  try {
    return await readFile(path, "utf8")
  } catch {
    return undefined
  }
}

/**
 * 配置查找顺序：项目 oml.json → 用户 oml.json → 内置默认。
 * 无论有无 oml.json，都会再叠加一层原版 OMO 配置兼容（OML 自己的键优先），
 * 这样用户既有的模型绑定不必重填。
 */
async function loadConfig(directory: string): Promise<{ config: OmlConfig; source: string; text?: string }> {
  const omo = await loadOmoCompat()
  for (const p of [join(directory, "oml.json"), join(homedir(), ".config/opencode/oml.json")]) {
    const text = await readConfigFile(p)
    if (text === undefined) continue
    const parsed = parseConfigText(text)
    const mine = resolveConfig(parsed.config)
    return { config: mergeOmo(mine, omo), source: p, text }
  }
  return { config: mergeOmo(resolveConfig(parseConfigText("{}").config), omo), source: "(builtin)" }
}

/** 读宿主 opencode.json 的插件列表（3rd systems 升级判定 missing 用；读不到给空）。 */
async function hostPluginList(): Promise<string[]> {
  try {
    const text = await readFile(join(homedir(), ".config/opencode/opencode.json"), "utf8")
    const raw = JSON.parse(text) as { plugin?: unknown }
    const list = Array.isArray(raw.plugin) ? raw.plugin : []
    return list.filter((x): x is string => typeof x === "string")
  } catch {
    return []
  }
}

/** 读宿主 opencode.json 的 mcp 段（读不到给空，不猜）。 */
async function readHostMcpDefs(): Promise<Record<string, McpDef>> {
  try {
    const text = await readFile(join(homedir(), ".config/opencode/opencode.json"), "utf8")
    const raw = JSON.parse(text) as { mcp?: unknown }
    if (typeof raw.mcp !== "object" || raw.mcp === null) return {}
    const out: Record<string, McpDef> = {}
    for (const [id, value] of Object.entries(raw.mcp as Record<string, unknown>)) {
      if (typeof value !== "object" || value === null) continue
      const d = value as Record<string, unknown>
      const command = Array.isArray(d["command"])
        ? d["command"].filter((x): x is string => typeof x === "string")
        : undefined
      const env = d["environment"]
      const headers = d["headers"]
      out[id] = {
        type: d["type"] === "remote" ? "remote" : "local",
        ...(command === undefined ? {} : { command }),
        ...(typeof d["url"] === "string" ? { url: d["url"] } : {}),
        ...(typeof d["enabled"] === "boolean" ? { enabled: d["enabled"] } : {}),
        ...(typeof env === "object" && env !== null ? { environment: env as Record<string, string> } : {}),
        ...(typeof headers === "object" && headers !== null ? { headers: headers as Record<string, string> } : {}),
      }
    }
    return out
  } catch {
    return {}
  }
}

/** OML 显式配置优先；OMO 只补空缺。 */
function mergeOmo(mine: OmlConfig, omo: OmoCompatResult): OmlConfig {
  if (!omo.found) return mine
  return {
    ...mine,
    agents: { ...(omo.config.agents ?? {}), ...(mine.agents ?? {}) },
    categories: { ...(omo.config.categories ?? {}), ...(mine.categories ?? {}) },
  }
}

export async function createOmoHost(input: PluginInput, options: OmoHostOptions = {}): Promise<Hooks> {
  return createHostCore({ directory: input.directory, client: sdkTaskClient(input.client) }, options)
}

/** 可测试的宿主核心：不碰 PluginInput，只依赖窄接口。 */
export async function createHostCore(input: HostInput, options: OmoHostOptions = {}): Promise<Hooks> {
  const found = options.config === undefined ? await loadConfig(input.directory) : { config: options.config, source: "(options)" }
  const config = found.config
  const builtinSkills = join(import.meta.dir, "..", "skills")
  const roots =
    options.skillRoots ??
    (config.skills?.roots && config.skills.roots.length > 0
      ? config.skills.roots
      : [builtinSkills, ...defaultSkillRoots()])

  const dir = options.stateDir
  const usageFile = dir ? join(dir, "skill-usage.json") : undefined
  const tasksFile = dir ? join(dir, "tasks.json") : undefined
  const logFile = dir ? join(dir, "budget.log") : statePath("budget.log")

  const disabledSkills = new Set(config.disabled_skills ?? [])
  // 宿主内置技能不在磁盘上，扫描扫不到；但它的目录条目已被我们剥离，
  // 所以必须由 OML 自己补一条，否则 customize-opencode 会从视野里消失。
  const BUILTIN_SKILLS: readonly SkillMeta[] = [
    {
      name: "customize-opencode",
      description:
        "编辑 opencode 自身配置时使用：opencode.json、.opencode/、~/.config/opencode/、agent/plugin/MCP/权限",
      root: "<built-in>",
      file: "<built-in>",
    },
  ]
  const scanned = (await scanSkills(roots)).filter((s) => !disabledSkills.has(s.name))
  const skills: SkillMeta[] = [
    ...BUILTIN_SKILLS.filter((b) => !disabledSkills.has(b.name) && !scanned.some((s) => s.name === b.name)),
    ...scanned,
  ]
  let usage: SkillUsageMap = await loadUsage(usageFile)
  let store: TaskStore = await loadTasks(tasksFile)
  const goalFile = dir ? join(dir, "goal.json") : statePath("goal.json")
  const overridesFile = dir ? join(dir, "model-overrides.json") : statePath("model-overrides.json")
  const memoryFile = dir ? join(dir, "memory.json") : statePath("memory.json")
  const compressFile = dir ? join(dir, "compress.json") : statePath("compress.json")
  const checkpointDir = dir ? join(dir, "checkpoints") : statePath("checkpoints")
  const mcpFile = dir ? join(dir, "mcp.json") : statePath("mcp.json")
  let goal: Goal | null = await loadGoal(goalFile)
  let memory: MemoryStore = await loadMemory(memoryFile)
  let compress: CompressStore = await loadCompress(compressFile)
  let overrides: ModelOverrides = await loadOverrides(overridesFile)
  let mcpCatalog: McpCatalog = await loadMcpCatalog(mcpFile)
  const ownershipFile = dir ? join(dir, "session-owners.json") : undefined
  const paFile = dir ? join(dir, "pending-pa.json") : undefined
  let ownershipLedger: import("@oml/core").OwnershipLedger = await loadOwnership(ownershipFile)
  let paQueue: import("@oml/core").PaQueue = await loadPa(paFile)

  const sessionImages = new Set<string>()

  const state: HostState = {
    config,
    skills,
    usage,
    store,
    directory: input.directory,
    client: input.client,
    sessionText: new Map(),
    sessionImages,
    sessionTitles: new Map(),
    ownership: ownershipLedger,
    paQueue,
    saveOwnership(next) {
      ownershipLedger = next
      state.ownership = next
      void saveOwnership(next, ownershipFile).catch((err: unknown) => {
        console.warn(`[omo] 保存所有权账本失败: ${err instanceof Error ? err.message : String(err)}`)
      })
    },
    savePa(next) {
      paQueue = next
      state.paQueue = next
      void savePa(next, paFile).catch((err: unknown) => {
        console.warn(`[omo] 保存 PA 队列失败: ${err instanceof Error ? err.message : String(err)}`)
      })
    },
    saveUsage(next) {
      usage = next
      state.usage = next
      void saveUsage(next, usageFile).catch((err: unknown) => {
        console.warn(`[omo] 保存技能用量失败: ${err instanceof Error ? err.message : String(err)}`)
      })
    },
    saveTasks(next) {
      store = next
      state.store = next
      void saveTasks(next, tasksFile).catch((err: unknown) => {
        console.warn(`[omo] 保存任务账本失败: ${err instanceof Error ? err.message : String(err)}`)
      })
    },
    overrides: EMPTY_OVERRIDES,
    stats: { startedAt: Date.now(), calls: {} },
    memory,
    compress,
    saveCompress(next: CompressStore) {
      compress = next
      state.compress = next
      void saveCompress(next, compressFile).catch((err: unknown) => {
        console.warn(`[omo] 保存压缩块失败: ${err instanceof Error ? err.message : String(err)}`)
      })
    },
    saveMemory(next: MemoryStore) {
      memory = next
      state.memory = next
      void saveMemory(next, memoryFile).catch((err: unknown) => {
        console.warn(`[omo] 保存记忆失败: ${err instanceof Error ? err.message : String(err)}`)
      })
    },
    saveOverrides(next: ModelOverrides) {
      overrides = next
      state.overrides = next
      void saveOverrides(next, overridesFile).catch((err: unknown) => {
        console.warn(`[omo] 保存模型覆盖失败: ${err instanceof Error ? err.message : String(err)}`)
      })
    },
    modelFor(agentId?: string, categoryId?: string, explicit?: string) {
      return effectiveModel({
        overrides,
        config,
        ...(agentId === undefined ? {} : { agentId }),
        ...(categoryId === undefined ? {} : { categoryId }),
        ...(explicit === undefined ? {} : { explicit }),
      })
    },
    async checkpoint(sessionId?: string) {
      await mkdir(checkpointDir, { recursive: true })
      const stamp = new Date().toISOString().replace(/[:.]/g, "-")
      const path = join(checkpointDir, `${stamp}.json`)
      const report = state.measure()
      await writeFile(
        path,
        `${JSON.stringify(
          {
            at: new Date().toISOString(),
            ...(sessionId === undefined ? {} : { sessionId }),
            ...(sessionId === undefined ? {} : { lastPrompt: state.sessionText.get(sessionId) ?? null }),
            report,
            tasks: store,
            usage,
            goal,
            overrides,
            memory,
            compress,
          },
          null,
          2,
        )}\n`,
        "utf8",
      )
      return path
    },
    getGoal: () => goal,
    async setGoal(text: string) {
      goal = await saveGoal(text, goalFile)
      return goal
    },
    async clearGoal() {
      const removed = await clearGoal(goalFile)
      goal = null
      return removed
    },
    measure(taskText?: string): BudgetReport {
      return buildSystemPrompt({
        config,
        ...(options.agentId ? { agentId: options.agentId } : {}),
        skills,
        usage,
        goal: goal?.text ?? null,
        ...(renderMemories(memory) !== "" ? { memory: renderMemories(memory) } : {}),
        ...(taskText !== undefined && taskText !== "" ? { taskText } : {}),
      }).report
    },
  settingsPath: found.source === "(builtin)" ? undefined : found.source,
  settingsText: found.text,
  thirdPlugins: await hostPluginList(),
  mcpCatalog,
  saveMcpCatalog(next) {
    mcpCatalog = next
    state.mcpCatalog = next
    void persistMcpCatalog(next, mcpFile).catch((err: unknown) => {
      console.warn(`[omo] 保存 MCP 目录失败: ${err instanceof Error ? err.message : String(err)}`)
    })
  },
  async hostMcpDefs() {
    return options.mcpDefs ?? (await readHostMcpDefs())
  },
  async writeHostMcp(catalog) {
    const path = options.hostConfigPath ?? join(homedir(), ".config/opencode/opencode.json")
    const text = await readFile(path, "utf8")
    const raw = JSON.parse(text) as Record<string, unknown>
    const { config: nextConfig, changed } = applyMcpToHost(raw, catalog)
    if (changed.length > 0) {
      const stamp = new Date().toISOString().replace(/[:.]/g, "-")
      await writeFile(`${path}.bak-mcp-${stamp}`, text, "utf8")
      await writeFile(path, `${JSON.stringify(nextConfig, null, 2)}\n`, "utf8")
    }
    return { path, changed }
  },
  }

  const limit = config.budget?.limit ?? DEFAULT_BUDGET_TOKENS
  const off = new Set(config.disabled_hooks ?? [])

  // MCP 自检：启动时对齐宿主的 mcp 段。新增/定义变化只降级为「待复核」，
  // 不替用户决定装了什么就该跑起来；消失的保留条目但标 missing。
  void (async () => {
    try {
      const defs = await state.hostMcpDefs()
      const r = syncCatalog(state.mcpCatalog, defs)
      if (r.added.length + r.changed.length + r.gone.length > 0) {
        state.saveMcpCatalog(r.catalog)
        console.warn(
          `[omo] MCP 目录已更新：新增 ${r.added.join(",") || "-"}；变化 ${r.changed.join(",") || "-"}；消失 ${r.gone.join(",") || "-"}。查看：omo_admin action=mcp op=show`,
        )
      }
    } catch (err) {
      console.warn(`[omo] MCP 自检失败: ${err instanceof Error ? err.message : String(err)}`)
    }
  })()

  const tools = buildTools(state)
  for (const name of config.disabled_tools ?? []) delete tools[name]
  const taskAlias = options.taskAlias ?? config.compat?.taskAlias === true
  if (taskAlias && tools["omo_task"]) tools["task"] = tools["omo_task"]

  // 原生 skill 工具会把**全部**技能描述塞进系统提示（本机实测 ~6 万 token）。
  // 换成按需读取：只保留一个 skill(name) 工具，正文现取。
  const skillTool = config.compat?.skillTool !== false
  const nativeSkills = config.compat?.nativeSkills === true
  const knowledge = tools["omo_knowledge"]
  if (skillTool && knowledge) {
    tools["skill"] = {
      description: "加载某个技能的完整说明（先用 omo_knowledge action=skill 找到名字）。",
      args: { name: tool.schema.string().describe("技能名") },
      async execute(args, ctx) {
        const result = await knowledge.execute({ action: "skill_read", name: String(args.name) }, ctx)
        const text = typeof result === "string" ? result : result.output
        if (!text.startsWith("无此技能") && !text.startsWith("读取失败")) {
          state.saveUsage(recordHit(state.usage, String(args.name), Date.now()))
        }
        return result
      },
    }
  }

  const hooks: Hooks = { tool: tools }
  const disabledAgents = new Set(config.disabled_agents ?? [])
  // 内置 agent 也要显式覆盖：否则拿不到它们的条目，就关不掉原生 skill 工具，
  // 而原生 skill 工具会把全部技能描述塞进系统提示（本机实测 ~5 万 token）。
  const BUILTIN_AGENTS = ["build", "plan", "general", "explore"] as const

  if (!off.has("config")) {
    hooks.config = async (cfg) => {
      const user = (cfg.agent ?? {}) as Record<string, Record<string, unknown> | undefined>
      const agents: Record<string, unknown> = {}
      for (const a of AGENTS) {
        if (disabledAgents.has(a.id)) continue
        const u = user[a.id] ?? {}
        const pick = resolveModel(a.id, a.category, config)
        agents[a.id] = {
          ...u,
          description: u["description"] ?? a.purpose,
          mode: u["mode"] ?? (a.tier === "primary" ? "all" : "subagent"),
          prompt: u["prompt"] ?? a.prompt,
          // 颜色与 OMO 对齐；用户显式配置优先
          ...(u["color"] === undefined && a.color !== undefined ? { color: a.color } : {}),
          ...(pick.model === null ? {} : { model: u["model"] ?? pick.model }),
          // 推理等级：用户显式配置优先，否则用 oml.json 的 variant
          ...(pick.variant === undefined ? {} : { variant: (u["variant"] as string | undefined) ?? pick.variant }),
          ...(a.readonly
            ? { tools: { ...((u["tools"] as Record<string, boolean> | undefined) ?? {}), edit: false, write: false, patch: false } }
            : {}),
        }
      }
      // 内置 agent 只补空缺（它们的 tools 也要被关掉原生 skill，见下）
      for (const id of BUILTIN_AGENTS) {
        if (disabledAgents.has(id)) continue
        if (agents[id] === undefined) agents[id] = user[id] ?? {}
      }
      if (!nativeSkills) {
        for (const [id, spec] of Object.entries(agents)) {
          if (spec === undefined || typeof spec !== "object") continue
          const entry = spec as { tools?: Record<string, boolean> }
          agents[id] = { ...entry, tools: { ...(entry.tools ?? {}), skill: false } }
        }
      }
      // 配置层权限绕过（学原版 OMO：dist/index.js:163166）——在权限弹窗之前生效，
      // 这是 /dev、/proc 等 external_directory 访问不被 PA 拦截的唯一可靠路径。
      // 插件 permission.ask 钩子拦不到配置层校验，故必须走 config.permission。
      // permissions:false 时完全不注入，回到宿主默认每次询问。
      if (config.permissions !== false) {
        const cfgRecord = cfg as unknown as Record<string, unknown>
        const userPerm = (cfgRecord["permission"] ?? {}) as Record<string, unknown>
        cfgRecord["permission"] = {
          webfetch: "allow",
          external_directory: "allow",
          ...userPerm, // 用户显式配置优先
        }
      }

      cfg.agent = agents as typeof cfg.agent
      // 启动默认代理：Sisyphus（1.19+ 支持 default_agent；必须是 primary 才生效，否则宿主回落到 build）。
      // 装的 SDK 类型是 1.14（无此字段），故经 Record 视图赋值；运行时 1.19.3 已确认支持。
      ;(cfg as unknown as Record<string, unknown>)["default_agent"] = "sisyphus"
    }
  }

  if (!off.has("chat.message")) {
    hooks["chat.message"] = async (hookInput, output) => {
      const texts: string[] = []
      for (const part of output.parts) {
        if (part.type === "text") texts.push(part.text)
      }
      const text = texts.join("\n").trim()
      if (text !== "") state.sessionText.set(hookInput.sessionID, text)
      // 视觉路由：记住哪个会话里出现过图片/PDF，system.transform 据此决定是否给提示。
      const partLike = output.parts as Array<{ type: string; mime?: string }>
      const hasVisual = partLike.some(
        (p) => p.type === "image" || (p.type === "file" && typeof p.mime === "string" && (p.mime.startsWith("image/") || p.mime === "application/pdf")),
      )
      if (hasVisual) sessionImages.add(hookInput.sessionID)

      // 滚动检查点：不指望模型自觉写 handoff。每一轮用户发言（60 秒限流）把
      // 任务账本 + 预算 + 目标落一次盘，进程被 kill 也还有可读的现状。
      // 这不是压缩，是给「恢复」留一个不依赖模型纪律的锚点。
      if (Date.now() - lastRollingCheckpoint > 15_000) {
        lastRollingCheckpoint = Date.now()
        void state.checkpoint(hookInput.sessionID).catch((err: unknown) => {
          console.warn(`[omo] 滚动检查点失败: ${err instanceof Error ? err.message : String(err)}`)
        })
      }
    }
  }

  if (!off.has("event")) {
    hooks.event = async (eventInput) => {
      const type = eventType(eventInput.event)
      const sessionId = eventSessionId(eventInput.event)
      if (type === "session.deleted" && sessionId) {
        state.sessionText.delete(sessionId)
        return
      }
      if (type === "session.idle") {
        const ttl = config.tasks?.ttlMs ?? 1_800_000
        const stale = Object.values(store.tasks).some((t) => !isTerminal(t.status) && Date.now() - t.updatedAt > ttl)
        const swept = stale ? expire(store, Date.now(), ttl) : store
        const next = pruneTerminal(swept, 50)
        if (next !== store) state.saveTasks(next)
      }
      if (type === "session.start") {
        // 3rd systems 自动升级检查（oml.json 第 18 键 third.autoUpgrade，默认开）：
        // 24h 节流、fire-and-forget——失败只告警，绝不伤会话。
        void (async () => {
          const ledger = await loadThirdLedger()
          if (!autoCheckDue(ledger, Date.now())) return
          const res = await runThirdUpgrade({ config, host: { name: "opencode" } })
          for (const r of res.results) {
            if (r.acted) console.warn(`[omo] 3rd systems ${r.system}：${r.note}`)
          }
        })().catch((err: unknown) => {
          console.warn(`[omo] 3rd systems 检查失败：${err instanceof Error ? err.message : String(err)}`)
        })
      }
    }
  }

  // 权限策略（oml.json 第 16 键，默认全放行）：主代理及其 omo_task 子会话的权限
  // 请求一律 allow，编排流水线不因「Permission required」中断。
  // config.permissions === false 时不注册此钩子，回到宿主默认「每次询问」，
  // 由宿主 commands 面板/配置接管细粒度控制。
  if (!off.has("permission.ask") && config.permissions !== false) {
    hooks["permission.ask"] = async (input, output) => {
      output.status = "allow"
      console.debug(`[omo] 权限自动放行：${input.type} ${input.pattern ?? ""}`.trim())
    }
  }

  let lastAutoCheckpoint = 0
  let lastRollingCheckpoint = 0 // 首轮就写一次：被 kill 时才有东西可读

  if (!off.has("system.transform")) {
    hooks["experimental.chat.system.transform"] = async (hookInput, output) => {
      if (output.system.some((s) => s.includes(OMO_MARKER))) return

      // 宿主核心会把它扫到的全部技能逐条写进系统提示。OML 的唯一职责就是在这里
      // 把它删掉，换成自己那张按任务相关性筛过的表——否则「惰性索引」只是叠加。
      const stripped = stripSkillCatalog(output.system)
      if (stripped.found) {
        output.system.splice(0, output.system.length, ...stripped.parts)
      }

      const taskText = latestText(state.sessionText, hookInput.sessionID)
      const review = Object.values(state.mcpCatalog.entries).filter((e) => e.needsReview && e.missing !== true)
      const mcpHint =
        review.length === 0
          ? ""
          : `## MCP 待复核\n- ${review.map((e) => e.id).join("、")}：默认禁用且不进提示。需要时 \`omo_admin action=mcp op=enable target=<id>\`，用完 \`op=disable\`；调用走 \`omo_mcp action=call\`。`
      const built = buildSystemPrompt({
        config,
        ...(options.agentId ? { agentId: options.agentId } : {}),
        skills,
        usage,
        goal: goal?.text ?? null,
        ...(renderMemories(memory) !== "" ? { memory: renderMemories(memory) } : {}),
        ...(taskText !== "" ? { taskText } : {}),
        ...(mcpHint === "" ? {} : { extraIdentity: mcpHint }),
      })

      const nextUsage = recordMisses(usage, built.indexedSkills.map((s) => s.name))
      if (nextUsage !== usage) {
        usage = nextUsage
        state.usage = nextUsage
      }

      const blocks = renderAllBlocks(compress)

      // 视觉路由：会话出现过图且当前模型看不见 → 一行提示（命中才出，预算外追加区）。
      // 判断顺序：模型自身声明的 capabilities.input（image/pdf）优先，静态清单兜底
      // （本地网关目录不一定填能力位）。
      const cap = hookInput.model?.capabilities?.input
      const modelId = hookInput.model?.id ?? ""
      const canSee = (cap?.image ?? cap?.pdf) === true || VISION_MODEL_IDS.has(modelId)
      const sid = hookInput.sessionID ?? ""
      const visionHint =
        sessionImages.has(sid) && !canSee
          ? `\n## 视觉\n- 本会话消息含图片/PDF，当前模型 ${modelId || "?"} 不可见：用 omo_admin action=model op=set target=agent:${options.agentId ?? "sisyphus"} model=<视觉模型> 切换，或 omo_task 派 multimodal-looker。`
          : ""

      // 会话身份：让每个会话（主会话派出的子会话）在自己的系统提示里看到「我是谁」，
      // 隶属链已经写进标题，主代理据此分辨 omo tX 分不清的隶属关系。
      const ownTitle = state.sessionTitles.get(sid)
      const identityHint = ownTitle === undefined ? "" : `\n## 会话身份\n- 本会话标题：${ownTitle}`

      // EigenFlux 主动提示：命中"外部事实/找 agent/广播"等场景才注（预算外追加区）。
      // 只读检索可主动；写操作内嵌"先取得用户授权"红线；心跳会话内不主动跑。
      const efHint = eigenfluxHint(taskText, { enabled: config.eigenflux?.proactive !== false })

      // PA 待批提示：让人类在此会话看到待裁决的授权请求（含工作说明+高价值警告）。
      // 预算外追加区，与 efHint 同类。所有权铁律常驻一行：删/改写他建会话前必查归属。
      const pending = pendingPa(state.paQueue)
      const ownershipRule = `\n## 会话所有权\n- 只可无 PA 删除自己创建的会话；删除/改写他人会话须先 omo_admin action=pa op=request 取得人类授权。\n- 查不明归属会话（可能是人类建的）：omo_admin action=pa op=list reconcile=true`
      const paHint = ownershipRule + (pending.length === 0
        ? ""
        : `\n## 待批权限（PA）\n${pending.map((r) =>
            `- [${r.id}] ${r.operation} ${r.sessionTitle ?? r.sessionId}（${r.owner}${r.highValue ? "，⚠高价值：清除前必须确认其工作说明" : ""}）\n  说明：${r.reason || "(无)"}\n  裁决：omo_admin action=pa op=approve/deny target=${r.id}`,
          ).join("\n")}`)

      // 主动控制：占用过八成就不再依赖模型自觉，直接把状态落盘成检查点。
      // 每 10 分钟最多一次，避免每轮 flush 写盘。
      const pct = Math.round((built.report.totalTokens / Math.max(1, built.report.budget.limit)) * 100)
      let rescue = ""
      if (pct >= 85 && Date.now() - lastAutoCheckpoint > 600_000) {
        lastAutoCheckpoint = Date.now()
        try {
          const path = await state.checkpoint()
          rescue = `\n\n<auto-checkpoint pct="${pct}">已自动保存检查点：${path}。现在可以安全压缩：先 omo_admin action=checkpoint 记录结论，再对本轮之前的内容做压缩。</auto-checkpoint>`
        } catch (err) {
          console.warn(`[omo] 自动检查点失败: ${err instanceof Error ? err.message : String(err)}`)
        }
      }

      output.system.push(`${OMO_MARKER}\n${built.prompt}${blocks === "" ? "" : `\n\n${blocks}`}${rescue}${visionHint}${identityHint}${efHint}${paHint}`)

      void gate({ sections: built.sections }, { limit, logPath: logFile }).catch(
        (err: unknown) => {
          console.warn(`[omo] 预算记账失败: ${err instanceof Error ? err.message : String(err)}`)
        },
      )
    }
  }

  if (!off.has("compaction")) {
    hooks["experimental.session.compacting"] = async (_hookInput, output) => {
      const live = Object.values(state.store.tasks).filter((t) => t.status === "running" || t.status === "pending")
      const blocks = renderAllBlocks(compress)
      const lines = [COMPACTION_RULES]
      if (live.length > 0) {
        lines.push(
          `未终结任务：${live.map((t) => `${t.id}(${t.status}) ${t.description}`).join("；")}`,
        )
      }
      if (goal?.text) lines.push(`当前目标：${goal.text}`)
      if (blocks !== "") lines.push(`OML 已有压缩块（可直接引用，勿重复总结）：\n${blocks}`)
      output.context.push(`<omo-compaction>\n${lines.join("\n")}\n</omo-compaction>`)
    }
  }

  return hooks
}

function eventType(event: unknown): string | undefined {
  if (typeof event !== "object" || event === null || !("type" in event)) return undefined
  const t = event.type
  return typeof t === "string" ? t : undefined
}

function eventSessionId(event: unknown): string | undefined {
  if (typeof event !== "object" || event === null || !("properties" in event)) return undefined
  const props = event.properties
  if (typeof props !== "object" || props === null || !("sessionID" in props)) return undefined
  const id = props.sessionID
  return typeof id === "string" ? id : undefined
}
