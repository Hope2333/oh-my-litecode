import { describe, expect, test } from "bun:test"
import { createBundle, mergeBundle, parseBundle, renderBundle } from "./bundle.ts"
import type { CompressBlock } from "../compress/store.ts"
import type { MemoryEntry } from "../memory/store.ts"

function block(id: string, summary: string): CompressBlock {
  return { id, from: "m1", to: "m9", summary, sources: {}, createdAt: 0, savedTokens: 100 }
}

function mem(id: string, text: string): MemoryEntry {
  return { id, text, kind: "antipattern", createdAt: 0, lastUsedAt: 0, hits: 3 }
}

describe("经验包", () => {
  test("往返：create → JSON → parse 不丢字段", () => {
    const b = createBundle({ from: "neko", blocks: [block("b1", "改配置后必须复跑门禁，否则漂移看不见")] })
    const back = parseBundle(JSON.stringify(b))
    expect(back.from).toBe("neko")
    expect(back.blocks).toHaveLength(1)
    expect(back.blocks[0]?.summary).toContain("复跑门禁")
  })

  test("校验严格：坏 format / 坏版本 / 非数组 全部整包拒绝", () => {
    expect(() => parseBundle("{}")).toThrow(/format/)
    expect(() => parseBundle(JSON.stringify({ format: "oml-experience", version: 2, from: "x", blocks: [], memories: [], skills: [] }))).toThrow(/版本/)
    expect(() => parseBundle(JSON.stringify({ format: "oml-experience", version: 1, from: "x", blocks: "no", memories: [], skills: [] }))).toThrow(/数组/)
    expect(() => parseBundle("not json")).toThrow(/JSON/)
  })

  test("合并不覆盖：同 id 不同摘要 → 保留本地并计 skipped", () => {
    const local = createBundle({ from: "a", blocks: [block("b1", "本地的结论，先记着别动")] })
    const remote = createBundle({ from: "b", blocks: [block("b1", "别人的结论，不能悄悄覆盖本地")] })
    const r = mergeBundle(local, remote)
    expect(r.stats.blocks).toBe(0)
    expect(r.stats.skipped).toBe(1)
    expect(r.bundle.blocks[0]?.summary).toContain("本地的结论")
  })

  test("记忆按相似度去重，导入条目换 X 前缀且 hits 归零", () => {
    const local = createBundle({ from: "a", memories: [mem("M1", "改完配置要复跑门禁否则漂移看不见")] })
    const dup = createBundle({ from: "b", memories: [mem("M1", "改完配置要复跑门禁否则漂移看不见")] })
    const fresh = createBundle({ from: "b", memories: [mem("M1", "宿主的技能目录会覆盖插件的索引，必须显式剥离")] })

    expect(mergeBundle(local, dup).stats.memories).toBe(0)
    const r = mergeBundle(local, fresh)
    expect(r.stats.memories).toBe(1)
    expect(r.bundle.memories[1]?.id).toBe("X1")
    expect(r.bundle.memories[1]?.hits).toBe(0)
  })

  test("渲染摘要包含条目数与首条内容", () => {
    const md = renderBundle(createBundle({ from: "neko", blocks: [block("b1", "一个可读的结论")] }))
    expect(md).toContain("# 经验包 neko")
    expect(md).toContain("压缩块 1")
    expect(md).toContain("一个可读的结论")
  })
})
