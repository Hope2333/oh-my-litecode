// omo zhengfeng —— 整风报告（公理 A6：继续革命；报告不是建议而是待执行队列）。
// 消灭的矛盾：无度量、无整风 → 无法阻止注入量回涨。
import {
  buildIndex,
  defaultSkillRoots,
  loadUsage,
  scanSkills,
  SKILL_INDEX_TOP,
  HOOK_BUDGET,
} from "@oml/core"
import { mkdir, writeFile } from "node:fs/promises"
import { statePath } from "@oml/core"
import { dirname } from "node:path"
import { measureReport } from "./measure.ts"
import { readStructure } from "./audit.ts"

/** BUDGET.md 上限（A8）。 */
const MCP_BUDGET = 3
const PLUGIN_BUDGET = 5

/** 解析 zhengfeng 参数并生成整风报告 markdown。返回退出码。 */
export async function runZhengfeng(args: string[]): Promise<number> {
  let out: string | undefined
  for (let i = 0; i < args.length; i++) {
    const a = args[i]
    if (a === "--out") {
      out = args[++i]
      if (out === undefined) {
        console.error("omo zhengfeng: --out 需要一个路径")
        return 2
      }
    } else if (typeof a === "string" && a.startsWith("--out=")) {
      out = a.slice("--out=".length)
    } else {
      console.error(`omo zhengfeng: 未知参数 ${String(a)}`)
      return 2
    }
  }

  const today = todayStr()
  const target = out ?? statePath("zhengfeng", `${today}.md`)

  // 1. 当日注入量
  let measureBlock: string
  let totalTokens = 0
  let overBudget = false
  try {
    const report = await measureReport()
    totalTokens = report.totalTokens
    overBudget = report.budget.status === "fail"
    const lines = report.sections.map(
      (s) => `| ${s.id} | ${s.tokens} | ${s.items} | ${s.truncated ? "是" : "否"} |`,
    )
    measureBlock = [
      `合计 **${report.totalTokens} tok** / 上限 ${report.budget.limit} tok — 状态 **${report.budget.status}**`,
      "",
      "| 段 | tokens | items | 截断 |",
      "|---|---|---|---|",
      ...lines,
    ].join("\n")
  } catch (err) {
    measureBlock = `> 度量失败：${err instanceof Error ? err.message : String(err)}`
  }

  // 2. top-40 索引 + 零命中清单
  let indexBlock: string
  let zeroHit: string[] = []
  let indexCount = 0
  try {
    const skills = await scanSkills(defaultSkillRoots())
    const usage = await loadUsage()
    const indexText = buildIndex(skills, usage)
    indexCount = skills.length
    indexBlock = `\`\`\`\n${indexText || "(索引为空)"}\n\`\`\``
    // 零命中 = 扫描到但 usage 无记录
    zeroHit = skills.map((s) => s.name).filter((n) => !(n in usage))
  } catch (err) {
    indexBlock = `> 索引生成失败：${err instanceof Error ? err.message : String(err)}`
  }

  // 3. 结构超限项
  const snap = await readStructure()
  const overItems: string[] = []
  if (snap.hooks > HOOK_BUDGET) overItems.push(`Hook ${snap.hooks} > 上限 ${HOOK_BUDGET}`)
  if (snap.mcp > MCP_BUDGET) overItems.push(`常驻 MCP ${snap.mcp} > 上限 ${MCP_BUDGET}`)
  if (snap.plugins > PLUGIN_BUDGET) overItems.push(`插件 ${snap.plugins} > 上限 ${PLUGIN_BUDGET}`)
  const structureBlock =
    overItems.length === 0
      ? "全部达标 ✅"
      : overItems.map((s) => `- ${s}`).join("\n")

  // 4. 建议删除队列（每条一行，可直接勾选）
  const queue: string[] = []
  for (const n of zeroHit) queue.push(`- [ ] 删除或归档零命中技能 \`${n}\``)
  if (snap.hooks > HOOK_BUDGET) {
    queue.push(`- [ ] 精简 Hook 至 ≤${HOOK_BUDGET}（当前 ${snap.hooks}）`)
  }
  if (snap.mcp > MCP_BUDGET) {
    queue.push(`- [ ] 常驻 MCP 降为按项目 opt-in 至 ≤${MCP_BUDGET}（当前 ${snap.mcp}）`)
  }
  if (snap.plugins > PLUGIN_BUDGET) {
    queue.push(`- [ ] 禁用多余插件至 ≤${PLUGIN_BUDGET}（当前 ${snap.plugins}）`)
  }
  if (overBudget) {
    queue.push(`- [ ] 系统提示超预算（${totalTokens} tok），按优先级裁剪 memory/skillIndex`)
  }
  const queueBlock = queue.length === 0 ? "- [ ] 暂无待执行项" : queue.join("\n")

  const md = `# 整风报告 · ${today}

> 公理 A6（继续革命）：报告不是建议，而是**待执行队列**。

## 1. 当日注入量

${measureBlock}

## 2. top-${SKILL_INDEX_TOP} 技能索引（共扫描 ${indexCount} 个）

${indexBlock}

## 3. 零命中技能清单（${zeroHit.length} 个）

${zeroHit.length === 0 ? "无" : zeroHit.map((n) => `- \`${n}\``).join("\n")}

## 4. 结构超限项（A8 精兵简政）

${structureBlock}

## 5. 建议删除队列

${queueBlock}
`

  try {
    await mkdir(dirname(target), { recursive: true })
    await writeFile(target, md, "utf8")
  } catch (err) {
    console.error(`omo zhengfeng: 写入失败 ${target}: ${err instanceof Error ? err.message : String(err)}`)
    return 1
  }

  console.log(target)
  return 0
}

/** 当日日期串 YYYY-MM-DD（本地时区）。 */
function todayStr(): string {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}
