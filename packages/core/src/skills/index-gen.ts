/**
 * 惰性技能索引 —— 索引生成层。
 *
 * 职责：把 SkillMeta 列表 + 使用统计压成一段极短的注入文本
 *   `- name: 触发语`，只保留当前可能用到的 top 条，冷技能被降级排除。
 */

import {
  SKILL_DEMOTE_AFTER_MISSES,
  SKILL_INDEX_TOP,
  SKILL_TRIGGER_MAX_CHARS,
  type SkillMeta,
  type SkillUsageMap,
} from "../contract.ts"

export interface IndexOptions {
  /** 最多保留条数（默认 SKILL_INDEX_TOP） */
  top?: number
  /** 单条触发语最大字符数（默认 SKILL_TRIGGER_MAX_CHARS） */
  maxTriggerChars?: number
}

/**
 * 从 description 提取触发语：取第一句/第一个分句，压缩空白，
 * 截断到 maxChars（默认 SKILL_TRIGGER_MAX_CHARS），超长加 "…"。
 * 剔除换行与 `|`、`>` 等 YAML 残留符号。
 */
export function triggerOf(description: string, maxChars: number = SKILL_TRIGGER_MAX_CHARS): string {
  // 换行与 YAML 残留符号统一替换为空格
  let s = description.replace(/[\r\n]+/g, " ").replace(/[|>`]/g, " ")
  // 压缩连续空白
  s = s.replace(/\s+/g, " ").trim()

  // 第一句：以中英句末标点切分
  const sentenceEnd = /[。．.!?！？;；]/.exec(s)
  let first = sentenceEnd && sentenceEnd.index > 0 ? s.slice(0, sentenceEnd.index) : s
  // 第一句仍过长时，尝试取第一个逗号分句
  if (first.length > maxChars) {
    const comma = /[，,]/.exec(first)
    if (comma && comma.index > 0) first = first.slice(0, comma.index)
  }
  first = first.trim()
  // 最终截断，超长加省略号
  if (first.length > maxChars) first = first.slice(0, maxChars) + "…"
  return first
}

/**
 * 过滤 + 排序 + 渲染索引行。
 * 过滤：usage[name].misses >= SKILL_DEMOTE_AFTER_MISSES 且 hits === 0 → 排除（已降级）。
 * 排序：hits 降序，其次 name 升序。
 * 取前 top 条（默认 SKILL_INDEX_TOP）。
 */
export function buildIndexLines(
  skills: SkillMeta[],
  usage: SkillUsageMap = {},
  opts: IndexOptions = {},
): string[] {
  const top = opts.top ?? SKILL_INDEX_TOP
  const maxChars = opts.maxTriggerChars ?? SKILL_TRIGGER_MAX_CHARS

  const rows: { name: string; hits: number; line: string }[] = []
  for (const s of skills) {
    const u = usage[s.name]
    // 已降级：从未命中且连续未命中达到阈值
    if (u && u.hits === 0 && u.misses >= SKILL_DEMOTE_AFTER_MISSES) continue
    const trigger = triggerOf(s.description, maxChars)
    rows.push({ name: s.name, hits: u?.hits ?? 0, line: `- ${s.name}: ${trigger}` })
  }

  rows.sort((a, b) => b.hits - a.hits || a.name.localeCompare(b.name))
  return rows.slice(0, top).map((r) => r.line)
}

/** 生成完整索引文本：`skills[n]:\n` + 行列表（n 为实际条目数） */
export function buildIndex(
  skills: SkillMeta[],
  usage: SkillUsageMap = {},
  opts: IndexOptions = {},
): string {
  const lines = buildIndexLines(skills, usage, opts)
  return `skills[${lines.length}]:\n` + lines.join("\n")
}
