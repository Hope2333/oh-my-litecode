/**
 * 上下文预算 —— token 估算口径（可审计）：
 *   1) CJK 字符（U+3000-U+303F、U+4E00-U+9FFF、U+FF00-U+FFEF）每个计 1 token；
 *   2) 其余非空白字符每 4 个计 1 token（向上取整）；
 *   3) 连续空白每 6 个计 1 token（向上取整）；
 *   4) 空字符串返回 0。
 * 纯函数：不读文件、不读环境变量。
 */

const CJK_RANGES: ReadonlyArray<readonly [number, number]> = [
  [0x3000, 0x303f],
  [0x4e00, 0x9fff],
  [0xff00, 0xffef],
]

function isCjk(code: number): boolean {
  for (const [lo, hi] of CJK_RANGES) {
    if (code >= lo && code <= hi) return true
  }
  return false
}

function ceilDiv(n: number, d: number): number {
  return Math.ceil(n / d)
}

/** 按 §7 口径估算一段文本占用的 token 数。 */
export function estimateTokens(text: string): number {
  if (text.length === 0) return 0
  let cjk = 0
  let other = 0
  let wsRun = 0
  let wsTokens = 0
  for (const ch of text) {
    const code = ch.codePointAt(0) as number
    if (isCjk(code)) {
      cjk += 1
      wsTokens += ceilDiv(wsRun, 6)
      wsRun = 0
    } else if (/\s/.test(ch)) {
      wsRun += 1
    } else {
      other += 1
      wsTokens += ceilDiv(wsRun, 6)
      wsRun = 0
    }
  }
  // 连续空白按每 6 个计 1 token（每段连续空白独立结算）
  wsTokens += ceilDiv(wsRun, 6)
  const otherTokens = ceilDiv(other, 4)
  return cjk + otherTokens + wsTokens
}
