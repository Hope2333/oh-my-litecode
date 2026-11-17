import { describe, expect, test } from "bun:test"
import { stripSkillCatalog } from "./strip.ts"

const REAL = [
  "You are opencode, the best coding agent.",
  "Skills provide specialized instructions and workflows for specific tasks.\nUse the skill tool to load a skill when a task matches its description.\n<available_skills>\n  <skill>\n    <name>frontend</name>\n    <description>Builds UI</description>\n  </skill>\n  <skill>\n    <name>pdf</name>\n    <description>PDF tools</description>\n  </skill>\n</available_skills>",
]

describe("stripSkillCatalog", () => {
  test("删掉目录块与使用说明，其余原文不动", () => {
    const r = stripSkillCatalog(REAL)
    expect(r.found).toBe(true)
    expect(r.removedSkills).toBe(2)
    expect(r.parts[0]).toBe("You are opencode, the best coding agent.")
    expect(r.parts[1]).toBe("")
    expect(r.parts.join("")).not.toContain("available_skills")
    expect(r.parts.join("")).not.toContain("frontend")
  })

  test("空目录形态也删干净", () => {
    const empty = ["x\nSkills provide specialized instructions and workflows for specific tasks.\nUse the skill tool to load a skill when a task matches its description.\nNo skills are currently available.\n"]
    const r = stripSkillCatalog(empty)
    expect(r.found).toBe(true)
    expect(r.parts[0]).not.toContain("No skills are currently available")
  })

  test("没有目录时原样返回且 found=false（不做无谓改写）", () => {
    const plain = ["abc", "def"]
    const r = stripSkillCatalog(plain)
    expect(r.found).toBe(false)
    expect(r.removedChars).toBe(0)
    expect(r.parts).toEqual(plain)
  })

  test("多段输入各扫各的，且不误伤 OML 自己的索引", () => {
    const r = stripSkillCatalog(["<available_skills><skill></skill></available_skills>", "skills[2]:\n- a: b"])
    expect(r.removedSkills).toBe(1)
    expect(r.parts[1]).toBe("skills[2]:\n- a: b")
  })

  test("跨段不合并：只有含关键字的段被处理", () => {
    const r = stripSkillCatalog(["keep me", "<available_skills></available_skills>", "and me"])
    expect(r.parts).toEqual(["keep me", "", "and me"])
  })
})
