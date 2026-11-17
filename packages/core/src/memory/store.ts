/**
 * 工作记忆（workspace memory）：跨会话持久的「值得记住的事实」。
 *
 * 吸收对象：opencode-working-memory（v1.6.9）的 workspace-memory 层。
 * 判据（扬弃）：
 *   - 保留：持久事实跨会话存活、注入系统提示、质量护栏（去重/凭据脱敏/弱记忆衰减）。
 *   - 废弃：它依赖宿主 compaction 钩子做 reinforce/replace，还要一个 /memory TUI 面板。
 *     OML 不做 TUI；记忆的增删查走 omo_admin 网关，注入走 budget 的 memory 段。
 *   - 降级：热会话状态（hot session state）由 checkpoint 承担，不在这里重复。
 *
 * 零运行时依赖：只用 node: 内建。记忆条目上限 HARD_CAP，超出时按分数淘汰最弱的。
 */
import { mkdir, readFile, writeFile } from "node:fs/promises"
import { statePath } from "../paths.ts"
import { estimateTokens } from "../budget/estimate.ts"

/** 单条持久记忆。id 是稳定引用（[M#]），供「忘掉这条」用。 */
export interface MemoryEntry {
  /** 稳定 id，形如 M1 / M2 … */
  readonly id: string
  /** 记忆正文；一句话，不带换行 */
  readonly text: string
  /** 记录时间（epoch ms） */
  readonly createdAt: number
  /** 最近一次被使用/强化时间；用于弱记忆衰减 */
  lastUsedAt: number
  /** 命中/强化次数 */
  hits: number
  /** 条目类型：fact 项目事实 / antipattern 反模式（dreams 蒸馏）/ snippet 可复用片段 */
  kind: MemoryKind
}

export type MemoryKind = "fact" | "antipattern" | "snippet"

export interface MemoryStore {
  version: 1
  /** 自增计数器，保证 id 单调不复用（删了也不复用，避免引用漂移） */
  seq: number
  memories: Record<string, MemoryEntry>
}

/** 硬上限：超出即淘汰最弱（分低、久未用）。防注入量无界增长。 */
export const MEMORY_HARD_CAP = 60
/** 注入系统提示的条数上限（渐进披露：只带最相关的头部）。 */
export const MEMORY_INJECT_LIMIT = 12
/** 注入预算（token）。超过就少注入几条，而不是把提示撑爆。 */
export const MEMORY_INJECT_TOKENS = 2_000
/** 检索候选宽度：先取 50 条算分，再按预算裁到实际注入条数。 */
export const MEMORY_RETRIEVE_LIMIT = 50
/**
 * 近重复判定阈值（Jaccard）。
 *
 * autopilot 用 0.6，但那是给「长会话笔记」用的；记忆条目平均只有几十字，
 * 0.6 会把「端口 8080 不通」和「端口 8081 不通」并成一条。故取 0.75，
 * 并且要求数字集合一致——数字不同就是不同的事实，不合并。
 */
export const MEMORY_DEDUP_JACCARD = 0.75
/** 短于这个 shingle 数的条目只做精确去重，不做近似去重。 */
export const MEMORY_DEDUP_MIN_SHINGLES = 8
/** 弱记忆衰减：超过这么多天没被强化，分数打折。 */
/**
 * 半衰期（天）：从「最后一次被强化」起算，超过 `MEMORY_FADE_START_DAYS` 后按半衰期衰减。
 *
 * 校准来源：autopilot 的 half-life 90d。太短会把「低频但关键」的经验（应急、安全）淘汰掉，
 * 太长则让过期结论一直占注入位。90 天是两者之间的折中，不是拍脑袋的整数。
 */
export const MEMORY_FADE_DAYS = 90
export const MEMORY_FADE_START_DAYS = 90
/** 正文上限（字符）；超长记忆说明没提炼，拒绝。 */
export const MEMORY_TEXT_MAX = 280

const CREDENTIAL_PATTERNS: readonly { re: RegExp; label: string }[] = [
  { re: /\b(?:sk|pk|rk|ghp|gho|xox[baprs]|AKIA)[-_.][A-Za-z0-9_-]*\d[A-Za-z0-9_-]*/gi, label: "<redacted-key>" },
  { re: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, label: "<redacted-email>" },
  { re: /\b(?:\d[ -]*?){13,19}\b/g, label: "<redacted-number>" },
]

export function emptyMemoryStore(): MemoryStore {
  return { version: 1, seq: 0, memories: {} }
}

export function memoryPath(): string {
  return statePath("memory.json")
}

/** 凭据脱敏：把疑似密钥/邮箱/卡号换成占位符。写入前调用。 */
export function redact(text: string): string {
  let out = text
  for (const { re, label } of CREDENTIAL_PATTERNS) out = out.replace(re, label)
  return out
}

function normalize(text: string): string {
  return text.replace(/\s+/g, " ").trim().toLowerCase()
}

/** 词的集合（拉丁词 + 单字 CJK）。用于近似重复判定。 */
function shingles(text: string): Set<string> {
  const out = new Set<string>()
  for (const m of normalize(text).matchAll(/[a-z0-9_]{2,}|[\u4e00-\u9fff]/g)) out.add(m[0])
  return out
}

/** 数字签名：数字不同就是不同的事实。用排序后的连接串做比较。 */
function numbersOf(text: string): string {
  return (normalize(text).match(/\d+/g) ?? []).sort().join(",")
}

/** Jaccard 相似度。空集视为不相似（避免两条空记忆互判重复）。 */
export function jaccard(a: string, b: string): number {
  const sa = shingles(a)
  const sb = shingles(b)
  if (sa.size === 0 || sb.size === 0) return 0
  let inter = 0
  for (const t of sa) if (sb.has(t)) inter += 1
  return inter / (sa.size + sb.size - inter)
}

/** 记忆强度：命中次数为主，久未强化则衰减。用于排序与淘汰。 */
export function memoryScore(entry: MemoryEntry, now: number): number {
  const ageDays = Math.max(0, (now - entry.lastUsedAt) / 86_400_000)
  const over = ageDays - MEMORY_FADE_START_DAYS
  const fade = over > 0 ? Math.exp((-Math.LN2 * over) / MEMORY_FADE_DAYS) : 1
  return entry.hits * fade
}

/** 追加一条记忆。去重（归一化文本相同则视为重复，改为强化旧条）。 */
export function addMemory(
  store: MemoryStore,
  rawText: string,
  now: number = Date.now(),
  kind: MemoryKind = "fact",
): { ok: true; store: MemoryStore; entry: MemoryEntry; deduped: boolean } | { ok: false; reason: string } {
  const text = redact(rawText.replace(/\s+/g, " ").trim())
  if (text.length < 3) return { ok: false, reason: "记忆内容过短（<3 字）" }
  if (text.length > MEMORY_TEXT_MAX) {
    return { ok: false, reason: `记忆过长（>${MEMORY_TEXT_MAX} 字），请先提炼成一句话` }
  }
  const key = normalize(text)
  const newNumbers = numbersOf(text)
  const newSize = shingles(text).size
  for (const existing of Object.values(store.memories)) {
    const same = normalize(existing.text) === key
    // 近似重复：同一件事换个说法反复记，会把注入位挤满，等于没有记忆。
    const nearDuplicate =
      !same &&
      newSize >= MEMORY_DEDUP_MIN_SHINGLES &&
      numbersOf(existing.text) === newNumbers &&
      jaccard(existing.text, text) >= MEMORY_DEDUP_JACCARD
    if (same || nearDuplicate) {
      existing.hits += 1
      existing.lastUsedAt = now
      return { ok: true, store, entry: existing, deduped: true }
    }
  }
  const seq = store.seq + 1
  const entry: MemoryEntry = {
    id: `M${seq}`,
    text,
    createdAt: now,
    lastUsedAt: now,
    hits: 1,
    kind,
  }
  const next: MemoryStore = {
    version: 1,
    seq,
    memories: { ...store.memories, [entry.id]: entry },
  }
  enforceCap(next, now)
  return { ok: true, store: next, entry, deduped: false }
}

/** 强化一条（被引用/被用到时 hits+1，重置衰减计时）。 */
export function reinforceMemory(store: MemoryStore, id: string, now: number = Date.now()): boolean {
  const e = store.memories[id]
  if (e === undefined) return false
  e.hits += 1
  e.lastUsedAt = now
  return true
}

/** 忘掉一条。返回是否真删了。 */
export function forgetMemory(store: MemoryStore, id: string): boolean {
  if (store.memories[id] === undefined) return false
  const memories = { ...store.memories }
  delete memories[id]
  store.memories = memories
  return true
}

/** 超出硬上限时淘汰最弱，直到回到上限内。原地改 store。 */
function enforceCap(store: MemoryStore, now: number): void {
  const ids = Object.keys(store.memories)
  if (ids.length <= MEMORY_HARD_CAP) return
  const ranked = ids
    .map((id) => ({ id, score: memoryScore(store.memories[id]!, now) }))
    .sort((a, b) => a.score - b.score)
  const victims = new Set(ranked.slice(0, ids.length - MEMORY_HARD_CAP).map((r) => r.id))
  for (const id of victims) delete store.memories[id]
}

/** 注入用的头部记忆：按分数降序取前 N 条。 */
export function topMemories(store: MemoryStore, limit: number = MEMORY_INJECT_LIMIT, now: number = Date.now()): MemoryEntry[] {
  return Object.values(store.memories)
    .sort((a, b) => memoryScore(b, now) - memoryScore(a, now))
    .slice(0, Math.max(0, limit))
}

/** 渲染成注入文本（进 budget 的 memory 段）。空库返回空串，不占 tok。 */
export function renderMemories(
  store: MemoryStore,
  limit: number = MEMORY_INJECT_LIMIT,
  now: number = Date.now(),
  tokenBudget: number = MEMORY_INJECT_TOKENS,
): string {
  const top = topMemories(store, Math.max(limit, MEMORY_RETRIEVE_LIMIT), now)
  if (top.length === 0) return ""
  const KIND_TAG: Record<MemoryKind, string> = {
    fact: "",
    antipattern: "[反模式] ",
    snippet: "[片段] ",
  }
  const header = "## 持久记忆"
  const lines: string[] = []
  let used = estimateTokens(header)
  for (const m of top) {
    if (lines.length >= limit) break
    const line = `- [${m.id}]${KIND_TAG[m.kind] ?? ""}${m.text}`
    const cost = estimateTokens(line) + 1
    if (used + cost > tokenBudget) break
    used += cost
    lines.push(line)
  }
  if (lines.length === 0) return ""
  return `${header}\n${lines.join("\n")}`
}

export async function loadMemory(path: string = memoryPath()): Promise<MemoryStore> {
  let raw: string
  try {
    raw = await readFile(path, "utf8")
  } catch {
    return emptyMemoryStore()
  }
  try {
    const parsed = JSON.parse(raw) as Partial<MemoryStore> & { store?: Partial<MemoryStore> }
    // 兼容：有工具会把「操作结果」整个落盘（{ok, store, entry}）。宁可救回来，也不要静默丢数据。
    const candidate =
      typeof parsed.memories === "object" && parsed.memories !== null ? parsed : parsed.store
    if (
      candidate === undefined ||
      candidate.version !== 1 ||
      typeof candidate.memories !== "object" ||
      candidate.memories === null
    ) {
      return emptyMemoryStore()
    }
    return { version: 1, seq: candidate.seq ?? 0, memories: candidate.memories }
  } catch {
    return emptyMemoryStore()
  }
}

/** 原子写：先写临时文件再 rename。目录不存在时重试一次。 */
export async function saveMemory(store: MemoryStore, path: string = memoryPath()): Promise<boolean> {
  const write = async (): Promise<void> => {
    const tmp = `${path}.${process.pid}.${Date.now()}.tmp`
    await writeFile(tmp, JSON.stringify(store, null, 2) + "\n", "utf8")
    await Bun.$`mv ${tmp} ${path}`.quiet()
  }
  try {
    await write()
    return true
  } catch {
    try {
      await mkdir(path.slice(0, path.lastIndexOf("/")), { recursive: true })
      await write()
      return true
    } catch {
      return false
    }
  }
}
