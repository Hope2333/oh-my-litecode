/**
 * 工作记忆测试：增删查、去重、凭据脱敏、弱记忆衰减、注入渲染、空库不占 tok。
 * 不启动宿主进程，直接打 store 层；注入路径由 host.test 的 system.transform 覆盖。
 */
import { describe, test, expect } from "bun:test"
import {
  addMemory,
  forgetMemory,
  reinforceMemory,
  renderMemories,
  redact,
  topMemories,
  memoryScore,
  emptyMemoryStore,
  MEMORY_HARD_CAP,
  type MemoryStore,
} from "./store.ts"

describe("工作记忆", () => {
  test("记住、列出、忘掉一条", () => {
    let s: MemoryStore = emptyMemoryStore()
    const r = addMemory(s, "本项目用 bun 跑测试，不用 npm")
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.deduped).toBe(false)
    expect(r.entry.id).toBe("M1")
    s = r.store

    const top = topMemories(s)
    expect(top.length).toBe(1)
    expect(top[0]?.text).toContain("bun")

    expect(forgetMemory(s, "M1")).toBe(true)
    expect(forgetMemory(s, "M1")).toBe(false)
    expect(topMemories(s).length).toBe(0)
  })

  test("等价记忆去重并强化，不新增条目", () => {
    let s: MemoryStore = emptyMemoryStore()
    const a = addMemory(s, "部署前先跑 bun run check")
    s = a.ok ? a.store : s
    const b = addMemory(s, "  部署前先跑 bun run check  ")
    expect(b.ok).toBe(true)
    if (!b.ok) return
    expect(b.deduped).toBe(true)
    expect(b.entry.id).toBe("M1")
    expect(b.entry.hits).toBe(2)
    expect(Object.keys(b.store.memories).length).toBe(1)
  })

  test("凭据脱敏后再存储", () => {
    expect(redact("key 是 sk-live-abcdef1234567890")).toContain("<redacted-key>")
    expect(redact("联系 a@b.com")).toContain("<redacted-email>")
    const r = addMemory(emptyMemoryStore(), "令牌 sk-live-abcdef1234567890 要轮换")
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.entry.text).toContain("<redacted-key>")
    expect(r.entry.text).not.toContain("sk-live-abcdef1234567890")
  })

  test("拒绝过长记忆", () => {
    const r = addMemory(emptyMemoryStore(), "x".repeat(400))
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.reason).toContain("过长")
  })

  test("弱记忆衰减：久未强化的排到后面", () => {
    const now = Date.now()
    let s: MemoryStore = emptyMemoryStore()
    const a = addMemory(s, "第一条很常用", now - 10 * 86_400_000)
    s = a.ok ? a.store : s
    if (a.ok) reinforceMemory(s, a.entry.id, now - 1 * 86_400_000)
    const b = addMemory(s, "第二条很久没用", now - 90 * 86_400_000)
    s = b.ok ? b.store : s
    const ranked = topMemories(s, 10, now)
    expect(ranked[0]?.text).toContain("第一条")
  })

  test("空库渲染为空串，不占 tok", () => {
    expect(renderMemories(emptyMemoryStore())).toBe("")
  })

  test("注入渲染带 [M#] 引用", () => {
    const r = addMemory(emptyMemoryStore(), "本项目主分支叫 main")
    expect(r.ok).toBe(true)
    if (!r.ok) return
    const text = renderMemories(r.store)
    expect(text).toContain("## 持久记忆")
    expect(text).toContain("[M1]")
  })

  test("硬上限淘汰最弱", () => {
    let s: MemoryStore = emptyMemoryStore()
    const now = Date.now()
    for (let i = 0; i < MEMORY_HARD_CAP + 10; i++) {
      const r = addMemory(s, `记忆条目编号 ${i}，用于撑爆上限的填充内容`, now - i * 1000)
      if (r.ok) s = r.store
    }
    expect(Object.keys(s.memories).length).toBe(MEMORY_HARD_CAP)
  })

  test("memoryScore 随 hits 增长", () => {
    const now = Date.now()
    const r = addMemory(emptyMemoryStore(), "计分用条目")
    expect(r.ok).toBe(true)
    if (!r.ok) return
    const e = r.entry
    const before = memoryScore(e, now)
    reinforceMemory(r.store, e.id, now)
    expect(memoryScore(e, now)).toBeGreaterThan(before)
  })
})

describe("近重复判定", () => {
  test("同义改写合并为一条", () => {
    const now = Date.now()
    const a = addMemory(emptyMemoryStore(), "跑测试必须用 bun，不要用 node，因为本机 node 已损坏", now)
    expect(a.ok).toBe(true)
    if (!a.ok) return
    const b = addMemory(a.store, "本机 node 已损坏，所以跑测试必须用 bun，不要用 node", now)
    expect(b.ok).toBe(true)
    if (!b.ok) return
    expect(b.deduped).toBe(true)
    expect(Object.keys(b.store.memories).length).toBe(1)
  })

  test("数字不同不合并", () => {
    const now = Date.now()
    const a = addMemory(emptyMemoryStore(), "端口 8080 已被网关占用，不要重复监听这个端口", now)
    expect(a.ok).toBe(true)
    if (!a.ok) return
    const b = addMemory(a.store, "端口 8081 已被网关占用，不要重复监听这个端口", now)
    expect(b.ok).toBe(true)
    if (!b.ok) return
    expect(b.deduped).toBe(false)
    expect(Object.keys(b.store.memories).length).toBe(2)
  })

  test("注入受 token 预算约束", () => {
    let s: MemoryStore = emptyMemoryStore()
    const now = Date.now()
    for (let i = 0; i < 30; i++) {
      const r = addMemory(s, `第 ${i} 条互不相同的经验：关于构建、部署、测试、回滚与监控的具体结论`, now - i * 1000)
      if (r.ok) s = r.store
    }
    const text = renderMemories(s, 12, now, 80)
    const lines = text.split("\n").filter((l) => l.startsWith("- "))
    expect(lines.length).toBeGreaterThan(0)
    expect(lines.length).toBeLessThan(12)
  })

  test("半衰期按 90 天衰减", () => {
    const now = Date.now()
    const old = { id: "M1", text: "旧条目", createdAt: 0, lastUsedAt: now - 180 * 86_400_000, hits: 10, kind: "fact" as const }
    const fresh = { id: "M2", text: "新条目", createdAt: 0, lastUsedAt: now, hits: 10, kind: "fact" as const }
    const ratio = memoryScore(fresh, now) / memoryScore(old, now)
    expect(ratio).toBeGreaterThan(1.9)
    expect(ratio).toBeLessThan(2.1)
  })
})
