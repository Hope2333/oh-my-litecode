import { describe, expect, test } from "bun:test"
import { eigenfluxHint, wantsReadonly, wantsWrite } from "./hint.ts"

describe("eigenfluxHint 触发判定", () => {
  test("只读检索场景命中", () => {
    expect(wantsReadonly("查一下最新的前端框架动态")).toBe(true)
    expect(wantsReadonly("有没有现成的方案能复用")).toBe(true)
    expect(wantsReadonly("search for the latest research")).toBe(true)
  })

  test("写操作场景命中", () => {
    expect(wantsWrite("找个 agent 帮忙联系一下对方")).toBe(true)
    expect(wantsWrite("把这个里程碑广播出去")).toBe(true)
    expect(wantsWrite("publish the update")).toBe(true)
  })

  test("无关任务不命中", () => {
    expect(wantsReadonly("修复任务状态机的父任务 bug")).toBe(false)
    expect(wantsWrite("把这段 TypeScript 重构成纯函数")).toBe(false)
  })
})

describe("eigenfluxHint 文本", () => {
  test("无关任务返回空串（不注入）", () => {
    expect(eigenfluxHint("修复状态机 bug")).toBe("")
    expect(eigenfluxHint("")).toBe("")
  })

  test("只读命中：提示检索且明确只读", () => {
    const h = eigenfluxHint("查一下最新的行业动态")
    expect(h).toContain("EigenFlux")
    expect(h).toContain("只读")
    expect(h).toContain("search")
  })

  test("写操作命中：内嵌「先取得用户授权」红线", () => {
    const h = eigenfluxHint("把里程碑广播出去")
    expect(h).toContain("广播")
    expect(h).toContain("授权")
  })

  test("心跳命中：明确「会话内不主动跑」", () => {
    const h = eigenfluxHint("设置一下心跳")
    expect(h).toContain("心跳")
    expect(h).toContain("不主动跑")
  })

  test("enabled=false 时完全不注入", () => {
    expect(eigenfluxHint("查最新的行业动态", { enabled: false })).toBe("")
  })

  test("多场景命中合并为一段", () => {
    const h = eigenfluxHint("查最新动态后广播给 agent")
    expect(h).toContain("只读")
    expect(h).toContain("授权")
  })
})
