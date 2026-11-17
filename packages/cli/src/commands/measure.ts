// omo measure —— 度量空闲会话系统提示注入量（公理 A9：实践是检验真理的唯一标准）
// 消灭的矛盾：C1「注入量无因果」——没有度量就无法证明精简有效。
import {
  assemble,
  buildIndex,
  buildIndexLines,
  defaultSkillRoots,
  loadGoal,
  loadUsage,
  scanSkills,
  DEFAULT_BUDGET_TOKENS,
} from "@oml/core"
import type { BudgetReport, Section, SystemPrompt } from "@oml/core"
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

/** 读取 identity 段来源：~/.config/opencode/AGENTS.md，不存在则优雅降级为空段。 */
async function readIdentity(): Promise<{ text: string; items: number }> {
  const p = join(homedir(), ".config", "opencode", "AGENTS.md")
  try {
    const text = await readFile(p, "utf8")
    return { text, items: 1 }
  } catch {
    // 配置不存在不 crash，回退空段（硬要求：优雅降级）
    return { text: "", items: 0 }
  }
}

/** 构建 SystemPrompt{sections}：tools / identity / skillIndex / memory，顺序即 SECTION_PRIORITY。 */
export async function buildSystemPrompt(): Promise<SystemPrompt> {
  const sections: Section[] = []

  // tools：空段（当前 CLI 不注册工具）
  sections.push({ id: "tools", text: "", items: 0 })

  // identity：AGENTS.md 内容
  const identity = await readIdentity()
  sections.push({ id: "identity", text: identity.text, items: identity.items })

  // skillIndex：惰性索引（名字 + ≤40 字触发语），items = 索引条目数
  const skills = await scanSkills(defaultSkillRoots())
  const usage = await loadUsage()
  const indexText = buildIndex(skills, usage)
  const indexItems = buildIndexLines(skills, usage).length
  sections.push({ id: "skillIndex", text: indexText, items: indexItems })

  // memory：当前目标（若已设定）。与宿主同一来源，保证 CLI 度量与真机一致。
  const goal = await loadGoal()
  sections.push({
    id: "memory",
    text: goal === null ? "" : `## 当前目标\n${goal.text}`,
    items: goal === null ? 0 : 1,
  })

  return { sections }
}

/** 跑 assemble 得到结构化预算报告。limit 省略时用 DEFAULT_BUDGET_TOKENS。 */
export async function measureReport(limit?: number): Promise<BudgetReport> {
  const prompt = await buildSystemPrompt()
  const lim = typeof limit === "number" && Number.isFinite(limit) ? limit : DEFAULT_BUDGET_TOKENS
  // assemble 返回 { prompt, report }，CLI 只关心 report
  return assemble(prompt.sections, lim).report
}

/** 解析 measure 参数，执行并输出报告。返回退出码。 */
export async function runMeasure(args: string[]): Promise<number> {
  let json = false
  let limit: number | undefined
  for (let i = 0; i < args.length; i++) {
    const a = args[i]
    if (a === "--json") {
      json = true
    } else if (a === "--limit") {
      const raw = args[++i]
      const n = raw === undefined ? NaN : Number(raw)
      if (!Number.isFinite(n)) {
        console.error(`omo measure: --limit 需要一个数字，收到: ${String(raw)}`)
        return 2
      }
      limit = n
    } else if (typeof a === "string" && a.startsWith("--limit=")) {
      const n = Number(a.slice("--limit=".length))
      if (!Number.isFinite(n)) {
        console.error(`omo measure: --limit 需要一个数字，收到: ${a}`)
        return 2
      }
      limit = n
    } else {
      console.error(`omo measure: 未知参数 ${String(a)}`)
      return 2
    }
  }

  let report: BudgetReport
  try {
    report = await measureReport(limit)
  } catch (err) {
    // 底层 @oml/core 缺实现时：报告错误到 stderr，不静默吞错
    console.error(`omo measure: 构建报告失败: ${err instanceof Error ? err.message : String(err)}`)
    return 1
  }

  if (json) {
    // JSON 契约形状见设计文档 §7
    console.log(JSON.stringify(report, null, 2))
  } else {
    printHuman(report)
  }

  // 退出码：status === "fail" → 1，否则 0
  return report.budget.status === "fail" ? 1 : 0
}

/** 人类可读表格：每段 tokens / items / 占比 / 是否截断。 */
function printHuman(report: BudgetReport): void {
  const total = report.totalTokens
  console.log("omo measure — 空闲会话系统提示度量")
  console.log("─".repeat(56))
  console.log(
    padEnd("段", 12) + padEnd("tokens", 10) + padEnd("items", 8) + padEnd("占比", 10) + "截断",
  )
  console.log("─".repeat(56))
  for (const s of report.sections) {
    const pct = total > 0 ? `${((s.tokens / total) * 100).toFixed(1)}%` : "0.0%"
    console.log(
      padEnd(s.id, 12) +
        padEnd(String(s.tokens), 10) +
        padEnd(String(s.items), 8) +
        padEnd(pct, 10) +
        (s.truncated ? "是" : "否"),
    )
  }
  console.log("─".repeat(56))
  console.log(
    `合计 ${total} tok / 上限 ${report.budget.limit} tok / 状态 ${report.budget.status}`,
  )
  for (const w of report.warnings) {
    console.error(`警告: ${w}`)
  }
}

function padEnd(s: string, n: number): string {
  return s.length >= n ? s : s + " ".repeat(n - s.length)
}
