/**
 * 上下文预算 —— 段拼装与截断。纯函数：不读写文件、不读环境变量。
 * 行为：
 *   1) 每段 tokens = estimateTokens(section.text)；
 *   2) total <= limit → status "pass"，不截断；
 *   3) total > limit → 按 SECTION_PRIORITY 逆序（memory → skillIndex → identity → tools）
 *      逐段从尾部按字符裁剪，直到 total <= limit 或该段为空；被裁剪段 truncated=true；
 *   4) 若裁完除 tools 外的所有段后仍超限 → status "fail"（tools 不裁剪）；
 *   5) prompt = 各段按原始数组顺序拼接，段间用 "\n\n"，段前缀为 `## <id>\n`；
 *   6) warnings 每条截断写一行中文。
 */
import type {
  Section,
  BudgetReport,
  BudgetSectionReport,
  BudgetStatus,
} from "../contract.ts"
import { SECTION_PRIORITY } from "../contract.ts"
import { estimateTokens } from "./estimate.ts"

export interface AssembleResult {
  prompt: string
  report: BudgetReport
}

/** 超预算时按优先级逆序牺牲段，tools 永不裁剪。 */
function trimToLimit(
  tokens: Map<string, number>,
  texts: Map<string, string>,
  limit: number,
): string[] {
  const warnings: string[] = []
  const order = [...SECTION_PRIORITY].reverse()
  let total = [...tokens.values()].reduce((a, b) => a + b, 0)
  for (let i = 0; i < order.length - 1; i++) {
    if (total <= limit) break
    const id = order[i]
    if (id === undefined) break
    if (!texts.has(id)) continue
    let text = texts.get(id) as string
    const before = tokens.get(id) as number
    while (total > limit && text.length > 0) {
      text = text.slice(0, -1)
      const t = estimateTokens(text)
      total = total - (tokens.get(id) as number) + t
      tokens.set(id, t)
    }
    texts.set(id, text)
    warnings.push(`[budget] 段 ${id} 被截断：${before} → ${tokens.get(id) as number} tok`)
  }
  return warnings
}

/** 把段拼装为系统提示并产出预算报告。 */
export function assemble(sections: Section[], limit?: number): AssembleResult {
  const cap = limit ?? 8192
  const tokens = new Map<string, number>()
  const texts = new Map<string, string>()
  for (const s of sections) {
    tokens.set(s.id, estimateTokens(s.text))
    texts.set(s.id, s.text)
  }
  let total = [...tokens.values()].reduce((a, b) => a + b, 0)

  let status: BudgetStatus = "pass"
  let warnings: string[] = []
  if (total > cap) {
    warnings = trimToLimit(tokens, texts, cap)
    total = [...tokens.values()].reduce((a, b) => a + b, 0)
    // 仅当 tools 之外全被砍空仍超限时才判 fail（tools 不裁剪）
    const onlyToolsLeft = sections
      .filter((s) => s.id !== "tools")
      .every((s) => (texts.get(s.id) as string).length === 0)
    status = onlyToolsLeft && total > cap ? "fail" : "truncated"
  }

  const reportSections: BudgetSectionReport[] = sections.map((s) => {
    const before = estimateTokens(s.text)
    const after = tokens.get(s.id) as number
    return {
      id: s.id,
      tokens: after,
      items: s.items,
      truncated: after < before,
    }
  })

  const prompt = sections
    .map((s) => `## ${s.id}\n${texts.get(s.id) as string}`)
    .join("\n\n")

  return {
    prompt,
    report: {
      totalTokens: total,
      sections: reportSections,
      budget: { limit: cap, used: total, status },
      warnings,
    },
  }
}
