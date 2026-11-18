/**
 * 单条工具返回分块压缩测试：chunkText 边界 / foldToolResult 分块+锚点+seq 递增 /
 * expandAnchor 取回原文 / renderToolResultRef 格式。断言 100% 还原。
 */
import { describe, test, expect } from "bun:test"
import {
  chunkText,
  foldToolResult,
  expandAnchor,
  renderToolResultRef,
  DEFAULT_CHUNK_CHARS,
} from "./tool-result.ts"
import { emptyCompressStore } from "./store.ts"
import type { CompressStore } from "./store.ts"

/** 不变式：各块拼接 == 原文，且每块不超上限。 */
function assertLosslessSplit(chunks: string[], text: string, maxChars: number): void {
  expect(chunks.join("")).toBe(text)
  for (const c of chunks) expect(c.length).toBeLessThanOrEqual(Math.max(1, Math.floor(maxChars)))
}

describe("chunkText 切块边界", () => {
  test("空文本返回 []", () => {
    expect(chunkText("", 10)).toEqual([])
  })

  test("短文本原样单块", () => {
    expect(chunkText("abc", 10)).toEqual(["abc"])
    expect(chunkText("abcde", 5)).toEqual(["abcde"])
  })

  test("超长无边界词硬切且 100% 还原", () => {
    const text = "a".repeat(25)
    const chunks = chunkText(text, 10)
    expect(chunks.length).toBe(3)
    assertLosslessSplit(chunks, text, 10)
  })

  test("换行边界收尾且 100% 还原", () => {
    const text = "line one\nline two\nline three\nline four"
    const chunks = chunkText(text, 12)
    expect(chunks.length).toBeGreaterThan(1)
    // 除末块外，优先在换行处收尾。
    for (const c of chunks.slice(0, -1)) expect(c.endsWith("\n")).toBe(true)
    assertLosslessSplit(chunks, text, 12)
  })

  test("句子边界收尾且 100% 还原", () => {
    const text = "第一句话。第二句话。第三句话。第四句话。"
    const chunks = chunkText(text, 8)
    expect(chunks.length).toBeGreaterThan(1)
    assertLosslessSplit(chunks, text, 8)
  })

  test("maxChars<1 不卡死、仍还原", () => {
    assertLosslessSplit(chunkText("abcd", 0), "abcd", 0)
  })
})

describe("foldToolResult 分块登记", () => {
  test("分块 → 锚点 → store.seq 递增，from/to=toolId，source key 规整", () => {
    let store: CompressStore = emptyCompressStore()
    const text = "甲".repeat(10) + "\n" + "乙".repeat(10) + "\n" + "丙".repeat(10)
    const r = foldToolResult(store, { toolId: "search", text, maxChars: 12, now: 1000 })
    expect(r.anchors).toEqual(["@b1", "@b2", "@b3"])
    expect(r.store.seq).toBe(3)
    store = r.store
    const b1 = store.blocks["b1"]
    expect(b1).toBeDefined()
    expect(b1!.from).toBe("search")
    expect(b1!.to).toBe("search")
    expect(b1!.createdAt).toBe(1000)
    expect(Object.keys(b1!.sources)).toEqual(["search#0"])
    expect(b1!.savedTokens).toBeGreaterThan(0)
  })

  test("同一 store 再折叠，块 id 顺延不冲突", () => {
    const first = foldToolResult(emptyCompressStore(), {
      toolId: "shell",
      text: "x".repeat(20),
      maxChars: 10,
    })
    expect(first.anchors).toEqual(["@b1", "@b2"])
    const second = foldToolResult(first.store, {
      toolId: "api",
      text: "y".repeat(15),
      maxChars: 10,
    })
    expect(second.anchors).toEqual(["@b3", "@b4"])
    expect(second.store.seq).toBe(4)
    expect(Object.keys(second.store.blocks)).toEqual(["b1", "b2", "b3", "b4"])
  })

  test("空文本不登记块", () => {
    const s = emptyCompressStore()
    const r = foldToolResult(s, { toolId: "empty", text: "" })
    expect(r.anchors).toEqual([])
    expect(r.store.seq).toBe(0)
    expect(r.store).toBe(s)
  })

  test("默认 maxChars 生效", () => {
    expect(DEFAULT_CHUNK_CHARS).toBeGreaterThan(0)
    const r = foldToolResult(emptyCompressStore(), { toolId: "big", text: "z".repeat(5000) })
    expect(r.anchors.length).toBeGreaterThan(1)
  })

  test("100% 还原：展开各锚点拼接 == 原文", () => {
    const text = "第一段内容概览\n细节行一\n细节行二。收尾。\n第二段内容概览\n更多细节……"
    const r = foldToolResult(emptyCompressStore(), { toolId: "doc", text, maxChars: 11 })
    const restored = r.anchors.map((a) => expandAnchor(r.store, a)).join("")
    expect(restored).toBe(text)
  })
})

describe("expandAnchor 取回原文", () => {
  test("锚点 / 裸块 id 都能取回单块原文，未知返回 undefined", () => {
    const text = "alpha\nbeta\ngamma"
    const r = foldToolResult(emptyCompressStore(), { toolId: "f", text, maxChars: 6 })
    const chunks = chunkText(text, 6)
    expect(expandAnchor(r.store, r.anchors[0]!)).toBe(chunks[0])
    expect(expandAnchor(r.store, "b1")).toBe(chunks[0])
    expect(expandAnchor(r.store, "@b999")).toBeUndefined()
    expect(expandAnchor(r.store, "not-an-anchor")).toBeUndefined()
  })
})

describe("renderToolResultRef 格式", () => {
  test("紧凑一行 + 展开提示", () => {
    const out = renderToolResultRef(["@b1", "@b2"])
    expect(out).toContain("@b1 @b2")
    expect(out).toContain("展开")
    expect(out).toContain("decompress bN")
  })

  test("空锚点返回空串", () => {
    expect(renderToolResultRef([])).toBe("")
  })
})
