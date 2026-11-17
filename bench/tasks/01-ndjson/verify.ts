/**
 * 验收：`bun src/cli.ts` 读 stdin 的 JSON 数组，输出 NDJSON（每行一个对象）。
 * 只判行为，不看实现——用什么写法都行。
 */
const dir = process.argv[2]
if (dir === undefined) {
  console.log("FAIL 缺少工作目录参数")
  process.exit(1)
}

const proc = Bun.spawnSync(["bun", "src/cli.ts"], {
  cwd: dir,
  stdin: new TextEncoder().encode('[{"a":1},{"b":2}]'),
  stdout: "pipe",
  stderr: "pipe",
  timeout: 30_000,
})

if (proc.exitCode !== 0) {
  console.log(`FAIL 退出码 ${proc.exitCode}：${proc.stderr.toString().slice(0, 200)}`)
  process.exit(1)
}

const lines = proc.stdout
  .toString()
  .split("\n")
  .map((l) => l.trim())
  .filter((l) => l !== "")

if (lines.length !== 2) {
  console.log(`FAIL 期望 2 行，实得 ${lines.length} 行：${lines.join(" | ").slice(0, 200)}`)
  process.exit(1)
}

const parsed: Record<string, number>[] = []
for (const line of lines) {
  try {
    parsed.push(JSON.parse(line) as Record<string, number>)
  } catch {
    console.log(`FAIL 不是合法 JSON：${line.slice(0, 120)}`)
    process.exit(1)
  }
}

const keys = parsed.map((p) => Object.keys(p).sort().join(",")).join(";")
if (keys !== "a;b") {
  console.log(`FAIL 输出对象不含原始字段：${keys}`)
  process.exit(1)
}

console.log("PASS NDJSON 两行且字段正确")
export {}
