/**
 * host 注入基准：不启 OpenCode，直接跑真实的 createHostCore + system.transform，
 * 度量「OML 真正塞进 system 的那一段」有多少 token。
 *
 * 与 bench/prompt.ts 的区别：那个测纯函数拼装；这个测宿主接线后的实际产物。
 */
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { estimateTokens } from "@oml/core"
import { createHostCore } from "../OC/omo/src/host.ts"
import type { TaskClient } from "../OC/omo/src/client.ts"

const client: TaskClient = {
  async createSession() {
    return { id: "ses_bench" }
  },
  async renameSession() {},
  async promptSession() {
    return { text: "" }
  },
  async abortSession() {},
  async lastAssistantText() {
    return ""
  },
}

const dir = await mkdtemp(join(tmpdir(), "omo-bench-"))
const skillsRoot = join(dir, "skills")
for (const name of ["frontend", "debugging", "git-master"]) {
  const d = join(skillsRoot, name)
  await mkdir(d, { recursive: true })
  await writeFile(
    join(d, "SKILL.md"),
    `---\nname: ${name}\ndescription: ${name} workflow for real tasks.\n---\n\n# ${name}\n`,
    "utf8",
  )
}

const hooks = await createHostCore(
  { directory: dir, client },
  { skillRoots: [skillsRoot], stateDir: join(dir, "state") },
)

const output = { system: ["<opencode 基础提示，此处不计入>"] }
const t0 = performance.now()
await hooks["experimental.chat.system.transform"]!({ model: {} as never }, output)
const ms = performance.now() - t0

const injected = output.system[1] ?? ""
const tokens = estimateTokens(injected)
const limit = 8192
const budgetMs = 50

console.log(`注入段字符数: ${injected.length}`)
console.log(`注入段 tokens: ${tokens}`)
console.log(`上限 tokens: ${limit}`)
console.log(`余量: ${limit - tokens}`)
console.log(`transform 耗时: ${ms.toFixed(2)}ms（预算 ${budgetMs}ms）`)

await rm(dir, { recursive: true, force: true })

if (tokens > limit) {
  console.error(`FAIL 注入段 ${tokens} tok 超过上限 ${limit}`)
  process.exit(1)
}
if (ms > budgetMs) {
  console.error(`FAIL transform ${ms.toFixed(2)}ms 超过预算 ${budgetMs}ms`)
  process.exit(1)
}
// 真实技能根（非确定，仅作诚实参考；门禁用 fixture 保证可复现）
if (process.argv.includes("--real")) {
  const realHooks = await createHostCore({ directory: dir, client }, { stateDir: join(dir, "state-real") })
  const realOut = { system: [] as string[] }
  await realHooks["experimental.chat.system.transform"]!({ model: {} as never }, realOut)
  const realInjected = realOut.system[0] ?? ""
  console.log(`真实技能根注入: ${estimateTokens(realInjected)} tok（${realInjected.length} 字符）`)
}

console.log("PASS host 注入在预算内")
