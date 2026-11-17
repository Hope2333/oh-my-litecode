import { describe, expect, test } from "bun:test"
import { scanSlop, summarizeSlop } from "./slop.ts"

const scan = (text: string, path = "a.ts") => scanSlop([{ path, text }])

describe("scanSlop", () => {
  test("注释复述下一行代码", () => {
    const f = scan(["// 设置 userName 为 input", "const userName = input", "export {}"].join("\n"))
    expect(f.map((x) => x.rule)).toContain("comment-restates-code")
  })

  test("中文动词开头的短复述", () => {
    const f = scan(["// 返回结果", "return result"].join("\n"))
    expect(f.map((x) => x.rule)).toContain("comment-restates-code")
  })

  test("装饰性横幅", () => {
    const f = scan(["// ==========", "export const a = 1"].join("\n"))
    expect(f.map((x) => x.rule)).toContain("decorative-banner")
  })

  test("占位符", () => {
    const f = scan(["// TODO: 待实现", "export const a = 1"].join("\n"))
    expect(f.map((x) => x.rule)).toContain("placeholder")
  })

  test("填充语", () => {
    const f = scan(["// 需要注意的是：", "export const a = 1"].join("\n"))
    expect(f.map((x) => x.rule)).toContain("filler-phrase")
  })

  test("注释占比过高", () => {
    const lines = Array.from({ length: 30 }, (_, i) => `// 说明 ${i}`)
    lines.push("export const a = 1")
    const f = scan(lines.join("\n"))
    expect(f.map((x) => x.rule)).toContain("comment-heavy")
  })

  test("自明的代码不误报", () => {
    const src = [
      "export function add(a: number, b: number): number {",
      "  return a + b",
      "}",
      "",
      "/** 为什么用整数：浮点在这里会累积误差。 */",
      "export const SCALE = 1000",
    ].join("\n")
    expect(scan(src)).toEqual([])
  })

  test("摘要统计各规则数量", () => {
    const f = scan(["// ==========", "// TODO: x", "export const a = 1"].join("\n"))
    expect(summarizeSlop(f)).toContain("处")
    expect(summarizeSlop([])).toBe("未发现 slop")
  })
})
