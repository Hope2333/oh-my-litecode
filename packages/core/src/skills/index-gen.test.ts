import { describe, test, expect } from "bun:test"
import { triggerOf, buildIndexLines, buildIndex } from "./index-gen.ts"
import { SKILL_DEMOTE_AFTER_MISSES, type SkillMeta, type SkillUsageMap } from "../contract.ts"

function meta(name: string, description: string): SkillMeta {
  return { name, description, root: "/r", file: `/r/${name}/SKILL.md` }
}

// ---------------------------------------------------------------- triggerOf

describe("triggerOf", () => {
  test("截断到 40 字符并加省略号", () => {
    const long = "a".repeat(50)
    const t = triggerOf(long, 40)
    expect(t).toBe("a".repeat(40) + "…")
    expect(t.length).toBe(41)
  })

  test("不超过 40 字符时不加省略号", () => {
    expect(triggerOf("short description", 40)).toBe("short description")
  })

  test("剔除换行与 YAML 残留符号 | >", () => {
    const t = triggerOf("line1\nline2 | leftover > junk", 40)
    expect(t).not.toContain("\n")
    expect(t).not.toContain("|")
    expect(t).not.toContain(">")
    expect(t).toBe("line1 line2 leftover junk")
  })

  test("取第一句", () => {
    expect(triggerOf("First sentence. Second one.", 40)).toBe("First sentence")
  })

  test("第一句过长时取第一个逗号分句", () => {
    const t = triggerOf("This is a very long first clause, and here is more text", 40)
    expect(t).toBe("This is a very long first clause")
  })

  test("默认 maxChars 为 40", () => {
    const t = triggerOf("x".repeat(60))
    expect(t).toBe("x".repeat(40) + "…")
  })
})

// ---------------------------------------------------------------- buildIndexLines / buildIndex

describe("buildIndexLines", () => {
  test("每行形如 `- name: trigger`", () => {
    const lines = buildIndexLines([meta("alpha", "Do alpha things. More.")])
    expect(lines).toEqual(["- alpha: Do alpha things"])
  })

  test("降级技能被排除（misses 达阈值且 hits=0）", () => {
    const skills = [meta("hot", "hot desc"), meta("cold", "cold desc")]
    const usage: SkillUsageMap = {
      hot: { hits: 3, lastUsed: 1, misses: 0 },
      cold: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES },
    }
    const lines = buildIndexLines(skills, usage)
    const names = lines.join("\n")
    expect(names).toContain("hot")
    expect(names).not.toContain("cold")
  })

  test("misses 未达阈值时不降级", () => {
    const skills = [meta("lukewarm", "desc")]
    const usage: SkillUsageMap = {
      lukewarm: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES - 1 },
    }
    expect(buildIndexLines(skills, usage)).toHaveLength(1)
  })

  test("hits 降序，其次 name 升序", () => {
    const skills = [meta("a", "d"), meta("b", "d"), meta("c", "d")]
    const usage: SkillUsageMap = {
      a: { hits: 1, lastUsed: 0, misses: 0 },
      b: { hits: 5, lastUsed: 0, misses: 0 },
      c: { hits: 5, lastUsed: 0, misses: 0 },
    }
    // b/c 同为 5 按 name 升序，a 的 hits 最低排最后
    const lines = buildIndexLines(skills, usage)
    expect(lines.map((l) => l.split(":")[0])).toEqual(["- b", "- c", "- a"])
  })

  test("top 生效", () => {
    const skills = ["a", "b", "c", "d", "e"].map((n) => meta(n, "desc"))
    const lines = buildIndexLines(skills, {}, { top: 3 })
    expect(lines).toHaveLength(3)
  })

  test("默认 top 为 40", () => {
    const skills = Array.from({ length: 60 }, (_, i) => meta(`s${i}`, "desc"))
    expect(buildIndexLines(skills)).toHaveLength(40)
  })
})

describe("buildIndex", () => {
  test("返回 skills[n] 头 + 行，n 为实际条目数", () => {
    const skills = [meta("a", "da"), meta("b", "db")]
    const out = buildIndex(skills)
    expect(out.startsWith("skills[2]:\n")).toBe(true)
    expect(out).toContain("- a: da")
    expect(out).toContain("- b: db")
  })

  test("全部降级时 n 为 0", () => {
    const skills = [meta("x", "d")]
    const usage: SkillUsageMap = {
      x: { hits: 0, lastUsed: 0, misses: SKILL_DEMOTE_AFTER_MISSES },
    }
    expect(buildIndex(skills, usage)).toBe("skills[0]:\n")
  })
})
