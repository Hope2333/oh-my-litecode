/**
 * MCP 目录：全量登记、默认禁用、按需启用。
 *
 * 扬弃对象：宿主把每个 MCP 的工具 schema 无条件注入系统提示（8 个 MCP ≈ 150 个
 * 工具定义，实测约 27K tok）。这里把「登记」和「加载」拆开：
 *
 *   - 目录（本文件）记录**有哪些服务器、值不值得用、上次用过没**，不产生注入；
 *   - 真正的调用走 `client.ts`（按需拉起进程、用完销毁），宿主侧一律 `enabled:false`。
 *
 * 自检规则（用户要求「更新或新装时自己维护条目」）：
 *   - 新服务器 → `enabled:false` + `needsReview:true`，等代理看完描述再决定；
 *   - 定义变化（digest 不同）→ 同样降级为待复核，并清空 `tools` 缓存；
 *   - 消失的服务器 → 条目保留但标 `missing:true`，不静默删除（数据比结论重要）。
 */

import { createHash } from "node:crypto"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { statePath } from "../paths.ts"

/** 宿主 opencode.json 里 `mcp[id]` 的形状（只取我们关心的字段）。 */
export interface McpDef {
  type?: "local" | "remote"
  command?: readonly string[]
  url?: string
  enabled?: boolean
  environment?: Readonly<Record<string, string>>
  headers?: Readonly<Record<string, string>>
}

export interface McpEntry {
  id: string
  kind: "local" | "remote"
  /** 定义的指纹；变化即触发复核 */
  digest: string
  enabled: boolean
  /** 新装或定义变了，等代理核过再启用 */
  needsReview: boolean
  /** 定义已从宿主配置里消失 */
  missing?: boolean
  calls: number
  lastUsedAt?: string
  checkedAt?: string
  /** 上次 tools/list 的工具名（自检缓存，避免每次重连） */
  tools?: readonly string[]
  note?: string
}

export interface McpCatalog {
  version: 1
  entries: Record<string, McpEntry>
  updatedAt: string
}

export const EMPTY_MCP_CATALOG: McpCatalog = { version: 1, entries: {}, updatedAt: "1970-01-01T00:00:00.000Z" }

export function mcpCatalogPath(): string {
  return statePath("mcp.json")
}

export function digestOf(def: McpDef): string {
  const stable = JSON.stringify({
    type: def.type ?? "local",
    command: def.command ?? [],
    url: def.url ?? "",
    // 值统一成字符串：宿主配置里 "9876" 与 9876 是同一个定义，
    // 若按类型比对，OML 自己回写一次 enabled 就会误判「定义变了」。
    environment: Object.entries(def.environment ?? {})
      .map(([k, v]) => [k, String(v)] as const)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
    headers: Object.entries(def.headers ?? {})
      .map(([k, v]) => [k, String(v)] as const)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
  })
  return createHash("sha256").update(stable).digest("hex").slice(0, 16)
}

export interface SyncResult {
  catalog: McpCatalog
  added: string[]
  changed: string[]
  gone: string[]
  unchanged: number
}

/**
 * 用宿主配置刷新目录。**只改元数据，不碰 enabled**——除了新增与定义变化这两种
 * 「必须复核」的情况，届时强制降级为禁用。
 */
export function syncCatalog(
  catalog: McpCatalog,
  hostDefs: Readonly<Record<string, McpDef>>,
  now: Date = new Date(),
): SyncResult {
  const stamp = now.toISOString()
  const entries: Record<string, McpEntry> = {}
  const added: string[] = []
  const changed: string[] = []
  let unchanged = 0

  for (const [id, def] of Object.entries(hostDefs)) {
    const digest = digestOf(def)
    const prev = catalog.entries[id]
    if (prev === undefined) {
      added.push(id)
      entries[id] = {
        id,
        kind: def.type === "remote" ? "remote" : "local",
        digest,
        enabled: false,
        needsReview: true,
        calls: 0,
        checkedAt: stamp,
      }
      continue
    }
    if (prev.digest !== digest) {
      changed.push(id)
      entries[id] = {
        ...prev,
        kind: def.type === "remote" ? "remote" : "local",
        digest,
        enabled: false,
        needsReview: true,
        missing: false,
        tools: undefined,
        checkedAt: stamp,
      }
      continue
    }
    unchanged += 1
    entries[id] = { ...prev, missing: false, checkedAt: stamp }
  }

  const gone: string[] = []
  for (const [id, prev] of Object.entries(catalog.entries)) {
    if (hostDefs[id] !== undefined) continue
    gone.push(id)
    entries[id] = { ...prev, missing: true, enabled: false }
  }

  return { catalog: { version: 1, entries, updatedAt: stamp }, added, changed, gone, unchanged }
}

export function setMcpEnabled(catalog: McpCatalog, id: string, enabled: boolean, now: Date = new Date()): McpCatalog {
  const prev = catalog.entries[id]
  if (prev === undefined) return catalog
  return {
    ...catalog,
    updatedAt: now.toISOString(),
    entries: { ...catalog.entries, [id]: { ...prev, enabled, needsReview: enabled ? false : prev.needsReview } },
  }
}

export function markMcpUsed(catalog: McpCatalog, id: string, tools?: readonly string[], now: Date = new Date()): McpCatalog {
  const prev = catalog.entries[id]
  if (prev === undefined) return catalog
  return {
    ...catalog,
    updatedAt: now.toISOString(),
    entries: {
      ...catalog.entries,
      [id]: { ...prev, calls: prev.calls + 1, lastUsedAt: now.toISOString(), ...(tools === undefined ? {} : { tools }) },
    },
  }
}

export function enabledMcpIds(catalog: McpCatalog): string[] {
  return Object.values(catalog.entries)
    .filter((e) => e.enabled && e.missing !== true)
    .map((e) => e.id)
    .sort()
}

/** 按查询挑候选（只在已登记且未禁用的池子里挑；返回 id 与理由）。 */
export function suggestMcp(
  query: string,
  catalog: McpCatalog,
  hostDefs: Readonly<Record<string, McpDef>>,
  limit = 3,
): Array<{ id: string; reason: string }> {
  const terms = new Set(
    query
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter((t) => t.length >= 2),
  )
  const scored: Array<{ id: string; score: number; reason: string }> = []
  for (const entry of Object.values(catalog.entries)) {
    if (entry.missing === true) continue
    const def = hostDefs[entry.id]
    if (def === undefined) continue
    // 名称、命令、已缓存工具名都算证据
    const haystack = [entry.id, ...(def.command ?? []), ...(entry.tools ?? [])].join(" ").toLowerCase()
    let score = 0
    for (const t of terms) if (haystack.includes(t)) score += 1
    if (score === 0) continue
    scored.push({ id: entry.id, score, reason: `命中 ${score} 个关键词` })
  }
  scored.sort((a, b) => b.score - a.score || (a.id < b.id ? -1 : 1))
  return scored.slice(0, limit).map(({ id, reason }) => ({ id, reason }))
}

export function renderMcpCatalog(catalog: McpCatalog): string {
  const rows = Object.values(catalog.entries).sort((a, b) => (a.id < b.id ? -1 : 1))
  if (rows.length === 0) return "MCP 目录为空（先跑 omo mcp sync 或 omo_admin action=mcp op=sync）"
  const lines = ["id".padEnd(18) + "状态".padEnd(10) + "调用  最近使用            工具"]
  for (const e of rows) {
    const state = e.missing === true ? "已移除" : e.enabled ? "启用" : e.needsReview ? "待复核" : "禁用"
    const used = e.lastUsedAt === undefined ? "-" : e.lastUsedAt.slice(0, 16).replace("T", " ")
    const tools = e.tools === undefined ? "-" : String(e.tools.length)
    lines.push(`${e.id.padEnd(18)}${state.padEnd(10)}${String(e.calls).padEnd(6)}${used.padEnd(20)}${tools}`)
  }
  return lines.join("\n")
}

/**
 * 把目录的启用状态写回宿主配置（opencode.json 的 `mcp[id].enabled`）。
 * 返回新配置与真正发生变化的 id；调用方负责落盘与备份。
 */
export function applyMcpToHost(
  hostConfig: Record<string, unknown>,
  catalog: McpCatalog,
): { config: Record<string, unknown>; changed: string[] } {
  const mcp = hostConfig["mcp"]
  if (typeof mcp !== "object" || mcp === null) return { config: hostConfig, changed: [] }
  const servers = { ...(mcp as Record<string, unknown>) }
  const changed: string[] = []
  for (const entry of Object.values(catalog.entries)) {
    const raw = servers[entry.id]
    if (typeof raw !== "object" || raw === null) continue
    const server = raw as Record<string, unknown>
    const want = entry.enabled && entry.missing !== true
    if (server["enabled"] === want) continue
    servers[entry.id] = { ...server, enabled: want }
    changed.push(entry.id)
  }
  return { config: { ...hostConfig, mcp: servers }, changed }
}

export async function loadMcpCatalog(path: string = mcpCatalogPath()): Promise<McpCatalog> {
  try {
    const raw = JSON.parse(await readFile(path, "utf8")) as Partial<McpCatalog>
    const entries: Record<string, McpEntry> = {}
    const source = typeof raw.entries === "object" && raw.entries !== null ? raw.entries : {}
    for (const [id, e] of Object.entries(source as Record<string, McpEntry>)) {
      if (typeof e !== "object" || e === null) continue
      entries[id] = {
        id,
        kind: e.kind === "remote" ? "remote" : "local",
        digest: typeof e.digest === "string" ? e.digest : "",
        enabled: e.enabled === true,
        needsReview: e.needsReview === true,
        ...(e.missing === true ? { missing: true } : {}),
        calls: typeof e.calls === "number" ? e.calls : 0,
        ...(typeof e.lastUsedAt === "string" ? { lastUsedAt: e.lastUsedAt } : {}),
        ...(typeof e.checkedAt === "string" ? { checkedAt: e.checkedAt } : {}),
        ...(Array.isArray(e.tools) ? { tools: e.tools.filter((t): t is string => typeof t === "string") } : {}),
        ...(typeof e.note === "string" ? { note: e.note } : {}),
      }
    }
    return {
      version: 1,
      entries,
      updatedAt: typeof raw.updatedAt === "string" ? raw.updatedAt : EMPTY_MCP_CATALOG.updatedAt,
    }
  } catch {
    return EMPTY_MCP_CATALOG
  }
}

let mcpSaveSeq = 0

export async function saveMcpCatalog(next: McpCatalog, path: string = mcpCatalogPath()): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  // 临时名带序号：启动自检与显式 sync 可能并发写，同名 tmp 会互相抢 rename。
  const tmp = `${path}.${process.pid}.${++mcpSaveSeq}.tmp`
  await writeFile(tmp, `${JSON.stringify(next, null, 2)}\n`, "utf8")
  try {
    await rename(tmp, path)
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err
    await mkdir(dirname(path), { recursive: true })
    await writeFile(tmp, `${JSON.stringify(next, null, 2)}\n`, "utf8")
    await rename(tmp, path)
  }
}
