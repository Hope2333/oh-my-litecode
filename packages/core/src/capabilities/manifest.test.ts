import { describe, expect, test } from "bun:test"
import { buildCapabilityManifest, CAPABILITIES } from "./manifest.ts"

describe("CAPABILITIES", () => {
  test("至少 7 条且 id 唯一", () => {
    expect(CAPABILITIES.length).toBeGreaterThanOrEqual(7)
    const ids = CAPABILITIES.map((c) => c.id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  test("覆盖全部关键能力", () => {
    const ids = CAPABILITIES.map((c) => c.id)
    for (const id of ["context7", "eigenflux", "vision", "team", "pa", "compress", "skill"]) {
      expect(ids).toContain(id)
    }
  })
})

describe("buildCapabilityManifest", () => {
  test("full 含标题、每条能力的场景与关键命令串", () => {
    const out = buildCapabilityManifest()
    expect(out).toContain("## 可用能力")
    for (const c of CAPABILITIES) expect(out).toContain(c.scene)
    for (const cmd of [
      "omo_admin action=mcp op=enable target=context7",
      "omo_mcp call",
      "omo_admin action=model op=set",
      "omo_task",
      "omo_channel",
      "omo_admin action=pa op=request",
      "omo_admin action=checkpoint",
      "skill(name)",
    ]) {
      expect(out).toContain(cmd)
    }
  })

  test("compact 更短，且仍保留调法命令", () => {
    const full = buildCapabilityManifest({ mode: "full" })
    const compact = buildCapabilityManifest({ mode: "compact" })
    expect(compact.length).toBeLessThan(full.length)
    expect(compact).toContain("skill(name)")
    expect(compact).toContain("- context7 →")
    const c7 = CAPABILITIES.find((c) => c.id === "context7")
    expect(compact).not.toContain(c7?.scene ?? "")
  })

  test("disabled 按 id 过滤，不误伤其他条目", () => {
    const out = buildCapabilityManifest({ disabled: ["context7", "eigenflux"] })
    for (const id of ["context7", "eigenflux"]) {
      const c = CAPABILITIES.find((x) => x.id === id)
      expect(out).not.toContain(`- ${c?.scene ?? ""}`)
    }
    const skill = CAPABILITIES.find((c) => c.id === "skill")
    expect(out).toContain(`- ${skill?.scene ?? ""}`)
  })

  test("全部 disabled 时只剩标题", () => {
    const out = buildCapabilityManifest({ disabled: CAPABILITIES.map((c) => c.id) })
    expect(out).toBe("## 可用能力（按需启用，默认不启用以省 token）\n")
  })

  test("纯函数：不改 CAPABILITIES 常量", () => {
    const before = JSON.stringify(CAPABILITIES)
    buildCapabilityManifest({ mode: "compact", disabled: ["pa"] })
    expect(JSON.stringify(CAPABILITIES)).toBe(before)
  })

  test("同一输入两次结果一致", () => {
    const a = buildCapabilityManifest({ mode: "compact", disabled: ["team"] })
    const b = buildCapabilityManifest({ mode: "compact", disabled: ["team"] })
    expect(a).toBe(b)
  })
})
