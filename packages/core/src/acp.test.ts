import { describe, expect, test } from "bun:test"
import { hasAcpPlugin, majorOf, pickAcp } from "./acp.ts"

describe("majorOf", () => {
  test("正常版本号取主版本", () => {
    expect(majorOf("1.19.3")).toBe(1)
    expect(majorOf("v2.0.0-rc")).toBe(2)
  })
  test("取不到返回 undefined，不抛错", () => {
    expect(majorOf(undefined)).toBeUndefined()
    expect(majorOf("dev")).toBeUndefined()
  })
})

describe("pickAcp：v1 硬带 opencode-acp，v2/dsh/未来走 billion-context", () => {
  test("OpenCode 1.x → opencode-acp", () => {
    const d = pickAcp({ name: "opencode", version: "1.19.5" })
    expect(d.plugin).toBe("opencode-acp")
    expect(d.reason).toContain("v1")
  })

  test("OpenCode 版本未知时保守按 v1 路由", () => {
    expect(pickAcp({ name: "opencode" }).plugin).toBe("opencode-acp")
  })

  test("OpenCode 2.x → billion-context", () => {
    expect(pickAcp({ name: "opencode", version: "2.0.0" }).plugin).toBe("billion-context")
  })

  test("dsh / dsh-codex / 未知宿主 → billion-context", () => {
    for (const name of ["dsh", "dsh-codex", "codex", "future-host"]) {
      expect(pickAcp({ name }).plugin).toBe("billion-context")
    }
  })
})

describe("hasAcpPlugin", () => {
  test("精确 / scope 前缀 / 裸名都能认出来", () => {
    expect(hasAcpPlugin(["opencode-acp"], "opencode-acp")).toBe(true)
    expect(hasAcpPlugin(["@foo/opencode-acp"], "opencode-acp")).toBe(true)
    expect(hasAcpPlugin(["opencode-notify"], "opencode-acp")).toBe(false)
  })
})
