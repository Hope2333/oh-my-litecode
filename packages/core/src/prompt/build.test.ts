import { describe, expect, test } from "bun:test"
import { buildSystemPrompt } from "./build.ts"
import type { SkillMeta, SkillUsageMap } from "../contract.ts"

function skill(i: number): SkillMeta {
  return {
    name: `skill-${String(i).padStart(3, "0")}`,
    description: `第 ${i} 个技能的触发语，用于测试索引预算。`,
    root: "/r",
    file: `/r/skill-${i}/SKILL.md`,
  }
}

describe("buildSystemPrompt", () => {
  test("默认构建：四段有序，总量在 8192 以内", () => {
    const out = buildSystemPrompt()
    expect(out.sections.map((s) => s.id)).toEqual(["tools", "identity", "skillIndex", "memory"])
    expect(out.report.totalTokens).toBeLessThanOrEqual(8192)
    expect(out.report.budget.status).toBe("pass")
    expect(out.prompt).toContain("## identity")
    expect(out.prompt).toContain("先读后改")
    expect(out.agent.id).toBe("sisyphus")
  })

  test("291 个技能时索引只取 40 条，且总量仍受控", () => {
    const skills = Array.from({ length: 291 }, (_, i) => skill(i))
    const out = buildSystemPrompt({ skills })
    expect(out.indexedSkills.length).toBe(40)
    const idx = out.report.sections.find((s) => s.id === "skillIndex")
    expect(idx?.items).toBe(40)
    expect(out.report.totalTokens).toBeLessThanOrEqual(8192)
  })

  test("任务文本决定索引内容", () => {
    const skills = [
      skill(1),
      { name: "git-master", description: "git 提交与变基", root: "/r", file: "/r/g/SKILL.md" },
      skill(2),
    ]
    const out = buildSystemPrompt({ skills, taskText: "用 git-master 提交" })
    expect(out.indexedSkills[0]?.name).toBe("git-master")
  })

  test("disabled_skills 与已降级技能都不进索引", () => {
    const skills = [skill(1), skill(2), skill(3)]
    const usage: SkillUsageMap = { "skill-002": { hits: 0, lastUsed: 1, misses: 10 } }
    const out = buildSystemPrompt({ skills, usage, config: { disabled_skills: ["skill-001"] } })
    const names = out.indexedSkills.map((s) => s.name)
    expect(names).not.toContain("skill-001")
    expect(names).not.toContain("skill-002")
    expect(names).toContain("skill-003")
  })

  test("超预算时先牺牲 memory，tools 段保留", () => {
    const out = buildSystemPrompt({ memory: "记忆".repeat(2000), config: { budget: { limit: 1200 } } })
    expect(out.report.budget.status).not.toBe("pass")
    const tools = out.report.sections.find((s) => s.id === "tools")
    const memory = out.report.sections.find((s) => s.id === "memory")
    expect(tools?.truncated).toBe(false)
    expect(memory?.truncated).toBe(true)
    expect(out.prompt).toContain("工具选择")
  })

  test("同一输入两次构建结果一致", () => {
    const a = buildSystemPrompt({ skills: [skill(1), skill(2)], taskText: "技能" })
    const b = buildSystemPrompt({ skills: [skill(1), skill(2)], taskText: "技能" })
    expect(a.prompt).toBe(b.prompt)
    expect(a.report.totalTokens).toBe(b.report.totalTokens)
  })

  test("可按 agent 定制身份段", () => {
    const out = buildSystemPrompt({ agentId: "oracle" })
    expect(out.agent.id).toBe("oracle")
    expect(out.prompt).toContain("你只读")
  })

  test("未知 agentId 回落到 sisyphus", () => {
    const out = buildSystemPrompt({ agentId: "nope" as never })
    expect(out.agent.id).toBe("sisyphus")
  })

  test("上下文管理默认展开，并带上真实占用数字", () => {
    const out = buildSystemPrompt({ agentId: "sisyphus", skills: [], config: {} })
    expect(out.prompt).toContain("## 上下文管理")
    expect(out.prompt).toMatch(/当前注入 \d+\/\d+ tok（\d+%）/)
  })

  test("占用过半时给出「先 checkpoint 再压缩」的明确指令", () => {
    // 用极小预算逼出高档位：identity 优先级高，tools 永不裁，所以占用必然接近上限。
    const out = buildSystemPrompt({ agentId: "sisyphus", skills: [], config: { budget: { limit: 1200 } } })
    const pct = out.report.totalTokens / 1200
    expect(pct).toBeGreaterThanOrEqual(0.7)
    expect(out.prompt).toContain("已过七成")
    expect(out.prompt).toContain("checkpoint")
  })
})

describe("language：TUI 无多语言，OML 自产内容按语言键渲染", () => {
  test("默认/zh 不注指令（内置即中文，0 收益不注）", () => {
    for (const cfg of [undefined, { language: "zh" }]) {
      const out = buildSystemPrompt({ agentId: "sisyphus", skills: [], ...(cfg === undefined ? {} : { config: cfg }) })
      expect(out.prompt).not.toContain("## 语言")
    }
  })

  test("language=en 注入一行翻译指令", () => {
    const out = buildSystemPrompt({ agentId: "sisyphus", skills: [], config: { language: "en" } })
    expect(out.prompt).toContain("## 语言")
    expect(out.prompt).toContain("使用 en")
  })
})

describe("世界观层与轻约束", () => {
  test("默认注入 light 世界观（不说明也生效）", () => {
    const out = buildSystemPrompt({ agentId: "sisyphus", skills: [], config: {} })
    expect(out.prompt).toContain("## 世界观（判断纪律，不是事实来源）")
    expect(out.prompt).toContain("抓主要矛盾")
    expect(out.prompt).toContain("反修防修")
    expect(out.prompt).toContain("蛊惑")
    expect(out.prompt).toContain("## 工作纪律（轻）")
  })

  test("worldview=off 时不注入；constraints=standard 时回到八条", () => {
    const off = buildSystemPrompt({ agentId: "sisyphus", skills: [], config: { worldview: "off", constraints: "standard" } })
    expect(off.prompt).not.toContain("## 世界观")
    expect(off.prompt).toContain("## 工作纪律")
    expect(off.prompt).not.toContain("## 工作纪律（轻）")
  })

  test("full 档多出阶段论/统一战线/判断权三条", () => {
    const out = buildSystemPrompt({ agentId: "sisyphus", skills: [], config: { worldview: "full" } })
    expect(out.prompt).toContain("阶段论")
    expect(out.prompt).toContain("统一战线")
  })

  test("预算被压到极小时，状态行仍然活着（它是最该活的那行）", () => {
    const out = buildSystemPrompt({ agentId: "sisyphus", skills: [], config: { budget: { limit: 900 } } })
    expect(out.prompt).toMatch(/当前注入 \d+\/900 tok/)
  })
})
