/**
 * 单条工具返回的分块压缩（DCP tool-result 粒度）。
 *
 * 判据（与会话区间压缩并存、不冲突）：
 *   - `compress/store.ts` 的 `compressRange` 压缩的是**会话消息区间**（from/to 是消息 id）。
 *   - 本模块压缩的是**单条工具返回**（文件搜索 / Shell 输出 / API 响应）：把大段文本切成
 *     带 `@bN` 锚点的块，逐块登记进同一个 CompressStore。锚点可引用、可扩展还原原文。
 *   - 两者共用 CompressStore / CompressBlock 结构与 `compressRange` 校验，seq 递增共用同一
 *     计数器，因此块 id 全局唯一；本模块不改 store.ts，也不另起一套存储。
 *
 * 零运行时依赖：只用 node: 内建（这里纯函数，连 node: 都不用）。
 */

import { compressRange } from "./store.ts"
import type { CompressStore } from "./store.ts"

/** 未指定 maxChars 时的默认块大小。 */
export const DEFAULT_CHUNK_CHARS = 2000
/** 摘要预览保留的最大字符数（超出加省略号）。 */
const PREVIEW_CHARS = 80

/**
 * 把长文本按长度切块，尽量在换行 / 句子边界收尾，避免腰斩单词。
 * - 空文本返回 []。
 * - 各块首尾相接：chunks.join("") === text（100% 还原前提）。
 * - maxChars < 1 时按 1 处理，保证循环推进（不产出无限空块）。
 */
export function chunkText(text: string, maxChars: number): string[] {
  if (text.length === 0) return []
  const limit = Math.max(1, Math.floor(maxChars))
  if (text.length <= limit) return [text]

  const chunks: string[] = []
  let start = 0
  const half = Math.floor(limit / 2)

  while (start < text.length) {
    const remaining = text.length - start
    if (remaining <= limit) {
      chunks.push(text.slice(start))
      break
    }

    const window = text.slice(start, start + limit)
    let cut = -1

    // 1) 优先：窗口内最后一个换行之后切（连同换行一起，还原不断行）。
    const nl = window.lastIndexOf("\n")
    if (nl >= half) cut = nl + 1

    // 2) 其次：窗口内最后一个句子标点之后切，优先跟空白的那个。
    if (cut < 0) {
      const marks = Array.from(window.matchAll(/[.!?。！？；;]/g))
      for (let k = marks.length - 1; k >= 0; k--) {
        const idx = marks[k]?.index ?? -1
        if (idx < half) continue
        const after = window[idx + 1]
        if (after === undefined || /\s/.test(after)) {
          cut = idx + 1
          break
        }
      }
      // 退一步：只要过半的句子标点也认，不强制后跟空白。
      if (cut < 0) {
        for (let k = marks.length - 1; k >= 0; k--) {
          const idx = marks[k]?.index ?? -1
          if (idx >= half) {
            cut = idx + 1
            break
          }
        }
      }
    }

    // 3) 找不到边界：硬切在 limit 处。
    if (cut <= 0) cut = limit
    chunks.push(text.slice(start, start + cut))
    start += cut
  }

  return chunks
}

export interface FoldToolResultInput {
  /** 工具返回来源标识，用作块的 from/to，并作为 source key 前缀（${toolId}#${i}）。 */
  toolId: string
  /** 待压缩的大段工具返回原文。 */
  text: string
  /** 块大小上限，缺省 DEFAULT_CHUNK_CHARS。 */
  maxChars?: number
  /** 注入块的时间戳，缺省 Date.now()。 */
  now?: number
  /** 可选的调用方摘要；过短（<20 字）时回退为自动预览，以通过 compressRange 校验。 */
  summary?: string
}

export interface FoldToolResultOutput {
  store: CompressStore
  /** 形如 @b1 / @b2，按块顺序，对应各块 id。 */
  anchors: string[]
}

/**
 * 把单条大工具返回分块并登记进 store：每块一个 CompressBlock，
 * from=to=toolId，sources[`${toolId}#${i}`]=块原文，summary=正文预览（或调用方摘要），
 * savedTokens 按 chunk.length/4 估算。内部走 compressRange 校验，不另起炉灶。
 * 空文本：不登记块，返回原 store 与空 anchors。
 */
export function foldToolResult(
  store: CompressStore,
  input: FoldToolResultInput,
): FoldToolResultOutput {
  const chunks = chunkText(input.text, input.maxChars ?? DEFAULT_CHUNK_CHARS)
  if (chunks.length === 0) return { store, anchors: [] }

  let next = store
  const anchors: string[] = []
  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i] ?? ""
    const sourceId = `${input.toolId}#${i}`
    const preview = chunk.length > PREVIEW_CHARS
      ? `${chunk.slice(0, PREVIEW_CHARS)}…`
      : chunk
    const callerSummary = input.summary?.trim()
    const summary = callerSummary !== undefined && callerSummary.length >= 20
      ? callerSummary
      : `工具返回 ${input.toolId} 第 ${i + 1}/${chunks.length} 块预览：${preview}`

    const r = compressRange(
      next,
      {
        from: input.toolId,
        to: input.toolId,
        summary,
        sources: { [sourceId]: chunk },
        savedTokens: Math.ceil(chunk.length / 4),
      },
      input.now,
    )
    // 生成的摘要恒 >=20 字且无 KEEP 引用，正常不会失败；失败即调用方契约问题，显式抛出。
    if (!r.ok) throw new Error(`foldToolResult 登记失败：${r.reason}`)
    next = r.store
    anchors.push(`@${r.block.id}`)
  }

  return { store: next, anchors }
}

/**
 * 锚点 → 原文：@bN（也接受裸 bN）取回该块 sources 的原文。
 * 单块拼接即块原文；多块按插入序拼接。找不到 / 格式不对返回 undefined。
 */
export function expandAnchor(store: CompressStore, anchor: string): string | undefined {
  const m = /^@?b(\d+)$/.exec(anchor.trim())
  if (m === null) return undefined
  const block = store.blocks[`b${m[1]}`]
  if (block === undefined) return undefined
  return Object.values(block.sources).join("")
}

/** 渲染一行紧凑引用：@b1 @b2 （展开：decompress bN）；空锚点返回空串。 */
export function renderToolResultRef(anchors: string[]): string {
  if (anchors.length === 0) return ""
  return `${anchors.join(" ")} （展开：decompress bN）`
}
