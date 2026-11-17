// omo settings / omo upgrade —— OML settings 面板 与 3rd systems 升级
// 消灭的矛盾：「OML 的行为（语言/权限/预算/自动升级…）只能靠翻文档改 JSON」——
// settings 给一个完整面板（现值/来源/缺省），upgrade 给 3rd systems
// 的查/升一条命令。
import { readFile } from "node:fs/promises"
import { spawn, spawnSync } from "node:child_process"
import { homedir } from "node:os"
import { join, resolve } from "node:path"
import {
  parseConfigText,
  resolveConfig,
  runThirdUpgrade,
  CONFIG_FILENAME,
  type OmlConfig,
} from "@oml/core"

const GREEN = "\x1b[32m"
const YELLOW = "\x1b[33m"
const DIM = "\x1b[2m"
const RESET = "\x1b[0m"

const CONFIG_PATHS = [
  join(process.cwd(), CONFIG_FILENAME),
  join(homedir(), ".config", "opencode", CONFIG_FILENAME),
]

async function findConfigFile(): Promise<{ path: string; text: string } | undefined> {
  for (const p of CONFIG_PATHS) {
    try {
      return { path: p, text: await readFile(p, "utf8") }
    } catch {
      // 找下一个
    }
  }
  return undefined
}

function hostLabel(): string {
  try {
    const r = spawnSync("opencode", ["--version"])
    const out = new TextDecoder().decode(r.stdout ?? Buffer.from("")).trim()
    return out === "" ? "opencode（版本未知）" : `opencode ${out}`
  } catch {
    return "opencode（二进制不在 PATH）"
  }
}

/** 面板：现值 / 来源（oml.json 里写了没）/ 缺省行为。 */
function settingsPanel(config: OmlConfig, raw: Record<string, unknown>): string[] {
  const set = (k: string) => raw[k] !== undefined
  const rows: string[] = []
  const row = (key: string, value: string, on: boolean, hint: string) => {
    rows.push(`  ${on ? `${GREEN}●${RESET}` : `${DIM}○${RESET}`} ${key.padEnd(22)} ${value} ${DIM}${on ? "" : "（缺省）"} ${hint}${RESET}`)
  }
  row("language", config.language ?? "zh", set("language"), "自产内容语言（宿主 TUI 无 i18n，OML 代管）")
  row("permissions", String(config.permissions !== false), set("permissions"), "true=主代理+子会话权限全放行；false=回宿主询问")
  row("worldview", config.worldview ?? "light", set("worldview"), "判断纪律层：off / light / full（默认 light，可关）")
  row("constraints", config.constraints ?? "light", set("constraints"), "工作纪律档位：light 五条 / standard 八条")
  row("budget.limit", String(config.budget?.limit ?? 8192), set("budget"), "空闲系统提示 token 上限")
  row("skills.maxIndex", String(config.skills?.maxIndex ?? 40), set("skills"), "技能索引条数（按任务相关性动态选）")
  row("tasks", `${config.tasks?.concurrency ?? 3} 并发 / 深度 ${config.tasks?.maxDepth ?? 2}`, set("tasks"), "任务网关并发与递归深度")
  row("agents / categories", `${Object.keys(config.agents ?? {}).length} / ${Object.keys(config.categories ?? {}).length} 条绑定`, set("agents") || set("categories"), "模型热分配（缺省=宿主默认）")
  row("teams", `${Object.keys(config.teams ?? {}).length} 个模板`, set("teams"), "团队特制（成员/模式/工具与 MCP 约束）")
  row("compat", JSON.stringify(config.compat ?? {}), set("compat"), "旧 OMO 兼容位（taskAlias/skillTool/nativeSkills）")
  row("third.autoUpgrade", String(config.third?.autoUpgrade !== false), set("third"), "3rd systems 自动装/升（默认开）")
  row("disabled_*", JSON.stringify(config.disabled_agents ?? []) + " " + JSON.stringify(config.disabled_skills ?? []), set("disabled_agents") || set("disabled_skills"), "点名停用")
  row("telemetry", "false（恒定）", false, "公理 A7：零遥测")
  return rows
}

/** omo settings —— OML settings（Neko Agent settings for <宿主 agent>）。 */
export async function runSettings(args: string[]): Promise<number> {
  const json = args.includes("--json")
  const found = await findConfigFile()
  const text = found?.text ?? "{}"
  const parsed = parseConfigText(text)
  const config = resolveConfig(parsed.config)

  if (json) {
    console.log(JSON.stringify({
      path: found?.path ?? "(未找到 oml.json，用内置默认)",
      config,
      warnings: parsed.warnings,
    }, null, 2))
    return 0
  }

  console.log(`${GREEN}OML settings${RESET} ${DIM}（Neko Agent settings for sisyphus @ ${hostLabel()}）${RESET}`)
  console.log(`配置源：${found?.path ?? "(未找到 oml.json —— 全部走内置默认；新建项目可在 .opencode/oml.json 或 ~/.config/opencode/oml.json 设)"}`)
  if (parsed.warnings.length > 0) {
    console.log(`${YELLOW}警告：${RESET}`)
    for (const w of parsed.warnings) console.log(`  - ${w}`)
  }
  for (const line of settingsPanel(config, rawOf(text))) console.log(line)
  console.log(`\n${DIM}改法：编辑 oml.json（20 键，解析器对未知键/错型只告警不炸）。改完 omo doctor 复核。${RESET}`)
  return 0
}

function rawOf(text: string): Record<string, unknown> {
  try {
    return JSON.parse(text) as Record<string, unknown>
  } catch {
    return {}
  }
}

async function hostPlugins(): Promise<string[]> {
  try {
    const text = await readFile(join(homedir(), ".config", "opencode", "opencode.json"), "utf8")
    const raw = JSON.parse(text) as { plugin?: unknown }
    const list = Array.isArray(raw.plugin) ? raw.plugin : []
    return list.filter((x): x is string => typeof x === "string")
  } catch {
    return []
  }
}

/** omo upgrade [3rd systems] —— 默认按 third.autoUpgrade（true）执行；--dry-run 只查不动。 */
export async function runUpgrade(args: string[]): Promise<number> {
  const dry = args.includes("--dry-run")
  const found = await findConfigFile()
  const config = found !== undefined ? resolveConfig(parseConfigText(found.text).config) : {}
  const auto = config.third?.autoUpgrade !== false
  const act = auto && !dry
  const out = await runThirdUpgrade({
    config,
    host: { name: "opencode" },
    currentPlugins: await hostPlugins(),
    spawn: act
      ? (cmd) => {
          const p = spawn(cmd[0] ?? "", cmd.slice(1), { stdio: "inherit" })
          p.on("error", (e) => console.warn(`[omo] ${cmd.join(" ")} 失败：${e.message}`))
        }
      : undefined,
  })
  for (const r of out.results) {
    const mark = r.acted ? `${GREEN}▲${RESET}` : r.upgradable || r.missing ? `${YELLOW}◆${RESET}` : "  "
    console.log(`${mark} ${r.system.padEnd(30)} installed=${r.installed ?? "?"} latest=${r.latest ?? "?"} ${r.missing ? "[缺失] " : ""}${r.upgradable ? "[可升] " : ""}${r.note}`)
  }
  if (dry) console.log(`\n${DIM}dry-run：只查不动。要真装/升：去掉 --dry-run（且 oml.json third.autoUpgrade=true，默认即开）。${RESET}`)
  return 0
}

/** 让 main.ts 复用；也供测试直接引。 */
export function settingsPaths(): string[] {
  return CONFIG_PATHS.map((p) => resolve(p))
}
