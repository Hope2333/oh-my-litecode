/**
 * 技能相关性选择 —— 只把「这一轮可能用得上」的技能放进索引。
 *
 * 扬弃对象：把 291 条技能目录全量注入系统提示（约 60K tok），
 * 而单轮实际最多加载 1–2 个。这是「装了什么都」压倒「要做什么」的典型。
 *
 * 打分是词面匹配，不引入模型调用：快、可测、可复现。误判的代价是漏掉一个
 * 技能——用户仍可直接 `skill(name)` 加载，所以漏判不是不可恢复的。
 */

import type { SkillMeta, SkillUsageMap } from "../contract.ts"

const STOP = new Set([
  "the", "and", "for", "with", "that", "this", "from", "into", "http", "https", "www",
  "a", "an", "of", "to", "in", "on", "is", "it", "or", "be", "by", "as", "at", "if",
])

/** 拉丁词（≥2 字符）+ CJK 单字与二元组（中文无空格，二元组比单字更有区分度） */
export function tokenize(text: string): string[] {
  const lower = text.toLowerCase()
  const out: string[] = []
  for (const m of lower.matchAll(/[a-z0-9][a-z0-9+#._-]+/g)) {
    const w = m[0]
    if (w.length >= 2 && !STOP.has(w)) out.push(w)
  }
  for (const m of lower.matchAll(/[\u4e00-\u9fff]+/g)) {
    const run = m[0]
    for (let i = 0; i < run.length; i++) out.push(run[i] ?? "")
    for (let i = 0; i + 1 < run.length; i++) out.push(run.slice(i, i + 2))
  }
  return out
}

const WEIGHT_NAME = 4
const WEIGHT_DESC = 1

export function scoreSkill(skill: SkillMeta, terms: readonly string[]): number {
  const name = skill.name.toLowerCase()
  const desc = skill.description.toLowerCase()
  let score = 0
  for (const t of terms) {
    if (t === "") continue
    if (name.includes(t)) score += WEIGHT_NAME
    else if (desc.includes(t)) score += WEIGHT_DESC
  }
  // 名字被完整提及额外加分（"用 git-master" 这种直呼其名）
  if (terms.some((t) => t.length >= 3 && name.includes(t))) score += 6
  return score
}

export interface SelectOptions {
  top?: number
  usage?: SkillUsageMap
  /** 已降级或显式禁用的名字，直接排除 */
  exclude?: Iterable<string>
  /**
   * 相对相关性下限（0–1，默认 0）。
   *
   * 判据是「相对本轮最高分」而不是绝对分数：绝对阈值会随任务描述的长短漂移，
   * 而相对阈值只回答一个问题——这条技能对本轮是否**明显**弱于最相关的那条。
   * 已命中的第一条永不被裁掉，避免索引为空。
   */
  minRelevance?: number
}

/**
 * 返回按相关性排序的技能。
 * 无任务文本时退化为「按使用频率」——首次使用则按名字字典序，保证可复现。
 */
export function selectSkills(
  skills: readonly SkillMeta[],
  taskText: string,
  opts: SelectOptions = {},
): SkillMeta[] {
  const top = opts.top ?? 40
  const usage = opts.usage ?? {}
  const exclude = new Set(opts.exclude ?? [])
  const terms = tokenize(taskText)

  const scored = skills
    .filter((s) => !exclude.has(s.name))
    .map((s) => ({ s, score: terms.length === 0 ? 0 : scoreSkill(s, terms) }))
    .filter((x) => (terms.length === 0 ? true : x.score > 0))

  scored.sort((a, b) => {
    const ua = usage[a.s.name]
    const ub = usage[b.s.name]
    return (
      b.score - a.score ||
      (ub?.hits ?? 0) - (ua?.hits ?? 0) ||
      a.s.name.localeCompare(b.s.name)
    )
  })

  const best = scored[0]?.score ?? 0
  const floor = best * Math.min(1, Math.max(0, opts.minRelevance ?? 0))
  const relevant = floor > 0 ? scored.filter((x, i) => i === 0 || x.score >= floor) : scored
  const picked = relevant.slice(0, top).map((x) => x.s)
  // 一个有相关度的都没命中时，退回使用频率最高的若干条（避免索引为空导致模型无从发现技能）
  if (picked.length === 0) {
    return [...skills]
      .filter((s) => !exclude.has(s.name))
      .sort((a, b) => (usage[b.name]?.hits ?? 0) - (usage[a.name]?.hits ?? 0) || a.name.localeCompare(b.name))
      .slice(0, top)
  }
  return picked
}
