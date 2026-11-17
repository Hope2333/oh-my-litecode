import { describe, test, expect } from "bun:test"
import { assemble } from "./assemble.ts"
import { estimateTokens } from "./estimate.ts"
import type { Section } from "../contract.ts"

function sec(id: Section["id"], text: string, items = 1): Section {
  return { id, text, items }
}

describe("assemble", () => {
  test("不超限 → pass，不截断", () => {
    const sections = [sec("tools", "abcd"), sec("identity", "你")]
    const { prompt, report } = assemble(sections, 100)
    expect(report.budget.status).toBe("pass")
    expect(report.warnings).toEqual([])
    expect(report.sections.every((s) => !s.truncated)).toBe(true)
    expect(prompt).toBe("## tools\nabcd\n\n## identity\n你")
  })

  test("超限时 memory 先被砍", () => {
    const sections = [
      sec("tools", "abcd"), // 1 tok
      sec("memory", "一二三四五六七八九十"), // 10 tok
    ]
    const { report } = assemble(sections, 5)
    expect(report.budget.status).toBe("truncated")
    const mem = report.sections.find((s) => s.id === "memory")
    expect(mem?.truncated).toBe(true)
    expect(report.totalTokens).toBeLessThanOrEqual(5)
  })

  test("memory 砍空后砍 skillIndex", () => {
    const sections = [
      sec("tools", "abcdefgh"), // 2 tok
      sec("identity", "ijklmnop"), // 2 tok
      sec("skillIndex", "qrstuvwx"), // 2 tok
      sec("memory", "一二三四五六七八九十"), // 10 tok
    ]
    const { report } = assemble(sections, 5)
    expect(report.budget.status).toBe("truncated")
    const mem = report.sections.find((s) => s.id === "memory")
    const skill = report.sections.find((s) => s.id === "skillIndex")
    expect(mem?.tokens).toBe(0)
    expect(skill?.truncated).toBe(true)
    expect(report.totalTokens).toBeLessThanOrEqual(5)
  })

  test("tools 不被砍", () => {
    const sections = [
      sec("tools", "abcdefgh"), // 2 tok
      sec("memory", "一二三四五六七八九十"), // 10 tok
    ]
    const { report } = assemble(sections, 4)
    const tools = report.sections.find((s) => s.id === "tools")
    expect(tools?.truncated).toBe(false)
    expect(tools?.tokens).toBe(2)
  })

  test("全砍完仍超限 → fail（tools 不裁）", () => {
    const sections = [
      sec("tools", "一二三四五六七八九十"), // 10 tok
      sec("memory", "abc"), // 1 tok
    ]
    const { report } = assemble(sections, 5)
    expect(report.budget.status).toBe("fail")
    expect(report.sections.find((s) => s.id === "tools")?.truncated).toBe(false)
  })

  test("prompt 段顺序与原始数组一致", () => {
    const sections = [
      sec("memory", "M"),
      sec("tools", "T"),
      sec("identity", "I"),
    ]
    const { prompt } = assemble(sections, 1000)
    expect(prompt).toBe("## memory\nM\n\n## tools\nT\n\n## identity\nI")
  })

  test("warnings 写中文告警，含前后 token 数", () => {
    const sections = [sec("tools", "abcd"), sec("memory", "一二三四五六七八九十")]
    const { report } = assemble(sections, 5)
    expect(report.warnings.length).toBeGreaterThan(0)
    expect(report.warnings[0]).toMatch(/^\[budget\] 段 memory 被截断：\d+ → \d+ tok$/)
    expect(estimateTokens("x")).toBe(1)
  })
})
