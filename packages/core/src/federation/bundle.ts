/**
 * 经验包（experience bundle）——「串联」的最小实现。
 *
 * 想解决的问题：一个人/一台机器踩过的坑、压过的块，换台机器要重新踩一遍。
 * 这里把「已压缩的对话块 + 反模式记忆 + 技能索引条目」打成一个纯 JSON 包，
 * 通过文件（或任何能传文件的东西）在本地/网络上交换；导入时去重合并。
 *
 * 三条边界，写死免得膨胀：
 * 1. **不传原始会话**，只传人写过的摘要与规则；包可以公开审阅。
 * 2. **不覆盖本地**：同 id 不同内容时保留本地并记 skipped，冲突要人看。
 * 3. **不联网**：传输方式由调用方决定（U 盘、git、HTTP 都行），本模块零网络。
 */

import type { CompressBlock } from "../compress/store.ts"
import type { MemoryEntry } from "../memory/store.ts"
import { jaccard } from "../memory/store.ts"

/** 包里只放技能的名字与触发语，不放正文（正文可能很大，且各机版本不同）。 */
export interface ExperienceSkill {
  name: string
  description: string
}

export interface ExperienceBundle {
  format: "oml-experience"
  version: 1
  /** 谁产的（主机名/人名/项目名），只作溯源，不参与合并 */
  from: string
  createdAt: string
  blocks: CompressBlock[]
  memories: MemoryEntry[]
  skills: ExperienceSkill[]
}

export interface BundleInput {
  from: string
  blocks?: readonly CompressBlock[]
  memories?: readonly MemoryEntry[]
  skills?: readonly ExperienceSkill[]
}

const MAX_BLOCKS = 500
const MAX_MEMORIES = 200
const MAX_SKILLS = 300

export function createBundle(input: BundleInput, now = Date.now()): ExperienceBundle {
  return {
    format: "oml-experience",
    version: 1,
    from: input.from,
    createdAt: new Date(now).toISOString(),
    blocks: [...(input.blocks ?? [])].slice(0, MAX_BLOCKS),
    memories: [...(input.memories ?? [])].slice(0, MAX_MEMORIES),
    skills: [...(input.skills ?? [])].slice(0, MAX_SKILLS),
  }
}

/** 解析并校验。宁可整包拒绝，也不要半包导入——半个经验比没有更危险。 */
export function parseBundle(text: string): ExperienceBundle {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    throw new Error("经验包不是合法 JSON")
  }
  if (typeof raw !== "object" || raw === null) throw new Error("经验包必须是对象")
  const b = raw as Record<string, unknown>
  if (b["format"] !== "oml-experience") throw new Error('经验包 format 必须是 "oml-experience"')
  if (b["version"] !== 1) throw new Error(`经验包版本不支持：${String(b["version"])}（本机支持 1）`)
  if (typeof b["from"] !== "string" || b["from"].trim() === "") throw new Error("经验包缺少 from")
  for (const key of ["blocks", "memories", "skills"] as const) {
    if (!Array.isArray(b[key])) throw new Error(`经验包字段 ${key} 必须是数组`)
  }
  const blocks = b["blocks"] as CompressBlock[]
  const memories = b["memories"] as MemoryEntry[]
  const skills = b["skills"] as ExperienceSkill[]
  if (blocks.length > MAX_BLOCKS) throw new Error(`blocks 过多（${blocks.length} > ${MAX_BLOCKS}）`)
  if (memories.length > MAX_MEMORIES) throw new Error(`memories 过多（${memories.length} > ${MAX_MEMORIES}）`)
  if (skills.length > MAX_SKILLS) throw new Error(`skills 过多（${skills.length} > ${MAX_SKILLS}）`)
  for (const m of memories) {
    if (typeof m?.text !== "string" || m.text.trim() === "") throw new Error("memories 里有空文本条目")
  }
  return {
    format: "oml-experience",
    version: 1,
    from: b["from"],
    createdAt: typeof b["createdAt"] === "string" ? b["createdAt"] : new Date(0).toISOString(),
    blocks,
    memories,
    skills,
  }
}

export interface MergeStats {
  blocks: number
  memories: number
  skills: number
  /** 冲突或重复而保留本地的条目数 */
  skipped: number
}

export interface MergeResult {
  bundle: ExperienceBundle
  stats: MergeStats
}

/**
 * 合并：本地优先。同 id 且内容不同 → 不动，记 skipped（让冲突可见）。
 * 记忆按文本相似度去重（jaccard ≥ 0.75），避免「同一个坑换个说法」被当成两条。
 */
export function mergeBundle(local: ExperienceBundle, remote: ExperienceBundle): MergeResult {
  const stats: MergeStats = { blocks: 0, memories: 0, skills: 0, skipped: 0 }

  const blocks = [...local.blocks]
  const byId = new Map(blocks.map((b) => [b.id, b]))
  for (const b of remote.blocks) {
    const mine = byId.get(b.id)
    if (mine === undefined) {
      blocks.push(b)
      byId.set(b.id, b)
      stats.blocks += 1
    } else if (mine.summary !== b.summary) {
      stats.skipped += 1
    }
  }

  const memories = [...local.memories]
  for (const r of remote.memories) {
    const dup = memories.some((m) => m.text === r.text || jaccard(m.text, r.text) >= 0.75)
    if (dup) {
      stats.skipped += 1
      continue
    }
    // 导入的记忆换新 id，避免和本地 M<n> 撞号；hits 归零（不是本机踩出来的）
    memories.push({ ...r, id: `X${memories.filter((m) => m.id.startsWith("X")).length + 1}`, hits: 0 })
    stats.memories += 1
  }

  const skills = [...local.skills]
  const names = new Set(skills.map((s) => s.name))
  for (const s of remote.skills) {
    if (names.has(s.name)) {
      stats.skipped += 1
      continue
    }
    skills.push(s)
    names.add(s.name)
    stats.skills += 1
  }

  return {
    bundle: { ...local, blocks, memories, skills },
    stats,
  }
}

/** 人读摘要。头部保持固定格式，便于 diff 与人工审阅。 */
export function renderBundle(b: ExperienceBundle): string {
  const lines = [
    `# 经验包 ${b.from} @ ${b.createdAt}`,
    "",
    `- 压缩块 ${b.blocks.length}`,
    `- 记忆 ${b.memories.length}`,
    `- 技能 ${b.skills.length}`,
    "",
  ]
  for (const block of b.blocks.slice(0, 8)) {
    lines.push(`## ${block.id}（${block.from} → ${block.to}）`, "", block.summary.trim(), "")
  }
  for (const m of b.memories.slice(0, 8)) {
    lines.push(`- [${m.kind}] ${m.text}`)
  }
  if (b.skills.length > 0) {
    lines.push("", `技能：${b.skills.map((s) => s.name).join(", ")}`)
  }
  return `${lines.join("\n")}\n`
}
