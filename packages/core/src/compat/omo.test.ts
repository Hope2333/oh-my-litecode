import { describe, expect, test } from "bun:test"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { loadOmoCompat, mapOmoConfig } from "./omo.ts"

describe("mapOmoConfig", () => {
  test("翻译模型绑定与 fallback，保留未内置的 agent 名并给出警告", () => {
    const r = mapOmoConfig({
      $schema: "x",
      agents: {
        sisyphus: { model: "opencode/big-pickle", fallback_models: ["anthropic/x"] },
        hephaestus: { model: "vendor/legacy" },
        oracle: { disabled: true },
        atlas: {},
      },
      categories: { "deep-low": { model: "vendor/cat", fallback_models: ["vendor/cat2"] }, broken: {} },
      tmux: { enabled: true },
    })
    expect(r.config.agents?.["sisyphus"]).toEqual({ model: "opencode/big-pickle", fallback: ["anthropic/x"] })
    expect(r.config.agents?.["hephaestus"]).toEqual({ model: "vendor/legacy" })
    expect(r.config.agents?.["oracle"]).toEqual({ disabled: true })
    expect(r.config.agents?.["atlas"]).toBeUndefined() // 空对象无信息，不落表
    expect(r.config.categories?.["deep-low"]).toEqual({ model: "vendor/cat", fallback: ["vendor/cat2"] })
    expect(r.config.categories?.["broken"]).toBeUndefined()
    expect(r.ignoredKeys).toContain("tmux")
    expect(r.warnings.join("\n")).toContain("hephaestus")
  })

  test("顶层不是对象时不抛错，只告警", () => {
    const r = mapOmoConfig([1, 2, 3])
    expect(r.config).toEqual({})
    expect(r.warnings.length).toBe(1)
  })
})

describe("loadOmoCompat", () => {
  test("支持带注释与尾逗号的 jsonc", async () => {
    const dir = await mkdtemp(join(tmpdir(), "omo-compat-"))
    const file = join(dir, "oh-my-openagent.json")
    await writeFile(
      file,
      `{
        // 用户注释
        "agents": { "sisyphus": { "model": "a/b" } },
        "categories": { "quick": { "model": "c/d" } },
      }`,
      "utf8",
    )
    try {
      const r = await loadOmoCompat([file])
      expect(r.found).toBe(true)
      expect(r.path).toBe(file)
      expect(r.agents).toBe(1)
      expect(r.categories).toBe(1)
      expect(r.config.agents?.["sisyphus"]?.model).toBe("a/b")
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("文件不存在时安静返回 found=false", async () => {
    const r = await loadOmoCompat(["/nonexistent/omo.json"])
    expect(r.found).toBe(false)
    expect(r.config).toEqual({})
  })
})
