import { describe, expect, test } from "bun:test"
import { selectSkills, scoreSkill, tokenize } from "./select.ts"
import type { SkillMeta, SkillUsageMap } from "../contract.ts"

function skill(name: string, description: string): SkillMeta {
  return { name, description, root: "/r", file: `/r/${name}/SKILL.md` }
}

const POOL: SkillMeta[] = [
  skill("git-master", "MUST USE for ANY git operations. Atomic commits, rebase, blame."),
  skill("frontend", "Builds and polishes anything drawn with HTML, CSS, or SVG. Styling, layout, animation."),
  skill("debugging", "Hypothesis-driven debugging loop for crashes, hangs, wrong responses."),
  skill("pdf", "Extract text, create PDFs, handle forms."),
  skill("data-scientist", "CSV parquet JSON analysis with DuckDB and Polars."),
]

describe("tokenize", () => {
  test("拉丁词保留，停用词剔除", () => {
    const t = tokenize("Fix the git rebase with a tool")
    expect(t).toContain("fix")
    expect(t).toContain("git")
    expect(t).toContain("rebase")
    expect(t).not.toContain("the")
    expect(t).not.toContain("a")
  })

  test("中文只产出二元组，不产单字（P0：单字是假相关噪音源）", () => {
    const t = tokenize("修复前端样式")
    expect(t).not.toContain("修")
    expect(t).not.toContain("前")
    expect(t).toContain("修复")
    expect(t).toContain("前端")
    expect(t).toContain("样式")
  })

  test("空文本返回空数组", () => {
    expect(tokenize("   ")).toEqual([])
  })
})

describe("scoreSkill", () => {
  test("名字命中权重高于描述命中", () => {
    const terms = tokenize("git")
    const byName = scoreSkill(POOL[0] as SkillMeta, terms)
    const byDesc = scoreSkill(skill("x", "mentions git only in description"), terms)
    expect(byName).toBeGreaterThan(byDesc)
  })
})

describe("selectSkills", () => {
  test("直呼其名的技能排第一", () => {
    const picked = selectSkills(POOL, "用 git-master 提交")
    expect(picked[0]?.name).toBe("git-master")
  })

  test("英文任务能选中 frontend（描述命中三项）", () => {
    const picked = selectSkills(POOL, "build a landing page with layout and animation")
    expect(picked[0]?.name).toBe("frontend")
  })

  test("中文任务对英文描述命不中时，回退而非报错（已知边界）", () => {
    const picked = selectSkills(POOL, "做一个落地页，调整布局和动效")
    expect(picked.length).toBe(POOL.length)
  })

  test("无相关命中时回退到使用频率，且不为空", () => {
    const usage: SkillUsageMap = { pdf: { hits: 9, lastUsed: 1, misses: 0 } }
    const picked = selectSkills(POOL, "zzz qqq", { usage })
    expect(picked.length).toBe(POOL.length)
    expect(picked[0]?.name).toBe("pdf")
  })

  test("空任务文本按使用频率排序", () => {
    const usage: SkillUsageMap = {
      debugging: { hits: 1, lastUsed: 1, misses: 0 },
      pdf: { hits: 7, lastUsed: 2, misses: 0 },
    }
    expect(selectSkills(POOL, "", { usage })[0]?.name).toBe("pdf")
  })

  test("exclude 生效", () => {
    const picked = selectSkills(POOL, "git", { exclude: ["git-master"] })
    expect(picked.some((s) => s.name === "git-master")).toBe(false)
  })

  test("中文 bugfix 任务不被无关技能的单字假命中污染（P0 回归）", () => {
    const noise = [
      skill("blender-scene-craft", "Blender 电影感三维场景制作规范——建模防穿模、材质防条纹"),
      skill("ppt-agent", "Generate visually striking PPT slides"),
      skill("systematic-debugging", "Hypothesis-driven debugging loop for crashes, hangs"),
    ]
    const picked = selectSkills(noise, "修复任务状态机的父任务 bug", { minRelevance: 0.35 })
    const names = picked.map((s) => s.name)
    // 单字「修/复/任/务」曾让 blender 得满分；去掉单字后它不应再命中。
    expect(names).not.toContain("blender-scene-craft")
    expect(names).not.toContain("ppt-agent")
  })

  test("top 截断且结果可复现", () => {
    const a = selectSkills(POOL, "git frontend pdf", { top: 2 })
    const b = selectSkills(POOL, "git frontend pdf", { top: 2 })
    expect(a.length).toBe(2)
    expect(a.map((s) => s.name)).toEqual(b.map((s) => s.name))
  })
})

describe("minRelevance", () => {
  const mk = (name: string, description: string) => ({ name, description, root: "r", file: `r/${name}/SKILL.md` })

  test("裁掉明显弱于最高分的条目", () => {
    const skills = [
      mk("frontend-design", "frontend landing page design"),
      mk("helper", "page utilities"),
    ]
    const all = selectSkills(skills, "frontend landing page", { top: 10 })
    expect(all.length).toBe(2)
    const pruned = selectSkills(skills, "frontend landing page", { top: 10, minRelevance: 0.5 })
    expect(pruned.map((s) => s.name)).toEqual(["frontend-design"])
  })

  test("最高分条目永不被裁", () => {
    const skills = [mk("only-one", "something unrelated")]
    const r = selectSkills(skills, "完全无关的查询内容", { top: 10, minRelevance: 0.9 })
    expect(r.length).toBeGreaterThanOrEqual(1)
  })
})
