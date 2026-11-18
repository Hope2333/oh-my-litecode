import { describe, expect, test } from "bun:test"
import {
  NULL_SENTINEL,
  UNDEF_SENTINEL,
  checkBudget,
  foldRecords,
  foldSavings,
  normalizeValue,
  redactSecrets,
  restoreSecrets,
  unfoldRecords,
  type FoldedTable,
} from "./fold.ts"

/** 与 unfoldRecords 对齐的期望值：列并集（首次出现序）+ 每值归一化 + 缺字段补哨兵。 */
function expected(records: readonly Record<string, unknown>[]): Record<string, string>[] {
  const columns: string[] = []
  for (const rec of records) for (const k of Object.keys(rec)) if (!columns.includes(k)) columns.push(k)
  return records.map((rec) => {
    const out: Record<string, string> = {}
    for (const col of columns) out[col] = normalizeValue(rec[col])
    return out
  })
}

describe("foldRecords / unfoldRecords —— 100% 无损往返", () => {
  test("空数组 -> 空折叠 -> 空还原", () => {
    const folded = foldRecords([])
    expect(folded.version).toBe(1)
    expect(folded.columns).toEqual([])
    expect(folded.rows).toEqual([])
    expect(unfoldRecords(folded)).toEqual([])
  })

  test("单列 + 全重复：字典只有 1 个值，行全是 0", () => {
    const rs = [{ role: "admin" }, { role: "admin" }, { role: "admin" }]
    const folded = foldRecords(rs)
    expect(folded.columns).toEqual(["role"])
    expect(folded.dict["role"]).toEqual(["admin"])
    expect(folded.rows).toEqual([[0], [0], [0]])
    expect(folded.counts?.["role"]).toEqual([3])
    expect(unfoldRecords(folded)).toEqual(expected(rs))
  })

  test("含 null / undefined / 空串 / 缺字段：哨兵互不混淆", () => {
    const rs: Record<string, unknown>[] = [
      { a: null, b: "", c: undefined },
      { a: "", b: null },
      { c: "x" },
    ]
    const folded = foldRecords(rs)
    const out = unfoldRecords(folded)
    expect(out).toEqual(expected(rs))
    expect(out[0]?.["a"]).toBe(NULL_SENTINEL)
    expect(out[0]?.["b"]).toBe("")
    expect(out[0]?.["c"]).toBe(UNDEF_SENTINEL)
    expect(out[1]?.["a"]).toBe("")
    expect(out[1]?.["b"]).toBe(NULL_SENTINEL)
    expect(out[2]?.["a"]).toBe(UNDEF_SENTINEL)
    // 三种值两两不同
    expect(new Set([out[0]?.["a"], out[0]?.["b"], out[0]?.["c"]]).size).toBe(3)
  })

  test("真实字符串与哨兵同形 -> 转义后往返仍一致", () => {
    const rs = [{ v: NULL_SENTINEL }, { v: UNDEF_SENTINEL }, { v: "\u0000ESC:tail" }, { v: null }]
    const folded = foldRecords(rs)
    expect(unfoldRecords(folded)).toEqual(expected(rs))
    // 转义后与真哨兵不同
    expect(folded.dict["v"]?.[0]).not.toBe(NULL_SENTINEL)
    expect(folded.dict["v"]).toHaveLength(4)
  })

  test("emoji / CJK / 数字 / 布尔混合往返一致", () => {
    const rs: Record<string, unknown>[] = [
      { 城市: "上海", emoji: "🚀🌟", n: 42, ok: true },
      { 城市: "北京", emoji: "🚀🌟", n: 0, ok: false },
    ]
    expect(unfoldRecords(foldRecords(rs))).toEqual(expected(rs))
  })

  test("纯函数：不修改入参，多次调用结果一致", () => {
    const rs = [{ a: 1, b: "x" }, { a: 1, b: "y" }]
    const snapshot = JSON.stringify(rs)
    const f1 = foldRecords(rs)
    const f2 = foldRecords(rs)
    expect(JSON.stringify(rs)).toBe(snapshot)
    expect(f1).toEqual(f2)
  })

  test("列并集顺序稳定，缺字段按并集补齐", () => {
    const rs = [{ b: 2 }, { a: 1, c: 3 }]
    const folded = foldRecords(rs)
    expect(folded.columns).toEqual(["b", "a", "c"])
    const out = unfoldRecords(folded)
    expect(out[0]).toEqual({ b: "2", a: UNDEF_SENTINEL, c: UNDEF_SENTINEL })
    expect(out[1]).toEqual({ b: UNDEF_SENTINEL, a: "1", c: "3" })
  })
})

describe("foldSavings —— 具体数字", () => {
  test("30 条高重复记录 savings > 50%", () => {
    const rs = Array.from({ length: 30 }, (_, i) => ({
      id: `item-${1000 + (i % 3)}`,
      region: "cn-east-1",
      role: i % 2 === 0 ? "admin" : "user",
      status: "active",
      plan: "pro",
      lang: "zh-CN",
      tz: "Asia/Shanghai",
      flag: true,
    }))
    const folded = foldRecords(rs)
    const s = foldSavings(rs, folded)
    expect(s.before).toBeGreaterThan(s.after)
    expect(s.savedPct).toBeGreaterThan(50)
    expect(s.before - s.after).toBeGreaterThan(0)
    // savedPct 保留 1 位小数
    expect(s.savedPct).toBe(Math.round(s.savedPct * 10) / 10)
  })

  test("空数组 savings 为 0，不除零", () => {
    const s = foldSavings([], foldRecords([]))
    expect(s).toEqual({ before: 0, after: 0, savedPct: 0 })
  })
})

describe("checkBudget —— 放行 / 拒收 + 明细小票", () => {
  test("未超预算 -> ok=true，小票含 before/cap/PASS", () => {
    const r = checkBudget(120, 8192)
    expect(r.ok).toBe(true)
    expect(r.receipt).toContain("PASS")
    expect(r.receipt).toContain("120")
    expect(r.receipt).toContain("8192")
    expect(r.receipt).toContain("放行")
  })

  test("超预算 -> ok=false，小票含 REJECT/拒收/超出额度", () => {
    const r = checkBudget(9000, 8192)
    expect(r.ok).toBe(false)
    expect(r.receipt).toContain("REJECT")
    expect(r.receipt).toContain("超额拒收")
    expect(r.receipt).toContain("9000")
    expect(r.receipt).toContain("8192")
    expect(r.receipt).toContain("超出 808")
  })

  test("恰好等于 cap 算放行", () => {
    expect(checkBudget(100, 100).ok).toBe(true)
  })
})

describe("redactSecrets —— 本地打码 + 本地复原", () => {
  test("多种密钥形态一次打码，vault 原文可本地精确复原", () => {
    const text =
      "key=sk-abcdefghijklmnopqrstuvwx " +
      "AIzaSyD-1234567890abcdefghij " +
      "ghp_abcdefghijklmnopqrstuvwxyz0123456789 " +
      "Authorization: Bearer abcdefghijklmnopqrstuvwxyz " +
      "password=hunter2secret"
    const { masked, vault } = redactSecrets(text)
    expect(masked).not.toContain("sk-abcdefghijklmnopqrstuvwx")
    expect(masked).not.toContain("AIzaSyD-1234567890abcdefghij")
    expect(masked).not.toContain("ghp_")
    expect(masked).not.toContain("abcdefghijklmnopqrstuvwxyz")
    expect(masked).toContain("⟦SECRET_1⟧")
    expect(Object.keys(vault).length).toBeGreaterThanOrEqual(5)
    expect(restoreSecrets(masked, vault)).toBe(text)
  })

  test("key= 只打码值，保留前缀；不打码非敏感文本", () => {
    const { masked, vault } = redactSecrets("hello world; api_key=sk-abcdefghijklmnopqrstuvwx; end")
    expect(masked).toContain("api_key=⟦SECRET_1⟧")
    expect(masked).toContain("hello world")
    expect(masked).toContain("end")
    expect(restoreSecrets(masked, vault)).toBe("hello world; api_key=sk-abcdefghijklmnopqrstuvwx; end")
  })

  test("无敏感信息：原文不变，vault 为空", () => {
    const { masked, vault } = redactSecrets("普通文本 no secrets here 123")
    expect(masked).toBe("普通文本 no secrets here 123")
    expect(vault).toEqual({})
  })
})

describe("FoldedTable 结构完整性", () => {
  test("字典值去重、列宽一致、counts 之和等于行数", () => {
    const rs: Record<string, unknown>[] = [
      { a: "x", b: null },
      { a: "x", b: "y" },
      { a: "z", b: "y", c: "extra" },
    ]
    const folded: FoldedTable = foldRecords(rs)
    expect(folded.version).toBe(1)
    // 每列字典内无重复值
    for (const col of folded.columns) {
      const d = folded.dict[col] as string[]
      expect(new Set(d).size).toBe(d.length)
      // 每行宽度 = 列数，索引落在字典范围内
      for (const row of folded.rows) {
        expect(row).toHaveLength(folded.columns.length)
        for (const idx of row) expect(idx).toBeGreaterThanOrEqual(0)
        for (const idx of row) expect(idx).toBeLessThan(d.length)
      }
      // 计数之和 = 行数
      expect((folded.counts?.[col] ?? []).reduce((s, n) => s + n, 0)).toBe(folded.rows.length)
    }
    expect(unfoldRecords(folded)).toEqual(expected(rs))
  })
})
