import { describe, expect, test } from "bun:test"
import { BUILTIN_MCP_DEFS, builtinMcpDefs, normalizeContext7ApiKey } from "./builtins.ts"

describe("normalizeContext7ApiKey", () => {
  test("真 key（含首尾空白）返回去空白值", () => {
    expect(normalizeContext7ApiKey("sk-context7-real-123")).toBe("sk-context7-real-123")
    expect(normalizeContext7ApiKey("  sk-abc  ")).toBe("sk-abc")
  })

  test("未传 / 空串 / 全空白 → null", () => {
    expect(normalizeContext7ApiKey()).toBe(null)
    expect(normalizeContext7ApiKey("")).toBe(null)
    expect(normalizeContext7ApiKey("   ")).toBe(null)
  })

  test("占位串 → null（大小写不敏感）", () => {
    expect(normalizeContext7ApiKey("your api key")).toBe(null)
    expect(normalizeContext7ApiKey("Your API Key")).toBe(null)
    expect(normalizeContext7ApiKey("your-api-key")).toBe(null)
    expect(normalizeContext7ApiKey("changeme")).toBe(null)
  })

  test("引号 / 尖括号包裹的占位 → null", () => {
    expect(normalizeContext7ApiKey('"your api key"')).toBe(null)
    expect(normalizeContext7ApiKey("'your-api-key'")).toBe(null)
    expect(normalizeContext7ApiKey("<your-api-key>")).toBe(null)
    expect(normalizeContext7ApiKey("<>")).toBe(null)
  })

  test("引号包裹的真 key → 去引号后的值", () => {
    expect(normalizeContext7ApiKey('"sk-real-key"')).toBe("sk-real-key")
  })
})

describe("BUILTIN_MCP_DEFS", () => {
  test("context7 是 remote / 官方端点 / 默认禁用", () => {
    const def = BUILTIN_MCP_DEFS["context7"]
    expect(def).toBeDefined()
    expect(def!.type).toBe("remote")
    expect(def!.url).toBe("https://mcp.context7.com/mcp")
    expect(def!.enabled).toBe(false)
  })

  test("常量里没有硬编码 key（无 headers）", () => {
    expect(BUILTIN_MCP_DEFS["context7"]!.headers).toBeUndefined()
    expect(JSON.stringify(BUILTIN_MCP_DEFS)).not.toContain("Bearer")
    expect(JSON.stringify(BUILTIN_MCP_DEFS)).not.toContain("Authorization")
  })
})

describe("builtinMcpDefs", () => {
  test("无 key：返回默认禁用且无 headers 的 def", () => {
    const defs = builtinMcpDefs({})
    expect(defs["context7"]!.enabled).toBe(false)
    expect(defs["context7"]!.headers).toBeUndefined()
  })

  test("有 key：注入 Bearer header", () => {
    const defs = builtinMcpDefs({ CONTEXT7_API_KEY: "sk-real-123" })
    expect(defs["context7"]!.headers).toEqual({ Authorization: "Bearer sk-real-123" })
    expect(defs["context7"]!.enabled).toBe(false)
  })

  test("占位 key 不当成真 key", () => {
    const defs = builtinMcpDefs({ CONTEXT7_API_KEY: "<your-api-key>" })
    expect(defs["context7"]!.headers).toBeUndefined()
  })

  test("不修改常量：调用后 BUILTIN_MCP_DEFS 仍无 headers", () => {
    builtinMcpDefs({ CONTEXT7_API_KEY: "sk-real-123" })
    expect(BUILTIN_MCP_DEFS["context7"]!.headers).toBeUndefined()
    const other = builtinMcpDefs({})
    expect(other["context7"]!.headers).toBeUndefined()
  })
})
