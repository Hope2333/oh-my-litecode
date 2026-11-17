import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, dirname } from "node:path"
import {
  usagePath,
  loadUsage,
  saveUsage,
  recordHit,
  recordMisses,
  hitRate,
  isDemoted,
  demoted,
} from "./usage.ts"
import { SKILL_DEMOTE_AFTER_MISSES, SKILL_MIN_HIT_RATE, type SkillUsageMap } from "../contract.ts"

describe("usagePath", () => {
  test("路径为 <stateDir>/skill-usage.json（默认 ~/.local/state/oml）", () => {
    expect(usagePath()).toMatch(/\.local[/\\]state[/\\]oml[/\\]skill-usage\.json$/)
  })
})

describe("recordHit（纯函数）", () => {
  test("hits+1、lastUsed 更新、misses 归零，且不修改入参", () => {
    const orig: SkillUsageMap = {
      a: { hits: 1, lastUsed: 100, misses: 5 },
    }
    const snapshot = JSON.stringify(orig)
    const next = recordHit(orig, "a", 200)

    // 返回新对象，原对象未变
    expect(next).not.toBe(orig)
    expect(JSON.stringify(orig)).toBe(snapshot)
    expect(orig["a"]?.hits).toBe(1)
    expect(orig["a"]?.misses).toBe(5)
    expect(orig["a"]?.lastUsed).toBe(100)

    expect(next.a).toEqual({ hits: 2, lastUsed: 200, misses: 0 })
  })

  test("对不存在条目新建：hits=1、misses=0", () => {
    const next = recordHit({}, "new", 42)
    expect(next.new).toEqual({ hits: 1, lastUsed: 42, misses: 0 })
  })
})

describe("recordMisses（纯函数）", () => {
  test("只有被提供的名字 misses+1，未提供的原样保留，不修改入参", () => {
    const orig: SkillUsageMap = {
      offered: { hits: 0, lastUsed: 0, misses: 3 },
      notOffered: { hits: 0, lastUsed: 0, misses: 1 },
    }
    const snapshot = JSON.stringify(orig)
    const next = recordMisses(orig, ["offered"])

    expect(next).not.toBe(orig)
    expect(JSON.stringify(orig)).toBe(snapshot)

    expect(next["offered"]?.misses).toBe(4)
    // 未被提供：不再制造假信号（旧实现会把它 +1 到 2）
    expect(next["notOffered"]?.misses).toBe(1)
  })

  test("真被加载的条目由 recordHit 归零，组合语义为真实未命中", () => {
    const offered = recordMisses({ x: { hits: 0, lastUsed: 0, misses: 0 } }, ["x"])
    expect(offered.x?.misses).toBe(1)
    const loaded = recordHit(offered, "x", 100)
    expect(loaded.x).toEqual({ hits: 1, lastUsed: 100, misses: 0 })
  })
})

describe("hitRate / isDemoted / demoted", () => {
  test("hitRate：命中率 = hits/(hits+misses)，无曝光视为 1", () => {
    expect(hitRate({ hits: 1, misses: 9 })).toBeCloseTo(0.1)
    expect(hitRate({ hits: 0, misses: 0 })).toBe(1)
  })

  test("一次历史命中不再是终身豁免（1 hit / 656 misses 仍降级）", () => {
    const stale = { hits: 1, lastUsed: 0, misses: 656 }
    expect(hitRate(stale)).toBeLessThan(SKILL_MIN_HIT_RATE)
    expect(isDemoted(stale)).toBe(true)
    expect(demoted({ stale })).toEqual(["stale"])
  })

  test("高频技能即使有未命中也不降级", () => {
    const hot = { hits: 20, lastUsed: 0, misses: 30 }
    expect(hitRate(hot)).toBeGreaterThan(SKILL_MIN_HIT_RATE)
    expect(isDemoted(hot)).toBe(false)
  })

  test("曝光不足不降级；返回名字字典序", () => {
    const u: SkillUsageMap = {
      b_cold: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES },
      a_cold: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES },
      warm: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES - 1 },
    }
    expect(demoted(u)).toEqual(["a_cold", "b_cold"])
  })

  test("自定义 threshold", () => {
    const u: SkillUsageMap = { x: { hits: 0, lastUsed: 0, misses: 3 } }
    expect(demoted(u, 3)).toEqual(["x"])
    expect(demoted(u, 5)).toEqual([])
  })
})

describe("loadUsage / saveUsage 往返", () => {
  let dir: string
  let file: string

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "oml-usage-"))
    file = join(dir, "nested", "sub", "skill-usage.json") // 故意多层，验证递归建目录
  })
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true })
  })

  test("saveUsage → loadUsage 往返一致", async () => {
    const u: SkillUsageMap = {
      a: { hits: 3, lastUsed: 111, misses: 0 },
      b: { hits: 0, lastUsed: 0, misses: 12 },
    }
    await saveUsage(u, file)
    const loaded = await loadUsage(file)
    expect(loaded).toEqual(u)
  })

  test("saveUsage 原子写：无残留 tmp，连续两次写后内容完整无 NUL（回归）", async () => {
    const a: SkillUsageMap = { x: { hits: 9, lastUsed: 1, misses: 0 } }
    const b: SkillUsageMap = { y: { hits: 1, lastUsed: 2, misses: 3 } }
    await saveUsage(a, file)
    await saveUsage(b, file)
    const { readdir, readFile } = await import("node:fs/promises")
    const entries = await readdir(dirname(file))
    expect(entries.some((e) => e.endsWith(".tmp"))).toBe(false)
    const raw = await readFile(file, "utf8")
    expect(raw).not.toContain("\0")
    expect(loadUsage(file)).resolves.toEqual(b)
  })

  test("loadUsage 对不存在的文件返回 {}", async () => {
    expect(await loadUsage(join(dir, "nope.json"))).toEqual({})
  })

  test("loadUsage 对损坏 JSON 返回 {}", async () => {
    const bad = join(dir, "bad.json")
    await writeFile(bad, "{ not valid json ]", "utf8")
    expect(await loadUsage(bad)).toEqual({})
  })

  test("loadUsage 对形状非法的条目过滤", async () => {
    const bad = join(dir, "shape.json")
    await writeFile(
      bad,
      JSON.stringify({ good: { hits: 1, lastUsed: 2, misses: 3 }, bad: { hits: "x" } }),
      "utf8",
    )
    const loaded = await loadUsage(bad)
    expect(Object.keys(loaded)).toEqual(["good"])
  })
})
