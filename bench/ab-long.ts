/**
 * 长任务 A/B：**中断 + 恢复**。
 *
 * 已有 `ab-task.ts` 量的是「一次对话能收尾」的短任务，证明不了 checkpoint/handoff
 * 的价值——短任务根本用不上恢复。这里造一个长任务（持久化 KV：实现 + 5 个测试 +
 * 跑绿），在固定时间点 **SIGKILL** 掉，然后用**同一句恢复提示词**再开一个会话收尾。
 *
 * 唯一变量仍然是「装 OML 还是装旧 OMO」；两边拿到完全相同的恢复提示词，
 * 提示词里列出同一批可探测路径（`.oml` 状态目录、handoff、checkpoint、任务账本）。
 * OML 那边真能读到东西，OMO 那边读不到——这个差别就是被测对象，不是我偏袒。
 *
 * 用法：
 *   bun bench/ab-long.ts --label oml
 *   bun bench/ab-long.ts --label omo --config /tmp/omo-only.json
 * 选项：--model（默认 bailing/Ling-3.0-flash）--kill 60000 --out --
 */
import { mkdtemp, cp, rm, readdir, stat } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"

const REPORT_DIR = "docs/bench"
const FIXTURE = "bench/tasks/06-store/fixture"
const VERIFY = "bench/tasks/06-store/verify.ts"

function arg(name: string, fallback?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`)
  return i === -1 ? fallback : process.argv[i + 1]
}

const label = arg("label", "run")!
const model = arg("model", "bailing/Ling-3.0-flash")!
const configPath = arg("config")
const killMs = Number(arg("kill", "60000"))
const outPath = arg("out", `${REPORT_DIR}/long-ab-${label}.json`)!

const TASK = `实现一份持久化键值存储，规格见 README.md。按顺序做完：先 src/store.ts，再 tests/store.test.ts（至少 5 个 case），最后跑 bun test 直到全绿。不要修改 README.md。`

const RESUME = `上一轮这个任务被强制中断了。先看工作目录现状，再继续做完 README.md 的要求（src/store.ts + tests/store.test.ts + bun test 全绿）。
若工作区里有 .oml-state/ 目录（checkpoints/、tasks.json、handoff/），先读它里面对应的文件再动手；没有就自己从代码现状推断进度。不要从头重写已经正确的部分。`

interface StepTotals { input: number; output: number; steps: number }

function tally(buf: string): StepTotals {
  let input = 0
  let output = 0
  let steps = 0
  for (const line of buf.split("\n")) {
    if (!line.startsWith("{")) continue
    try {
      const ev = JSON.parse(line) as { type?: string; part?: { type?: string; tokens?: { input?: number; output?: number } } }
      const part = ev.part
      const isFinish = ev.type === "step_finish" || part?.type === "step-finish"
      if (!isFinish) continue
      steps += 1
      input += part?.tokens?.input ?? 0
      output += part?.tokens?.output ?? 0
    } catch {
      // 半行 JSON（被杀时常见）直接跳过
    }
  }
  return { input, output, steps }
}

async function run(cwd: string, prompt: string, timeoutMs?: number): Promise<{ buf: string; killed: boolean; ms: number }> {
  const started = Date.now()
  const cmd = ["opencode", "run", "--format", "json", "--print-logs", "--model", model, "--agent", "sisyphus", "--dir", cwd, prompt]
  const proc = Bun.spawn(cmd, {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
    // 两边都给同一个状态目录变量：OML 会在里面写 checkpoints/tasks，
    // OMO 不认识它（等于没写）。目录放进工作区，恢复时两边都能"看见"它。
    env: {
      ...process.env,
      OML_STATE_DIR: join(cwd, ".oml-state"),
      ...(configPath === undefined ? {} : { OPENCODE_CONFIG: configPath }),
    },
  })
  let buf = ""
  let killed = false
  const timer =
    timeoutMs === undefined
      ? undefined
      : setTimeout(() => {
          killed = true
          proc.kill(9)
        }, timeoutMs)
  const decoder = new TextDecoder()
  for await (const chunk of proc.stdout) buf += decoder.decode(chunk as Uint8Array)
  await proc.exited
  if (timer !== undefined) clearTimeout(timer)
  return { buf, killed, ms: Date.now() - started }
}

async function listState(dir: string): Promise<string[]> {
  try {
    const names = await readdir(dir, { recursive: true })
    return names.filter((n) => !n.includes("node_modules")).slice(0, 30)
  } catch {
    return []
  }
}

const work = await mkdtemp(join(tmpdir(), "oml-long-"))
await cp(FIXTURE, work, { recursive: true })

console.log(`[${label}] 阶段 1：跑 ${killMs / 1000}s 后强杀`)
const phase1 = await run(work, TASK, killMs)
const t1 = tally(phase1.buf)
const midFiles = await listState(work)
console.log(`[${label}] 阶段 1 结束 killed=${phase1.killed} steps=${t1.steps} in=${t1.input} 文件=${midFiles.length}`)

const hasState = midFiles.some((n) => n.includes("handoff") || n.includes("checkpoint") || n.includes("tasks.json") || n.includes(".oml"))
console.log(`[${label}] 中断后留下的可读状态文件：${hasState ? "有" : "无"}`)

console.log(`[${label}] 阶段 2：恢复并收尾`)
const phase2 = await run(work, RESUME)
const t2 = tally(phase2.buf)

const verify = Bun.spawnSync(["bun", VERIFY, work], { cwd: process.cwd(), stdout: "pipe", stderr: "pipe" })
const verifyOut = new TextDecoder().decode(verify.stdout).trim()
const ok = verify.exitCode === 0
console.log(`[${label}] 验收：${ok ? "✓" : "✗"} ${verifyOut.slice(0, 120)}`)

const files = await listState(work)
const size = await Promise.all(files.map(async (f) => {
  try {
    return (await stat(join(work, f))).size
  } catch {
    return 0
  }
}))

const record = {
  label,
  model,
  killedAtMs: killMs,
  stateAfterKill: hasState,
  phase1: { ...t1, killed: phase1.killed, ms: phase1.ms },
  phase2: { ...t2, ms: phase2.ms },
  totalInput: t1.input + t2.input,
  ok,
  verify: verifyOut.slice(0, 400),
  artifacts: files.slice(0, 40).map((f, i) => `${f} (${size[i]} B)`),
}
await Bun.write(outPath, `${JSON.stringify(record, null, 2)}\n`)
console.log(`[${label}] 写入 ${outPath}；总输入 ${record.totalInput}`)
if (process.env["OML_LONG_KEEP"] === undefined) await rm(work, { recursive: true, force: true })
