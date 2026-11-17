/**
 * 5 任务真实 A/B —— 评审第 5 条验收。
 *
 * 为什么要有这个文件：`bench/parity.ts` 量的是**提示体积**，不是**任务能力**。
 * 体积小十倍但做不对事，等于把成本转移给用户。这里用 5 个可机器判定的任务
 * （各带 verify 脚本，只判行为不看实现）测三件事：完成率、返工步数、真实 token。
 *
 * 用法：
 *   bun bench/ab-task.ts --label oml
 *   bun bench/ab-task.ts --label omo --config /tmp/omo-only.json
 *   bun bench/ab-task.ts --label oml --only 02-bugfix,03-cache
 */
import { cp, mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { mkdir } from "node:fs/promises"

const HERE = import.meta.dir
const ROOT = dirname(HERE)

interface TaskDef {
  readonly id: string
  readonly prompt: string
  readonly fixture: string
  readonly verify: string
  /** 单任务墙钟上限（ms） */
  readonly timeout: number
}

const TASKS: readonly TaskDef[] = [
  {
    id: "01-ndjson",
    prompt:
      "在 src/cli.ts 实现一个命令行工具：从 stdin 读入一个 JSON 数组，把每个元素作为一行 JSON 输出（NDJSON）。用 `bun src/cli.ts` 可直接运行。不要写测试，只要实现。",
    fixture: join(HERE, "tasks/01-ndjson/fixture"),
    verify: join(HERE, "tasks/01-ndjson/verify.ts"),
    timeout: 480_000,
  },
  {
    id: "02-bugfix",
    prompt: "运行 `bun test`，找到失败原因并修复实现。禁止修改 sum.test.ts。",
    fixture: join(HERE, "tasks/02-bugfix/fixture"),
    verify: join(HERE, "tasks/02-bugfix/verify.ts"),
    timeout: 480_000,
  },
  {
    id: "03-cache",
    prompt: "给 src/fib.ts 加缓存，使 fib(40) 在 300ms 内返回，且 `bun test` 仍然通过。不要改 fib.test.ts。",
    fixture: join(HERE, "tasks/03-cache/fixture"),
    verify: join(HERE, "tasks/03-cache/verify.ts"),
    timeout: 480_000,
  },
  {
    id: "04-readme",
    prompt: "为这个仓库写 README.md：说明 src/index.ts 导出的每个函数的用途，并给出运行测试的命令。不要改动源码。",
    fixture: join(HERE, "tasks/04-readme/fixture"),
    verify: join(HERE, "tasks/04-readme/verify.ts"),
    timeout: 480_000,
  },
  {
    id: "05-refactor",
    prompt: "消掉 src/a.ts 与 src/b.ts 之间的重复实现，保持 `bun test` 通过。可以新增文件，但不要改 refactor.test.ts。",
    fixture: join(HERE, "tasks/05-refactor/fixture"),
    verify: join(HERE, "tasks/05-refactor/verify.ts"),
    timeout: 480_000,
  },
]

interface StepFinish {
  /** 事件流的外层 type 是 `step_finish`（下划线），part.type 才是 `step-finish`。两者都收。 */
  readonly type: "step_finish" | "step-finish"
  readonly part: { readonly tokens: { readonly input: number; readonly output: number } }
}

function parseSteps(stdout: string): { input: number; output: number; steps: number } {
  let input = 0
  let output = 0
  let steps = 0
  for (const line of stdout.split("\n")) {
    const trimmed = line.trim()
    if (trimmed === "" || !trimmed.startsWith("{")) continue
    let parsed: unknown
    try {
      parsed = JSON.parse(trimmed)
    } catch {
      continue
    }
    if (typeof parsed !== "object" || parsed === null) continue
    const ev = parsed as Partial<StepFinish>
    if (ev.type !== "step_finish" && ev.type !== "step-finish") continue
    if (ev.part === undefined) continue
    steps += 1
    input += ev.part.tokens.input
    output += ev.part.tokens.output
  }
  return { input, output, steps }
}

function arg(name: string): string | undefined {
  const argv = process.argv.slice(2)
  const i = argv.indexOf(`--${name}`)
  return i >= 0 ? argv[i + 1] : undefined
}

const label = arg("label") ?? "oml"
const model = arg("model") ?? "bailing/Ling-3.0-flash"
const configPath = arg("config")
const only = arg("only")?.split(",").map((s) => s.trim())
const outPath = arg("out") ?? join(ROOT, "docs/bench", `task-ab-${label}.json`)

interface Result {
  readonly id: string
  readonly ok: boolean
  readonly reason: string
  readonly inputTokens: number
  readonly outputTokens: number
  readonly steps: number
  readonly ms: number
  readonly exitCode: number
}

const picked = only === undefined ? TASKS : TASKS.filter((t) => only.includes(t.id))
const results: Result[] = []

for (const task of picked) {
  const work = await mkdtemp(join(tmpdir(), `oml-${task.id}-`))
  try {
    await cp(task.fixture, work, { recursive: true })
    // fixture 里的测试文件以 `.fixture` 结尾存放：否则仓库根目录的 `bun test` 会
    // 扫到这些**故意失败**的样例，把 OML 自己的门禁搞红。
    const copyGlob = new Bun.Glob("**/*.ts.fixture")
    for await (const rel of copyGlob.scan({ cwd: work })) {
      await Bun.write(join(work, rel.replace(/\.fixture$/, "")), await Bun.file(join(work, rel)).text())
      await rm(join(work, rel))
    }
    // 必须带 --print-logs：不带时 opencode 在无 TTY 环境下会静默 exit 1（实测三次）。
    const argv = ["opencode", "run", "--format", "json", "--print-logs", "--model", model, "--agent", "sisyphus", "--dir", work, task.prompt]
    const started = performance.now()
    const proc = Bun.spawnSync(argv, {
      cwd: work,
      stdout: "pipe",
      stderr: "pipe",
      timeout: task.timeout,
      // 只在需要换配置时显式传 env：显式传 process.env 反而会让子进程拿不到 TTY 相关变量，
      // opencode 会静默 exit 1（实测）。
      ...(configPath === undefined ? {} : { env: { ...process.env, OPENCODE_CONFIG: configPath } }),
    })
    const ms = performance.now() - started
    const stdout = proc.stdout.toString()
    if (process.env["OML_AB_DEBUG"] === "1") {
      await Bun.write(`/tmp/ab-debug-${task.id}.out`, stdout)
      await Bun.write(`/tmp/ab-debug-${task.id}.err`, proc.stderr.toString())
    }
    const counts = parseSteps(stdout)

    const verify = Bun.spawnSync(["bun", task.verify, work], { stdout: "pipe", stderr: "pipe", timeout: 120_000 })
    const verdict = verify.stdout.toString().trim()
    const ok = verify.exitCode === 0 && verdict.startsWith("PASS")

    results.push({
      id: task.id,
      ok,
      reason: verdict === "" ? proc.stderr.toString().slice(-200) : verdict.slice(0, 300),
      inputTokens: counts.input,
      outputTokens: counts.output,
      steps: counts.steps,
      ms: Math.round(ms),
      exitCode: proc.exitCode,
    })
    console.log(`${ok ? "✓" : "✗"} ${task.id}  in=${counts.input} out=${counts.output} steps=${counts.steps} ${Math.round(ms)}ms`)
    if (!ok) console.log(`   run stderr: ${proc.stderr.toString().split("\n").filter((l) => l.includes("ERROR") || l.includes("error")).slice(-2).join(" | ").slice(-400)}`)
    if (!ok) console.log(`   ${verdict.slice(0, 200)}`)
  } finally {
    if (process.env["OML_AB_KEEP"] === "1") console.log(`   workdir: ${work}`)
    else await rm(work, { recursive: true, force: true })
  }
}

const passed = results.filter((r) => r.ok).length
const totalIn = results.reduce((a, r) => a + r.inputTokens, 0)
const summary = {
  label,
  model,
  config: configPath ?? null,
  at: new Date().toISOString(),
  passed,
  total: results.length,
  inputTokens: totalIn,
  avgSteps: results.length === 0 ? 0 : Number((results.reduce((a, r) => a + r.steps, 0) / results.length).toFixed(2)),
  tasks: results,
}

await mkdir(dirname(outPath), { recursive: true })
await Bun.write(outPath, `${JSON.stringify(summary, null, 2)}\n`)

console.log(`\n${label}: ${passed}/${results.length} 通过 | 总输入 ${totalIn} tok | 平均 ${summary.avgSteps} 步`)
console.log(`写入 ${outPath}`)