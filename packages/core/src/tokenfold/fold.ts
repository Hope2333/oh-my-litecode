/**
 * tokenfold —— 结构化无损折叠（纯 TS / 无损 / 纯本地 / 零依赖 / 纯函数）。
 *
 * 设计铁律：
 *   1) 无损：把「重复字段/重复值」提取成列字典 + 行索引，往返 100% 一致；
 *      null / undefined / 空串 / 与哨兵同形的值全部可区分（哨兵 + 转义）。
 *   2) 纯本地：不读文件、不读环境变量、不发网络；密钥打码仅在内存中做，
 *      原文存进返回的 vault 供调用方本地复原，绝不外传。
 *   3) 零运行时依赖：token 估算复用仓库内 budget/estimate.ts，不引入 Rust 二进制。
 *   4) 纯函数：不修改入参，不共享可变状态。
 */
import { estimateTokens } from "../budget/estimate.ts"

/** null 的固定哨兵（U+0000 前缀，正常业务文本几乎不会出现）。 */
export const NULL_SENTINEL = "\u0000NULL"
/** undefined / 缺字段的固定哨兵。 */
export const UNDEF_SENTINEL = "\u0000UNDEF"
/** 转义前缀：真实字符串若与哨兵同形、或以此前缀开头，则前置本前缀避免歧义。 */
const ESCAPE_PREFIX = "\u0000ESC:"

/**
 * 把任意值归一成可入字典的存储字符串。
 * 映射是单射：null / undefined / 真实字符串 / 其它类型互不混淆，保证往返无损。
 * - null            -> NULL_SENTINEL
 * - undefined       -> UNDEF_SENTINEL（含对象上「缺字段」的情况）
 * - string s        -> 若 s 与哨兵同形或以 ESCAPE_PREFIX 开头，则 ESCAPE_PREFIX + s；否则 s
 * - 其它（数字/布尔/bigint/对象等） -> String(v)
 */
export function normalizeValue(value: unknown): string {
  if (value === null) return NULL_SENTINEL
  if (value === undefined) return UNDEF_SENTINEL
  if (typeof value === "string") {
    if (value === NULL_SENTINEL || value === UNDEF_SENTINEL || value.startsWith(ESCAPE_PREFIX)) {
      return ESCAPE_PREFIX + value
    }
    return value
  }
  return String(value)
}

/**
 * 列式无损折叠后的结构。
 * - version    : 固定 1，便于后续演进/兼容判定
 * - columns    : 列名的并集，按首次出现顺序（稳定可复现）
 * - dict[col]  : 该列去重后的归一化字符串值列表
 * - rows[i][j] : 第 i 行、第 columns[j] 列的值在 dict[col] 中的下标
 * - counts[col][k] : dict[col][k] 在全表出现的次数（用于「减脂 select」看哪些值最冗余）
 */
export interface FoldedTable {
  version: 1
  columns: string[]
  dict: Record<string, string[]>
  rows: number[][]
  counts?: Record<string, number[]>
}

/** 折叠/还原的 token 收益明细。 */
export interface Savings {
  before: number
  after: number
  savedPct: number
}

/** 预算帽裁定结果：ok 为是否放行，receipt 为可读明细小票。 */
export interface BudgetReceipt {
  ok: boolean
  receipt: string
}

/** 本地打码结果：masked 为打码文本，vault 为「占位符 -> 原文」映射，供本地复原。 */
export interface RedactionResult {
  masked: string
  vault: Record<string, string>
}

/**
 * 把记录数组折成列式字典 + 行索引（无损、纯函数、不改入参）。
 * 所有值统一经 normalizeValue 变成存储字符串；缺字段补 UNDEF_SENTINEL。
 */
export function foldRecords(records: readonly Record<string, unknown>[]): FoldedTable {
  // 列 = 所有记录键的并集，保持首次出现顺序
  const columns: string[] = []
  const seenColumn = new Set<string>()
  for (const record of records) {
    for (const key of Object.keys(record)) {
      if (!seenColumn.has(key)) {
        seenColumn.add(key)
        columns.push(key)
      }
    }
  }

  const dict: Record<string, string[]> = {}
  const counts: Record<string, number[]> = {}
  const index: Record<string, Map<string, number>> = {}
  for (const col of columns) {
    dict[col] = []
    counts[col] = []
    index[col] = new Map()
  }

  const rows: number[][] = []
  for (const record of records) {
    const row: number[] = []
    for (const col of columns) {
      const normalized = normalizeValue(record[col])
      const colIndex = index[col] as Map<string, number>
      const colDict = dict[col] as string[]
      const colCounts = counts[col] as number[]
      let idx = colIndex.get(normalized)
      if (idx === undefined) {
        idx = colDict.length
        colDict.push(normalized)
        colCounts.push(0)
        colIndex.set(normalized, idx)
      }
      colCounts[idx] = (colCounts[idx] as number) + 1
      row.push(idx)
    }
    rows.push(row)
  }

  return { version: 1, columns, dict, rows, counts }
}

/**
 * 把 FoldedTable 还原成字符串记录数组（无损、纯函数、不改入参）。
 * 返回值为归一化字符串：null / undefined 分别还原成各自的固定哨兵，互不混淆。
 * 往返性质：unfoldRecords(foldRecords(rs)) === rs 的「归一 + 补列」形式。
 */
export function unfoldRecords(folded: FoldedTable): Record<string, string>[] {
  return folded.rows.map((row) => {
    const out: Record<string, string> = {}
    for (let j = 0; j < folded.columns.length; j += 1) {
      const col = folded.columns[j] as string
      const idx = row[j]
      const value = idx === undefined ? undefined : (folded.dict[col]?.[idx] ?? undefined)
      out[col] = value === undefined ? UNDEF_SENTINEL : value
    }
    return out
  })
}

/**
 * 计算折叠收益：before/after 都用仓库统一的 estimateTokens 口径，
 * 比较对象分别是 JSON.stringify(原始记录) 与 JSON.stringify(折叠结构)。
 * savedPct 保留 1 位小数；before=0 时定义为 0（避免除零）。
 */
export function foldSavings(records: readonly Record<string, unknown>[], folded: FoldedTable): Savings {
  // 空输入无 token 可省，直接归零（避免 JSON 结构开销算出负收益 / 除零）
  if (records.length === 0) return { before: 0, after: 0, savedPct: 0 }
  const before = estimateTokens(JSON.stringify(records))
  const after = estimateTokens(JSON.stringify(folded))
  const savedPct = before === 0 ? 0 : Math.round(((before - after) / before) * 1000) / 10
  return { before, after, savedPct }
}

/**
 * 预算帽裁定：tokens 超过 cap 即拒收，并返回带 before/cap/verdict 的明细小票。
 * 纯计算，不写盘、不联网（与 budget/gate.ts 的落盘审计职责分离）。
 */
export function checkBudget(tokens: number, cap: number): BudgetReceipt {
  const ok = tokens <= cap
  const delta = cap - tokens
  const verdict = ok ? "PASS" : "REJECT"
  const receipt = [
    "[tokenfold budget] === 明细小票 ===",
    `verdict : ${verdict} (${ok ? "放行" : "超额拒收"})`,
    `before  : ${tokens} tok  (待折叠 token 数)`,
    `cap     : ${cap} tok  (预算帽)`,
    `delta   : ${delta >= 0 ? "剩余" : "超出"} ${Math.abs(delta)} tok`,
    ok ? "结论   : 未越预算帽，放行。" : "结论   : 越预算帽，拒收并保留本小票。",
  ].join("\n")
  return { ok, receipt }
}

/** 打码占位符的包裹符（本地唯一、正常文本几乎不出现）。 */
const PH_OPEN = "⟦"
const PH_CLOSE = "⟧"

/**
 * 单一正则一次扫描，避免「key=sk-xxx」被二次打码。
 * 捕获组顺序：1 sk / 2 AIza / 3 ghp_ / 4 Bearer 前缀 / 5 Bearer 值 / 6 key 名 / 7 = / 8 key 值。
 */
const SECRET_RE =
  /\b(sk-[A-Za-z0-9_-]{16,})\b|\b(AIza[A-Za-z0-9_-]{20,})\b|\b(ghp_[A-Za-z0-9]{20,})\b|(Bearer\s+)([A-Za-z0-9._~+/=-]{10,})|\b(api[_-]?key|apikey|secret|password|token|key)(\s*=\s*)([^\s&;"'<>]+)/gi

/**
 * 本地密钥打码（零 IO / 零网络 / 纯本地内存操作）。
 * 命中 sk- / AIza / ghp_ / Bearer token / 常见 key=xxx 等模式，
 * 每个命中换成编号占位符 ⟦SECRET_n⟧，原文存入 vault[key]=value 供本地复原。
 * 绝不在模块内发起任何请求或写盘。
 */
export function redactSecrets(text: string): RedactionResult {
  const vault: Record<string, string> = {}
  let counter = 0

  const register = (raw: string): string => {
    counter += 1
    const placeholder = `${PH_OPEN}SECRET_${counter}${PH_CLOSE}`
    vault[placeholder] = raw
    return placeholder
  }

  const masked = text.replace(
    SECRET_RE,
    (
      _match: string,
      sk?: string,
      aiza?: string,
      ghp?: string,
      bearerPrefix?: string,
      bearerVal?: string,
      kvKey?: string,
      kvEq?: string,
      kvVal?: string,
    ): string => {
      if (sk !== undefined) return register(sk)
      if (aiza !== undefined) return register(aiza)
      if (ghp !== undefined) return register(ghp)
      if (bearerPrefix !== undefined && bearerVal !== undefined) return bearerPrefix + register(bearerVal)
      if (kvKey !== undefined && kvEq !== undefined && kvVal !== undefined) {
        return kvKey + kvEq + register(kvVal)
      }
      return _match
    },
  )

  return { masked, vault }
}

/**
 * 用 redactSecrets 返回的 vault 在本地复原掩码文本（零 IO / 零网络）。
 * 逐个把占位符换回原文；未登记的占位符原样保留。
 */
export function restoreSecrets(masked: string, vault: Record<string, string>): string {
  let out = masked
  for (const [placeholder, raw] of Object.entries(vault)) {
    out = out.split(placeholder).join(raw)
  }
  return out
}
