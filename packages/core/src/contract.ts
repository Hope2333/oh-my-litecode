/**
 * OML 内核契约 —— 平台无关。
 *
 * 公理 A5（反修）：本文件存在的理由 = 消灭「抽象绑定单一平台」这个矛盾。
 * 任何新增类型必须能回答：它让 OC 与 OC2 的哪一处重复消失？
 */

// ---------------------------------------------------------------- 系统提示

/** 提示段的身份。顺序即优先级（见 SECTION_PRIORITY）。 */
export type SectionId = "tools" | "identity" | "skillIndex" | "memory"

/** 一段可计量的提示内容。 */
export interface Section {
  id: SectionId
  text: string
  /** 该段包含的逻辑条目数（工具数 / 技能数 / 记忆条数），仅用于报告。 */
  items: number
}

/** 完整系统提示：由段拼装，而非一整块字符串。 */
export interface SystemPrompt {
  sections: Section[]
}

/**
 * 段优先级：**高 → 低**。
 * 超预算时从数组末尾开始截断，因此 memory 最先被牺牲，tools 最后。
 */
export const SECTION_PRIORITY: readonly SectionId[] = [
  "tools",
  "identity",
  "skillIndex",
  "memory",
] as const

/** 默认空闲会话预算（token）。改这个值必须同步 BUDGET.md。 */
export const DEFAULT_BUDGET_TOKENS = 8192

// ---------------------------------------------------------------- 预算报告

export interface BudgetSectionReport {
  id: SectionId
  tokens: number
  items: number
  /** 该段是否被截断 */
  truncated: boolean
}

export type BudgetStatus = "pass" | "truncated" | "fail"

export interface BudgetReport {
  totalTokens: number
  sections: BudgetSectionReport[]
  budget: {
    limit: number
    used: number
    status: BudgetStatus
  }
  /** 可见告警。截断绝不静默（反修：不隐瞒矛盾）。 */
  warnings: string[]
}

// ---------------------------------------------------------------- 技能

export interface SkillMeta {
  /** frontmatter name，缺省回退为目录名 */
  name: string
  /** frontmatter description，可能很长 */
  description: string
  /** 技能根目录 */
  root: string
  /** SKILL.md 绝对路径 */
  file: string
}

export interface SkillUsage {
  hits: number
  /** 最后一次命中的 epoch ms */
  lastUsed: number
  /** 连续未命中次数（用于降级） */
  misses: number
}

export type SkillUsageMap = Record<string, SkillUsage>

// ---------------------------------------------------------------- 代理 / 工具

export type AgentMode = "primary" | "subagent"

export interface AgentSpec {
  name: string
  description: string
  prompt: string
  model?: string
  mode?: AgentMode
  /** 允许使用的技能名；省略 = 不限制 */
  skills?: string[]
}

export interface ToolSpec {
  name: string
  description: string
  /** JSON Schema（由宿主校验） */
  schema: unknown
  handler: (args: unknown) => Promise<unknown>
}

// ---------------------------------------------------------------- 宿主

export interface ChatMessage {
  role: "user" | "assistant" | "system"
  content: string
}

/**
 * 平台宿主契约。OC 与 OC2 各自实现，适配层目标 ≤300 行。
 *
 * 公理 A4（民主集中制）：内核是唯一决策中心，宿主只做协议翻译，
 * **不得包含业务逻辑**。
 */
export interface PluginHost {
  onSessionStart(cb: () => Promise<void>): void
  onChatMessage(cb: (m: ChatMessage) => Promise<ChatMessage | void>): void
  transformSystemPrompt(cb: (p: SystemPrompt) => Promise<SystemPrompt>): void
  registerTool(t: ToolSpec): void
  registerAgent(a: AgentSpec): void
  readFile(path: string): Promise<string>
  listSkills(): Promise<SkillMeta[]>
}

// ---------------------------------------------------------------- 常量

/** 技能索引最多注入的条目数（A1：只留当前可能用到的） */
export const SKILL_INDEX_TOP = 40

/** 索引中每条触发语的最大字符数 */
export const SKILL_TRIGGER_MAX_CHARS = 40

/** 被提供（进候选索引）却未被加载多少次后，才有资格降级出索引 */
export const SKILL_DEMOTE_AFTER_MISSES = 10

/**
 * 降级命中率下限（P2·群众路线：看真实反馈，不看名头）。
 * 命中率 = hits / (hits + misses)。低于此值且被提供够多次 → 降级。
 * 推翻旧 `hits===0` 规则：一次历史命中不再是终身豁免（1 hit / 656 misses 仍应降级）。
 */
export const SKILL_MIN_HIT_RATE = 0.05

/** Hook 硬上限（A8 精兵简政） */
export const HOOK_BUDGET = 8
