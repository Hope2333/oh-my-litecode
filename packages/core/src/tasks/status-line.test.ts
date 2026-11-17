import { describe, expect, test } from "bun:test"
import { commandHead, compactTok, formatStatusLine } from "./status-line.ts"

describe("compactTok", () => {
  test("量级格式", () => {
    expect(compactTok(undefined)).toBe("—")
    expect(compactTok(999)).toBe("999")
    expect(compactTok(1500)).toBe("1.5K")
    expect(compactTok(2_400_000)).toBe("2.4M")
  })
})

describe("commandHead", () => {
  test("取第一行并截断", () => {
    expect(commandHead("cd /x && grep a\nb")).toBe("cd /x && grep a")
    expect(commandHead("a".repeat(100))).toHaveLength(61)
  })
})

describe("formatStatusLine：用户样例对照", () => {
  test("正常态：标题行 + 工具/命令头/次数/新增/累计", () => {
    const out = formatStatusLine({
      agent: "Sisyphus-Junior 任务",
      id: "t11",
      name: "批量编辑与父/子范围",
      toolUses: 6,
      newTokens: 1520,
      cumTokens: 43_200,
      tool: "Bash",
      commandHead: "cd /home/miao/Projects/NekoOLMR && grep -n toolbar webui/app.css",
    })
    expect(out).toContain("Sisyphus-Junior 任务 t11 批量编辑与父/子范围")
    expect(out).toContain("↳ Bash cd /home/miao/Projects/NekoOLMR && grep -n toolbar webui/app.css ×6 ↓1.5K ✏43.2K")
  })

  test("出错态：失败码 + 倒计时占位", () => {
    const out = formatStatusLine({
      id: "t12",
      tool: "Bash",
      commandHead: "npm test",
      error: { code: "429", countdown: 30 },
    })
    expect(out).toContain("✗429 重试30s")
  })

  test("出错无倒计时（OML 插件层拿不到宿主定时器，只给码）", () => {
    const out = formatStatusLine({ id: "t13", error: { code: "502" } })
    expect(out).toContain("✗502")
    expect(out).not.toContain("重试")
  })
})
