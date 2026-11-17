// omo stop / handoff —— 收束与交接
// 消灭的矛盾：C5「任务派出去收不回来」与「换会话即失忆」。
import { mkdir, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import {
  isTerminal,
  loadTasks,
  pruneTerminal,
  runningCount,
  saveTasks,
  readSources,
  scanSlop,
  summarizeSlop,
  statePath,
  tasksPath,
  transition,
  type TaskRecord,
} from "@oml/core"
import { clearGoal, loadGoal, saveGoal } from "@oml/core"
import { measureReport } from "./measure.ts"

/** 把所有未终结任务置为 cancelled（不删账本）。 */
export async function runStop(args: string[]): Promise<number> {
  const store = await loadTasks()
  let next = store
  let stopped = 0
  for (const t of Object.values(store.tasks)) {
    if (isTerminal(t.status)) continue
    const res = transition(next, t.id, "cancelled", { now: Date.now(), error: "omo stop：用户中止" })
    if (res.ok) {
      next = res.store
      stopped++
    }
  }
  if (stopped > 0) await saveTasks(next)
  const pruned = pruneTerminal(next, 200)
  if (pruned !== next) await saveTasks(pruned)
  if (args.includes("--json")) {
    console.log(JSON.stringify({ stopped, running: runningCount(pruned) }, null, 2))
    return 0
  }
  console.log(stopped === 0 ? "没有未终结的任务。" : `已中止 ${stopped} 个任务；账本仍保留（omo tasks --all 可查）。`)
  return 0
}

function line(t: TaskRecord): string {
  const brief = t.description.length > 70 ? `${t.description.slice(0, 70)}…` : t.description
  return `- \`${t.id}\` [${t.status}] ${t.category}｜${brief}${t.error ? `｜错误：${t.error}` : ""}`
}

/** 生成交接文档：结论化、带路径、≤80 行。 */
export async function runHandoff(args: string[]): Promise<number> {
  const print = args.includes("--print")
  const store = await loadTasks()
  const report = await measureReport()
  const live = Object.values(store.tasks).filter((t) => !isTerminal(t.status))
  const done = Object.values(store.tasks)
    .filter((t) => t.status === "done")
    .slice(-8)

  const body = [
    `# 交接 ${new Date().toISOString().slice(0, 16).replace("T", " ")}`,
    "",
    "## 当前注入预算",
    `- OML 自身 ${report.totalTokens}/${report.budget.limit} tok（${report.budget.status}）`,
    `- 分段：${report.sections.map((s) => `${s.id}=${s.tokens}`).join(" / ")}`,
    "",
    "## 未终结任务",
    live.length === 0 ? "- 无" : live.map(line).join("\n"),
    "",
    "## 最近完成（末 8 条）",
    done.length === 0 ? "- 无" : done.map(line).join("\n"),
    "",
    "## 恢复入口",
    `- 任务账本：\`${tasksPath()}\``,
    "- 下一步：按未终结任务的 description 继续；续接用 `omo_task(taskId=<id>)`",
    "- 复核：`bun run check`（7 道门）",
    "",
    "## 未验证项",
    "- [未验证] 交接文档由账本自动生成，人工待补：目标、约束、失败记录",
  ].join("\n")

  if (print) {
    console.log(body)
    return 0
  }
  const stamp = new Date().toISOString().slice(0, 16).replace(/[-:]/g, "").replace("T", "-")
  const target = statePath("handoff", `${stamp}.md`)
  await mkdir(dirname(target), { recursive: true })
  await writeFile(target, `${body}\n`, "utf8")
  console.log(`已写入 ${target}`)
  console.log("提示：目标 / 约束 / 失败记录需人工补充——自动生成的部分只有账本事实。")
  return 0
}

/** omo goal [set <文本> | show | clear] —— 目标账本的命令行入口。 */
export async function runGoal(args: string[]): Promise<number> {
  const sub = args[0] ?? "show"
  if (sub === "show") {
    const goal = await loadGoal()
    if (goal === null) {
      console.log("当前没有目标。用 `omo goal set <文本>` 设定。")
      return 0
    }
    console.log(goal.text)
    console.log(`\n（更新于 ${new Date(goal.updatedAt).toISOString()}）`)
    return 0
  }
  if (sub === "clear") {
    console.log((await clearGoal()) ? "目标已清除" : "当前没有目标")
    return 0
  }
  if (sub === "set") {
    const text = args.slice(1).join(" ").trim()
    if (text === "") {
      console.error("用法：omo goal set <文本>")
      return 1
    }
    const goal = await saveGoal(text)
    console.log(`目标已设为：${goal.text}`)
    return 0
  }
  console.error(`未知子命令：${sub}（可用 set / show / clear）`)
  return 1
}

/**
 * omo slop [目录] —— 反 slop 扫描。
 *
 * 只报告，不改写：自动「优化」注释会制造新的 slop，而且改错时代价更高。
 */
export async function runSlop(argv: readonly string[]): Promise<number> {
  const root = argv.find((a) => !a.startsWith("-")) ?? "."
  const files = await readSources(root)
  if (files.length === 0) {
    console.log(`在 ${root} 下没找到可扫描的源码`)
    return 1
  }
  const findings = scanSlop(files)
  if (findings.length === 0) {
    console.log(`扫描 ${files.length} 个文件：未发现 slop`)
    return 0
  }
  console.log(`扫描 ${files.length} 个文件：${summarizeSlop(findings)}`)
  for (const f of findings.slice(0, 60)) {
    console.log(`  ${f.path}:${f.line} [${f.rule}] ${f.evidence}`)
  }
  if (findings.length > 60) console.log(`  …还有 ${findings.length - 60} 处`)
  return 0
}
