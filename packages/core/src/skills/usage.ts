/**
 * 惰性技能索引 —— 使用统计层。
 *
 * 职责：持久化每个技能的 hits / lastUsed / misses，驱动索引的排序与降级。
 * recordHit / recordMisses 均为**纯函数**：返回新对象，不修改入参。
 */

import { mkdir, readFile, writeFile } from "node:fs/promises"
import { dirname, join } from "node:path"
import { SKILL_DEMOTE_AFTER_MISSES, type SkillUsageMap } from "../contract.ts"
import { legacyStateDir, statePath } from "../paths.ts"

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

/** 写入使用统计，递归创建父目录。 */
export async function saveUsage(u: SkillUsageMap, path: string = usagePath()): Promise<void> {
  const write = async (): Promise<void> => {
    await mkdir(dirname(path), { recursive: true })
    await writeFile(path, JSON.stringify(u, null, 2), "utf8")
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
 * 记录一轮未命中：activeNames 中的名字 misses 归零；其余已有条目 misses+1。
 * 纯函数，返回新对象。
 */
export function recordMisses(u: SkillUsageMap, activeNames: string[]): SkillUsageMap {
  const active = new Set(activeNames)
  const out: SkillUsageMap = {}
  for (const [key, val] of Object.entries(u)) {
    out[key] = active.has(key) ? { ...val, misses: 0 } : { ...val, misses: val.misses + 1 }
  }
  return out
}

/** 返回已降级的名字列表（misses >= threshold 且 hits === 0），字典序。 */
export function demoted(
  u: SkillUsageMap,
  threshold: number = SKILL_DEMOTE_AFTER_MISSES,
): string[] {
  return Object.entries(u)
    .filter(([, v]) => v.misses >= threshold && v.hits === 0)
    .map(([k]) => k)
    .sort((a, b) => a.localeCompare(b))
}
