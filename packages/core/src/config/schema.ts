/**
 * OML 配置的形状与默认值。
 *
 * 从 index.ts 拆出：契约（有哪些键、默认多少）与解析（怎么读、怎么告警）分居两文件，
 * 让「改默认值」和「改容错策略」不会互相踩。
 */

export const AGENT_IDS = [
  "sisyphus",
  "prometheus",
  "atlas",
  "sisyphus-junior",
  "oracle",
  "librarian",
  "explore",
  "momus",
] as const
export type AgentId = (typeof AGENT_IDS)[number]

export const CATEGORY_IDS = [
  "quick",
  "deep-low",
  "deep-high",
  "ultrabrain",
  "visual-engineering",
  "writing",
] as const
export type CategoryId = (typeof CATEGORY_IDS)[number]

export interface ModelSpec {
  /** provider/model，例如 "anthropic/claude-sonnet-4" */
  model: string
  /** 推理等级（宿主的 model variant，例如 low/medium/high/max）；缺省=宿主默认 */
  variant?: string
  temperature?: number
  maxTokens?: number
  /** 主模型不可用时按序尝试；只保留一层回退 */
  fallback?: string[]
}

export interface AgentOverride extends Partial<ModelSpec> {
  disabled?: boolean
}

/** 团队模板的一个成员。`task` 是给这个成员的固定 brief（可被调用方覆盖）。 */
export interface TeamMember {
  readonly role: string
  readonly agent?: string
  readonly category?: string
  readonly model?: string
  readonly task?: string
}

/**
 * 特制团队：把「哪个角色、什么模型、能碰哪些工具」写死在配置里，
 * 而不是每轮让模型现编。
 *
 * 为什么需要：通用 category 只回答「多难」，不回答「谁来做、拿什么做」。
 * 真实工作里这两件事都要钉死，否则同一句提示词每次派出去的班子都不一样。
 */
export interface TeamProfile {
  readonly description: string
  readonly members: readonly TeamMember[]
  readonly mode?: "parallel" | "pipeline"
  /**
   * 允许成员使用的内置工具名。**提示级约束**：会写进成员 brief 并记录在任务上；
   * 真正的沙箱需要在宿主侧为每个 agent 生成 tools 白名单（见 docs/design/omo-v2.md）。
   */
  readonly tools?: readonly string[]
  /** 这队人需要的 MCP。当前只做记录与提醒：MCP 装载属于宿主配置，切换需重启。 */
  readonly mcp?: readonly string[]
}

export interface OmlConfig {
  $schema?: string
  agents?: Record<string, AgentOverride>
  categories?: Record<string, ModelSpec>
  skills?: {
    roots?: string[]
    /** 注入索引的条数上限，默认 40 */
    maxIndex?: number
    /**
     * 相对相关性下限（0–1）：只保留「明显强于本轮最高分」的技能。默认 0.35。
     * P1（2026-11-17）：旧值 0.1 形同虚设（best=10→floor=1，26 条全过）。
     * 提高后弱相关条目不再占注入预算；漏判可恢复（skill(name) 直载）。
     */
    minRelevance?: number
  }
  tasks?: {
    concurrency?: number
    maxDepth?: number
    ttlMs?: number
  }
  budget?: {
    /** 系统提示 token 上限，默认 8192 */
    limit?: number
  }
  /** 特制团队模板：`omo_task action=team team=<名字>` 直接调用。 */
  teams?: Record<string, TeamProfile>
  disabled_agents?: string[]
  disabled_skills?: string[]
  disabled_tools?: string[]
  disabled_hooks?: string[]
  /** 与旧 OMO 的兼容开关；关掉旧 OMO 后才建议打开。 */
  compat?: {
    /** 额外注册名为 `task` 的工具（等价于 omo_task）。默认关，避免同名互撞。 */
    taskAlias?: boolean
    /** 额外注册名为 `skill` 的工具（按需读取技能正文，替代原生技能目录）。默认开。 */
    skillTool?: boolean
    /** 保留 OpenCode 原生技能目录（会把全部技能的描述塞进系统提示）。默认关。 */
    nativeSkills?: boolean
  }
  /** 全局默认模型（最低优先级）。子代理/类别未配置时用它。 */
  models?: ModelSpec
  /**
   * 界面/输出语言（第 17 键，默认 "zh"）。宿主 TUI（OpenCode 1.x/2.x）没有多语言
   * 显示：OML 自产的内容（系统提示、技能正文、命令说明、任务/团队/交接文案）
   * 全部按这个键渲染。新建项目时 `omo install` 会把它写进 .opencode/oml.json，
   * 走宿主 commands 面板可改。宿主自身的 UI 文案不归 OML 管（那是宿主 i18n 的事）。
   */
  language?: string

  /**
   * 3rd systems（第 18 键）：内置三方系统（ACP 引擎 + TUI 件）的自动升级开关，
   * 默认 **true**（用户决策）。设 false = 只在 omo upgrade 里报告，不自动装/升。
   */
  third?: { autoUpgrade?: boolean }

  /**
   * 权限策略（第 16 键）：宿主插件注册 permission.ask 钩子，默认「主代理全放行」。
   * true（默认，省略即 true）：权限请求一律 output.status="allow"，编排流水线不被打断。
   * false：不注册该钩子，回到宿主默认「每次询问」流程（commands 面板里逐条配）。
   * 语义是「默认放行 + 一个开关」，不是细粒度矩阵——矩阵属于宿主的配置系统，
   * OML 不重造它（A8）。
   */
  permissions?: boolean
  /**
   * 世界观层。默认 "light"——轻约束、高兼容，不说明也生效。
   * "off" 时系统提示里不出现这一节；"full" 多三条（阶段论/统一战线/判断权）。
   */
  worldview?: "off" | "light" | "full"
  /** 工作纪律档位。默认 "light"（五条），"standard" 才注入完整八条。 */
  constraints?: "light" | "standard"

  /** 恒为 false；存在只是为了在配置里显式表达「不要遥测」 */
  telemetry?: false
}

export const DEFAULT_CONFIG: Required<Pick<OmlConfig, "skills" | "tasks" | "budget">> = {
  skills: { maxIndex: 40, minRelevance: 0.35 },
  tasks: { concurrency: 3, maxDepth: 2, ttlMs: 30 * 60_000 },
  budget: { limit: 8192 },
}
