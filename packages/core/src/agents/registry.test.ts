import { describe, expect, test } from "bun:test"
import {
  AGENTS,
  AGENT_MAP,
  CATEGORIES,
  LEGACY_AGENT_ALIASES,
  agentExists,
  resolveModel,
} from "./registry.ts"
import { AGENT_IDS, CATEGORY_IDS } from "../config/index.ts"

describe("AGENTS", () => {
  test("恰好 6 个，id 与契约枚举一致且不重复", () => {
    expect(AGENTS.length).toBe(8)
    expect([...AGENTS.map((a) => a.id)].sort()).toEqual([...AGENT_IDS].sort())
    expect(new Set(AGENTS.map((a) => a.id)).size).toBe(8)
  })

  test("每个 agent 都写明它消灭的矛盾（公理 A5）", () => {
    for (const a of AGENTS) {
      expect(a.eliminates.trim().length).toBeGreaterThan(8)
      expect(a.purpose.trim().length).toBeGreaterThan(4)
    }
  })

  test("只读角色不含写工具", () => {
    for (const a of AGENTS.filter((x) => x.readonly)) {
      expect(a.tools).not.toBe("all")
      if (a.tools !== "all") expect(a.tools).not.toContain("edit")
    }
  })

  test("映射表覆盖全部 agent", () => {
    for (const id of AGENT_IDS) expect(AGENT_MAP.get(id)?.id).toBe(id)
  })
})

describe("CATEGORIES", () => {
  test("恰好 6 个且与契约枚举一致", () => {
    expect([...CATEGORIES.map((c) => c.id)].sort()).toEqual([...CATEGORY_IDS].sort())
  })

  test("没有 unspecified-* 这种语义空洞的类别", () => {
    for (const c of CATEGORIES) expect(c.id.startsWith("unspecified")).toBe(false)
  })
})

describe("LEGACY_AGENT_ALIASES", () => {
  test("全部指向真实存在的 OML agent", () => {
    for (const target of Object.values(LEGACY_AGENT_ALIASES)) expect(agentExists(target)).toBe(true)
  })
})

describe("resolveModel", () => {
  test("未配置时不内置任何模型 id，并给出可执行的提示", () => {
    const r = resolveModel("sisyphus-junior", "deep-low", {})
    expect(r.model).toBeNull()
    expect(r.chain).toEqual([])
    expect(r.source).toBe("none")
    expect(r.note).toContain("categories[\"deep-low\"].model")
  })

  test("agent 覆盖优先于 category", () => {
    const r = resolveModel("oracle", "ultrabrain", {
      agents: { oracle: { model: "p/a", fallback: ["p/b"] } },
      categories: { ultrabrain: { model: "p/c" } },
    })
    expect(r.model).toBe("p/a")
    expect(r.chain).toEqual(["p/a", "p/b"])
    expect(r.source).toBe("agent")
  })

  test("无 agent 覆盖时用 category，且只有一层回退", () => {
    const r = resolveModel("explore", "quick", {
      categories: { quick: { model: "p/q", fallback: ["p/r"] } },
    })
    expect(r.source).toBe("category")
    expect(r.chain).toEqual(["p/q", "p/r"])
  })

  test("空字符串视为未配置", () => {
    expect(resolveModel("explore", "quick", { agents: { explore: { model: "" } } }).source).toBe("none")
  })
})
