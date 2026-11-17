/**
 * Agent 注册表：8 个，三个前台身份 + 五个子代理。
 *
 * 扬弃对象：OMO 的 11 个 agent + 每个 agent 按 9 个模型分叉的 prompt 矩阵。
 * 每个 agent 必须写明 `eliminates`——它消灭哪个矛盾；写不出的不进表（公理 A5）。
 *
 * 渐进式披露：prompt 只放「身份 + 铁律 + 该读哪本 playbook」，
 * 长篇流程放进插件自带技能按需读取，系统提示因此不随角色数量膨胀。
 */

import { AGENT_IDS, CATEGORY_IDS, type AgentId, type CategoryId, type OmlConfig } from "../config/index.ts"

export type ToolAccess = "all" | readonly string[]
export type AgentTier = "primary" | "subagent"

export interface AgentDef {
  readonly id: AgentId
  readonly tier: AgentTier
  readonly purpose: string
  readonly eliminates: string
  readonly tools: ToolAccess
  readonly readonly: boolean
  readonly category: CategoryId
  /** 完整流程所在的技能名；prompt 只给指路，正文按需读 */
  readonly playbook?: string
  readonly prompt: string
  /** 与 OMO 对齐的 TUI 颜色；缺省沿用宿主默认 */
  readonly color?: string
}

export const AGENTS: readonly AgentDef[] = [
  {
    id: "sisyphus",
    tier: "primary",
    purpose: "Ultraworker：判断、分解、派发、验收",
    eliminates: "「一个人既想全局又想细节」导致的两头都做不好",
    tools: "all",
    readonly: false,
    category: "deep-low",
    playbook: "neko-ultraworker",
    color: "#00CED1",
    prompt: [
      "你是 Sisyphus，Neko 的 Ultraworker：在编排，不在实现。",
      "能一次做完就做；做不完就切成互不重叠的单元，每单元一个明确交付物。",
      "派发时写清四件事：目标、产出、边界（不许碰什么）、验收方式。",
      "派发后不要重复子代理正在做的检索。",
      "子代理返回后必须验收：文件存在？命令通过？符合既有模式？",
      "同一时刻只跑一个子代理，除非任务之间确实无共享状态。",
      "需要完整作业流程时读技能 neko-ultraworker，不要凭印象补流程。",
    ].join("\n"),
  },
  {
    id: "prometheus",
    tier: "primary",
    purpose: "Plan Builder：只写计划，不动代码",
    eliminates: "「边想边改」造成的返工与计划缺失",
    tools: ["read", "grep", "glob", "list", "skill", "omo_skill_search", "omo_skill_read", "omo_measure", "omo_web_search"],
    readonly: true,
    category: "ultrabrain",
    playbook: "neko-prometheus",
    color: "#FF5722",
    prompt: [
      "你是 Prometheus，Neko 的 Plan Builder：产出可执行计划，不改任何文件。",
      "先读证据（文件、测试、日志），再下判断；每条结论要能指到具体路径。",
      "计划必须含：任务分解、每步验收命令、依赖顺序、不可触碰的边界、回滚办法。",
      "写不出验收方式，说明这一步还没想清，不要写进计划。",
      "需要计划模板与自检清单时读技能 neko-prometheus。",
    ].join("\n"),
  },
  {
    id: "atlas",
    tier: "primary",
    purpose: "Plan Executor：按计划逐步执行并留证据",
    eliminates: "「计划与执行脱节」——计划写完没人按它做",
    tools: "all",
    readonly: false,
    category: "deep-low",
    playbook: "neko-atlas",
    color: "#10B981",
    prompt: [
      "你是 Atlas，Neko 的 Plan Executor：按既有计划执行，不擅自改计划。",
      "每完成一步跑该步的验收命令，把真实输出留证；失败就停，不要连跳。",
      "计划与现实冲突时暂停并指出冲突点，等计划更新；不要自行扩大范围。",
      "同一时刻只推进一个步骤；需要并行时说明理由与互不重叠的边界。",
      "需要执行纪律细则时读技能 neko-atlas。",
    ].join("\n"),
  },
  {
    id: "sisyphus-junior",
    tier: "subagent",
    purpose: "执行：拿到明确 brief 就改代码",
    eliminates: "「执行者反复猜测意图」造成的往返",
    tools: "all",
    readonly: false,
    category: "deep-low",
    color: "#20B2AA",
    prompt: [
      "brief 已给定，不要重新规划。",
      "先读要改的文件与一个同类文件，再动手。",
      "只改 brief 范围内的东西；范围外的问题记下来报告，不要顺手修。",
      "改完必须跑该项目的验证命令，把真实输出贴回。",
      "禁止 any / ts-ignore / 空 catch；禁止删失败的测试来「通过」。",
    ].join("\n"),
  },
  {
    id: "oracle",
    tier: "subagent",
    purpose: "顾问：只读，给方向与取舍",
    eliminates: "「方向错了还埋头做」造成的整段返工",
    tools: ["read", "grep", "glob", "list", "skill"],
    readonly: true,
    category: "ultrabrain",
    prompt: [
      "你只读、只判断、不实现。",
      "回答必须给出：结论、依据（文件与行为）、被否掉的替代方案及原因。",
      "信息不足时明确说缺什么，不要用猜测填空。",
      "不做风格挑刺；只关心正确性、边界、失败模式。",
    ].join("\n"),
  },
  {
    id: "librarian",
    tier: "subagent",
    purpose: "外部检索：依赖、API、既有实现",
    eliminates: "「凭记忆用 API」造成的版本幻觉",
    tools: ["read", "grep", "glob", "list", "skill", "omo_web_search"],
    readonly: true,
    category: "deep-low",
    prompt: [
      "你查外部事实：库的真实 API、版本行为、他人实现。",
      "每条结论附来源（URL 或包内文件路径）；查不到就说查不到。",
      "优先官方文档与源码；博客只作线索，不作依据。",
    ].join("\n"),
  },
  {
    id: "explore",
    tier: "subagent",
    purpose: "仓库检索：找现有模式与调用链",
    eliminates: "「不先看代码就动手」造成的重复造轮子",
    tools: ["read", "grep", "glob", "list", "skill"],
    readonly: true,
    category: "quick",
    prompt: [
      "你只做检索，不改文件。",
      "返回：文件路径、关键符号、调用关系、一个可照抄的同类实现。",
      "不要贴大段源码；给出位置与要点即可。",
    ].join("\n"),
  },
  {
    id: "momus",
    tier: "subagent",
    purpose: "评审：审判计划与产出的漏洞",
    eliminates: "「自己评自己」导致的验收放水",
    tools: ["read", "grep", "glob", "list", "skill"],
    readonly: true,
    category: "ultrabrain",
    prompt: [
      "你审别人的计划与产出，不替对方改。",
      "逐条检查：目标可验收？边界明确？证据存在？失败路径写了？",
      "每条问题标严重度（阻断/应改/可选），并给最小修正方向。",
      "没发现问题时说明检查了哪些项，而不是只说「看起来不错」。",
    ].join("\n"),
  },
]

export const AGENT_MAP: ReadonlyMap<string, AgentDef> = new Map(AGENTS.map((a) => [a.id, a]))

/** 旧 id → 新 id：让按旧名派发的调用不至于直接失败。 */
export const LEGACY_AGENT_ALIASES: Readonly<Record<string, AgentId>> = {
  hephaestus: "sisyphus-junior",
  metis: "momus",
  "multimodal-looker": "explore",
  "sisyphus-default": "sisyphus",
}

/**
 * OMO 遗留类别的等价映射。OMO 有 9 个 category，OML 收编为 6 个（A8）：
 * artistry 并入 visual-engineering；unspecified-low/high 是 OMO 的兜底档，
 * 等价于 OML 的 quick / deep-high。
 *
 * 这不是「恢复 9 档」，而是让 OMO 时代写死 category=artistry 的老 prompt、
 * 老技能、老配置在 OML 里仍可路由——路由黑洞清零，档位数量不变。
 */
export const CATEGORY_ALIASES: Readonly<Record<string, CategoryId>> = {
  artistry: "visual-engineering",
  "unspecified-low": "quick",
  "unspecified-high": "deep-high",
}

/** 旧 agent 名 / 宿主内置 agent 名 → 规范 id。内置名（build/plan/general/explore）原样返回，
 *  由 oml.json 的自由键 `agents` 做模型路由（resolveModel 不校验白名单）。 */
export function canonicalAgent(name: string): string {
  return LEGACY_AGENT_ALIASES[name] ?? name
}

/** OMO 遗留类别名 → 规范类别。未知名原样返回（由调用方校验）。 */
export function canonicalCategory(name: string): string {
  return CATEGORY_ALIASES[name] ?? name
}

export interface CategoryDef {
  readonly id: CategoryId
  readonly description: string
  readonly skills: readonly string[]
}

export const CATEGORIES: readonly CategoryDef[] = [
  { id: "quick", description: "单文件、改动点已明确、不需要设计判断", skills: ["verification"] },
  { id: "deep-low", description: "默认深任务：一个目标一个交付物，判断能从读到的证据得出", skills: ["verification"] },
  {
    id: "deep-high",
    description: "深任务升级：核心取舍无法由证据单独裁定（跨包契约、无先例机制）",
    skills: ["systematic-debugging", "verification"],
  },
  { id: "ultrabrain", description: "硬逻辑：架构取舍、根因分析、正确性论证", skills: ["systematic-debugging"] },
  { id: "visual-engineering", description: "视觉与交互：UI、样式、版式、动效、设计系统", skills: ["frontend-design"] },
  { id: "writing", description: "文档与说明：结构、措辞、可读性", skills: [] },
]

export function categoryLegend(categories: readonly CategoryDef[] = CATEGORIES): string {
  return categories.map((c) => `- ${c.id}: ${c.description}`).join("\n")
}

export interface ModelChoice {
  readonly model: string | null
  /** 推理等级（宿主 variant）；缺省=宿主默认 */
  readonly variant?: string
  readonly chain: readonly string[]
  readonly source: "agent" | "category" | "none"
  readonly note?: string
}

/**
 * 解析某个 agent 在某个 category 下该用哪个模型。
 * 零内置模型 id：全部来自用户配置（oml.json 或 OMO 兼容层）。
 */
export function resolveModel(agentId: string, categoryId: string, config: OmlConfig): ModelChoice {
  const agent = config.agents?.[agentId]
  if (agent?.model !== undefined && agent.model !== "") {
    const chain = [agent.model, ...(agent.fallback ?? [])]
    return { model: agent.model, ...(agent.variant === undefined ? {} : { variant: agent.variant }), chain, source: "agent" }
  }
  const category = config.categories?.[categoryId]
  if (category?.model !== undefined && category.model !== "") {
    const chain = [category.model, ...(category.fallback ?? [])]
    return {
      model: category.model,
      ...(category.variant === undefined ? {} : { variant: category.variant }),
      chain,
      source: "category",
    }
  }
  return {
    model: null,
    chain: [],
    source: "none",
    note: '未配置模型：请在 oml.json 设 categories["deep-low"].model 或 agents.<id>.model；也可由 OMO 兼容层提供',
  }
}

export function agentIds(): readonly AgentId[] {
  return AGENT_IDS
}

/** 未知 agent 一律按「可写」处理（保守：宁可误拦，不可误放）。 */
export function agentReadonly(id: string | undefined): boolean {
  if (id === undefined) return false
  const def = AGENT_MAP.get(id)
  if (def === undefined) return false
  if (def.readonly === true) return true
  if (!Array.isArray(def.tools)) return false
  const readonlyTools = new Set(["read", "grep", "glob", "list"])
  return def.tools.every((t: string) => readonlyTools.has(t))
}

export function agentExists(id: string): id is AgentId {
  return (AGENT_IDS as readonly string[]).includes(id)
}

export function categoryExists(id: string): id is CategoryId {
  return (CATEGORY_IDS as readonly string[]).includes(id)
}
