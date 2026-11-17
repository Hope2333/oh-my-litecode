/**
 * 剥离宿主注入的技能目录。
 *
 * 为什么必须由 OML 来做，而不是靠环境变量：
 *   opencode 核心的 `SkillGuidance` 会把「所有带 description 的技能」逐条写进系统提示
 *   （`<available_skills>`）。它只受进程启动时的 `OPENCODE_DISABLE_EXTERNAL_SKILLS`
 *   / `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` 影响，而这两个变量只要没进到**正在运行的
 *   那个进程**，全量目录就照旧注入——本机实测正是如此（变量在 .zshrc 与 systemd 里，
 *   运行中的 daemon env 为空）。
 *
 * 依赖外部启动参数 = 不可复现。所以 OML 在唯一的注入点把这块删掉，再写自己的索引：
 * 无论宿主装了多少技能，最终提示里只有 OML 的 `skills[N]` 表。
 */

/** opencode 核心 `fmt()` 生成的目录块，以及它前面的两行使用说明。 */
const CATALOG = /<available_skills>[\s\S]*?<\/available_skills>/g
const PREAMBLE =
  /(?:^|\n)Skills provide specialized instructions and workflows for specific tasks\.\nUse the skill tool to load a skill when a task matches its description\.\n?/g
const EMPTY_CATALOG = /(?:^|\n)Skills provide specialized instructions and workflows for specific tasks\.\nUse the skill tool to load a skill when a task matches its description\.\nNo skills are currently available\.\n?/g

export interface StripResult {
  readonly parts: string[]
  /** 是否有任何一段被改写 */
  readonly found: boolean
  readonly removedChars: number
  /** 目录里原本有多少条 <skill> */
  readonly removedSkills: number
}

export function stripSkillCatalog(parts: readonly string[]): StripResult {
  let removedChars = 0
  let removedSkills = 0
  let found = false
  const next: string[] = []

  for (const part of parts) {
    if (!part.includes("available_skills") && !part.includes("Use the skill tool to load a skill")) {
      next.push(part)
      continue
    }
    removedSkills += (part.match(/<skill>/g) ?? []).length
    const stripped = part
      .replace(EMPTY_CATALOG, "")
      .replace(CATALOG, "")
      .replace(PREAMBLE, "")
      .replace(/\n{3,}/g, "\n\n")
      .trim()
    if (stripped !== part) {
      found = true
      removedChars += part.length - stripped.length
    }
    next.push(stripped)
  }

  return { parts: next, found, removedChars, removedSkills }
}
