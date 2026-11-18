#!/usr/bin/env bun
/**
 * 七道门。任一「判定失败」即 exit 1；标 INFO 的只是信息，不参与判定。
 *
 * 公理 A9：实践是检验真理的唯一标准 —— 没有实测的门禁等于没有门禁。
 * 公理 A10：零增长 —— 新增必须伴随等量删除或书面豁免。
 */
import { existsSync, readFileSync, readdirSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const ROOT = join(import.meta.dir, "..")
const results: Array<{ gate: string; ok: boolean; detail: string }> = []

/** 只打印、不参与判定。用于「宿主遗留数据」这类不该由 OML 负责的事实。 */
function info(detail: string): void {
  console.log(`INFO  ${detail}`)
}

function record(gate: string, ok: boolean, detail: string): void {
  results.push({ gate, ok, detail })
  const mark = ok ? "PASS" : "FAIL"
  console.log(`${mark}  ${gate}  ${detail}`)
}

async function run(cmd: string[]): Promise<{ code: number; out: string }> {
  const p = Bun.spawn(cmd, { cwd: ROOT, stdout: "pipe", stderr: "pipe" })
  const out = (await new Response(p.stdout).text()) + (await new Response(p.stderr).text())
  const code = await p.exited
  return { code, out }
}

// ---------------------------------------------------------------- 1. 类型
async function gateTypes(): Promise<void> {
  const tsc = join(ROOT, "node_modules/typescript/lib/tsc.js")
  if (!existsSync(tsc)) {
    record("types", false, "未找到 node_modules/typescript/lib/tsc.js，请先 bun install")
    return
  }
  const r = await run(["bun", tsc, "-p", "tsconfig.json", "--noEmit"])
  record("types", r.code === 0, r.code === 0 ? "tsc --noEmit 干净" : r.out.split("\n").slice(0, 12).join(" | "))
}

// ---------------------------------------------------------------- 2. 单测
async function gateTests(): Promise<void> {
  const r = await run(["bun", "test", "--bail"])
  const summary = r.out.split("\n").filter((l) => /\b(pass|fail|Ran)\b/i.test(l)).slice(-3).join(" | ")
  record("tests", r.code === 0, summary || (r.code === 0 ? "通过" : r.out.slice(0, 400)))
}

// ---------------------------------------------------------------- 3. 预算
async function gateBudget(): Promise<void> {
  const bench = join(ROOT, "bench/prompt.ts")
  if (!existsSync(bench)) {
    record("budget", false, "bench/prompt.ts 不存在，无法验证注入量")
    return
  }
  const r = await run(["bun", bench])
  const line = r.out.trim().split("\n").pop() ?? ""
  record("budget", r.code === 0, line || r.out.slice(0, 400))
}

// ---------------------------------------------------------------- 3b. 宿主注入
async function gateHost(): Promise<void> {
  const bench = join(ROOT, "bench/host.ts")
  if (!existsSync(bench)) {
    record("host", false, "bench/host.ts 不存在，无法验证宿主注入")
    return
  }
  const r = await run(["bun", bench])
  const lines = r.out.trim().split("\n").filter((l) => l.includes("tokens") || l.includes("PASS") || l.includes("FAIL"))
  record("host", r.code === 0, lines.slice(-2).join(" | ") || r.out.slice(0, 300))
}

// ---------------------------------------------------------------- 3c. 插件面
interface Surface {
  tools: number
  hookKeys: number
  actions: number
  parity: boolean
  toolNames: string[]
  hookNames: string[]
}

/** 真实加载一次宿主，数它到底挂了什么。数目录是自欺：hook 在 host.ts 里，不在 hooks/ 目录。 */
async function measureSurface(): Promise<Surface> {
  const dir = join(ROOT, ".oml-check-surface")
  const { mkdir, rm } = await import("node:fs/promises")
  await mkdir(dir, { recursive: true })
  try {
    const { createHostCore } = await import("../OC/omo/src/host.ts")
    const client = {
      async createSession() { return { id: "ses_check" } },
      async renameSession() {},
      async promptSession() { return { text: "" } },
      async abortSession() {},
      async lastAssistantText() { return "" },
      async listSessions() { return [] },
      async deleteSession() {},
    }
    const hooks = await createHostCore({ directory: dir, client }, { skillRoots: [], stateDir: join(dir, "state") })
    const { ACTION_TOTAL } = await import("../OC/omo/src/tools.ts")
    const toolNames = Object.keys(hooks.tool ?? {})
    const hookNames = Object.keys(hooks)

    const oc = await import("../OC/omo/src/index.ts")
    const oc2 = await import("../OC2/omo/src/index.ts")
    // OC1（生产）：V1 真机约束——运行时只导出 default 一个函数，多导出常量会被加载器丢弃。
    const ocOnlyDefault =
      Object.keys(oc).length === 1 && typeof (oc as Record<string, unknown>)["default"] === "function"
    // OC2（V2 理论插件）：官方 V1→V2 迁移后 default 是定义对象 {id, setup, server}，
    // 不再是函数（函数导出在 2.3.0 真机被拒，见 dialect.ts DIFF-6）。
    const d = (oc2 as Record<string, unknown>)["default"] as Record<string, unknown> | undefined
    const oc2V2Definition =
      Object.keys(oc2).length === 1 &&
      d !== undefined &&
      d["id"] === "oml.oc2" &&
      typeof d["setup"] === "function" &&
      typeof d["server"] === "function"
    return { tools: toolNames.length, hookKeys: hookNames.length, actions: ACTION_TOTAL, parity: ocOnlyDefault && oc2V2Definition, toolNames, hookNames }
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
}

let surfaceOnce: Promise<Surface> | undefined
function surface(): Promise<Surface> {
  surfaceOnce ??= measureSurface()
  return surfaceOnce
}

async function gateSurface(): Promise<void> {
  try {
    const s = await surface()
    const lim = readLimits()
    const ok = s.tools <= lim.tools && s.hookKeys <= lim.hooks && s.parity
    record("surface", ok, `tools=${s.tools}/${lim.tools} hooks=${s.hookKeys}/${lim.hooks} 导出面一致=${s.parity}`)
  } catch (err: unknown) {
    record("surface", false, `检测失败: ${err instanceof Error ? err.message : String(err)}`)
  }
}

// ---------------------------------------------------------------- 4. 结构
interface Limits { hooks: number; tools: number; actions: number; mcp: number; plugins: number }

function readLimits(): Limits {
  const limits: Limits = { hooks: 8, tools: 14, actions: 29, mcp: 3, plugins: 5 }
  const p = join(ROOT, "BUDGET.md")
  if (!existsSync(p)) return limits
  const txt = readFileSync(p, "utf8")
  const pick = (label: string, fallback: number): number => {
    const m = new RegExp(`\\|\\s*${label}\\s*\\|\\s*(\\d+)\\s*\\|`).exec(txt)
    return m?.[1] ? Number(m[1]) : fallback
  }
  limits.hooks = pick("Hook 数量", limits.hooks)
  limits.tools = pick("工具数量", limits.tools)
  limits.actions = pick("网关 action 槽位", limits.actions)
  limits.mcp = pick("常驻 MCP", limits.mcp)
  limits.plugins = pick("启用插件", limits.plugins)
  return limits
}

function countDirs(p: string): number {
  if (!existsSync(p)) return 0
  try {
    return readdirSync(p, { withFileTypes: true }).filter((e) => e.isDirectory()).length
  } catch {
    return 0
  }
}

async function gateStructure(): Promise<void> {
  const limits = readLimits()

  // 判定项：OML 自己的足迹（真实加载后数出来的）
  let own: Surface
  try {
    own = await surface()
  } catch (err: unknown) {
    record("structure", false, `无法测量自身足迹: ${err instanceof Error ? err.message : String(err)}`)
    return
  }
  const over: string[] = []
  if (own.hookKeys > limits.hooks) over.push(`自身 hook ${own.hookKeys} > ${limits.hooks}`)
  if (own.tools > limits.tools) over.push(`自身 tool ${own.tools} > ${limits.tools}`)
  // 真实复杂度货币：网关 action 槽位。工具数可以把 18 个分支藏进 1 个 enum 里。
  if (own.actions > limits.actions) over.push(`网关 action ${own.actions} > ${limits.actions}`)

  // 信息项：宿主遗留（不是 OML 的足迹，改造前如实展示，但不参与判定）
  const ocConfig = join(homedir(), ".config/opencode/opencode.json")
  if (existsSync(ocConfig)) {
    try {
      const cfg = JSON.parse(readFileSync(ocConfig, "utf8")) as {
        mcp?: Record<string, unknown>
        plugin?: unknown[]
      }
      const mcpCount = Object.keys(cfg.mcp ?? {}).length
      const pluginCount = (cfg.plugin ?? []).length
      info(`宿主 opencode.json：MCP=${mcpCount}（上限 ${limits.mcp}）插件=${pluginCount}（上限 ${limits.plugins}）`)
      if (mcpCount > limits.mcp) info(`  ↑ MCP 超出 OML 预算 ${mcpCount - limits.mcp} 个（属宿主决策，不计入 structure 判定）`)
      if (pluginCount > limits.plugins) info(`  ↑ 插件超出 OML 预算 ${pluginCount - limits.plugins} 个（同上）`)
    } catch {
      info("宿主 opencode.json 无法解析")
    }
  }
  const legacyHooks = countDirs(
    join(homedir(), ".cache/opencode/packages/oh-my-openagent@5.1.43/node_modules/oh-my-openagent/dist/hooks"),
  )
  info(`旧 OMO 遗留 hooks 目录=${legacyHooks}（不参与判定）`)

  record(
    "structure",
    over.length === 0,
    `自身 hook=${own.hookKeys}/${limits.hooks} tool=${own.tools}/${limits.tools} action=${own.actions}/${limits.actions}` +
      (over.length ? ` 超限: ${over.join("; ")}` : ""),
  )
}

// ---------------------------------------------------------------- 5. 零增长
/** 零增长：与 manifest 基线比，而不是与未提交的 git 索引比。
 * 后者在「仓库零提交」时 git 直接 exit 128，而旧实现只看以 A 开头的行 →
 * added.length === 0 → 打印 PASS。那就是空过。没有基线时必须报「无法判定」。 */
async function gateZeroGrowth(): Promise<void> {
  const manifestFile = join(ROOT, "manifest.json")
  if (!existsSync(manifestFile)) {
    record("zero-growth", false, "无基线：manifest.json 不存在 → 无法判定。先跑 `bun run manifest` 建立基线")
    return
  }
  const baseline = JSON.parse(readFileSync(manifestFile, "utf8")) as { files?: Record<string, string> }
  const base = baseline.files ?? {}
  const { buildManifest } = await import("../scripts/manifest.ts")
  const current = await buildManifest(ROOT)

  const added = Object.keys(current).filter((k) => base[k] === undefined)
  const changed = Object.keys(current).filter((k) => base[k] !== undefined && base[k] !== current[k])
  const removed = Object.keys(base).filter((k) => current[k] === undefined)

  const budgetTouched = changed.includes("BUDGET.md")
  const ack = process.env["OMO_BUDGET_ACK"] === "1"

  if (added.length === 0) {
    record(
      "zero-growth",
      true,
      `无新增（相对基线）；变更 ${changed.length} 删除 ${removed.length}` +
        (changed.length + removed.length > 0 ? " —— 记得 `bun run manifest` 刷新基线" : ""),
    )
    return
  }
  if (budgetTouched || ack) {
    record("zero-growth", true, `新增 ${added.length} 项，已记账（BUDGET.md=${budgetTouched}, ACK=${ack}）`)
    return
  }
  record(
    "zero-growth",
    false,
    `新增 ${added.length} 个文件但 BUDGET.md 未改动（A10）：${added.slice(0, 6).join(", ")}${added.length > 6 ? " …" : ""}。要么记账，要么 OMO_BUDGET_ACK=1 豁免`,
  )
}

// ---------------------------------------------------------------- main
console.log(`OMO check @ ${ROOT}\n`)
await gateTypes()
await gateTests()
await gateBudget()
await gateHost()
await gateSurface()
await gateStructure()
await gateZeroGrowth()

const failed = results.filter((r) => !r.ok)
console.log(`\n${results.length - failed.length}/${results.length} 通过`)
if (failed.length > 0) {
  console.log(`失败: ${failed.map((f) => f.gate).join(", ")}`)
  process.exit(1)
}
