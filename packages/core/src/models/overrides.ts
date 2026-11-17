/**
 * 运行中模型分配（热分配）。
 *
 * 层次（后者覆盖前者）：models.default → categories.<cat>.model → agents.<id>.model → 运行中 override。
 * override 落 stateDir/model-overrides.json，只影响**之后新建**的子会话；
 * 已经在跑的子会话不会被改名——那会破坏它自己的上下文。
 */

import { existsSync } from "node:fs"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { AgentOverride, ModelSpec, OmlConfig } from "../config/index.ts"
import { statePath } from "../paths.ts"

export type ModelTarget = `agent:${string}` | `category:${string}` | "default"

export interface ModelOverrides {
  readonly version: 1
  readonly default?: string
  readonly agents: Readonly<Record<string, string>>
  readonly categories: Readonly<Record<string, string>>
}

export const EMPTY_OVERRIDES: ModelOverrides = { version: 1, agents: {}, categories: {} }

export function overridesPath(): string {
  return statePath("model-overrides.json")
}

export async function loadOverrides(path = overridesPath()): Promise<ModelOverrides> {
  if (!existsSync(path)) return EMPTY_OVERRIDES
  try {
    const raw: unknown = JSON.parse(await readFile(path, "utf8"))
    if (typeof raw !== "object" || raw === null) return EMPTY_OVERRIDES
    const o = raw as Record<string, unknown>
    const agents = sanitize(o["agents"])
    const categories = sanitize(o["categories"])
    return typeof o["default"] === "string" && o["default"] !== ""
      ? { version: 1, default: o["default"], agents, categories }
      : { version: 1, agents, categories }
  } catch {
    return EMPTY_OVERRIDES
  }
}

function sanitize(v: unknown): Record<string, string> {
  if (typeof v !== "object" || v === null) return {}
  const out: Record<string, string> = {}
  for (const [k, val] of Object.entries(v as Record<string, unknown>)) {
    if (typeof val === "string" && val.trim() !== "") out[k] = val
  }
  return out
}

export async function saveOverrides(next: ModelOverrides, path = overridesPath()): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const tmp = `${path}.${process.pid}.tmp`
  await writeFile(tmp, `${JSON.stringify(next, null, 2)}\n`, "utf8")
  await rename(tmp, path)
}

/** 返回新对象；model 为 null 表示删除该层 override。非法 target 返回原对象。 */
export function setOverride(
  prev: ModelOverrides,
  target: string,
  model: string | null,
): { overrides: ModelOverrides; ok: boolean; reason?: string } {
  const value = model === null ? null : model.trim()
  if (value !== null && !/^[\w.-]+\/[\w.:@-]+$/.test(value)) {
    return { overrides: prev, ok: false, reason: `模型 id 形状应为 provider/model，收到：${model ?? ""}` }
  }
  if (target === "default") {
    const { default: _drop, ...rest } = prev
    return {
      overrides: value === null ? rest : { ...rest, default: value },
      ok: true,
    }
  }
  const m = /^(agent|category):(.+)$/.exec(target)
  if (m === null) return { overrides: prev, ok: false, reason: `target 应为 agent:<id> / category:<id> / default，收到：${target}` }
  const field = m[1] === "agent" ? "agents" : "categories"
  const key = m[2] ?? ""
  const table = { ...prev[field] }
  if (value === null) delete table[key]
  else table[key] = value
  return { overrides: { ...prev, [field]: table }, ok: true }
}

export interface EffectiveModel {
  readonly model: string | null
  /** 推理等级（宿主 variant）；缺省=宿主默认 */
  readonly variant?: string
  readonly source: "override" | "agent" | "category" | "default" | "none"
  readonly chain: readonly string[]
  readonly note?: string
}

/**
 * 决定一个子任务该用哪个模型。
 * chain 是「依次尝试」的候选列表（首个即 model）；空表示交给宿主默认。
 */
export function effectiveModel(input: {
  readonly overrides: ModelOverrides
  readonly config: OmlConfig
  readonly agentId?: string
  readonly categoryId?: string
  readonly explicit?: string
}): EffectiveModel {
  const { overrides, config, agentId, categoryId, explicit } = input
  if (explicit !== undefined && explicit !== "") {
    return { model: explicit, source: "override", chain: [explicit], note: "调用方显式指定" }
  }
  if (agentId !== undefined && overrides.agents[agentId] !== undefined) {
    return { model: overrides.agents[agentId]!, source: "override", chain: [overrides.agents[agentId]!], note: `热分配 agent:${agentId}` }
  }
  if (categoryId !== undefined && overrides.categories[categoryId] !== undefined) {
    return {
      model: overrides.categories[categoryId]!,
      source: "override",
      chain: [overrides.categories[categoryId]!],
      note: `热分配 category:${categoryId}`,
    }
  }
  const agent: AgentOverride | undefined = agentId === undefined ? undefined : config.agents?.[agentId]
  if (agent?.model !== undefined) {
    return {
      model: agent.model,
      ...(agent.variant === undefined ? {} : { variant: agent.variant }),
      source: "agent",
      chain: [agent.model, ...(agent.fallback ?? [])],
    }
  }
  const cat: ModelSpec | undefined = categoryId === undefined ? undefined : config.categories?.[categoryId]
  if (cat?.model !== undefined) {
    return {
      model: cat.model,
      ...(cat.variant === undefined ? {} : { variant: cat.variant }),
      source: "category",
      chain: [cat.model, ...(cat.fallback ?? [])],
    }
  }
  if (overrides.default !== undefined) {
    return { model: overrides.default, source: "override", chain: [overrides.default], note: "热分配 default" }
  }
  if (config.models?.model !== undefined) {
    return {
      model: config.models.model,
      ...(config.models.variant === undefined ? {} : { variant: config.models.variant }),
      source: "default",
      chain: [config.models.model, ...(config.models.fallback ?? [])],
    }
  }
  return {
    model: null,
    source: "none",
    chain: [],
    note: '未配置：请在 oml.json 设 models.model、categories["deep-low"].model 或 agents.<id>.model',
  }
}
