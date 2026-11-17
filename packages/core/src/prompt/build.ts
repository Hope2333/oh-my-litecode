/**
 * 单一系统提示构建器 —— 全系统只有这一处拼装系统提示。
 *
 * 扬弃对象：OMO 的 4 个注入器 hook + 57 个 hook 各自往 messages/system 里塞内容。
 * 一处拼装 → 段可计数、可截断、可审计；多处注入 → 谁都不知道最终有多少。
 *
 * 段优先级（高→低）：tools > identity > skillIndex > memory。
 * 超预算时从 memory 开始砍（见 budget/assemble.ts）。
 */

import type { SkillMeta, SkillUsageMap, SystemPrompt } from "../contract.ts"
import { DEFAULT_BUDGET_TOKENS } from "../contract.ts"
import { CONTEXT_RULES } from "../context/module.ts"
import { worldviewBlock } from "./worldview.ts"
import { assemble } from "../budget/assemble.ts"
import type { AssembleResult } from "../budget/assemble.ts"
import type { AgentId, OmlConfig } from "../config/index.ts"
import { DEFAULT_CONFIG, resolveConfig } from "../config/index.ts"
import { AGENT_MAP, type AgentDef, categoryLegend } from "../agents/registry.ts"
import { buildIndex } from "../skills/index-gen.ts"
import { demoted } from "../skills/usage.ts"
import { selectSkills } from "../skills/select.ts"

/** 全局工作纪律（约 350 tok）。每一条都对应一个可观察的失败模式。 */
/** 轻约束档：五条。默认注入这一档——高兼容，不拿规则压住判断。 */
export const LIGHT_RULES = `## 工作纪律（轻）
1. 先读后改：改文件前先读它，并读一个同类文件当参照。
2. 证据先于结论：跑过、看过退出码，再说「完成」；没跑就说「未验证」。
3. 单一写入者：同一文件同一时刻只有一个执行者，并行前先划边界。
4. 消灭矛盾：新增必须说明替代了什么；说不出来就不要加。
5. 一次只做一件事；范围外的问题记录并报告。`

export const WORK_RULES = `## 工作纪律
1. 先读后改：改文件前先读它，并读一个同类文件作模式参照。未读先写是禁止的。
2. 具体问题具体分析：每个判断都要能指出依据（文件:行、命令输出、文档）。不套模板。
3. 单一写入者：同一文件同一时刻只有一个执行者；并行前先划清边界。
4. 委派不等于免责：子代理产出必须验收——文件存在？测试通过？符合既有模式？
5. 消灭矛盾：新增模块必须说明它替代了什么、删除了什么。说不出来就不要加。
6. 证据先于结论：跑命令、看退出码、贴真实输出。无证据不得声称「已完成」。
7. 禁止：any / @ts-ignore / 空 catch / 删除失败测试 / 空话开场 / 修 bug 时顺手重构。
8. 一次只做一件事。范围外的问题记录并报告，不擅自扩大。`

const TOOL_POLICY = `## 工具选择
- 定位代码：explore / grep / glob；跨模块调用链用 lsp_find_references。
- 外部事实：librarian（文档、他人实现、版本差异）。不凭记忆回答库的用法。
- 硬决策（架构、疑难 bug、取舍）：oracle，只读顾问。
- 实现：task(category=..., background=true) 交给执行者；同一时刻只保留一个活跃子代理。
- 技能：skill(name) 按需加载正文；索引里没有的也可以直接按名加载。
- 上下文吃紧：compress 压缩已消费的区间；不要压缩正在推理的内容。`

export interface BuildInput {
  /** 当前目标（来自 goal 账本）；有则进 memory 段，超预算时最先被裁 */
  readonly goal?: string | null
  config?: OmlConfig
  agentId?: AgentId
  skills?: readonly SkillMeta[]
  usage?: SkillUsageMap
  /** 当前任务文本，用于技能相关性排序；为空则按使用频率 */
  taskText?: string
  toolNames?: readonly string[]
  /** 跨会话记忆（已由调用方裁剪） */
  memory?: string
  /** 追加到 identity 段的额外文本（例如项目约定） */
  extraIdentity?: string
}

export interface BuildOutcome extends AssembleResult {
  agent: AgentDef
  /** 实际写入索引的技能（按相关性排序） */
  indexedSkills: SkillMeta[]
  sections: SystemPrompt["sections"]
}

/**
 * 构建系统提示。
 * 纯函数：不做 IO，便于测试与 bench；读写配置/文件由 CLI 与 host 负责。
 */
export function buildSystemPrompt(input: BuildInput = {}): BuildOutcome {
  const config = resolveConfig(input.config ?? {})
  const agent = AGENT_MAP.get(input.agentId ?? "sisyphus") ?? (AGENT_MAP.get("sisyphus") as AgentDef)

  const all = input.skills ?? []
  const disabled = new Set(config.disabled_skills ?? [])
  const excluded = new Set<string>([...disabled, ...demoted(input.usage ?? {})])
  const indexed = selectSkills(all, input.taskText ?? "", {
    top: config.skills?.maxIndex ?? DEFAULT_CONFIG.skills.maxIndex,
    // 只留明显相关的：弱相关条目占的是注入预算，不是注意力预算。
    // P1：从硬编码 0.1 提到默认 0.35，并可由 oml.json skills.minRelevance 覆盖。
    minRelevance: config.skills?.minRelevance ?? DEFAULT_CONFIG.skills.minRelevance,
    usage: input.usage ?? {},
    exclude: excluded,
  })

  const rules = (input.config?.constraints ?? "light") === "light" ? LIGHT_RULES : WORK_RULES
  const identityParts = [agent.prompt, rules]
  const worldview = worldviewBlock(input.config?.worldview ?? "light")
  if (worldview !== "") identityParts.push(worldview)
  identityParts.push(CONTEXT_RULES)
  if (input.extraIdentity !== undefined && input.extraIdentity.trim() !== "") {
    identityParts.push(input.extraIdentity.trim())
  }
  identityParts.push(`## 委派类别\n${categoryLegend()}`)

  // 宿主 TUI 无多语言：OML 自产内容按 language 键渲染。内置提示/技能是中文，
  // 中文时不注指令（0 收益），非中文时加一行翻译指令。
  const lang = (input.config?.language ?? "").trim()
  if (lang !== "" && lang !== "zh") {
    identityParts.push(`## 语言\n所有回复与产出物使用 ${lang}。内置技能与规则为中文，按需翻译后再输出。`)
  }

  const toolsText =
    input.toolNames === undefined || input.toolNames.length === 0
      ? TOOL_POLICY
      : `${TOOL_POLICY}\n已启用工具：${[...input.toolNames].sort().join(", ")}`

  const sections: SystemPrompt["sections"] = [
    { id: "tools", text: toolsText, items: input.toolNames?.length ?? 0 },
    { id: "identity", text: identityParts.join("\n\n"), items: 1 },
    {
      id: "skillIndex",
      text: indexed.length === 0 ? "skills[0]:" : buildIndex(indexed, input.usage ?? {}),
      items: indexed.length,
    },
    { id: "memory", text: memoryText(input), items: memoryText(input) === "" ? 0 : 1 },
  ]

  const limit = config.budget?.limit ?? DEFAULT_BUDGET_TOKENS
  // 两遍装配：第一遍量出真实占用，第二遍把「现在用了多少」写进提示。
  // 只给规则不给数字，模型无从判断何时该收——这正是「会话不主动压制上下文」的成因。
  const first = assemble(sections, limit)
  const used = first.report.totalTokens
  const pct = limit === 0 ? 0 : Math.round((used / limit) * 100)
  const status =
    pct >= 70
      ? `当前注入 ${used}/${limit} tok（${pct}%）。已过七成：先 checkpoint，再对一个明确区间做压缩，不要等到超限被动截断。`
      : `当前注入 ${used}/${limit} tok（${pct}%）。余量充足，不必提前压缩；同一话题超过两轮再考虑收。`
  const identityIndex = sections.findIndex((s) => s.id === "identity")
  const identitySection = sections[identityIndex]
  if (identitySection !== undefined) {
    // 状态行放 identity **开头**：截断从段末开始，放末尾会被第一个砍掉，
    // 而它恰恰是「现在该不该收」的唯一依据。可操作的信息优先于铺垫。
    sections[identityIndex] = { ...identitySection, text: `${status}\n\n${identitySection.text}` }
  }
  const result = assemble(sections, limit)
  return { ...result, agent, indexedSkills: indexed, sections }
}

/** memory 段：当前目标 + 显式附加记忆。两者都为空时整段为空（不占 tok）。 */
function memoryText(input: BuildInput): string {
  const parts: string[] = []
  const goal = input.goal?.trim() ?? ""
  if (goal !== "") parts.push(`## 当前目标\n${goal}`)
  const extra = input.memory?.trim() ?? ""
  if (extra !== "") parts.push(extra)
  return parts.join("\n\n")
}
