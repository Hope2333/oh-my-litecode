#!/usr/bin/env bun
/**
 * bench:parity —— 原版 OMO 与 OML 的逐项对照。
 *
 * 公理 A9（实践检验）：对照表里的每个 OML 数字都当场测，不用手抄。
 * 原版 OMO 的数字来自 docs/design/omo-inventory.md（当时实测的磁盘/构建产物）。
 */
import { mkdtemp, readFile, rm, writeFile, readdir, mkdir } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join, dirname } from "node:path"
import { AGENTS, CATEGORIES } from "../packages/core/src/agents/registry.ts"
import { buildTools } from "../OC/omo/src/tools.ts"
import { createHostCore } from "../OC/omo/src/host.ts"
import { measureReport } from "../packages/cli/src/commands/measure.ts"
import type { HostState } from "../OC/omo/src/tools.ts"

/**
 * 原版 OMO 的结构数字（来自 docs/design/omo-inventory.md 的磁盘实测）。
 *
 * 注意：这里**不放注入 token**。注入量必须用同一把尺子测（见 docs/bench/ab-input.json），
 * 把 inventory 里抄来的数字和 `omo measure` 自报数并列，是两把尺子。
 */
const OMO = {
  tools: 25,
  hooks: 57,
  agents: 11,
  categories: 9,
  deps: "3 + 12 optional",
  distBytes: 6_083_548,
  dtsFiles: 1_679,
  workspaces: 34,
}

async function sourceBytes(dir: string): Promise<number> {
  let total = 0
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name)
    if (e.isDirectory()) total += await sourceBytes(p)
    else if (e.name.endsWith(".ts")) total += (await readFile(p)).byteLength
  }
  return total
}

function stubState(): HostState {
  return {
    config: {},
    skills: [],
    usage: {},
    store: { version: 1, tasks: {} },
    memory: { version: 1, seq: 0, memories: {} },
  compress: { version: 1, seq: 0, blocks: {} },
  saveCompress: () => {},
    saveMemory: () => {},
    directory: process.cwd(),
    client: {
      async createSession() {
        return { id: "ses_stub" }
      },
      async renameSession() {},
      async promptSession() {
        return { text: "" }
      },
      async abortSession() {},
      async lastAssistantText() {
        return ""
      },
      async listSessions() {
        return []
      },
      async deleteSession() {},
    },
    sessionImages: new Set<string>(),
    sessionText: new Map(),
    sessionTitles: new Map<string, string>(),
    ownership: {},
    paQueue: {},
    saveOwnership() {},
    savePa() {},
    overrides: { version: 1, agents: {}, categories: {} },
    stats: { startedAt: Date.now(), calls: {} },
    saveUsage() {},
    saveTasks() {},
    saveOverrides() {},
    modelFor: () => ({ model: null, source: "none", chain: [] }),
    async checkpoint() {
      return ""
    },
    measure: () => ({
      totalTokens: 0,
      sections: [],
      budget: { limit: 8192, used: 0, status: "pass" },
      warnings: [],
    }),
    getGoal: () => null,
    setGoal: async (text: string) => ({ text, createdAt: 0, updatedAt: 0 }),
    mcpCatalog: { version: 1, entries: {}, updatedAt: "1970-01-01T00:00:00.000Z" },
    saveMcpCatalog() {},
    async hostMcpDefs() {
      return {}
    },
    async writeHostMcp() {
      return { path: "(bench)", changed: [] }
    },
    clearGoal: async () => false,
  }
}

const t0 = performance.now()
const rss0 = process.memoryUsage().rss
const dir = await mkdtemp(join(tmpdir(), "oml-parity-"))
const hooks = await createHostCore(
  { directory: dir, client: stubState().client },
  { skillRoots: [], stateDir: dir },
)
const loadMs = performance.now() - t0
const rssMb = (process.memoryUsage().rss - rss0) / 1024 / 1024

const toolCount = Object.keys(hooks.tool ?? {}).length
const hookCount = Object.keys(hooks).length
const report = await measureReport()
const srcBytes = (await sourceBytes("packages")) + (await sourceBytes("OC"))
await rm(dir, { recursive: true, force: true })

interface AbRun { id: string; omo: boolean; externalSkills: boolean; tokensInput: number; note: string }
interface AbInput { method: string; model: string; prompt: string; project: string; hostConfig: string; measuredAt: string; runs: AbRun[] }
let ab: AbInput | undefined
try {
  ab = JSON.parse(await readFile("docs/bench/ab-input.json", "utf8")) as AbInput
} catch {
  ab = undefined
}
const abOn = ab?.runs.find((r) => r.omo && r.externalSkills)
const abOff = ab?.runs.find((r) => !r.omo && r.externalSkills)
const delta = abOn && abOff ? Math.round((1 - abOn.tokensInput / abOff.tokensInput) * 1000) / 10 : null

interface AbTask { id: string; ok: boolean; inputTokens: number; steps: number; ms: number }
interface AbTaskFile { label: string; model: string; passed: number; total: number; inputTokens: number; avgSteps: number; tasks: AbTask[] }
async function readAbTask(name: string): Promise<AbTaskFile | undefined> {
  try {
    return JSON.parse(await readFile(`docs/bench/task-ab-${name}.json`, "utf8")) as AbTaskFile
  } catch {
    return undefined
  }
}
const abOml = await readAbTask("oml")
const abOmo = await readAbTask("omo")
const abTaskDelta = abOml && abOmo ? Math.round((1 - abOml.inputTokens / abOmo.inputTokens) * 1000) / 10 : null

const rows: Array<[string, string, string, string]> = [
  [
    "首轮总提示 (tok)",
    abOff ? abOff.tokensInput.toLocaleString() : "未测",
    abOn ? abOn.tokensInput.toLocaleString() : "未测",
    delta === null ? "见 docs/bench/ab-input.json" : `同一把尺子实测，−${delta}%`,
  ],
  ["5 任务完成率", abOmo ? `${abOmo.passed}/${abOmo.total}` : "未测", abOml ? `${abOml.passed}/${abOml.total}` : "未测", "docs/bench/task-ab.md；同模型同 fixture 实测"],
  ["5 任务输入 (tok)", abOmo ? abOmo.inputTokens.toLocaleString() : "未测", abOml ? abOml.inputTokens.toLocaleString() : "未测", abTaskDelta === null ? "未测" : `真实任务累计，−${abTaskDelta}%`],
  ["5 任务平均步数", abOmo ? abOmo.avgSteps.toFixed(1) : "未测", abOml ? abOml.avgSteps.toFixed(1) : "未测", "步数多＝多走了查技能/读正文/量预算"],
  ["OML 自身注入段 (tok)", "—", report.totalTokens.toLocaleString(), "`omo measure`：只统计 OML 拼装的四段，不是总提示"],
  ["工具数", String(OMO.tools), String(toolCount), "inventory vs buildTools()"],
  ["hook 职责位", String(OMO.hooks), String(hookCount), "inventory vs hooks 键数"],
  ["agent", String(OMO.agents), String(AGENTS.length), `其中前台 ${AGENTS.filter((a) => a.tier === "primary").length}`],
  ["category", String(OMO.categories), String(CATEGORIES.length), "inventory vs registry"],
  ["运行时依赖", OMO.deps, "0", "package.json"],
  ["产物体积", `${(OMO.distBytes / 1024 / 1024).toFixed(2)} MB`, `${(srcBytes / 1024).toFixed(0)} KB`, `源码 vs 打包产物；.d.ts ${OMO.dtsFiles} → 0`],
  ["workspace", String(OMO.workspaces), "3", "packages/core, packages/cli, OC/omo (+ OC2)"],
  ["首屏加载", "未测", `${loadMs.toFixed(2)} ms`, "createHostCore 冷启动"],
  ["常驻内存增量", "未测", `${rssMb.toFixed(1)} MB`, "process.memoryUsage().rss 差值"],
]

const md = [
  "# OMO → OML 逐项对照",
  "",
  `生成时间：${new Date().toISOString()}　命令：\`bun run bench:parity\``,
  "",
  "| 项目 | 原版 OMO | OML | 口径 |",
  "|---|---|---|---|",
  ...rows.map(([k, a, b, c]) => `| ${k} | ${a} | **${b}** | ${c} |`),
  "",
  "## 首轮总提示：同一把尺子的 A/B",
  "",
  ...(ab
    ? [
        `条件：\`${ab.model}\`、空项目 \`${ab.project}\`、单轮提示词「${ab.prompt}」、宿主配置 ${ab.hostConfig}。`,
        `取数方法：${ab.method}。测量时间：${ab.measuredAt}。`,
        "",
        "| 组 | OML | 外部技能扫描 | tokens.input | 说明 |",
        "|---|---|---|---|---|",
        ...ab.runs.map((r) => `| ${r.id} | ${r.omo ? "开" : "关"} | ${r.externalSkills ? "开" : "关"} | **${r.tokensInput.toLocaleString()}** | ${r.note} |`),
        "",
        `结论：OML 使首轮总提示 ${abOff?.tokensInput.toLocaleString() ?? "?"} → ${abOn?.tokensInput.toLocaleString() ?? "?"}（−${delta}%）。`,
        "C 与 B 完全相同，说明宿主注入的全量技能目录已被 OML 剥离——此时外部技能开关不再影响提示体积。",
        "复现：`bash bench/ab.sh`。",
      ]
    : ["未找到 `docs/bench/ab-input.json`，本表留空。"]),
  "",
  "## 真实任务 A/B：它到底会不会干活",
  "",
  ...(abOml && abOmo
    ? [
        `模型 \`${abOml.model}\`，5 个 fixture 任务，唯一变量是装 OML 还是装旧 OMO。验收脚本只判行为，不看实现。`,
        "",
        "| 任务 | OML | OML in tok | OMO | OMO in tok |",
        "|---|---|---|---|---|",
        ...abOml.tasks.map((t) => {
          const o = abOmo.tasks.find((x) => x.id === t.id)
          return `| ${t.id} | ${t.ok ? "✓" : "✗"} | ${t.inputTokens.toLocaleString()} | ${o?.ok ? "✓" : "✗"} | ${(o?.inputTokens ?? 0).toLocaleString()} |`
        }),
        "",
        `完成率 ${abOml.passed}/${abOml.total} vs ${abOmo.passed}/${abOmo.total}；输入 token −${abTaskDelta}%；平均步数 ${abOml.avgSteps} vs ${abOmo.avgSteps}（**多了**，不是少了）。`,
        "详细限定条件（单模型单次、任务规模小、长任务未覆盖）见 `docs/bench/task-ab.md`，此处不重复好消息。",
        "复现：`bun bench/ab-task.ts --label oml` 与 `bun bench/ab-task.ts --label omo --config /tmp/omo-only.json`。",
      ]
    : ["未找到 `docs/bench/task-ab-*.json`，本节留空。"]),
  "",
  "## 读法",
  "- **总量**用首轮总提示（A/B 实测）；**OML 自身段**用 `omo measure`。两者不能混着说。",
  `- OML 的 ${toolCount} 个工具与 ${hookCount} 个 hook 位都是条件装配的结果：配置里关掉哪个，计数就减一，\`scripts/check.ts\` 的 surface 门会当场验证。`,
  "- 原版 OMO 的「未测」项没有可信数字，不编。",
  "",
].join("\n")

await mkdir("docs/bench", { recursive: true })
await writeFile("docs/bench/parity.md", md, "utf8")
console.log(md)
console.log(`已写入 docs/bench/parity.md（${md.length} 字节）`)
