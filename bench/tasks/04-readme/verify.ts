/**
 * 验收：README.md 存在，说明三个导出函数，并给出运行测试的命令。
 */
const dir = process.argv[2]
if (dir === undefined) {
  console.log("FAIL 缺少工作目录参数")
  process.exit(1)
}

const file = Bun.file(`${dir}/README.md`)
if (!(await file.exists())) {
  console.log("FAIL 没有 README.md")
  process.exit(1)
}

const text = await file.text()
const missing = ["slugify", "chunk", "clamp"].filter((n) => !text.includes(n))
if (missing.length > 0) {
  console.log(`FAIL README 未提到：${missing.join(", ")}`)
  process.exit(1)
}

// 至少要有一条可执行命令（bun test / bun run / bunx 之类）
if (!/(^|\n)\s*(```[a-z]*\n)?\s*(bun|npm|node|bunx)\s+\S+/m.test(text)) {
  console.log("FAIL README 没有给出可执行命令")
  process.exit(1)
}

console.log(`PASS README ${text.length} 字符，三个函数与命令齐备`)
export {}
