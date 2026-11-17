/**
 * 统一任务状态机 —— 替代 OMO 的六处状态：background-agent、boulder-state、
 * ralph-loop、run-continuation-state、task-resume-info、task-toast-manager。
 *
 * 一个文件、五个状态。终态默认不可逆——唯一例外是 resume：done/failed 可以回到
 * running，但必须累加 attempts 并把上一轮的错误留在 lastError 里，否则「曾经失败过」
 * 这条信息会被静默抹掉。cancelled 永久终态（取消是人的意图，不是可重试的故障）。
 */

import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { statePath } from "../paths.ts"

export const TASK_STATUSES = ["pending", "running", "done", "failed", "cancelled"] as const
export type TaskStatus = (typeof TASK_STATUSES)[number]

export type TaskKind = "task" | "team"

export interface TaskMember {
  readonly taskId: string
  readonly role: string
  readonly model?: string
}

export interface TaskRecord {
  id: string
  parentId: string | null
  depth: number
  description: string
  /** team = 一个群组任务，members 指向它的子任务 */
  kind?: TaskKind
  members?: readonly TaskMember[]
  category: string
  agent?: string
  /** 本次任务的显式模型（provider/model）；空则按 agent/category 解析 */
  model?: string
  status: TaskStatus
  /** 第几次尝试；resume 会让它 +1，首次为 1 */
  attempts?: number
  /** 上一轮失败原因（resume 后仍保留） */
  lastError?: string
  createdAt: number
  updatedAt: number
  sessionId?: string
  result?: string
  error?: string
}

export interface TaskStore {
  version: 1
  tasks: Record<string, TaskRecord>
  /** ID 高水位：prune 之后不回退，防止 t1 被复用到无关的新任务上（BUG-2）。 */
  lastId?: number
}

const LEGAL: Readonly<Record<TaskStatus, readonly TaskStatus[]>> = {
  pending: ["running", "cancelled"],
  running: ["done", "failed", "cancelled"],
  // resume：续接同一子会话继续干。只加这两条，cancelled 仍然不可逆。
  done: ["running"],
  failed: ["running"],
  cancelled: [],
}

export function emptyStore(): TaskStore {
  return { version: 1, tasks: {} }
}

export function tasksPath(): string {
  return statePath("tasks.json")
}

/** t1、t2……按高水位递增；lastId 在 prune 后仍保留，编号永不回退（BUG-2）。 */
export function nextTaskId(store: TaskStore): string {
  let max = store.lastId ?? 0
  for (const id of Object.keys(store.tasks)) {
    const n = Number.parseInt(id.replace(/^t/, ""), 10)
    if (Number.isFinite(n) && n > max) max = n
  }
  return `t${max + 1}`
}

export type AddResult =
  | { ok: true; store: TaskStore; task: TaskRecord }
  | { ok: false; reason: string }

export interface AddInput {
  description: string
  category: string
  parentId?: string | null
  agent?: string
  /** 显式模型（provider/model）；缺省时由 effectiveModel 解析 */
  model?: string
  kind?: TaskKind
  members?: readonly TaskMember[]
  now?: number
  maxDepth?: number
}

/** 新建任务。约束：深度不超过 maxDepth（默认 2），父任务必须存在且未终结。 */
export function addTask(store: TaskStore, input: AddInput): AddResult {
  const now = input.now ?? Date.now()
  const maxDepth = input.maxDepth ?? 2
  const parentId = input.parentId ?? null
  let depth = 0

  if (parentId !== null) {
    const parent = store.tasks[parentId]
    if (parent === undefined) return { ok: false, reason: `父任务 ${parentId} 不存在` }
    if (parent.status === "done" || parent.status === "failed" || parent.status === "cancelled") {
      return { ok: false, reason: `父任务 ${parentId} 已终结（${parent.status}），不能再派生` }
    }
    depth = parent.depth + 1
    if (depth > maxDepth) return { ok: false, reason: `任务深度 ${depth} 超过上限 ${maxDepth}` }
  }

  const id = nextTaskId(store)
  const newLastId = Math.max(store.lastId ?? 0, Number.parseInt(id.slice(1), 10))
  const task: TaskRecord = {
    id,
    parentId,
    depth,
    description: input.description,
    category: input.category,
    ...(input.agent === undefined ? {} : { agent: input.agent }),
    ...(input.model === undefined ? {} : { model: input.model }),
    ...(input.kind === undefined ? {} : { kind: input.kind }),
    ...(input.members === undefined ? {} : { members: input.members }),
    status: "pending",
    createdAt: now,
    updatedAt: now,
  }
  return { ok: true, store: { ...store, lastId: newLastId, tasks: { ...store.tasks, [task.id]: task } }, task }
}

/** 把成员登记到团队任务上（成员只有在 spawn 之后才知道 id，所以不能在 addTask 时一次写完）。 */
export function attachMembers(store: TaskStore, id: string, members: readonly TaskMember[]): TaskStore {
  const current = store.tasks[id]
  if (current === undefined) return store
  return { ...store, tasks: { ...store.tasks, [id]: { ...current, members, updatedAt: Date.now() } } }
}

export type TransitionResult =
  | { ok: true; store: TaskStore; task: TaskRecord }
  | { ok: false; reason: string }

export interface TransitionPatch {
  sessionId?: string
  result?: string
  error?: string
  now?: number
}

/** 合法迁移才写；否则返回原因，不改状态（让调用方看到矛盾，而不是被静默吞掉）。 */
export function transition(
  store: TaskStore,
  id: string,
  next: TaskStatus,
  patch: TransitionPatch = {},
): TransitionResult {
  const current = store.tasks[id]
  if (current === undefined) return { ok: false, reason: `任务 ${id} 不存在` }
  const legal = LEGAL[current.status]
  if (legal === undefined) {
    return { ok: false, reason: `任务 ${id} 状态非法：${String(current.status)}` }
  }
  if (!legal.includes(next)) {
    return { ok: false, reason: `非法迁移 ${current.status} → ${next}（${id}）` }
  }
  const resuming = next === "running" && (current.status === "done" || current.status === "failed")
  // resume 时的错误来源：本轮 patch.error 优先（如"续接后启动即失败"），否则沿用上一轮 current.error。
  // 两者都没给才不写 lastError——避免 BUG-3：patch.error 被无条件 delete 后彻底蒸发。
  const resumeErr = patch.error ?? current.error
  const updated: TaskRecord = {
    ...current,
    status: next,
    ...(resuming ? { attempts: (current.attempts ?? 1) + 1 } : {}),
    ...(resuming && resumeErr !== undefined ? { lastError: resumeErr } : {}),
    updatedAt: patch.now ?? Date.now(),
    ...(patch.sessionId === undefined ? {} : { sessionId: patch.sessionId }),
    ...(patch.result === undefined ? {} : { result: patch.result }),
    ...(patch.error === undefined ? {} : { error: patch.error }),
  }
  if (resuming) {
    delete updated.error // 失败历史已搬进 lastError，不再算「当前错误」
    delete updated.result // 上一轮的陈旧结果不能挂在新一轮 running 上（BUG-4）
  }
  return { ok: true, store: { ...store, tasks: { ...store.tasks, [id]: updated } }, task: updated }
}

/**
 * 终态显式定义，不再用「有没有出边」反推。
 * 反推的写法在加了 resume（done/failed → running）之后立刻失真：
 * done 不再是零出边，于是 isTerminal 返回 false，并发上限、prune、liveChildren 全线失效。
 */
const TERMINAL: ReadonlySet<TaskStatus> = new Set(["done", "failed", "cancelled"])

export function isTerminal(status: TaskStatus): boolean {
  return TERMINAL.has(status)
}

/** 某父任务下仍在运行/待运行的孩子。 */
export function liveChildren(store: TaskStore, parentId: string | null): TaskRecord[] {
  return Object.values(store.tasks)
    .filter((t) => t.parentId === parentId && !isTerminal(t.status))
    .sort((a, b) => a.createdAt - b.createdAt || a.id.localeCompare(b.id))
}

export function runningCount(store: TaskStore): number {
  return Object.values(store.tasks).filter((t) => t.status === "running").length
}

/** 并发闸门：返回拒绝原因，null 表示可以派生。 */
export function concurrencyReason(store: TaskStore, limit: number): string | null {
  const running = runningCount(store)
  return running >= limit ? `并发已达上限 ${limit}（运行中 ${running}）` : null
}

/** 超时回收：把 pending/running 且超过 ttl 的任务标为 failed（不是 cancelled——它确实失败了）。 */
export function expire(store: TaskStore, now: number, ttlMs: number): TaskStore {
  const tasks: Record<string, TaskRecord> = {}
  for (const [id, t] of Object.entries(store.tasks)) {
    const stale = !isTerminal(t.status) && now - t.updatedAt > ttlMs
    tasks[id] = stale ? { ...t, status: "failed", updatedAt: now, error: `超时 ${ttlMs}ms 未完成` } : t
  }
  return { ...store, tasks }
}

/** 清理终态任务，只保留最近 keep 个（防状态文件无限增长）。 */
export function pruneTerminal(store: TaskStore, keep: number): TaskStore {
  const all = Object.values(store.tasks)
  const terminal = all
    .filter((t) => isTerminal(t.status))
    .sort((a, b) => b.updatedAt - a.updatedAt)

  // 子→父索引：用于判断某终态任务是否仍有活着的后代（BUG-1）。
  const childrenOf = new Map<string, TaskRecord[]>()
  for (const t of all) {
    if (t.parentId === null) continue
    const siblings = childrenOf.get(t.parentId) ?? []
    siblings.push(t)
    childrenOf.set(t.parentId, siblings)
  }
  const hasLiveDescendant = (id: string): boolean => {
    for (const child of childrenOf.get(id) ?? []) {
      if (!isTerminal(child.status) || hasLiveDescendant(child.id)) return true
    }
    return false
  }

  // 只删「没有活后代」的终态任务，避免留下 parentId 指向已删父任务的孤儿（BUG-1）。
  const drop = new Set(
    terminal.slice(keep).filter((t) => !hasLiveDescendant(t.id)).map((t) => t.id),
  )
  if (drop.size === 0) return store
  const tasks: Record<string, TaskRecord> = {}
  for (const [id, t] of Object.entries(store.tasks)) if (!drop.has(id)) tasks[id] = t
  return { ...store, tasks }
}

export async function loadTasks(path: string = tasksPath()): Promise<TaskStore> {
  try {
    const parsed: unknown = JSON.parse(await readFile(path, "utf8"))
    if (typeof parsed !== "object" || parsed === null) return emptyStore()
    const maybe = parsed as { version?: unknown; tasks?: unknown; lastId?: unknown }
    if (maybe.version !== 1 || typeof maybe.tasks !== "object" || maybe.tasks === null) {
      return emptyStore()
    }
    // 逐条校验：未知 status 的脏记录会让 transition 抛 TypeError（BUG-5）。
    // 丢弃它们而不是让整本账本带病运行；高水位 lastId 必须保留，否则 prune 后编号回退（BUG-2）。
    const tasks: Record<string, TaskRecord> = {}
    for (const [id, raw] of Object.entries(maybe.tasks)) {
      if (typeof raw !== "object" || raw === null) continue
      const rec = raw as Partial<TaskRecord>
      if (rec.id !== id || typeof rec.status !== "string" || !(rec.status in LEGAL)) continue
      tasks[id] = rec as TaskRecord
    }
    const lastId = typeof maybe.lastId === "number" && Number.isFinite(maybe.lastId)
      ? maybe.lastId
      : undefined
    return { version: 1, tasks, ...(lastId === undefined ? {} : { lastId }) }
  } catch {
    return emptyStore()
  }
}

/** 原子写：先写 .tmp 再 rename，避免进程被杀时留下半个 JSON。 */
let tmpSeq = 0

export async function saveTasks(store: TaskStore, path: string = tasksPath()): Promise<void> {
  const write = async (): Promise<void> => {
    await mkdir(dirname(path), { recursive: true })
    // 每次写用独立临时名：并发写同一账本时不会互相 rename 掉对方的 .tmp
    const tmp = `${path}.${process.pid}.${++tmpSeq}.tmp`
    await writeFile(tmp, JSON.stringify(store, null, 2), "utf8")
    await rename(tmp, path)
  }
  try {
    await write()
  } catch (err) {
    // 状态目录可能被外部清掉（整风/清理脚本）；重建再试一次，仍失败才上报。
    if ((err as { code?: string }).code !== "ENOENT") throw err
    await write()
  }
}
