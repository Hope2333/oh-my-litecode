/**
 * 惰性技能索引 —— 使用统计层。
 *
 * 职责：持久化每个技能的 hits / lastUsed / misses，驱动索引的排序与降级。
 * recordHit / recordMisses 均为**纯函数**：返回新对象，不修改入参。
 */

import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname, join } from "node:path"
import { SKILL_DEMOTE_AFTER_MISSES, SKILL_MIN_HIT_RATE, type SkillUsageMap } from "../contract.ts"
import { legacyStateDir, statePath } from "../paths.ts"

/** 并发写序号：host 自检与显式调用可能同时保存，独立 tmp 名避免互抢 rename。 */
let usageSaveSeq = 0

/** 使用统计文件的默认存储路径 */
export function usagePath(): string {
  return statePath("skill-usage.json")
}

function isUsageMap(v: unknown): v is SkillUsageMap {
  return typeof v === "object" && v !== null && !Array.isArray(v)
}

/** 读一个统计文件；不存在或损坏 → null（与「空统计」区分开，便于回落旧目录）。 */
async function readUsageFile(path: string): Promise<SkillUsageMap | null> {
  try {
    const raw = await readFile(path, "utf8")
    const parsed: unknown = JSON.parse(raw)
    if (!isUsageMap(parsed)) return null
    const out: SkillUsageMap = {}
    for (const [key, val] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof val !== "object" || val === null) continue
      const o = val as Record<string, unknown>
      if (
        typeof o.hits !== "number" ||
        typeof o.lastUsed !== "number" ||
        typeof o.misses !== "number"
      ) {
        continue
      }
      out[key] = { hits: o.hits, lastUsed: o.lastUsed, misses: o.misses }
    }
    return out
  } catch {
    return null
  }
}

/**
 * 读取使用统计。文件不存在或内容损坏 → 返回 {}。
 * 默认路径为空时回落读取 OMO 遗留目录一次（迁移期），避免历史命中被清零。
 */
export async function loadUsage(path: string = usagePath()): Promise<SkillUsageMap> {
  const primary = await readUsageFile(path)
  if (primary !== null) return primary
  if (path === usagePath()) {
    const legacy = await readUsageFile(join(legacyStateDir(), "skill-usage.json"))
    if (legacy !== null) return legacy
  }
  return {}
}

/**
 * 写入使用统计，递归创建父目录，原子替换。
 *
 * 质量探测发现（2026-11-17）：曾用裸 writeFile，并发/中断写留下尾部 NUL 与截断，
 * 实际损坏过本机 skill-usage.json（末尾 `},` 后缺 `}` 且被 NUL 填充）。
 * 与 mcp/catalog、memory/store 等所有其它状态写入对齐：tmp → rename 原子提交。
 */
export async function saveUsage(u: SkillUsageMap, path: string = usagePath()): Promise<void> {
  const write = async (): Promise<void> => {
    await mkdir(dirname(path), { recursive: true })
    const tmp = `${path}.${process.pid}.${++usageSaveSeq}.tmp`
    await writeFile(tmp, `${JSON.stringify(u, null, 2)}\n`, "utf8")
    await rename(tmp, path)
  }
  try {
    await write()
  } catch (err) {
    // 状态目录被外部删除时重建一次；仍失败才抛出。
    if ((err as { code?: string }).code !== "ENOENT") throw err
    await write()
  }
}

/** 记录一次命中：hits+1、lastUsed=now、misses 归零。纯函数。 */
export function recordHit(
  u: SkillUsageMap,
  name: string,
  now: number = Date.now(),
): SkillUsageMap {
  const prev = u[name]
  return {
    ...u,
    [name]: { hits: (prev?.hits ?? 0) + 1, lastUsed: now, misses: 0 },
  }
}

/**
 * 记录一轮「真实未命中」（P2·群众路线）。
 *
 * offeredNames 是本轮**被放进候选索引、模型有机会看到**的技能名。
 * 语义：只有「被提供却没被 skill(name) 加载」才算未命中——
 *   - 被提供的名字：misses+1（若本轮真被加载，随后的 recordHit 会把 misses 归零）
 *   - 未被提供的名字：不计 miss（它根本没机会被选中，不算它的错）
 *
 * 这推翻了旧实现「没进索引就 +1」的轮计数器：那会让满屏技能每轮饱和累加，
 * 且与命中率无关。新语义下 misses 是真实的「 offered-but-unused 」次数。
 * 纯函数，返回新对象。
 */
export function recordMisses(u: SkillUsageMap, offeredNames: string[]): SkillUsageMap {
  const offered = new Set(offeredNames)
  const out: SkillUsageMap = {}
  for (const [key, val] of Object.entries(u)) {
    // 未提供的名字：原样保留，不制造假信号
    if (!offered.has(key)) {
      out[key] = val
      continue
    }
    // 被提供：累计一次曝光未使用；真正加载会被 recordHit 归零
    out[key] = { ...val, misses: val.misses + 1 }
  }
  return out
}

/**
 * 命中率：hits / (hits + misses)。无曝光（分母 0）视为 1（不降级）。
 * 这是「真实反馈」信号——一次历史命中不再给终身豁免。
 */
export function hitRate(v: { hits: number; misses: number }): number {
  const total = v.hits + v.misses
  return total === 0 ? 1 : v.hits / total
}

/**
 * 单个条目是否该降级：曝光够多（misses>=threshold）且命中率低于下限。
 * 唯一判据源——build.ts（exclude）与 index-gen.ts（buildIndexLines）共用，消灭重复。
 */
export function isDemoted(
  v: { hits: number; misses: number },
  threshold: number = SKILL_DEMOTE_AFTER_MISSES,
  minRate: number = SKILL_MIN_HIT_RATE,
): boolean {
  return v.misses >= threshold && hitRate(v) < minRate
}

/** 返回已降级的名字列表，字典序。 */
export function demoted(
  u: SkillUsageMap,
  threshold: number = SKILL_DEMOTE_AFTER_MISSES,
  minRate: number = SKILL_MIN_HIT_RATE,
): string[] {
  return Object.entries(u)
    .filter(([, v]) => isDemoted(v, threshold, minRate))
    .map(([k]) => k)
    .sort((a, b) => a.localeCompare(b))
}
