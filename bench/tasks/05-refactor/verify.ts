/**
 * 验收：测试全绿，且 a.ts / b.ts 里那段四行规范化链条只剩一处（消重成功）。
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

// 重复的识别标志：连续出现 .trim().toLowerCase() 再 replace 空白——数出现次数。
const glob = new Bun.Glob("src/**/*.ts")
let occurrences = 0
for await (const path of glob.scan({ cwd: dir })) {
  const text = await Bun.file(`${dir}/${path}`).text()
  const matches = text.match(/\.trim\(\)\s*\n?\s*\.toLowerCase\(\)\s*\n?\s*\.replace\(\/\\s\+\//g)
  occurrences += matches === null ? 0 : matches.length
}

if (occurrences > 1) {
  console.log(`FAIL 规范化链条仍出现 ${occurrences} 次（应为 1）`)
  process.exit(1)
}

console.log(`PASS 测试通过，规范化链条 ${occurrences} 处`)
export {}
