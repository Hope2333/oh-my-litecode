import { describe, expect, test } from "bun:test"
import { context7Hint, wantsContext7Docs } from "./context7-hint.ts"

describe("wantsContext7Docs 触发判定", () => {
  test("库/框架怎么用文档类命中", () => {
    expect(wantsContext7Docs("这个库怎么用？看下文档")).toBe(true)
    expect(wantsContext7Docs("React 框架的官方文档")).toBe(true)
    expect(wantsContext7Docs("查一下某个库的 API 用法")).toBe(true)
    expect(wantsContext7Docs("official docs of zustand")).toBe(true)
    expect(wantsContext7Docs("how to use axios")).toBe(true)
  })

  test("无关任务不命中", () => {
    expect(wantsContext7Docs("修复任务状态机的父任务 bug")).toBe(false)
    expect(wantsContext7Docs("把这段 TypeScript 重构成纯函数")).toBe(false)
  })
})

describe("context7Hint 文本", () => {
  test("无关任务 / 空输入返回空串（不注入）", () => {
    expect(context7Hint("修复状态机 bug")).toBe("")
    expect(context7Hint("")).toBe("")
  })

  test("命中：给出调用链 + 反修措辞 + 默认禁用说明", () => {
    const h = context7Hint("这个库怎么用，查下官方文档")
    expect(h).toContain("context7")
    expect(h).toContain("resolve-library-id")
    expect(h).toContain("query-docs")
    expect(h).toContain("交叉验证")
    expect(h).toContain("权威≠真理")
    expect(h).toContain("默认禁用")
    expect(h).toContain("omo_admin action=mcp op=enable target=context7")
  })

  test("enabled=false 时完全不注入", () => {
    expect(context7Hint("这个库怎么用，查下官方文档", { enabled: false })).toBe("")
  })
})
