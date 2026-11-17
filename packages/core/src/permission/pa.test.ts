import { describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  loadPa,
  savePa,
  isHighValue,
  needsJustification,
  submitPa,
  resolvePa,
  expirePa,
  pendingPa,
  isAuthorized,
  HIGH_VALUE_CACHE_READ_TOKENS,
  HIGH_VALUE_TURNS,
  PA_TTL_MS,
  type PaQueue,
} from "./pa.ts"

const NOW = 1_700_000_000_000

describe("isHighValue 高价值判定", () => {
  test("Read 100M tok+ 判高价值", () => {
    expect(isHighValue({ cacheReadTokens: HIGH_VALUE_CACHE_READ_TOKENS })).toBe(true)
    expect(isHighValue({ cacheReadTokens: HIGH_VALUE_CACHE_READ_TOKENS - 1 })).toBe(false)
  })
  test("Turn 16+ 判高价值", () => {
    expect(isHighValue({ turns: HIGH_VALUE_TURNS })).toBe(true)
    expect(isHighValue({ turns: HIGH_VALUE_TURNS - 1 })).toBe(false)
  })
  test("无数据不判高价值", () => {
    expect(isHighValue({})).toBe(false)
  })
})

describe("needsJustification 强制说明", () => {
  test("高价值且归属不明 → 必须说明", () => {
    expect(needsJustification("unknown", true)).toBe(true)
    expect(needsJustification("human", true)).toBe(true)
  })
  test("oml 自创即使高价值也不强制；非高价值不强制", () => {
    expect(needsJustification("oml", true)).toBe(false)
    expect(needsJustification("unknown", false)).toBe(false)
  })
})

describe("PA 队列状态机", () => {
  const input = (over: Record<string, unknown> = {}) => ({
    id: "pa1",
    sessionId: "ses_human",
    sessionTitle: "重要总会话",
    operation: "delete" as const,
    owner: "unknown" as const,
    reason: "这是旧会话已无用",
    value: { cacheReadTokens: 1_100_000_000, turns: 20 },
    ...over,
  })

  test("高价值未明归属无说明 → 拒绝提交", () => {
    const r = submitPa({}, input({ reason: "" }), NOW)
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.error).toContain("必须说明")
  })

  test("带说明 → 提交成功，状态 pending", () => {
    const r = submitPa({}, input(), NOW)
    expect(r.ok).toBe(true)
    if (r.ok) {
      expect(r.request.status).toBe("pending")
      expect(r.request.highValue).toBe(true)
      expect(r.queue["pa1"]?.reason).toBe("这是旧会话已无用")
    }
  })

  test("oml 自创会话提交被拒（不该进 PA）", () => {
    const r = submitPa({}, input({ owner: "oml" }), NOW)
    expect(r.ok).toBe(false)
  })

  test("非高价值未明归属无需说明也可提交", () => {
    const r = submitPa({}, input({ value: {}, reason: "" }), NOW)
    expect(r.ok).toBe(true)
  })

  test("approve/deny 流转，重复裁决无效", () => {
    const r = submitPa({}, input(), NOW)
    if (!r.ok) throw new Error("submit failed")
    let q: PaQueue = r.queue
    q = resolvePa(q, "pa1", "approved", NOW + 1)
    expect(q["pa1"]?.status).toBe("approved")
    expect(q["pa1"]?.resolvedAt).toBe(NOW + 1)
    // 已裁决后再 deny 不变
    expect(resolvePa(q, "pa1", "denied", NOW + 2)).toBe(q)
    expect(isAuthorized(q, "ses_human", "delete")).toBe(true)
    expect(isAuthorized(q, "ses_human", "write")).toBe(false)
  })

  test("过期清理：pending 超过 TTL → expired", () => {
    const r = submitPa({}, input(), NOW)
    if (!r.ok) throw new Error("submit failed")
    expect(expirePa(r.queue, NOW + PA_TTL_MS - 1)).toBe(r.queue) // 未过期原样
    const expired = expirePa(r.queue, NOW + PA_TTL_MS + 1)
    expect(expired["pa1"]?.status).toBe("expired")
  })

  test("pendingPa 只列待批", () => {
    const r = submitPa({}, input(), NOW)
    if (!r.ok) throw new Error("submit failed")
    expect(pendingPa(r.queue).length).toBe(1)
    const resolved = resolvePa(r.queue, "pa1", "approved", NOW + 1)
    expect(pendingPa(resolved).length).toBe(0)
  })

  test("save/load 往返一致", async () => {
    const dir = await mkdtemp(join(tmpdir(), "oml-pa-"))
    const file = join(dir, "pa.json")
    try {
      const r = submitPa({}, input(), NOW)
      if (!r.ok) throw new Error("submit failed")
      await savePa(r.queue, file)
      expect(await loadPa(file)).toEqual(r.queue)
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })
})
