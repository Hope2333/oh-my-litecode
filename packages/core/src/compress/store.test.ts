/**
 * 主动上下文裁剪测试：KEEP 展开 / REF 紧凑引用 / 缺失 KEEP 拒绝 / 短摘要拒绝 /
 * 块列表排序 / decompress 回溯 / 节省统计。打 store 层，不启动宿主。
 */
import { describe, test, expect } from "bun:test"
import {
  compressRange,
  decompressSource,
  listBlocks,
  missingKeeps,
  renderBlock,
  renderSummary,
  totalSavedTokens,
  emptyCompressStore,
  type CompressStore,
} from "./store.ts"

describe("主动上下文裁剪", () => {
  test("compressRange 登记块，KEEP 缺失时拒绝", () => {
    const s: CompressStore = emptyCompressStore()
    // KEEP 引用未提供原文 → 拒绝
    const bad = compressRange(s, {
      from: "m1",
      to: "m3",
      summary: "这段讨论了认证流程的设计 [[KEEP:m2]]",
      sources: {},
      savedTokens: 500,
    })
    expect(bad.ok).toBe(false)
    if (bad.ok) return
    expect(bad.reason).toContain("未提供")

    // 提供原文 → 通过
    const good = compressRange(s, {
      from: "m1",
      to: "m3",
      summary: "这段讨论了认证流程 [[KEEP:m2]]",
      sources: { m2: "auth.ts:347 const token = sign(payload)" },
      savedTokens: 500,
    })
    expect(good.ok).toBe(true)
    if (!good.ok) return
    expect(good.block.id).toBe("b1")
    expect(good.block.savedTokens).toBe(500)
  })

  test("短摘要被拒绝", () => {
    const r = compressRange(emptyCompressStore(), {
      from: "m1",
      to: "m2",
      summary: "太短",
      sources: {},
      savedTokens: 10,
    })
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.reason).toContain("过短")
  })

  test("renderSummary 展开 KEEP、压缩 REF", () => {
    const sources = { m5: "model.py:45 kv = load()" }
    const out = renderSummary("见 [[KEEP:m5]] 和 [[REF:m9|早前结论]]", sources)
    expect(out).toContain("[[KEEP:m5]]")
    expect(out).toContain("model.py:45 kv = load()")
    expect(out).toContain("[→ m9: 早前结论]")
    // 未知 KEEP 降级为 REF，不丢标记
    const out2 = renderSummary("[[KEEP:mX]]", {})
    expect(out2).toContain("[→ mX: 原文缺失]")
  })

  test("missingKeeps 列出缺失 id", () => {
    const missing = missingKeeps("[[KEEP:a]] [[KEEP:b]] [[REF:c]]", { a: "x" })
    expect(missing).toEqual(["b"])
  })

  test("listBlocks 按 id 序，decompress 回溯原文", () => {
    let s: CompressStore = emptyCompressStore()
    const items = [
      { id: "m1", key: "m1", src: "src1.ts:1 line" },
      { id: "m2", key: "m2", src: "src2.ts:1 line" },
      { id: "m3", key: "m3", src: "src3.ts:1 line" },
    ]
    for (const it of items) {
      const r = compressRange(s, {
        from: it.id,
        to: it.id,
        summary: `讨论了模块 ${it.id} 的取舍与结论，含关键行`,
        sources: { [it.key]: it.src },
        savedTokens: 100,
      })
      if (r.ok) s = r.store
    }
    const blocks = listBlocks(s)
    expect(blocks.map((b) => b.id)).toEqual(["b1", "b2", "b3"])
    const first = blocks[0]
    expect(first).toBeDefined()
    expect(decompressSource(first!, "m1")).toBe("src1.ts:1 line")
    expect(decompressSource(first!, "nope")).toBeUndefined()
  })

  test("renderBlock 带头部与节省统计；totalSavedTokens 累加", () => {
    const r = compressRange(emptyCompressStore(), {
      from: "m1",
      to: "m4",
      summary: "这四条消息的核心是：先跑测试再改代码，避免返工",
      sources: { m1: "x" },
      savedTokens: 320,
    })
    expect(r.ok).toBe(true)
    if (!r.ok) return
    const text = renderBlock(r.block)
    expect(text).toContain("压缩块 b1")
    expect(text).toContain("m1–m4")
    expect(text).toContain("320 tok")
    expect(totalSavedTokens(r.store)).toBe(320)
  })
})
