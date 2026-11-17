/**
 * OML 配置：一个文件，15 个键。
 *
 * 扬弃对象：OMO 的 35 个 zod schema 文件与 11 个 background-task 旋钮。
 * 判据：旋钮多不产生控制力，只产生「配错了也不知道」。
 * 保留的每个键都在某处被真实读取——见 `grep -r "config\." packages/`。
 */

export {
  AGENT_IDS,
  CATEGORY_IDS,
  DEFAULT_CONFIG,
  type AgentId,
  type AgentOverride,
  type CategoryId,
  type ModelSpec,
  type OmlConfig,
  type TeamMember,
  type TeamProfile,
} from "./schema.ts"

import { DEFAULT_CONFIG, type ModelSpec, type OmlConfig } from "./schema.ts"

const KNOWN_KEYS = new Set([
  "$schema",
  "agents",
  "categories",
  "skills",
  "tasks",
  "budget",
  "disabled_agents",
  "disabled_skills",
  "disabled_tools",
  "disabled_hooks",
  "compat",
  "permissions",
  "language",
  "third",
  "worldview",
  "constraints",
  "models",
  "eigenflux",
  "telemetry",
])

export interface ParseResult {
  config: OmlConfig
  warnings: string[]
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v)
}

function pickNumbers(
  raw: Record<string, unknown>,
  keys: readonly string[],
  warnings: string[],
  prefix: string,
): Record<string, number> {
  const out: Record<string, number> = {}
  for (const k of keys) {
    const v = raw[k]
    if (v === undefined) continue
    if (typeof v !== "number" || !Number.isFinite(v) || v <= 0) {
      warnings.push(`${prefix}.${k} 必须是正数，已忽略`)
      continue
    }
    out[k] = v
  }
  return out
}

/**
 * 宽松解析：未知键只告警不抛错（具体问题具体分析——用户的配置不该因为
 * OML 落后一个版本就整份失效）；类型错误也降级为告警并回落默认值。
 */
export function parseConfig(raw: unknown): ParseResult {
  const warnings: string[] = []
  if (raw === undefined || raw === null) return { config: {}, warnings }
  if (!isRecord(raw)) return { config: {}, warnings: ["配置根必须是对象，已忽略整份配置"] }

  const config: OmlConfig = {}
  for (const key of Object.keys(raw)) {
    if (!KNOWN_KEYS.has(key)) warnings.push(`未知配置键 "${key}"，已忽略（拼写错误？）`)
  }

  if (isRecord(raw["agents"])) config.agents = raw["agents"] as OmlConfig["agents"]
  else if (raw["agents"] !== undefined) warnings.push("agents 必须是对象")

  if (isRecord(raw["categories"])) config.categories = raw["categories"] as OmlConfig["categories"]
  else if (raw["categories"] !== undefined) warnings.push("categories 必须是对象")

  if (isRecord(raw["models"])) config.models = raw["models"] as unknown as OmlConfig["models"]
  else if (raw["models"] !== undefined) warnings.push("models 必须是对象")

  if (isRecord(raw["compat"])) config.compat = raw["compat"] as OmlConfig["compat"]
  else if (raw["compat"] !== undefined) warnings.push("compat 必须是对象")

  if (isRecord(raw["skills"])) {
    const s = raw["skills"]
    const roots = Array.isArray(s["roots"]) ? s["roots"].filter((x): x is string => typeof x === "string") : undefined
    const nums = pickNumbers(s, ["maxIndex", "minRelevance"], warnings, "skills")
    config.skills = { ...(roots === undefined ? {} : { roots }), ...nums }
  } else if (raw["skills"] !== undefined) warnings.push("skills 必须是对象")

  if (isRecord(raw["tasks"])) {
    config.tasks = pickNumbers(raw["tasks"], ["concurrency", "maxDepth", "ttlMs"], warnings, "tasks")
  } else if (raw["tasks"] !== undefined) warnings.push("tasks 必须是对象")

  if (isRecord(raw["budget"])) {
    config.budget = pickNumbers(raw["budget"], ["limit"], warnings, "budget")
  } else if (raw["budget"] !== undefined) warnings.push("budget 必须是对象")

  if (raw["models"] !== undefined) {
    if (!isRecord(raw["models"])) {
      warnings.push("models 必须是对象")
    } else {
      const m = raw["models"]
      const spec: ModelSpec = { model: "" }
      if (typeof m["model"] === "string") spec.model = m["model"]
      else warnings.push("models.model 必须是字符串（provider/model）")
      const nums = pickNumbers(m, ["temperature", "maxTokens"], warnings, "models")
      Object.assign(spec, nums)
      if (Array.isArray(m["fallback"])) {
        const fb = m["fallback"].filter((x): x is string => typeof x === "string")
        if (fb.length > 0) spec.fallback = fb
      } else if (m["fallback"] !== undefined) warnings.push("models.fallback 必须是字符串数组")
      config.models = spec
    }
  }

  if (raw["eigenflux"] !== undefined) {
    if (!isRecord(raw["eigenflux"])) {
      warnings.push("eigenflux 必须是对象")
    } else {
      const e = raw["eigenflux"]
      const eig: NonNullable<OmlConfig["eigenflux"]> = {}
      if (e["proactive"] !== undefined) {
        if (typeof e["proactive"] === "boolean") eig.proactive = e["proactive"]
        else warnings.push("eigenflux.proactive 必须是布尔值")
      }
      config.eigenflux = eig
    }
  }

  if (raw["compat"] !== undefined) {
    if (!isRecord(raw["compat"])) {
      warnings.push("compat 必须是对象")
    } else {
      const c = raw["compat"]
      const compat: NonNullable<OmlConfig["compat"]> = {}
      for (const k of ["taskAlias", "skillTool", "nativeSkills"] as const) {
        if (c[k] !== undefined) {
          if (typeof c[k] === "boolean") compat[k] = c[k]
          else warnings.push(`compat.${k} 必须是布尔值`)
        }
      }
      config.compat = compat
    }
  }

  for (const key of ["disabled_agents", "disabled_skills", "disabled_tools", "disabled_hooks"] as const) {
    const v = raw[key]
    if (v === undefined) continue
    if (!Array.isArray(v)) {
      warnings.push(`${key} 必须是字符串数组`)
      continue
    }
    config[key] = v.filter((x): x is string => typeof x === "string")
  }

  if (raw["language"] !== undefined) {
    if (typeof raw["language"] === "string" && raw["language"].trim() !== "") config.language = raw["language"].trim()
    else warnings.push('language 必须是非空字符串（如 "zh" / "en"，省略默认 "zh"）')
  }

  if (raw["worldview"] !== undefined) {
    const v = raw["worldview"]
    if (v === "off" || v === "light" || v === "full") config.worldview = v
    else warnings.push('worldview 只能是 "off" / "light" / "full"')
  }

  if (raw["constraints"] !== undefined) {
    const v = raw["constraints"]
    if (v === "light" || v === "standard") config.constraints = v
    else warnings.push('constraints 只能是 "light" / "standard"')
  }

  if (raw["permissions"] !== undefined) {
    if (typeof raw["permissions"] === "boolean") config.permissions = raw["permissions"]
    else warnings.push("permissions 必须是布尔值（true=主代理全放行，false=每次询问）")
  }

  if (raw["third"] !== undefined) {
    const t = raw["third"]
    if (typeof t === "object" && t !== null && !Array.isArray(t)) {
      config.third = {}
      if ((t as Record<string, unknown>)["autoUpgrade"] !== undefined) {
        if (typeof (t as Record<string, unknown>)["autoUpgrade"] === "boolean") config.third.autoUpgrade = (t as Record<string, boolean>)["autoUpgrade"]
        else warnings.push("third.autoUpgrade 必须是布尔值（默认 true）")
      }
    } else if (t !== undefined) {
      warnings.push("third 必须是对象 { autoUpgrade: boolean }")
    }
  }

  if (raw["telemetry"] === true) warnings.push("telemetry=true 被拒绝：OML 不收集任何遥测（公理 A7）")
  else if (raw["telemetry"] !== undefined) config.telemetry = false

  return { config, warnings }
}

/** 深合并用户配置与默认值；数组整体替换而非拼接（拼接会制造「删不掉」）。 */
export function resolveConfig(partial: OmlConfig): OmlConfig {
  return {
    ...partial,
    skills: { ...DEFAULT_CONFIG.skills, ...partial.skills },
    tasks: { ...DEFAULT_CONFIG.tasks, ...partial.tasks },
    budget: { ...DEFAULT_CONFIG.budget, ...partial.budget },
    telemetry: false,
  }
}

export const CONFIG_FILENAME = "oml.json"

/** 纯读，不含 IO：调用方决定从哪里取文本（便于测试与 CLI 复用）。 */
export function parseConfigText(text: string): ParseResult {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return { config: {}, warnings: [`配置不是合法 JSON：${msg}`] }
  }
  return parseConfig(raw)
}
