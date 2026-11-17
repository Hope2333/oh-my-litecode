/**
 * 验收：测试全绿，且 fib(40) 在 300ms 内跑完（朴素递归约 1.3s+）。
 * 只判性能与行为，不管用 map 还是迭代。
 */
const dir = process.argv[2]
if (dir === undefined) {
  console.log("FAIL 缺少工作目录参数")
  process.exit(1)
}

const test = Bun.spawnSync(["bun", "test"], { cwd: dir, stdout: "pipe", stderr: "pipe", timeout: 60_000 })
if (test.exitCode !== 0) {
  console.log(`FAIL 测试未通过：${(test.stdout.toString() + test.stderr.toString()).slice(-300)}`)
  process.exit(1)
}

const probe = `import { fib } from "./src/fib.ts"
const t0 = performance.now()
const v = fib(40)
const ms = performance.now() - t0
console.log(JSON.stringify({ v, ms }))`

const run = Bun.spawnSync(["bun", "-e", probe], { cwd: dir, stdout: "pipe", stderr: "pipe", timeout: 60_000 })
if (run.exitCode !== 0) {
  console.log(`FAIL 性能探针失败：${run.stderr.toString().slice(0, 200)}`)
  process.exit(1)
}

let out: { v: number; ms: number }
try {
  out = JSON.parse(run.stdout.toString().trim()) as { v: number; ms: number }
} catch {
  console.log(`FAIL 探针输出不是 JSON：${run.stdout.toString().slice(0, 120)}`)
  process.exit(1)
}

if (out.v !== 102334155) {
  console.log(`FAIL fib(40) = ${out.v}，应为 102334155`)
  process.exit(1)
}
if (out.ms > 300) {
  console.log(`FAIL fib(40) 用了 ${out.ms.toFixed(0)}ms（>300ms），基本是没缓存`)
  process.exit(1)
}

console.log(`PASS 测试通过，fib(40) ${out.ms.toFixed(1)}ms`)
export {}
