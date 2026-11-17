/**
 * `omo mcp`：MCP 目录的离线管理（不开会话也能改）。
 *
 * 与会话内的 `omo_admin action=mcp` 共用同一份策略（syncCatalog / applyMcpToHost），
 * 差别只在入口：这里是终端，那边是代理。默认 dry-run 的只有 enable/disable 的回写？
 * 不——**都真写**，但每次都先备份宿主配置，并在输出里给出备份路径。
 */

import { readFile, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { homedir } from "node:os"
import {
  applyMcpToHost,
  loadMcpCatalog,
  mcpCatalogPath,
  renderMcpCatalog,
  saveMcpCatalog,
  setMcpEnabled,
  syncCatalog,
  type McpDef,
} from "@oml/core"

const HOST_CONFIG = join(homedir(), ".config/opencode/opencode.json")

async function readHost(): Promise<{ text: string; raw: Record<string, unknown>; defs: Record<string, McpDef> }> {
  const text = await readFile(HOST_CONFIG, "utf8")
  const raw = JSON.parse(text) as Record<string, unknown>
  const defs: Record<string, McpDef> = {}
  const mcp = raw["mcp"]
  if (typeof mcp === "object" && mcp !== null) {
    for (const [id, value] of Object.entries(mcp as Record<string, unknown>)) {
      if (typeof value !== "object" || value === null) continue
      const d = value as Record<string, unknown>
      const command = Array.isArray(d["command"])
        ? d["command"].filter((x): x is string => typeof x === "string")
        : undefined
      defs[id] = {
        type: d["type"] === "remote" ? "remote" : "local",
        ...(command === undefined ? {} : { command }),
        ...(typeof d["url"] === "string" ? { url: d["url"] } : {}),
        ...(typeof d["enabled"] === "boolean" ? { enabled: d["enabled"] } : {}),
      }
    }
  }
  return { text, raw, defs }
}

export async function runMcp(argv: readonly string[]): Promise<number> {
  const sub = argv[0] ?? "list"
  const catalog = await loadMcpCatalog(mcpCatalogPath())

  if (sub === "list") {
    console.log(renderMcpCatalog(catalog))
    return 0
  }

  if (sub === "sync") {
    const { defs } = await readHost()
    const r = syncCatalog(catalog, defs)
    await saveMcpCatalog(r.catalog, mcpCatalogPath())
    console.log(
      `同步 ${Object.keys(defs).length} 个：新增 ${r.added.length}、变化 ${r.changed.length}、消失 ${r.gone.length}、未变 ${r.unchanged}`,
    )
    for (const id of r.added) console.log(`  新增 ${id}（默认禁用，待复核）`)
    for (const id of r.changed) console.log(`  变化 ${id}（已降级禁用，待复核）`)
    for (const id of r.gone) console.log(`  消失 ${id}（条目保留，标 missing）`)
    return 0
  }

  if (sub === "enable" || sub === "disable") {
    const id = argv[1] ?? ""
    if (id === "") {
      console.error("用法：omo mcp enable|disable <id>")
      return 2
    }
    if (catalog.entries[id] === undefined) {
      console.error(`没有登记 [${id}]；先跑 omo mcp sync`)
      return 1
    }
    const next = setMcpEnabled(catalog, id, sub === "enable")
    await saveMcpCatalog(next, mcpCatalogPath())
    const { text, raw } = await readHost()
    const applied = applyMcpToHost(raw, next)
    if (applied.changed.length > 0) {
      const stamp = new Date().toISOString().replace(/[:.]/g, "-")
      await writeFile(`${HOST_CONFIG}.bak-mcp-${stamp}`, text, "utf8")
      await writeFile(HOST_CONFIG, `${JSON.stringify(applied.config, null, 2)}\n`, "utf8")
      console.log(`已${sub === "enable" ? "启用" : "禁用"} [${id}]；回写 ${applied.changed.join(", ")}（备份 ${HOST_CONFIG}.bak-mcp-${stamp}）`)
    } else {
      console.log(`[${id}] 宿主配置已是目标状态，未改动`)
    }
    console.log("重启宿主后生效；会话内可直接用 omo_mcp 拉起。")
    return 0
  }

  console.error("用法：omo mcp [list|sync|enable <id>|disable <id>]")
  return 2
}
