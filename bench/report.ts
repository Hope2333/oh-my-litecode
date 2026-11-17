/**
 * 5 任务 A/B 重复基准报告：读两个 label 的结果 JSON，算均值 ± 样本标准差，出 markdown。
 *
 * 用法：
 *   bun bench/report.ts --labels oml-r5,omo-r5
 *   bun bench/report.ts --labels oml-r5,omo-r5 --out docs/bench/task-ab-repeat.md
 *
 * 口径声明（务必保留在报告里）：
 *   N=5 重复只给「均值 ± 样本标准差」的量级，样本标准差 s = sqrt(Σ(x−x̄)²/(n−1))。
 *   这不是置信区间，也不做显著性检验；小样本 + 模型采样噪声，结论只到「量级」。
 */
import { mkdir } from "node:fs/promises"
import { dirname, join } from "node:path"

const HERE = import.meta.dir
const ROOT = dirname(HERE)

function arg(name: string): string | undefined {
  const argv = process.argv.slice(2)
  const i = argv.indexOf(`--${name}`)
  return i >= 0 ? argv[i + 1] : undefined
}

interface Sample {
  readonly run: number
  readonly id: string
  readonly ok: boolean
  readonly inputTokens: number
  readonly outputTokens: number
  readonly steps: number
  readonly ms: number
}

interface ResultJson {
  readonly label: string
  readonly model: string
  readonly config: string | null
  readonly repeat?: number
  readonly seed?: number
  readonly passed: number
  readonly total: number
  readonly tasks: readonly Sample[]
}

const METRICS = [
  { key: "inputTokens", label: "输入 token" },
  { key: "outputTokens", label: "输出 token" },
  { key: "steps", label: "步数" },
  { key: "ms", label: "墙钟 ms" },
] as const
type MetricKey = (typeof METRICS)[number]["key"]

interface Stats {
  readonly n: number
  readonly mean: number
  readonly sd: number
  readonly min: number
  readonly max: number
}

function stats(values: readonly number[]): Stats {
  const n = values.length
  if (n === 0) return { n: 0, mean: NaN, sd: NaN, min: NaN, max: NaN }
  const mean = values.reduce((a, b) => a + b, 0) / n
  const min = Math.min(...values)
  const max = Math.max(...values)
  // 样本标准差（n−1）；n<2 时无意义，记为 0。
  const sd = n < 2 ? 0 : Math.sqrt(values.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1))
  return { n, mean, sd, min, max }
}

function fmtNum(x: number, digits: number): string {
  return x.toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits })
}

function fmt(s: Stats, digits = 0): string {
  if (s.n === 0) return "—"
  return `${fmtNum(s.mean, digits)} ± ${fmtNum(s.sd, digits)}`
}

/** (a − b) / b，百分比，带符号 */
function relDiff(a: number, b: number): string {
  if (!Number.isFinite(a) || !Number.isFinite(b) || b === 0) return "—"
  const pct = (a / b - 1) * 100
  return `${pct > 0 ? "+" : ""}${pct.toFixed(1)}%`
}

async function loadResult(label: string): Promise<ResultJson> {
  const path = join(ROOT, "docs/bench", `task-ab-${label}.json`)
  const file = Bun.file(path)
  if (!file.exists()) {
    throw new Error(`找不到结果文件 ${path}；请先跑 bun bench/ab-task.ts --label ${label} --repeat 5`)
  }
  return (await file.json()) as ResultJson
}

/** 每个 label：按任务分组 → 每指标跨轮取值 */
function perTaskGroups(data: ResultJson): Map<string, Map<MetricKey, number[]>> {
  const byId = new Map<string, Map<MetricKey, number[]>>()
  for (const sample of data.tasks) {
    let group = byId.get(sample.id)
    if (group === undefined) {
      group = new Map<MetricKey, number[]>()
      for (const m of METRICS) group.set(m.key, [])
      byId.set(sample.id, group)
    }
    for (const m of METRICS) group.get(m.key)!.push(sample[m.key])
  }
  return byId
}

/** 每个 label：按轮次把 5 任务求和 → 每指标得到 repeat 个总体样本 */
function perRunTotals(data: ResultJson): Map<MetricKey, number[]> {
  const runs = [...new Set(data.tasks.map((t) => t.run))].sort((a, b) => a - b)
  const totals = new Map<MetricKey, number[]>()
  for (const m of METRICS) totals.set(m.key, [])
  for (const run of runs) {
    const inRun = data.tasks.filter((t) => t.run === run)
    for (const m of METRICS) totals.get(m.key)!.push(inRun.reduce((a, t) => a + t[m.key], 0))
  }
  return totals
}

const labelsArg = arg("labels") ?? "oml-r5,omo-r5"
const labels = labelsArg.split(",").map((s) => s.trim()).filter(Boolean)
if (labels.length !== 2) {
  console.error(`--labels 需要恰好两个 label（逗号分隔），收到: ${labelsArg}`)
  process.exit(1)
}

const [dataA, dataB] = await Promise.all(labels.map(loadResult)) as [ResultJson, ResultJson]
const [labelA, labelB] = labels

/** 某侧是否真的跑起来：全部样本 token=0 说明子进程在初始化阶段就失败，数据不可用于比较。 */
function isExecuted(d: ResultJson): boolean {
  return d.tasks.some((t) => t.inputTokens > 0 || t.outputTokens > 0 || t.steps > 0)
}
const aOK = isExecuted(dataA)
const bOK = isExecuted(dataB)
/** 只有当两侧都真正执行了，才给相对差；否则标记 N/A，避免伪造出 −100% 之类的假结论。 */
function cmp(a: number, b: number): string {
  return aOK && bOK ? relDiff(a, b) : "N/A（该配置未能执行）"
}
function delta(a: number, b: number, digits: number): string {
  return aOK && bOK ? fmtNum(a - b, digits) : "N/A"
}

const groupsA = perTaskGroups(dataA)
const groupsB = perTaskGroups(dataB)
const totalsA = perRunTotals(dataA)
const totalsB = perRunTotals(dataB)
const taskIds = [...new Set([...groupsA.keys(), ...groupsB.keys()])].sort()
const nA = new Set(dataA.tasks.map((t) => t.run)).size
const nB = new Set(dataB.tasks.map((t) => t.run)).size

function completion(d: ResultJson): string {
  const ok = d.tasks.filter((t) => t.ok).length
  const total = d.tasks.length
  const pct = total === 0 ? "—" : `${((ok / total) * 100).toFixed(1)}%`
  return `${ok}/${total} (${pct})`
}

const lines: string[] = []
lines.push(`# 5 任务 A/B 重复基准报告（${labelA} vs ${labelB}）`)
lines.push("")
lines.push(`> **N=${nA}/${nB} 重复，存在性量级证据，非显著性检验。** 报告只给「均值 ± 样本标准差」，不构造置信区间、不做 t 检验；小样本 + 模型采样噪声，结论只到量级。`)
lines.push("")
if (!aOK || !bOK) {
  const bad = [!aOK ? labelA : null, !bOK ? labelB : null].filter(Boolean).join("、")
  lines.push(`> ⚠️ **数据有效性告警：${bad} 未能执行。** 该侧全部样本 exitCode≠0、input/output token=0、steps=0；opencode 在 session step=0 抛出 \`UnknownError ... at SessionPrompt.run\` 与 \`Invalid number of options.\`（见 \`docs/bench/task-ab-omo-r5.json\` 的 reason 字段）。根因是 \`oh-my-openagent\` 插件在 opencode 1.19.3 下初始化失败——属于配置/环境故障，不是模型行为。**该侧数字不可用于 A/B 比较，所有相对差记为 N/A。** 不伪造数据。`)
  lines.push("")
}
lines.push("## 方法")
lines.push("")
lines.push(`- 同一模型 \`${dataA.model}\`、同一批 fixture、同一句 prompt；变量只有装 OML 还是装旧 OMO。`)
lines.push(`- ${labelA}: config=${dataA.config ?? "默认（OML）"}；${labelB}: config=${dataB.config ?? "默认（OML）"}（非默认 config 通过 \`OPENCODE_CONFIG\` 临时装载）。`)
lines.push(`- 每个任务独立 mkdtemp 工作目录，每轮新建、互不复用；seed=${dataA.seed ?? "—"} 仅作运行标记，不改 prompt。`)
lines.push(`- 样本标准差 s = sqrt(Σ(x−x̄)²/(n−1))，n=重复轮数。总体表按「每轮 5 任务求和」后跨轮统计，故总体 n=${nA}/${nB}。`)
lines.push(`- 原始数据：\`docs/bench/task-ab-${labelA}.json\`、\`docs/bench/task-ab-${labelB}.json\`；复现：\`bun bench/ab-task.ts --label <label> --repeat 5\`。`)
lines.push("")
lines.push("## 总体（每轮 5 任务求和后跨轮统计）")
lines.push("")
lines.push(`| 指标 | ${labelA} 均值 ± s (n=${nA}) | ${labelB} 均值 ± s (n=${nB}) | ${labelA}−${labelB} | 相对差 |`)
lines.push("|---|---|---|---|---|")
for (const m of METRICS) {
  const sa = stats(totalsA.get(m.key)!)
  const sb = stats(totalsB.get(m.key)!)
  const digits = m.key === "steps" ? 1 : 0
  lines.push(`| ${m.label} | ${fmt(sa, digits)} | ${fmt(sb, digits)} | ${delta(sa.mean, sb.mean, digits)} | ${cmp(sa.mean, sb.mean)} |`)
}
lines.push("")
lines.push("## 每任务（跨轮统计）")
lines.push("")
lines.push(`| 任务 | 指标 | ${labelA} 均值 ± s | ${labelB} 均值 ± s | 相对差 |`)
lines.push("|---|---|---|---|---|")
for (const id of taskIds) {
  for (const m of METRICS) {
    const va = groupsA.get(id)?.get(m.key) ?? []
    const vb = groupsB.get(id)?.get(m.key) ?? []
    const sa = stats(va)
    const sb = stats(vb)
    const digits = m.key === "steps" ? 1 : 0
    lines.push(`| ${id} | ${m.label} | ${fmt(sa, digits)} | ${fmt(sb, digits)} | ${cmp(sa.mean, sb.mean)} |`)
  }
}
lines.push("")
lines.push("## 完成率")
lines.push("")
lines.push(`| 配置 | ok/总（完成率） |`)
lines.push(`|---|---|`)
lines.push(`| ${labelA} | ${completion(dataA)} |`)
lines.push(`| ${labelB} | ${completion(dataB)} |`)
lines.push("")
lines.push("## 每轮输入 token 原始值（透明度）")
lines.push("")
lines.push(`| run | ${labelA} | ${labelB} |`)
lines.push("|---|---|---|")
const runs = [...new Set([...dataA.tasks, ...dataB.tasks].map((t) => t.run))].sort((a, b) => a - b)
for (const run of runs) {
  const a = dataA.tasks.filter((t) => t.run === run).reduce((s, t) => s + t.inputTokens, 0)
  const b = dataB.tasks.filter((t) => t.run === run).reduce((s, t) => s + t.inputTokens, 0)
  lines.push(`| ${run} | ${fmtNum(a, 0)} | ${fmtNum(b, 0)} |`)
}
lines.push("")
lines.push("## 怎么读（量级，不是显著性）")
lines.push("")
const inA = stats(totalsA.get("inputTokens")!)
const inB = stats(totalsB.get("inputTokens")!)
lines.push(`- 输入 token 总体：${labelA} ${fmt(inA)} vs ${labelB} ${fmt(inB)}，相对差 ${cmp(inA.mean, inB.mean)}。`)
if (aOK && bOK) {
  lines.push(`- σ 本身较大且样本仅 ${nA} 轮；若两组均值差与 σ 同量级，只能说「方向如此」，不能宣称统计显著。`)
  lines.push("- 步数、墙钟与 token 一起看：OML 以更多轮次换更低输入体积，是否划算取决于调用计费口径。")
} else {
  lines.push("- 本轮 A/B 比较未完成：一侧配置未能执行，无法给出相对量级结论。已交付 `--repeat` 与 `report.ts` 代码，待 OMO 配置环境修复后重跑即可。")
}
lines.push("")

const outPath = arg("out") ?? join(ROOT, "docs/bench", "task-ab-repeat.md")
await mkdir(dirname(outPath), { recursive: true })
await Bun.write(outPath, lines.join("\n"))
console.log(`报告写入 ${outPath}`)
console.log(`总体输入 token: ${labelA} ${fmt(inA)} vs ${labelB} ${fmt(inB)} (${cmp(inA.mean, inB.mean)})`)
console.log(`完成率: ${labelA} ${completion(dataA)} | ${labelB} ${completion(dataB)}`)
