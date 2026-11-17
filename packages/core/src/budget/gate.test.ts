import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { mkdtemp, readFile, chmod, mkdir } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { gate } from "./gate.ts"
import type { SystemPrompt, Section } from "../contract.ts"

function prompt(sections: Section[]): SystemPrompt {
  return { sections }
}

describe("gate", () => {
  let dir: string
  let logPath: string

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "budget-gate-"))
    logPath = join(dir, "sub", "budget.log")
  })

  test("pass 不写盘，written=false", async () => {
    const p = prompt([{ id: "tools", text: "abcd", items: 1 }])
    const r = await gate(p, { limit: 100, logPath })
    expect(r.report.budget.status).toBe("pass")
    expect(r.written).toBe(false)
    await expect(readFile(logPath, "utf8")).rejects.toBeTruthy()
  })

  test("truncated 写盘且文件含时间戳与警告", async () => {
    const p = prompt([
      { id: "tools", text: "abcd", items: 1 },
      { id: "memory", text: "一二三四五六七八九十", items: 3 },
    ])
    const r = await gate(p, { limit: 5, logPath })
    expect(r.report.budget.status).toBe("truncated")
    expect(r.written).toBe(true)
    const text = await readFile(logPath, "utf8")
    // ISO 时间戳形如 2026-11-13T...
    expect(text).toMatch(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    expect(text).toContain("[budget] 段 memory 被截断")
  })

  test("logPath 指向不可写路径时不抛异常且 written=false", async () => {
    const locked = join(dir, "locked")
    await mkdir(locked, { recursive: true })
    await chmod(locked, 0o500) // 只读
    const target = join(locked, "budget.log")
    const p = prompt([
      { id: "tools", text: "abcd", items: 1 },
      { id: "memory", text: "一二三四五六七八九十", items: 3 },
    ])
    const r = await gate(p, { limit: 5, logPath: target })
    expect(r.written).toBe(false)
    expect(r.report.budget.status).toBe("truncated")
  })

  afterEach(async () => {
    // 尽力恢复权限，便于 tmpdir 清理
    try {
      await chmod(join(dir, "locked"), 0o700)
    } catch {
      /* 忽略 */
    }
  })
})
