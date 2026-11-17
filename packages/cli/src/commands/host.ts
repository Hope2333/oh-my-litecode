// omo doctor / install —— 宿主足迹诊断与接入
// 消灭的矛盾：C1「注入量无因果」的宿主侧延伸——OML 自己的注入只占小头，
// 大头在宿主（MCP 工具 schema、插件、原生技能目录）。不把大头量出来，
// 精简就永远只能在小头上打转（公理 A2：具体问题具体分析）。
import { readFile, writeFile, mkdir, stat } from "node:fs/promises"
import { homedir } from "node:os"
import { join, dirname } from "node:path"
import { defaultSkillRoots, scanSkills, hasAcpPlugin, pickAcp } from "@oml/core"
import { readStructure } from "./audit.ts"
import { measureReport } from "./measure.ts"

/**
 * 本机实测的宿主成本常数（2026-11-13，opencode 1.19.3，deepseek-v4.1-flash-free）：
 * 同一提示词、同一模型、逐个变量开关的差值。改环境后必须重测，不要当常量信。
 */
const MEASURED = {
  base: 7_811, // 干净 HOME + --pure：OpenCode 自身底噪
  externalSkills: 20_329, // OPENCODE_DISABLE_EXTERNAL_SKILLS=1 省下的
  claudeSkills: 2_657, // OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 省下的
  plugins: 18_800, // 18 个插件相对 --pure 的增量
  mcpThree: 9_581, // 保留的 3 个 MCP（blender/codegraph/unreal）8→3 的实测差值
  mcpFull: 27_000, // 8 个 MCP 全开的估算（干净 HOME 与真实 HOME 剩余差值）
} as const

const GREEN = "\x1b[32m"
const YELLOW = "\x1b[33m"
const RED = "\x1b[31m"
const DIM = "\x1b[2m"
const RESET = "\x1b[0m"

function mark(ok: boolean): string {
  return ok ? `${GREEN}OK${RESET}` : `${RED}!!${RESET}`
}

async function exists(p: string): Promise<boolean> {
  try {
    await stat(p)
    return true
  } catch {
    return false
  }
}

/** 读 opencode.json 的插件列表（容忍注释缺失/损坏）。 */
async function readPlugins(): Promise<{ path: string; plugins: string[]; exists: boolean }> {
  const path = join(homedir(), ".config", "opencode", "opencode.json")
  try {
    const text = await readFile(path, "utf8")
    const raw: unknown = JSON.parse(text)
    if (typeof raw !== "object" || raw === null) return { path, plugins: [], exists: true }
    const list = (raw as { plugin?: unknown }).plugin
    const plugins = Array.isArray(list) ? list.filter((x): x is string => typeof x === "string") : []
    return { path, plugins, exists: true }
  } catch {
    return { path, plugins: [], exists: false }
  }
}


/** 宿主版本探测：doctor 用。二进制不在就按「未知」走保守路由，不报错。 */
function detectOpenCodeVersion(): string | undefined {
  try {
    const r = Bun.spawnSync(["opencode", "--version"], { stdout: "pipe", stderr: "pipe" })
    const out = new TextDecoder().decode(r.stdout).trim()
    return out === "" ? undefined : out
  } catch {
    return undefined
  }
}

export async function runDoctor(args: string[]): Promise<number> {
  const json = args.includes("--json")
  const report = await measureReport()
  const skills = await scanSkills(defaultSkillRoots())
  const roots = defaultSkillRoots()
  const structure = await readStructure()
  const { plugins } = await readPlugins()
  const legacy = plugins.filter((p) => p.includes("oh-my-openagent"))
  // 当前进程、shell 启动文件、systemd drop-in 任一处生效即视为已关闭
  let externalSkillsOff = process.env["OPENCODE_DISABLE_EXTERNAL_SKILLS"] === "1"
  if (!externalSkillsOff) {
    const seen: string[] = []
    for (const f of [
      join(homedir(), ".zshrc"),
      join(homedir(), ".config/systemd/user/opencode-serve.service.d/oml.conf"),
    ]) {
      try {
        if ((await readFile(f, "utf8")).includes("OPENCODE_DISABLE_EXTERNAL_SKILLS=1")) externalSkillsOff = true
      } catch {
        seen.push(f)
      }
    }
    void seen
  }

  const facts = {
    oml: {
      promptTokens: report.totalTokens,
      limit: report.budget.limit,
      status: report.budget.status,
      sections: report.sections.map((s) => ({ id: s.id, tokens: s.tokens, items: s.items })),
    },
    skills: { unique: skills.length, roots: roots.length, indexCap: 40 },
    host: {
      mcp: structure.mcp,
      plugins: plugins.length,
      legacyOmoPlugins: legacy,
      legacyOmoHooks: structure.hooks,
      externalSkillsOff,
      acp: { hostVersion: detectOpenCodeVersion(), pick: pickAcp({ name: "opencode", version: detectOpenCodeVersion() }), installed: hasAcpPlugin(plugins, pickAcp({ name: "opencode", version: detectOpenCodeVersion() }).plugin) },
    },
    measured: MEASURED,
  }

  if (json) {
    console.log(JSON.stringify(facts, null, 2))
    return report.budget.status === "fail" ? 1 : 0
  }

  console.log(`OML 自身注入   ${mark(report.budget.status !== "fail")} ${report.totalTokens}/${report.budget.limit} tok`)
  for (const s of report.sections) {
    console.log(`  ${DIM}${s.id.padEnd(10)}${RESET} ${String(s.tokens).padStart(6)} tok  ${DIM}items=${s.items}${RESET}`)
  }
  console.log(`技能           ${skills.length} 个唯一（根 ${roots.length} 个；索引上限 40 条）`)

  console.log("\n宿主足迹")
  console.log(`  MCP 常驻     ${mark(structure.mcp <= 3)} ${structure.mcp} 个 ${DIM}（8→3 实测省 ${(MEASURED.mcpThree / 1000).toFixed(1)}K tok；8 个全开约 ${(MEASURED.mcpFull / 1000).toFixed(0)}K 估算）${RESET}`)
  console.log(`  插件         ${mark(plugins.length <= 5)} ${plugins.length} 个 ${DIM}（实测增量 ~${(MEASURED.plugins / 1000).toFixed(1)}K tok）${RESET}`)
  console.log(`  外部技能扫描 ${mark(externalSkillsOff)} ${externalSkillsOff ? "已关闭" : "开启"} ${DIM}（开启时实测 +${(MEASURED.externalSkills / 1000).toFixed(1)}K tok）${RESET}`)
  console.log(`  旧 OMO 插件  ${mark(legacy.length === 0)} ${legacy.length === 0 ? "已移除" : legacy.join(", ")}`)
  const hostVer = detectOpenCodeVersion()
  const acp = pickAcp({ name: "opencode", version: hostVer })
  const acpOk = hasAcpPlugin(plugins, acp.plugin)
  console.log(`  ACP 路由     ${mark(acpOk)} 宿主 ${hostVer ?? "版本未知"} → 应带 ${acp.plugin}${acpOk ? "（已在插件列表）" : "（未安装，跑 omo install --apply）"}`)
  const acpTip = acpOk ? "" : `装上 ${acp.plugin}：${acp.reason}`
  if (legacy.length > 0 || structure.hooks > 0) {
    console.log(`  ${DIM}旧 OMO 残留 hook 目录: ${structure.hooks} 个（不影响加载，占磁盘）${RESET}`)
  }

  console.log("\n建议（按收益排序）")
  const tips: string[] = []
  if (acpTip !== "") tips.push(acpTip)
  if (!externalSkillsOff) {
    tips.push(`设 OPENCODE_DISABLE_EXTERNAL_SKILLS=1：省 ~${(MEASURED.externalSkills / 1000).toFixed(1)}K tok，技能改由 omo_skill_search 按需查`)
  }
  if (structure.mcp > 3) {
    tips.push(`常驻 MCP 从 ${structure.mcp} 降到 ≤3：实测每 5 个约 9.6K tok`)
  }
  if (plugins.length > 5) {
    tips.push(`插件从 ${plugins.length} 降到 ≤5：省 ~${(MEASURED.plugins / 1000).toFixed(1)}K tok`)
  }
  if (legacy.length > 0) {
    tips.push("先跑 omo install 移除旧 OMO 插件")
  }
  if (tips.length === 0) console.log(`  ${GREEN}已是精简状态${RESET}`)
  else for (const t of tips) console.log(`  - ${t}`)

  return report.budget.status === "fail" ? 1 : 0
}

const PLUGIN_SOURCE = `// OML：以 OMO 兼容接口重写的编排层（OpenCode 1.x）。
// 加载器要求每个运行时导出都是函数，因此这里只转发 default。
export { default } from "file://__OML_OC_INDEX__"
`

/** omo install —— 把 OML 接到当前 OpenCode：写插件入口、移除旧 OMO、补 oml.json。幂等。 */
export async function runInstall(args: string[]): Promise<number> {
  const dryRun = !args.includes("--apply")
  const root = join(import.meta.dir, "../../../..")
  const ocIndex = join(root, "OC/omo/src/index.ts")
  const pluginPath = join(homedir(), ".config", "opencode", "plugin/omo.ts")
  const configPath = join(homedir(), ".config", "opencode/opencode.json")
  const omlPath = join(homedir(), ".config", "opencode/oml.json")

  const steps: string[] = []

  const pluginBody = PLUGIN_SOURCE.replace("__OML_OC_INDEX__", ocIndex)
  let pluginChanged = true
  try {
    const cur = await readFile(pluginPath, "utf8")
    pluginChanged = cur !== pluginBody
  } catch {
    pluginChanged = true
  }
  if (pluginChanged) steps.push(`写 ${pluginPath}`)
  else steps.push(`跳过 ${pluginPath}（已是最新）`)

  let nextConfig: string | undefined
  try {
    const text = await readFile(configPath, "utf8")
    const raw: unknown = JSON.parse(text)
    if (typeof raw === "object" && raw !== null) {
      const obj = raw as { plugin?: unknown }
      if (Array.isArray(obj.plugin)) {
        const kept = obj.plugin.filter((p) => !(typeof p === "string" && p.includes("oh-my-openagent")))
        let acpNote = ""
        const decision = pickAcp({ name: "opencode", version: detectOpenCodeVersion() })
        if (!hasAcpPlugin(kept, decision.plugin)) {
          kept.push(decision.plugin)
          acpNote = `；补 ${decision.plugin}（${decision.reason}）`
        }
        if (kept.length !== obj.plugin.length || acpNote !== "") {
          obj.plugin = kept
          nextConfig = JSON.stringify(obj, null, 2) + "\n"
          steps.push(`从 ${configPath} 移除 oh-my-openagent（保留 ${kept.length - (acpNote === "" ? 0 : 1)} 个插件）${acpNote}`)
        } else {
          steps.push("跳过 opencode.json（无旧 OMO 条目，ACP 插件已就位）")
        }
      }
    }
  } catch {
    steps.push(`跳过 opencode.json（读不到或不是 JSON）`)
  }

  let writeOml = false
  if (!(await exists(omlPath))) {
    writeOml = true
    steps.push(`写 ${omlPath}（compat.taskAlias=true, budget.limit=8192）`)
  } else {
    steps.push(`跳过 ${omlPath}（已存在，不覆盖用户配置）`)
  }

  if (dryRun) {
    console.log("dry-run（加 --apply 才写入）")
    for (const s of steps) console.log(`  - ${s}`)
    return 0
  }

  if (pluginChanged) {
    await mkdir(dirname(pluginPath), { recursive: true })
    await writeFile(pluginPath, pluginBody, "utf8")
    // 写完当场验：文件能 import 且 default 是函数。入口语法错过一次就整插件失联。
    try {
      const mod = (await import(`file://${pluginPath}?t=${Date.now()}`)) as { default?: unknown }
      if (typeof mod.default !== "function") throw new Error("default 不是函数")
    } catch (err) {
      console.error(`${RED}插件入口校验失败${RESET}: ${err instanceof Error ? err.message : String(err)}`)
      console.error(`文件: ${pluginPath}`)
      return 1
    }
  }
  if (nextConfig !== undefined) {
    const backup = `${configPath}.bak-omo-install-${Date.now()}`
    await writeFile(backup, await readFile(configPath, "utf8"), "utf8")
    await writeFile(configPath, nextConfig, "utf8")
  }
  if (writeOml) {
    await writeFile(
      omlPath,
      JSON.stringify({ compat: { taskAlias: true }, budget: { limit: 8192 } }, null, 2) + "\n",
      "utf8",
    )
  }
  for (const s of steps) console.log(`  - ${s}`)
  console.log(`${GREEN}完成${RESET}：重启 OpenCode 后生效；重启前可用 omo doctor 复核。`)
  return 0
}
