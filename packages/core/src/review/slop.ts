/**
 * 反 slop 扫描：找出「注释在复述代码」的地方。
 *
 * 为什么单独做：AI 生成的代码最常见的不是错误，是**低信息量的填充**——
 * 注释把下一行翻译一遍、把「注意」写成一段、给显然的东西加小标题。
 * 它不导致 bug，但抬高阅读成本，并且会被后来者当成规范模仿。
 *
 * 设计取向：**warn-only**。这里只负责把证据摆出来，删不删由人/代理判断；
 * 自动改写会制造新的 slop（而且改错时代价更高）。
 */

export type SlopRule =
  | "comment-restates-code"
  | "decorative-banner"
  | "filler-phrase"
  | "placeholder"
  | "comment-heavy"

export interface SlopFinding {
  readonly path: string
  readonly line: number
  readonly rule: SlopRule
  /** 证据：原文行（去缩进，最长 120 字） */
  readonly evidence: string
  /** 一句话说明为什么算 slop */
  readonly why: string
}

/** 填充词：出现在注释里但不携带信息。 */
const FILLER = [
  /^\/\/\s*(?:注意|需要注意的是|请注意)\s*[:：]?\s*$/,
  /\b(?:it(?:'| i)s important to note|please note that|as (?:you|we) can see)\b/i,
  /^\/\/\s*(?:此|该)(?:函数|方法|代码|处)\s*(?:用于|主要)?\s*(?:实现|完成|处理)/,
  /^\/\/\s*(?:这里|此处)\s*(?:我们)?\s*(?:需要|要)?\s*(?:注意|说明)/,
]

/** 装饰性横幅：全角线、箭头堆、emoji 分隔。 */
const BANNER = /^\s*(?:\/\/|\/\*|#)\s*(?:[=\-*#~_]\s*){6,}|^\s*\/\/\s*(?:\S\s*){1,3}\s*(?:={3,}|-{3,}|\*{3,})/

/**
 * 占位符：承诺了但没做。
 *
 * 不打「占位符」「placeholder」这两个词——它们是**描述这个规则**的措辞，
 * 出现在文档注释里是正常的。真正的标记只有 TODO/FIXME/XXX/TBD 与「待实现」。
 */
const PLACEHOLDER = /\b(?:TODO|FIXME|XXX|TBD)\b|待实现|尚未实现|not implemented/i

function looksLikeRestatement(comment: string, next: string): boolean {
  const c = comment.replace(/^\s*(?:\/\/|\/\*|\*|#)\s*/, "").trim()
  if (c.length < 4) return false
  // 长注释是在解释「为什么」，不是复述「是什么」；只抓短注释。
  if (c.length > 40) return false
  const code = next.trim()
  if (code.length === 0) return false
  // 注释里出现的标识符，若超过一半直接来自下一行代码，基本就是复述
  // 中文复述：注释去标点后是下一行的子串式描述（如「设置 x」「返回 y」）
  const cn = c.replace(/[\s，。、：:,.]/g, "")
  if (cn.length >= 4 && cn.length <= 16 && /^(?:设置|赋值|返回|调用|初始化|创建|获取|判断)/.test(cn) && code.length < 80) {
    return true
  }
  const ids = c.match(/[A-Za-z_][A-Za-z0-9_]{2,}/g) ?? []
  if (ids.length === 0) return false
  const hits = ids.filter((id) => code.includes(id)).length
  if (hits / ids.length < 0.6 || code.length >= 100) return false
  // 复述的标志：把标识符挖掉后，注释几乎没剩下自己的内容。
  // 「配置查找顺序：项目 → 用户 → 内置」挖掉标识符仍有完整句子，不算复述。
  const proseLeft = c.replace(/[A-Za-z_][A-Za-z0-9_]{2,}/g, "").replace(/[\s，。、：:,.;!?！？()（）\-—→]/g, "")
  return proseLeft.length < 6
}

export interface SlopOptions {
  /** 单文件注释行占比超过该值即报 comment-heavy（默认 0.45） */
  readonly commentRatio?: number
}

/** 扫描一批文件。`files` 由调用方读盘提供，便于测试与复用。 */
export function scanSlop(files: ReadonlyArray<{ path: string; text: string }>, opts: SlopOptions = {}): SlopFinding[] {
  const ratioLimit = opts.commentRatio ?? 0.45
  const out: SlopFinding[] = []

  for (const f of files) {
    const lines = f.text.split("\n")
    let commentLines = 0
    let codeLines = 0
    for (let i = 0; i < lines.length; i += 1) {
      const raw = lines[i] ?? ""
      const trimmed = raw.trim()
      if (trimmed.length === 0) continue
      const isComment = /^(?:\/\/|\/\*|\*|#)/.test(trimmed)
      if (isComment) commentLines += 1
      else codeLines += 1

      const evidence = trimmed.slice(0, 120)

      if (BANNER.test(raw)) {
        out.push({ path: f.path, line: i + 1, rule: "decorative-banner", evidence, why: "装饰性分隔线，不传达信息" })
        continue
      }
      // 只在注释里判占位符：代码/测试里出现 "TODO" 字样（比如断言文本）不是承诺。
      if (isComment && PLACEHOLDER.test(trimmed)) {
        out.push({ path: f.path, line: i + 1, rule: "placeholder", evidence, why: "承诺了但没实现；要么做，要么删掉这句话" })
        continue
      }
      if (!isComment) continue
      if (FILLER.some((re) => re.test(trimmed))) {
        out.push({ path: f.path, line: i + 1, rule: "filler-phrase", evidence, why: "填充语，删掉不损失信息" })
        continue
      }
      const next = lines[i + 1] ?? ""
      if (looksLikeRestatement(raw, next)) {
        out.push({ path: f.path, line: i + 1, rule: "comment-restates-code", evidence, why: "注释复述下一行代码" })
      }
    }
    const total = commentLines + codeLines
    if (total >= 30 && commentLines / total > ratioLimit) {
      out.push({
        path: f.path,
        line: 1,
        rule: "comment-heavy",
        evidence: `注释 ${commentLines} / 非空行 ${total}（${Math.round((commentLines / total) * 100)}%）`,
        why: `注释占比超过 ${Math.round(ratioLimit * 100)}%，多半在解释本该自明的代码`,
      })
    }
  }
  return out
}

/** 一行摘要，给报告用。 */
export function summarizeSlop(findings: readonly SlopFinding[]): string {
  if (findings.length === 0) return "未发现 slop"
  const byRule = new Map<SlopRule, number>()
  for (const f of findings) byRule.set(f.rule, (byRule.get(f.rule) ?? 0) + 1)
  const parts = [...byRule.entries()].sort((a, b) => b[1] - a[1]).map(([r, n]) => `${r}×${n}`)
  return `${findings.length} 处：${parts.join("，")}`
}

const CODE_EXT = /\.(?:ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|c|h|cc|cpp|hpp|rb|php|sh|zsh|lua)$/

/**
 * 从目录读源码（剔除 node_modules/.git/dist/build），最多 `limit` 个文件。
 *
 * 上限是刻意的：扫描是为了给出可行动的证据，不是做全仓静态分析。
 * 一次列 5000 条发现，等于没有发现。
 */
export async function readSources(
  root: string,
  opts: { limit?: number; maxBytes?: number } = {},
): Promise<Array<{ path: string; text: string }>> {
  const { readdir, readFile } = await import("node:fs/promises")
  const { join, relative } = await import("node:path")
  const limit = opts.limit ?? 200
  const maxBytes = opts.maxBytes ?? 400_000
  const skip = new Set(["node_modules", ".git", "dist", "build", ".oml-check-surface", "coverage"])
  const out: Array<{ path: string; text: string }> = []

  const walk = async (dir: string): Promise<void> => {
    if (out.length >= limit) return
    let entries
    try {
      entries = await readdir(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      if (out.length >= limit) return
      if (e.name.startsWith(".") && e.name !== ".") continue
      const full = join(dir, e.name)
      if (e.isDirectory()) {
        if (skip.has(e.name)) continue
        await walk(full)
        continue
      }
      if (!CODE_EXT.test(e.name)) continue
      try {
        const text = await readFile(full, "utf8")
        if (text.length > maxBytes) continue
        out.push({ path: relative(root, full), text })
      } catch {
        // 读不了就跳过：扫描器不因为一个文件失败而中断
      }
    }
  }
  await walk(root)
  return out
}
