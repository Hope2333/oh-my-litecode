// omo audit —— 结构与技能审计（公理 A6：整风可解释，A8：精兵简政）
// 消灭的矛盾：C2「Hook 官僚化」+ C1「技能通胀」——把超限项与零命中项摊在阳光下。
import {
  buildIndexLines,
  defaultSkillRoots,
  demoted,
  loadUsage,
  scanSkills,
  HOOK_BUDGET,
} from "@oml/core"
import { readdir, readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

/** BUDGET.md 的结构上限（A8）。MCP / 插件上限取自 BUDGET.md 表格。 */
const MCP_BUDGET = 3
const PLUGIN_BUDGET = 5

/** ANSI 红（不引入依赖）；非 TTY 时由调用方决定，这里始终加前缀 "!!" 保证可读。 */
const RED = "\x1b[31m"
const RESET = "\x1b[0m"

/** 结构计数快照，供 audit 与 zhengfeng 共用。 */
export interface StructureSnapshot {
  hooks: number
  mcp: number
  plugins: number
  /** 各项是否存在（缺失时计数为 0 并标注） */
  hooksDirExists: boolean
  configExists: boolean
}

/** 读取结构计数：hook 目录数 + opencode.json 的 mcp/plugin 数。任何缺失都优雅降级。 */
export async function readStructure(): Promise<StructureSnapshot> {
  const home = homedir()
  const hooksDir = join(
    home,
    ".cache",
    "opencode",
    "packages",
    "oh-my-openagent@5.1.43",
    "node_modules",
    "oh-my-openagent",
    "dist",
    "hooks",
  )
  const configPath = join(home, ".config", "opencode", "opencode.json")

  let hooks = 0
  let hooksDirExists = false
  try {
    const entries = await readdir(hooksDir, { withFileTypes: true })
    hooks = entries.filter((e) => e.isDirectory()).length
    hooksDirExists = true
  } catch {
    hooks = 0
    hooksDirExists = false
  }

  let mcp = 0
  let plugins = 0
  let configExists = false
  try {
    const raw = await readFile(configPath, "utf8")
    const parsed: unknown = JSON.parse(raw)
    mcp = countField(parsed, "mcp")
    plugins = countField(parsed, "plugin")
    configExists = true
  } catch {
    mcp = 0
    plugins = 0
    configExists = false
  }

  return { hooks, mcp, plugins, hooksDirExists, configExists }
}

/** 从已解析的 opencode.json 里取某字段的“数量”：数组取长度，对象取键数，缺失取 0。 */
function countField(parsed: unknown, key: string): number {
  if (typeof parsed !== "object" || parsed === null) return 0
  const rec = parsed as Record<string, unknown>
  const v = rec[key]
  if (Array.isArray(v)) return v.length
  if (typeof v === "object" && v !== null) return Object.keys(v).length
  return 0
}

/** 对单项做超限判定，返回带颜色的行。 */
function verdictLine(label: string, current: number, limit: number, note: string): string {
  const over = current > limit
  const prefix = over ? `${RED}!!${RESET} ` : "   "
  const status = over ? "超限" : "正常"
  const body = `${prefix}${label}: ${current} / 上限 ${limit}  [${status}]  ${note}`
  return over ? body : body
}

/** 解析 audit 参数并执行。默认 = --skills --structure。 */
export async function runAudit(args: string[]): Promise<number> {
  let doSkills = false
  let doStructure = false
  for (const a of args) {
    if (a === "--skills") doSkills = true
    else if (a === "--structure") doStructure = true
    else {
      console.error(`omo audit: 未知参数 ${String(a)}`)
      return 2
    }
  }
  // 无参数 = 全开
  if (!doSkills && !doStructure) {
    doSkills = true
    doStructure = true
  }

  if (doSkills) {
    try {
      await auditSkills()
    } catch (err) {
      console.error(`omo audit --skills: 失败: ${err instanceof Error ? err.message : String(err)}`)
      return 1
    }
  }

  if (doStructure) {
    await auditStructure()
  }

  return 0
}

/** 技能三张表：索引内 / 已降级 / 从未命中。 */
async function auditSkills(): Promise<void> {
  const skills = await scanSkills(defaultSkillRoots())
  const usage = await loadUsage()

  // 索引内 = buildIndexLines 的结果名
  const indexed = buildIndexLines(skills, usage)
  // 已降级 = demoted()
  const demotedList = demoted(usage)
  // 从未命中 = 扫描到但 usage 无记录
  const indexedSet = new Set(indexed)
  const neverHit = skills.map((s) => s.name).filter((n) => !(n in usage))

  console.log("═".repeat(60))
  console.log(`技能审计 · 共扫描 ${skills.length} 个`)
  console.log("═".repeat(60))

  console.log(`\n【索引内】(${indexed.length} 条，进入 top-${40} 注入)`)
  console.log("─".repeat(60))
  if (indexed.length === 0) console.log("  (空)")
  for (const n of indexed) console.log(`  ${n}`)

  console.log(`\n【已降级】(${demotedList.length} 个，连续未命中已移出索引)`)
  console.log("─".repeat(60))
  if (demotedList.length === 0) console.log("  (无)")
  for (const n of demotedList) console.log(`  ${n}`)

  console.log(`\n【从未命中】(${neverHit.length} 个，usage 无记录)`)
  console.log("─".repeat(60))
  if (neverHit.length === 0) console.log("  (无)")
  for (const n of neverHit) console.log(`  ${n}`)

  // 防止 indexedSet 未使用告警（用于交叉校验数量一致性）
  void indexedSet
}

/** 结构审计：hook / MCP / 插件 三项与 BUDGET.md 上限对比，超限标红。 */
async function auditStructure(): Promise<void> {
  const snap = await readStructure()
  console.log("\n" + "═".repeat(60))
  console.log("结构审计（A8 精兵简政）")
  console.log("═".repeat(60))
  console.log(
    verdictLine(
      "Hook 数",
      snap.hooks,
      HOOK_BUDGET,
      snap.hooksDirExists ? "oh-my-openagent dist/hooks 目录数" : "(hooks 目录不存在，计 0)",
    ),
  )
  console.log(
    verdictLine(
      "常驻 MCP",
      snap.mcp,
      MCP_BUDGET,
      snap.configExists ? "opencode.json 的 mcp 字段" : "(opencode.json 不存在，计 0)",
    ),
  )
  console.log(
    verdictLine(
      "启用插件",
      snap.plugins,
      PLUGIN_BUDGET,
      snap.configExists ? "opencode.json 的 plugin 字段" : "(opencode.json 不存在，计 0)",
    ),
  )
  console.log("说明: 「!!」前缀 = 超限，须先删后加（A8）")
}
