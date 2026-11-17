/**
 * 经验蒸馏（吸收自 opencode-dreams）。
 *
 * 判据（扬弃）：
 *   - 保留：从历史提炼「不再重复犯错」的规则，落成持久记忆。
 *   - 废弃：dreams 的独立守护进程 / 定时 consolidate / LLM 总结调用。OML 不跑后台进程、
 *     不额外调模型；蒸馏是**确定性**的：从任务账本的失败记录里抽共因，产出反模式候选，
 *     由主代理审阅后用 memory_add（kind=antipattern）落库。
 *   - 归并：dreams 的「经验」= OML 的 antipattern 记忆；snippets = 片段记忆。一套账本。
 *
 * 零运行时依赖。
 */
import type { TaskStore } from "../tasks/store.ts"
import type { MemoryStore } from "./store.ts"
import { addMemory } from "./store.ts"

/** 一条蒸馏出的反模式候选。 */
export interface AntiPatternCandidate {
  /** 触发反模式的关键词/短语（从失败任务描述里抽） */
  readonly pattern: string
  /** 建议写入的记忆正文（祈使句，可直接当规则用） */
  readonly rule: string
  /** 支撑它的失败任务数 */
  readonly occurrences: number
  /** 样例失败原因（脱敏后） */
  readonly sampleError: string
}

/** 失败任务里可作共因信号的「停用词」：太泛，不构成反模式。 */
const GENERIC = new Set([
  "任务", "失败", "错误", "超时", "未完成", "执行", "处理", "完成", "实现", "修改",
  // 泛动词：几乎所有任务描述都带，不构成反模式信号
  "修复", "添加", "更新", "检查", "调整", "重构", "优化", "支持", "问题", "功能", "模块",
  "fix", "add", "update", "check", "refactor", "optimize", "support", "issue", "module", "make",
  "the", "and", "for", "with", "error", "failed", "task", "timeout",
])

function tokenize(text: string): string[] {
  return text
    .replace(/[^\p{Script=Han}A-Za-z0-9]+/gu, " ")
    .split(/\s+/)
    .map((w) => w.trim())
    .filter((w) => w.length >= 2 && !GENERIC.has(w.toLowerCase()))
}

/**
 * 从任务账本蒸馏反模式候选。
 * 信号：status=failed 的任务，按「描述里的关键词」聚类，出现 ≥minOccurrences 次的算共因。
 * 已在记忆里的规则不重复产出（按归一化文本判重）。
 */
export function distillAntiPatterns(
  tasks: TaskStore,
  memory: MemoryStore,
  opts: { minOccurrences?: number; limit?: number; now?: number } = {},
): AntiPatternCandidate[] {
  const minOccurrences = opts.minOccurrences ?? 2
  const limit = opts.limit ?? 8
  const now = opts.now ?? Date.now()

  // 已有记忆的归一化集合，避免重复建议
  const known = new Set(
    Object.values(memory.memories).map((m) => m.text.replace(/\s+/g, " ").trim().toLowerCase()),
  )

  // 收集失败任务
  const failed = Object.values(tasks.tasks).filter((t) => t.status === "failed")
  // 关键词 → 失败任务集合
  const buckets = new Map<string, { count: number; errors: string[]; desc: string }>()
  for (const t of failed) {
    const words = new Set(tokenize(t.description))
    const err = (t.error ?? "").replace(/\s+/g, " ").trim().slice(0, 160)
    for (const w of words) {
      const b = buckets.get(w) ?? { count: 0, errors: [], desc: w }
      b.count += 1
      if (err !== "" && b.errors.length < 3) b.errors.push(err)
      buckets.set(w, b)
    }
  }

  const candidates: AntiPatternCandidate[] = []
  const ranked = [...buckets.values()]
    .filter((b) => b.count >= minOccurrences)
    .sort((a, b) => b.count - a.count)
    .slice(0, limit)
  for (const b of ranked) {
    const rule = `反复在「${b.desc}」上失败（${b.count} 次）。动这块前先复现最近一次失败、确认根因，再动手；不要凭印象重试同样做法。`
    if (known.has(rule.toLowerCase())) continue
    candidates.push({
      pattern: b.desc,
      rule,
      occurrences: b.count,
      sampleError: b.errors[0] ?? "",
    })
  }
  void now
  return candidates
}

/** 把候选直接落成反模式记忆（跳过审阅，供 CLI --apply 用）。 */
export function applyAntiPatterns(
  memory: MemoryStore,
  candidates: AntiPatternCandidate[],
  now: number = Date.now(),
): { store: MemoryStore; added: number; deduped: number } {
  let store = memory
  let added = 0
  let deduped = 0
  for (const c of candidates) {
    const r = addMemory(store, c.rule, now, "antipattern")
    if (!r.ok) continue
    store = r.store
    if (r.deduped) deduped += 1
    else added += 1
  }
  return { store, added, deduped }
}
