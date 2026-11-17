/**
 * 主动上下文裁剪（吸收自 opencode-acp / DCP）。
 *
 * 判据（扬弃）：
 *   - 保留：模型自主决定何时/压缩什么；[[KEEP]] 原样保留、[[REF]] 紧凑引用；摘要块替换原始区间、可回溯。
 *   - 废弃：ACP 的 nudge 状态机（nudgeFrequency/iterationNudgeThreshold/turnNudgeAnchors）依赖
 *     messages.transform 全量改写历史。OML 不做长会话历史改写（宿主 1.19 的 compaction 已管）；
 *     OML 只提供 compress 工具 + 摘要块落盘 + 注入摘要块，nudge 降级为 system 规则一句话。
 *   - 废弃：外部 tokenizer。用 budget/estimate 的估算，省 @anthropic-ai/tokenizer 依赖。
 *
 * 零运行时依赖：只用 node: 内建。
 */

/** 一条压缩摘要块。range 是被替换的原始消息 id 区间（闭区间）。 */
export interface CompressBlock {
  /** 块 id，形如 b1 / b2 … */
  readonly id: string
  /** 被压缩的原始消息 id 起点 */
  readonly from: string
  /** 被压缩的原始消息 id 终点 */
  readonly to: string
  /** 模型写的自包含摘要正文（含 [[KEEP:id]] / [[REF:id|说明]] 标记） */
  readonly summary: string
  /** 原始消息正文，按 id 存，供 decompress 回溯 */
  readonly sources: Record<string, string>
  readonly createdAt: number
  /** 摘要覆盖的原始 token 估算，用于统计节省 */
  readonly savedTokens: number
}

export interface CompressStore {
  version: 1
  seq: number
  blocks: Record<string, CompressBlock>
}

/** KEEP 标记：[[KEEP:mNNNNN]] —— 摘要里声明「这条原文必须原样保留」。 */
const KEEP_RE = /\[\[KEEP:([^\]]+?)\]\]/g
/** REF 标记：[[REF:mNNNNN|说明]] —— 紧凑引用，不展开原文。 */
const REF_RE = /\[\[REF:([^\]|]+?)(?:\|([^\]]+))?\]\]/g

export function emptyCompressStore(): CompressStore {
  return { version: 1, seq: 0, blocks: {} }
}

/** 校验摘要里的 KEEP 引用都有对应来源；返回缺失的 id。 */
export function missingKeeps(summary: string, sources: Record<string, string>): string[] {
  const missing: string[] = []
  for (const m of summary.matchAll(KEEP_RE)) {
    const id = m[1]?.trim() ?? ""
    if (id !== "" && sources[id] === undefined) missing.push(id)
  }
  return missing
}

/**
 * 把摘要渲染成注入文本：
 * - [[KEEP:id]] → 展开成原文块（verbatim）
 * - [[REF:id|说明]] → 一行紧凑引用
 * 未知 id 的 KEEP 降级为 REF（不丢标记，只丢原文）。
 */
export function renderSummary(
  summary: string,
  sources: Record<string, string>,
): string {
  const keepExpanded = summary.replace(KEEP_RE, (_all, rawId: string) => {
    const id = rawId.trim()
    const src = sources[id]
    if (src === undefined) return `[[REF:${id}|原文缺失]]`
    return `[[KEEP:${id}]]\n${src}\n[[/KEEP:${id}]]`
  })
  return keepExpanded.replace(REF_RE, (_all, rawId: string, desc?: string) => {
    const id = rawId.trim()
    const label = desc?.trim() ?? ""
    return label === "" ? `[→ ${id}]` : `[→ ${id}: ${label}]`
  })
}

/** 压缩：登记一个摘要块。KEEP 引用缺失时拒绝（防丢原文）。 */
export function compressRange(
  store: CompressStore,
  input: {
    from: string
    to: string
    summary: string
    sources: Record<string, string>
    savedTokens: number
  },
  now: number = Date.now(),
): { ok: true; store: CompressStore; block: CompressBlock } | { ok: false; reason: string } {
  const missing = missingKeeps(input.summary, input.sources)
  if (missing.length > 0) {
    return { ok: false, reason: `摘要引用了未提供的原文：${missing.join(", ")}。请把这些消息正文放进 sources，或改用 [[REF:id|说明]]。` }
  }
  if (input.summary.trim().length < 20) {
    return { ok: false, reason: "摘要过短（<20 字），请写成自包含、可独立续作的摘要。" }
  }
  const seq = store.seq + 1
  const block: CompressBlock = {
    id: `b${seq}`,
    from: input.from,
    to: input.to,
    summary: input.summary.trim(),
    sources: input.sources,
    createdAt: now,
    savedTokens: Math.max(0, Math.round(input.savedTokens)),
  }
  return {
    ok: true,
    store: { version: 1, seq, blocks: { ...store.blocks, [block.id]: block } },
    block,
  }
}

/** 块 id 的数字序（b1 < b2 < …）；非数字后缀排最后。 */
function blockSeq(b: CompressBlock): number {
  const n = Number(b.id.replace(/^b/, ""))
  return Number.isFinite(n) ? n : Number.MAX_SAFE_INTEGER
}

/** 列出块（按 id 序，最新的在后）。 */
export function listBlocks(store: CompressStore): CompressBlock[] {
  return Object.values(store.blocks).sort((a, b) => blockSeq(a) - blockSeq(b))
}

/** 渲染一个块为注入文本（摘要 + KEEP 展开 + 统计行）。 */
export function renderBlock(block: CompressBlock): string {
  const body = renderSummary(block.summary, block.sources)
  const header = `> 压缩块 ${block.id}（原 ${block.from}–${block.to}，省约 ${block.savedTokens} tok）`
  return `${header}\n${body}`
}

/** 渲染全部块（按 id 序）。 */
export function renderAllBlocks(store: CompressStore): string {
  const blocks = listBlocks(store)
  if (blocks.length === 0) return ""
  return blocks.map(renderBlock).join("\n\n")
}

/** 回溯：取某块的某条原文。 */
export function decompressSource(block: CompressBlock, messageId: string): string | undefined {
  return block.sources[messageId]
}

/** 统计：总节省 token。 */
export function totalSavedTokens(store: CompressStore): number {
  return Object.values(store.blocks).reduce((sum, b) => sum + b.savedTokens, 0)
}

/** 落盘路径：<stateDir>/compress.json */
import { mkdir, readFile, writeFile } from "node:fs/promises"
import { statePath } from "../paths.ts"

export function compressPath(): string {
  return statePath("compress.json")
}

export async function loadCompress(path: string = compressPath()): Promise<CompressStore> {
  let raw: string
  try {
    raw = await readFile(path, "utf8")
  } catch {
    return emptyCompressStore()
  }
  try {
    const parsed = JSON.parse(raw) as Partial<CompressStore> & { store?: Partial<CompressStore> }
    // 同上：救回被「结果包装」写坏的文件，而不是静默返回空账本。
    const candidate = typeof parsed.blocks === "object" && parsed.blocks !== null ? parsed : parsed.store
    if (
      candidate === undefined ||
      candidate.version !== 1 ||
      typeof candidate.blocks !== "object" ||
      candidate.blocks === null
    ) {
      return emptyCompressStore()
    }
    return { version: 1, seq: candidate.seq ?? 0, blocks: candidate.blocks }
  } catch {
    return emptyCompressStore()
  }
}

/** 原子写：先写临时文件再 rename。目录不存在时重试一次。 */
export async function saveCompress(store: CompressStore, path: string = compressPath()): Promise<boolean> {
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
