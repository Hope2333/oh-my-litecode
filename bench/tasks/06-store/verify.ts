/**
 * 验收：不看实现，只验行为。API 在 README 里钉死，所以可以直接 import。
 */
import { spawnSync } from "node:child_process"
import { existsSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const work = process.argv[2]
if (!work) {
  console.log("FAIL 缺少工作目录")
  process.exit(1)
}

const testRun = spawnSync("bun", ["test"], { cwd: work, encoding: "utf8" })
if (testRun.status !== 0) {
  console.log(`FAIL 测试未通过\n${(testRun.stdout ?? "").slice(-800)}`)
  process.exit(1)
}
if (!existsSync(join(work, "tests", "store.test.ts"))) {
  console.log("FAIL 缺少 tests/store.test.ts")
  process.exit(1)
}

const probeDir = mkdtempSync(join(tmpdir(), "oml-store-"))
const file = join(probeDir, "db.json")
const probe = `
import { createStore } from ${JSON.stringify(join(work, "src", "store.ts"))}
const s = createStore(${JSON.stringify(file)})
s.set("a", "1")
if (s.get("a") !== "1") throw new Error("set/get 不一致")
if (s.del("b") !== false) throw new Error("del(不存在的键) 应为 false")
s.save()
const s2 = createStore(${JSON.stringify(file)})
s2.load()
if (s2.get("a") !== "1") throw new Error("重开后数据丢失")
if (s2.del("a") !== true) throw new Error("del(存在的键) 应为 true")
const s3 = createStore(${JSON.stringify(join(probeDir, "none.json"))})
s3.load()
console.log("PROBE_OK")
`
const p = spawnSync("bun", ["-e", probe], { encoding: "utf8" })
rmSync(probeDir, { recursive: true, force: true })
if (p.status !== 0 || !(p.stdout ?? "").includes("PROBE_OK")) {
  console.log(`FAIL 行为探针未通过\n${(p.stderr ?? "").slice(-800)}`)
  process.exit(1)
}

const count = (testRun.stdout ?? "").match(/(\d+) pass/)
console.log(`OK 测试通过（${count?.[1] ?? "?"} 个 case），行为探针通过`)
export {}
