import { describe, expect, test } from "bun:test"
import { DEFAULT_CONFIG, parseConfig, parseConfigText, resolveConfig } from "./index.ts"

describe("parseConfig", () => {
  test("空/非法根返回空配置并告警", () => {
    expect(parseConfig(undefined)).toEqual({ config: {}, warnings: [] })
    const bad = parseConfig([1, 2])
    expect(bad.config).toEqual({})
    expect(bad.warnings[0]).toContain("必须是对象")
  })

  test("未知键只告警，不丢弃已知键", () => {
    const { config, warnings } = parseConfig({ budget: { limit: 4096 }, team_mode: true })
    expect(config.budget).toEqual({ limit: 4096 })
    expect(warnings.some((w) => w.includes('"team_mode"'))).toBe(true)
  })

  test("数字旋钮必须为正数，否则忽略并告警", () => {
    const { config, warnings } = parseConfig({ tasks: { concurrency: 0, maxDepth: 3, ttlMs: -1 } })
    expect(config.tasks).toEqual({ maxDepth: 3 })
    expect(warnings.filter((w) => w.includes("必须是正数")).length).toBe(2)
  })

  test("字符串数组逐项过滤非字符串", () => {
    const { config } = parseConfig({ disabled_skills: ["a", 1, null, "b"] })
    expect(config.disabled_skills).toEqual(["a", "b"])
  })

  test("telemetry=true 被拒绝（A7）", () => {
    const { config, warnings } = parseConfig({ telemetry: true })
    expect(config.telemetry).toBeUndefined()
    expect(warnings.join()).toContain("不收集任何遥测")
  })
})

describe("parseConfig：models 与 compat 两个键真实落地（回归：曾静默丢弃）", () => {
  test("models 与 compat 被赋值而非 undefined", () => {
    const r = parseConfig({
      models: { model: "bailing/Ling-3.0-flash", fallback: ["agnes/agnes-3.0-flash"] },
      compat: { taskAlias: true, skillTool: true, nativeSkills: false },
    })
    expect(r.warnings).toEqual([])
    expect(r.config.models).toEqual({ model: "bailing/Ling-3.0-flash", fallback: ["agnes/agnes-3.0-flash"] })
    expect(r.config.compat).toEqual({ taskAlias: true, skillTool: true, nativeSkills: false })
  })

  test("models.model / compat.* 形状错误只告警，不误吞其余字段", () => {
    const r = parseConfig({ models: { model: 1, temperature: 0.5 }, compat: { taskAlias: "yes" } })
    expect(r.warnings).toEqual(["models.model 必须是字符串（provider/model）", "compat.taskAlias 必须是布尔值"])
    expect(r.config.models?.temperature).toBe(0.5)
    expect(r.config.compat).toEqual({})
  })
})

describe("permissions 与 language 两个新键", () => {
  test("permissions 布尔落地，language 非空串落地", () => {
    const r = parseConfig({ permissions: false, language: "en" })
    expect(r.warnings).toEqual([])
    expect(r.config.permissions).toBe(false)
    expect(r.config.language).toBe("en")
  })

  test("形状错误只告警（language 检查先于 permissions）", () => {
    const r = parseConfig({ permissions: "all", language: "" })
    expect(r.warnings).toEqual([
      'language 必须是非空字符串（如 "zh" / "en"，省略默认 "zh"）',
      "permissions 必须是布尔值（true=主代理全放行，false=每次询问）",
    ])
  })
})

describe("parseConfigText", () => {
  test("坏 JSON 不抛错，返回告警", () => {
    const r = parseConfigText("{oops")
    expect(r.config).toEqual({})
    expect(r.warnings[0]).toContain("不是合法 JSON")
  })

  test("合法 JSON 走同一套解析", () => {
    const r = parseConfigText('{"skills":{"maxIndex":12}}')
    expect(r.config.skills).toEqual({ maxIndex: 12 })
  })
})

describe("resolveConfig", () => {
  test("缺失项补默认值，telemetry 恒 false", () => {
    const c = resolveConfig({ budget: { limit: 2048 } })
    expect(c.budget).toEqual({ limit: 2048 })
    expect(c.skills).toEqual(DEFAULT_CONFIG.skills)
    expect(c.tasks).toEqual(DEFAULT_CONFIG.tasks)
    expect(c.telemetry).toBe(false)
  })

  test("不修改入参", () => {
    const partial = { skills: { maxIndex: 5 } }
    resolveConfig(partial)
    expect(partial.skills).toEqual({ maxIndex: 5 })
  })
})
