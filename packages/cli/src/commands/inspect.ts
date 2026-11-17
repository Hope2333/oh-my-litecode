// omo skills / tasks / config —— 只读检视命令。不写盘、不改配置。
import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import {
  defaultSkillRoots,
  loadTasks,
  loadUsage,
  parseConfigText,
  resolveConfig,
  scanSkills,
  selectSkills,
  type SkillUsageMap,
  type TaskRecord,
} from "@oml/core"

function pad(s: string, n: number): string {
  return s.length >= n ? s.slice(0, n) : s + " ".repeat(n - s.length)
}

export async function runSkills(argv: string[]): Promise<number> {
  const query = argv.filter((a) => !a.startsWith("-")).join(" ").trim()
  const limitArg = argv.find((a) => a.startsWith("--limit="))
  const limit = limitArg ? Number.parseInt(limitArg.slice(8), 10) : 12
  // 宿主注入 = [OC/omo/skills(插件内置), ...默认根]；CLI 必须同口径，
  // 否则 omo skills 检索不到插件自带的 neko-* / neko-eigenflux。
  const builtinRoot = join(import.meta.dir, "../../../../OC/omo/skills")
  const roots = [builtinRoot, ...defaultSkillRoots()]
  const skills = await scanSkills(roots)
  const usage: SkillUsageMap = await loadUsage()

  const picked =
    query === ""
      ? [...skills].sort((a, b) => (usage[b.name]?.hits ?? 0) - (usage[a.name]?.hits ?? 0)).slice(0, limit)
      : selectSkills(skills, query, { top: limit, usage })

  console.log(`技能根 ${roots.length} 个；命中 ${skills.length} 个；${query === "" ? "按使用频次" : `按查询「${query}」`}取前 ${picked.length}\n`)
  console.log(`${pad("name", 34)} ${pad("hits", 5)} trigger`)
  for (const s of picked) {
    console.log(`${pad(s.name, 34)} ${pad(String(usage[s.name]?.hits ?? 0), 5)} ${s.description.replace(/\s+/g, " ").slice(0, 70)}`)
  }
  return 0
}

export async function runTasks(argv: string[]): Promise<number> {
  const all = argv.includes("--all")
  const store = await loadTasks()
  const list: TaskRecord[] = Object.values(store.tasks).filter((t) => all || (t.status !== "done" && t.status !== "failed" && t.status !== "cancelled"))
  if (list.length === 0) {
    console.log(all ? "任务账本为空。" : "没有未终结任务（加 --all 看全部）。")
    return 0
  }
  console.log(`${pad("id", 5)} ${pad("status", 9)} ${pad("cat", 20)} ${pad("depth", 5)} description`)
  for (const t of list) {
    console.log(`${pad(t.id, 5)} ${pad(t.status, 9)} ${pad(t.category, 20)} ${pad(String(t.depth), 5)} ${t.description.slice(0, 60)}`)
  }
  return 0
}

export async function runConfig(argv: string[]): Promise<number> {
  const cwd = argv.find((a) => !a.startsWith("-")) ?? process.cwd()
  const candidates = [join(cwd, "oml.json"), join(homedir(), ".config/opencode/oml.json")]
  for (const p of candidates) {
    try {
      const text = await readFile(p, "utf8")
      const parsed = parseConfigText(text)
      console.log(`来源: ${p}`)
      for (const w of parsed.warnings) console.log(`警告: ${w}`)
      console.log(JSON.stringify(resolveConfig(parsed.config), null, 2))
      return 0
    } catch {
      continue
    }
  }
  const parsed = parseConfigText("{}")
  console.log("来源: (builtin)")
  console.log(JSON.stringify(resolveConfig(parsed.config), null, 2))
  return 0
}
