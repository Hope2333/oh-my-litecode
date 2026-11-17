import { describe, test, expect } from "bun:test"
import { estimateTokens } from "./estimate.ts"

describe("estimateTokens", () => {
  test("纯 ASCII：每 4 个非空白字符计 1 token", () => {
    expect(estimateTokens("abcdefgh")).toBe(2)
    expect(estimateTokens("abc")).toBe(1)
  })

  test("纯 CJK：每字计 1 token", () => {
    expect(estimateTokens("上下文预算")).toBe(5)
  })

  test("混合：CJK 计 1，ASCII 每 4 计 1", () => {
    // 2 个 CJK = 2；8 个 ASCII = 2
    expect(estimateTokens("预算abcdefgh")).toBe(4)
  })

  test("空字符串返回 0", () => {
    expect(estimateTokens("")).toBe(0)
  })

  test("纯空白：连续空白每 6 个计 1 token", () => {
    expect(estimateTokens("      ")).toBe(1)
    expect(estimateTokens("           ")).toBe(2)
  })

  test("非空白字符会打断连续空白计数", () => {
    // 3 空白 + a + 3 空白 => other=1 -> 1 tok, 两个空白段各 ceil(3/6)=1 => 3
    expect(estimateTokens("   a   ")).toBe(3)
  })

  test("CJK 标点区间（U+3000-U+303F）按 1 计", () => {
    expect(estimateTokens("\u3002\u3001")).toBe(2)
  })
})
