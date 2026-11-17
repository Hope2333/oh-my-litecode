/**
 * OC2 前线的真机等价测试。
 *
 * 2.x 未发布（见 dialect.ts 的上游探测），所以这里验证的是**当前能验证的部分**：
 * 给定一个 OC1/OC2 同形的 input，适配层能装配出与 OC 前线同构的钩子集合，
 * 且系统提示确实被 OML 接管。2.x 发布后，这些断言应当全部继续成立。
 */

import { afterAll, describe, expect, test } from "bun:test"
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { createOc2Host } from "./host.ts"
import { toV1Input } from "./dialect.ts"

const dirs: string[] = []

async function scaffold(): Promise<{ dir: string; stateDir: string; skillRoots: string[] }> {
  const dir = await mkdtemp(join(tmpdir(), "oml-oc2-"))
  dirs.push(dir)
  const skillsRoot = join(dir, "skills")
  await mkdir(join(skillsRoot, "demo"), { recursive: true })
  await writeFile(
    join(skillsRoot, "demo", "SKILL.md"),
    "---\nname: demo\ndescription: 演示技能，用于验证索引与正文读取\n---\n\n正文\n",
    "utf8",
  )
  return { dir, stateDir: join(dir, "state"), skillRoots: [skillsRoot] }
}

afterAll(async () => {
  for (const d of dirs) await rm(d, { recursive: true, force: true })
})

describe("createOc2Host", () => {
  test("缺少 directory 时立刻抛错，而不是带半个上下文跑起来", () => {
    expect(() => toV1Input({ client: {} })).toThrow(/directory/)
  })

  test("缺少 client 时立刻抛错", () => {
    expect(() => toV1Input({ directory: "/tmp" })).toThrow(/client/)
  })

  test("装配出的钩子与 OC 前线同构，且带 5 个工具", async () => {
    const { dir, stateDir, skillRoots } = await scaffold()
    const hooks = await createOc2Host({ directory: dir, client: {} }, { skillRoots, stateDir, config: {} })

    expect(Object.keys(hooks).sort()).toEqual(
      ["chat.message", "config", "event", "experimental.chat.system.transform", "experimental.session.compacting", "permission.ask", "tool"].sort(),
    )
    expect(Object.keys(hooks["tool"] ?? {}).sort()).toEqual(
      ["omo_admin", "omo_knowledge", "omo_mcp", "omo_task", "skill"].sort(),
    )
  })

  test("系统提示被 OML 接管（注入标记 + 剥离宿主技能目录）", async () => {
    const { dir, stateDir, skillRoots } = await scaffold()
    const hooks = await createOc2Host({ directory: dir, client: {} }, { skillRoots, stateDir, config: {} })
    const output = { system: ["base", "<available_skills>\n- 一堆不该出现的技能\n</available_skills>"] }
    await hooks["experimental.chat.system.transform"]!({ model: {} as never }, output)

    const joined = output.system.join("\n")
    expect(joined).toContain("<!-- omo:system -->")
    expect(joined).not.toContain("一堆不该出现的技能")
  })
})
