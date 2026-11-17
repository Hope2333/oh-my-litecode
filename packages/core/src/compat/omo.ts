/**
 * 原版 OMO 配置兼容层。
 *
 * 为什么要有：用户的 OMO 配置（`~/.config/opencode/oh-my-openagent.json`）里已经
 * 存着真实在用的模型绑定与 fallback 链（约 28KB）。重写系统不该逼用户重填一遍。
 * 这里只做「读得懂 + 能翻译」，不追求全字段兼容——不认识的一律计数上报，
 * 而不是静默忽略（静默忽略会让用户以为配置生效了）。
 */

import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { AGENT_IDS, CATEGORY_IDS, type OmlConfig } from "../config/index.ts"

export const OMO_CONFIG_PATHS: readonly string[] = [
  join(homedir(), ".config", "opencode", "oh-my-openagent.json"),
  join(homedir(), ".config", "opencode", "oh-my-opencode.jsonc"),
]

/** OMO 里存在、OML 也有对应能力的顶层键。 */
const MAPPED_KEYS = new Set(["agents", "categories", "disabled_hooks", "disabled_mcps", "skills"])

export interface OmoCompatResult {
  readonly found: boolean
  readonly path?: string
  readonly agents: number
  readonly categories: number
  readonly ignoredKeys: readonly string[]
  readonly warnings: readonly string[]
  /** 可直接合并进 OmlConfig 的部分（OML 自己的配置优先） */
  readonly config: OmlConfig
  readonly raw?: unknown
}

function stripJsonc(text: string): string {
  // 只处理行注释与尾逗号；不碰字符串内部。
  let out = ""
  let inStr = false
  let esc = false
  for (let i = 0; i < text.length; i++) {
    const ch = text[i] ?? ""
    if (inStr) {
      out += ch
      if (esc) esc = false
      else if (ch === "\\") esc = true
      else if (ch === '"') inStr = false
      continue
    }
    if (ch === '"') {
      inStr = true
      out += ch
      continue
    }
    if (ch === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") i++
      out += "\n"
      continue
    }
    out += ch
  }
  return out.replace(/,(\s*[}\]])/g, "$1")
}

function asRecord(v: unknown): Record<string, unknown> | undefined {
  return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined
}

function asStringArray(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []
}

function pickModel(v: Record<string, unknown>): { model?: string; fallback?: string[] } {
  const out: { model?: string; fallback?: string[] } = {}
  if (typeof v["model"] === "string" && v["model"] !== "") out.model = v["model"]
  const fb = asStringArray(v["fallback_models"])
  if (fb.length > 0) out.fallback = fb
  return out
}

/** 把已解析的 OMO 配置翻译成 OmlConfig 片段。纯函数，便于测试。 */
export function mapOmoConfig(raw: unknown): OmoCompatResult {
  const root = asRecord(raw)
  if (root === undefined) {
    return {
      found: true,
      agents: 0,
      categories: 0,
      ignoredKeys: [],
      warnings: ["OMO 配置不是对象，已跳过"],
      config: {},
    }
  }

  const warnings: string[] = []
  const agents: Record<string, { model?: string; fallback?: string[]; disabled?: boolean }> = {}
  const agentSrc = asRecord(root["agents"]) ?? {}
  for (const [name, value] of Object.entries(agentSrc)) {
    const v = asRecord(value)
    if (v === undefined) continue
    const mapped = pickModel(v)
    const disabled = v["disabled"] === true
    if (mapped.model === undefined && mapped.fallback === undefined && !disabled) continue
    agents[name] = { ...mapped, ...(disabled ? { disabled: true } : {}) }
  }

  const categories: Record<string, { model: string; fallback?: string[] }> = {}
  const catSrc = asRecord(root["categories"]) ?? {}
  for (const [name, value] of Object.entries(catSrc)) {
    const v = asRecord(value)
    if (v === undefined) continue
    const mapped = pickModel(v)
    // category 没有 model 就没有意义（只有 fallback 链无法起步）
    if (mapped.model === undefined) continue
    categories[name] = { model: mapped.model, ...(mapped.fallback === undefined ? {} : { fallback: mapped.fallback }) }
  }

  const ignoredKeys = Object.keys(root)
    .filter((k) => k !== "$schema" && !MAPPED_KEYS.has(k))
    .sort()

  // 不在 OML 花名册里的 agent 名：提示但不丢弃（用户可能自定义过）
  const known = new Set<string>([...AGENT_IDS])
  const unknownAgents = Object.keys(agents).filter((a) => !known.has(a))
  if (unknownAgents.length > 0) {
    warnings.push(`OMO 配置里有 OML 未内置的 agent：${unknownAgents.join(", ")}（模型绑定已保留，派发时需显式指定）`)
  }
  const knownCat = new Set<string>([...CATEGORY_IDS])
  const unknownCats = Object.keys(categories).filter((c) => !knownCat.has(c))
  if (unknownCats.length > 0) {
    warnings.push(`OMO 配置里有 OML 未内置的 category：${unknownCats.join(", ")}`)
  }

  return {
    found: true,
    agents: Object.keys(agents).length,
    categories: Object.keys(categories).length,
    ignoredKeys,
    warnings,
    config: { agents, categories },
    raw,
  }
}

/** 读盘 + 翻译。找不到文件时不报错（这是常态）。 */
export async function loadOmoCompat(paths: readonly string[] = OMO_CONFIG_PATHS): Promise<OmoCompatResult> {
  for (const path of paths) {
    let text: string
    try {
      text = await readFile(path, "utf8")
    } catch {
      continue
    }
    try {
      const parsed: unknown = JSON.parse(stripJsonc(text))
      return { ...mapOmoConfig(parsed), path }
    } catch (err) {
      return {
        found: true,
        path,
        agents: 0,
        categories: 0,
        ignoredKeys: [],
        warnings: [`OMO 配置无法解析：${err instanceof Error ? err.message : String(err)}`],
        config: {},
      }
    }
  }
  return { found: false, agents: 0, categories: 0, ignoredKeys: [], warnings: [], config: {} }
}
