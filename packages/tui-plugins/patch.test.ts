import { describe, expect, test } from "bun:test"
import { readFileSync } from "node:fs"
import { join } from "node:path"
import {
  patchMagazine,
  patchVisualCache,
  verifyPatch,
  PATCH_META,
} from "./patch.ts"

const MAG_SRC = readFileSync(join(import.meta.dir, "subagent-magazine/bundle/tui.js"), "utf8")
const VC_SRC = readFileSync(join(import.meta.dir, "visual-cache/bundle/tui.js"), "utf8")

describe("magazine 补丁", () => {
  test("前缀隔离 + 设置迁移 + 版本标记均落地", () => {
    const { src, changes } = patchMagazine(MAG_SRC)
    expect(changes["mag.prefixDecl"]).toBe(1)
    expect(changes["mag.migration"]).toBe(1)
    expect(changes["mag.versionToast"]).toBe(1)
    expect(src).toContain('var KV_PREFIX = "oml_subagent_magazine";')
    expect(src).toContain("__omlLegacyPrefix")
    expect(src).toContain("OML fork · subagent-magazine")
  })

  test("绝不迁 session_data：迁移块里无 session_data 字样", () => {
    const { src } = patchMagazine(MAG_SRC)
    // 迁移块设置清单不含 session_data
    expect(src).toContain('["lang", "max_entries", "order", "scroll_mode", "open", "ttl_days"]')
    const block = src.slice(src.indexOf("__omlSettings"), src.indexOf("__omlSettings") + 400)
    expect(block).not.toContain("session_data")
  })

  test("slot id / clearedIds / session_data 读写均保留", () => {
    const { src } = patchMagazine(MAG_SRC)
    expect(src).toContain('id: "opencode-subagent-magazine"')
    expect(src).toContain("clearedIds")
    expect(src).toContain(".session_data")
    expect(verifyPatch("magazine", src).ok).toBe(true)
  })

  test("幂等：二次补丁不再注入迁移块", () => {
    const once = patchMagazine(MAG_SRC).src
    const twice = patchMagazine(once)
    expect(twice.changes["mag.prefixDecl"]).toBe(0)
    expect(twice.changes["mag.migration"]).toBe(0)
    expect(twice.src).toBe(once)
  })

  test("补丁后整段 bundle 语法仍合法（注入块无语法错误）", () => {
    for (const src of [patchMagazine(MAG_SRC).src, patchVisualCache(VC_SRC).src]) {
      // transformSync 语法错会抛；返回 string（部分版本）或 {code}（另一版本）都接受
      const out = new Bun.Transpiler({ loader: "js" }).transformSync(src) as unknown
      const code = typeof out === "string" ? out : (out as { code: string }).code
      expect(code.length).toBeGreaterThan(0)
    }
  })
})

describe("visual-cache 补丁", () => {
  test("3 处前缀 + 1 处 session key 全替换", () => {
    const { src, changes } = patchVisualCache(VC_SRC)
    expect(changes["vc.prefixDecl"]).toBe(3)
    expect(changes["vc.sessionKey"]).toBe(1)
    expect(src).not.toContain('const KV_PREFIX = "cache_panel";')
    expect(src).not.toContain('"cache_panel.session"')
    expect(src).toContain('const KV_PREFIX = "oml_cache_panel";')
  })

  test("slot id 保留 + verify 通过 + 幂等", () => {
    const once = patchVisualCache(VC_SRC).src
    expect(once).toContain('id: "opencode-visual-cache"')
    expect(verifyPatch("visual-cache", once).ok).toBe(true)
    const twice = patchVisualCache(once)
    expect(twice.changes["vc.prefixDecl"]).toBe(0)
    expect(twice.src).toBe(once)
  })
})

describe("元信息", () => {
  test("版本与包名对齐运行版本", () => {
    expect(PATCH_META.magazine.upstreamVersion).toBe("1.5.2")
    expect(PATCH_META["visual-cache"].upstreamVersion).toBe("1.6.2")
  })
})
