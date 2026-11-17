/**
 * 经验蒸馏测试：从失败任务账本提炼反模式候选、按出现次数排序、
 * 已知规则不重复建议、applyAntiPatterns 落库为 antipattern 记忆。
 */
import { describe, test, expect } from "bun:test"
import { emptyStore, addTask, transition, type TaskStore } from "../tasks/store.ts"
import { addMemory, emptyMemoryStore, type MemoryStore } from "./store.ts"
import { applyAntiPatterns, distillAntiPatterns } from "./dreams.ts"

/** 造若干失败任务：同一关键词出现多次。 */
function seedFailed(n: number, keyword: string): TaskStore {
  let s = emptyStore()
  for (let i = 0; i < n; i++) {
    const r = addTask(s, {
      description: `修复 ${keyword} 模块的布局错位问题`,
      category: "quick",
    })
    if (!r.ok) continue
    s = r.store
    const t = transition(s, r.task.id, "running")
    if (!t.ok) continue
    s = t.store
    const f = transition(s, r.task.id, "failed", { error: `布局 ${i} 又错位了` })
    if (f.ok) s = f.store
  }
  return s
}

describe("经验蒸馏", () => {
  test("反复失败的关键词被提炼为反模式候选", () => {
    const tasks = seedFailed(3, "布局")
    const cands = distillAntiPatterns(tasks, emptyMemoryStore(), { minOccurrences: 2 })
    expect(cands.length).toBeGreaterThan(0)
    expect(cands[0]?.occurrences).toBe(3)
    expect(cands[0]?.rule).toContain("布局")
  })

  test("单次失败不成候选（低于 minOccurrences）", () => {
    const tasks = seedFailed(1, "布局")
    const cands = distillAntiPatterns(tasks, emptyMemoryStore(), { minOccurrences: 2 })
    expect(cands.length).toBe(0)
  })

  test("已落库的规则不再重复建议", () => {
    const tasks = seedFailed(3, "布局")
    const first = distillAntiPatterns(tasks, emptyMemoryStore(), { minOccurrences: 2 })
    expect(first.length).toBeGreaterThan(0)
    // 把第一条落库
    let mem: MemoryStore = emptyMemoryStore()
    const r = addMemory(mem, first[0]!.rule, Date.now(), "antipattern")
    if (r.ok) mem = r.store
    // 再蒸馏：同一条应被已知集合滤掉
    const second = distillAntiPatterns(tasks, mem, { minOccurrences: 2 })
    expect(second.find((c) => c.rule === first[0]!.rule)).toBeUndefined()
  })

  test("applyAntiPatterns 落库为 antipattern 类型", () => {
    const tasks = seedFailed(3, "布局")
    const cands = distillAntiPatterns(tasks, emptyMemoryStore(), { minOccurrences: 2 })
    const r = applyAntiPatterns(emptyMemoryStore(), cands)
    expect(r.added).toBeGreaterThan(0)
    const entries = Object.values(r.store.memories)
    expect(entries.every((m) => m.kind === "antipattern")).toBe(true)
  })

  test("无失败任务时空手而归", () => {
    const cands = distillAntiPatterns(emptyStore(), emptyMemoryStore())
    expect(cands.length).toBe(0)
  })
})
