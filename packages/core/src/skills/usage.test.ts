import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  usagePath,
  loadUsage,
  saveUsage,
  recordHit,
  recordMisses,
  demoted,
} from "./usage.ts"
import { SKILL_DEMOTE_AFTER_MISSES, type SkillUsageMap } from "../contract.ts"

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
  test("activeNames 归零，其余 misses+1，不修改入参", () => {
    const orig: SkillUsageMap = {
      active: { hits: 0, lastUsed: 0, misses: 3 },
      idle: { hits: 0, lastUsed: 0, misses: 1 },
    }
    const snapshot = JSON.stringify(orig)
    const next = recordMisses(orig, ["active"])

    expect(next).not.toBe(orig)
    expect(JSON.stringify(orig)).toBe(snapshot)

    expect(next["active"]?.misses).toBe(0)
    expect(next["idle"]?.misses).toBe(2)
  })
})

describe("demoted", () => {
  test("返回 misses>=threshold 且 hits=0 的名字，字典序", () => {
    const u: SkillUsageMap = {
      b_cold: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES },
      a_cold: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES },
      warm: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES - 1 },
      used: { hits: 2, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES },
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
