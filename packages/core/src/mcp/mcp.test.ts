import { afterAll, describe, expect, test } from "bun:test"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  EMPTY_MCP_CATALOG,
  applyMcpToHost,
  digestOf,
  enabledMcpIds,
  markMcpUsed,
  renderMcpCatalog,
  setMcpEnabled,
  suggestMcp,
  syncCatalog,
  type McpCatalog,
} from "./catalog.ts"
import { connectMcp, parseTools, renderCallResult } from "./client.ts"

const dirs: string[] = []
afterAll(async () => {
  for (const d of dirs) await rm(d, { recursive: true, force: true })
})

const SERVER = `
const respond = (id, result) => process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\\n")
const dec = new TextDecoder()
let buf = ""
for await (const chunk of Bun.stdin.stream()) {
  buf += dec.decode(chunk)
  let i = buf.indexOf("\\n")
  while (i !== -1) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1); i = buf.indexOf("\\n")
    if (line === "") continue
    const msg = JSON.parse(line)
    if (msg.method === "initialize") respond(msg.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "fake", version: "1" } })
    else if (msg.method === "tools/list") respond(msg.id, { tools: [
      { name: "echo", description: "回显", inputSchema: { type: "object" } },
      { name: "add", description: "求和", inputSchema: { type: "object" } },
    ] })
    else if (msg.method === "tools/call") {
      if (msg.params.name === "echo") respond(msg.id, { content: [{ type: "text", text: String(msg.params.arguments.text) }] })
      else if (msg.params.name === "add") respond(msg.id, { content: [{ type: "text", text: String(msg.params.arguments.a + msg.params.arguments.b) }] })
      else respond(msg.id, { content: [{ type: "text", text: "unknown tool" }], isError: true })
    } else if (msg.id !== undefined) respond(msg.id, {})
  }
}
`

async function fakeServer(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "oml-mcp-"))
  dirs.push(dir)
  const path = join(dir, "server.ts")
  await writeFile(path, SERVER, "utf8")
  return path
}

describe("MCP 目录", () => {
  const host = {
    blender: { command: ["uvx", "blender-mcp"], enabled: true },
    codegraph: { command: ["codegraph", "mcp"], enabled: true },
  }

  test("新服务器一律降级为待复核", () => {
    const r = syncCatalog(EMPTY_MCP_CATALOG, host, new Date("2026-01-01T00:00:00Z"))
    expect(r.added.sort()).toEqual(["blender", "codegraph"])
    expect(r.catalog.entries["blender"]?.enabled).toBe(false)
    expect(r.catalog.entries["blender"]?.needsReview).toBe(true)
  })

  test("定义变化触发复核并清空工具缓存", () => {
    const first = syncCatalog(EMPTY_MCP_CATALOG, host)
    const on = setMcpEnabled(first.catalog, "blender", true)
    const withTools: McpCatalog = {
      ...on,
      entries: { ...on.entries, blender: { ...on.entries["blender"]!, tools: ["x", "y"] } },
    }
    const r = syncCatalog(withTools, { ...host, blender: { command: ["uvx", "blender-mcp", "--new"] } })
    expect(r.changed).toEqual(["blender"])
    expect(r.catalog.entries["blender"]?.enabled).toBe(false)
    expect(r.catalog.entries["blender"]?.tools).toBeUndefined()
  })

  test("未变动的服务器保留启用状态", () => {
    const first = syncCatalog(EMPTY_MCP_CATALOG, host)
    const on = setMcpEnabled(first.catalog, "codegraph", true)
    const again = syncCatalog(on, host)
    expect(again.changed).toEqual([])
    expect(again.catalog.entries["codegraph"]?.enabled).toBe(true)
    expect(enabledMcpIds(again.catalog)).toEqual(["codegraph"])
  })

  test("消失的服务器标 missing 但保留条目", () => {
    const first = syncCatalog(EMPTY_MCP_CATALOG, host)
    const r = syncCatalog(first.catalog, { blender: host.blender })
    expect(r.gone).toEqual(["codegraph"])
    expect(r.catalog.entries["codegraph"]?.missing).toBe(true)
    expect(r.catalog.entries["codegraph"]?.enabled).toBe(false)
    expect(enabledMcpIds(r.catalog)).toEqual([])
  })

  test("回归：同定义不同键序 digest 相同", () => {
    const a = digestOf({ type: "local", command: ["x"], environment: { A: "1", B: "2" } })
    const b = digestOf({ type: "local", command: ["x"], environment: { B: "2", A: "1" } })
    expect(a).toBe(b)
  })

  test("按查询给候选，只从登记池里挑", () => {
    const cat = syncCatalog(EMPTY_MCP_CATALOG, {
      ...host,
      ocr: { command: ["python", "ocr/mcp_server.py"] },
    }).catalog
    expect(suggestMcp("找 blender 场景", cat, { ...host, ocr: { command: [] } })[0]?.id).toBe("blender")
    expect(suggestMcp("识别图片文字", cat, host)).toEqual([])
  })

  test("回写宿主配置只动 enabled", () => {
    const cat = setMcpEnabled(syncCatalog(EMPTY_MCP_CATALOG, host).catalog, "blender", true)
    const { config, changed } = applyMcpToHost(
      { mcp: { blender: { command: ["uvx", "blender-mcp"], enabled: false }, codegraph: { command: ["codegraph", "mcp"], enabled: false } } },
      cat,
    )
    expect(changed).toEqual(["blender"])
    expect((config["mcp"] as Record<string, { enabled?: boolean }>)["blender"]?.enabled).toBe(true)
  })

  test("渲染含状态与调用次数", () => {
    const cat = markMcpUsed(syncCatalog(EMPTY_MCP_CATALOG, host).catalog, "blender", ["echo"])
    const text = renderMcpCatalog(cat)
    expect(text).toContain("blender")
    expect(text).toContain("待复核")
    expect(text).toContain("1")
  })
})

describe("MCP 客户端（stdio 真进程）", () => {
  test("握手 → tools/list → tools/call → close", async () => {
    const path = await fakeServer()
    const session = await connectMcp("fake", { command: ["bun", path] }, { timeoutMs: 8000 })
    const tools = await session.listTools()
    expect(tools.map((t) => t.name)).toEqual(["echo", "add"])
    expect(renderCallResult(await session.callTool("echo", { text: "你好" }))).toBe("你好")
    expect(renderCallResult(await session.callTool("add", { a: 2, b: 3 }))).toBe("5")
    await session.close()
  })

  test("服务器不存在时报错且不留进程", async () => {
    await expect(connectMcp("ghost", { command: ["definitely-not-a-command-xyz"] }, { timeoutMs: 3000 })).rejects.toThrow()
  })

  test("协议面解析：非对象/无 name 的工具被丢弃", () => {
    expect(parseTools({ tools: [{ name: "a" }, { name: 1 }, null, { description: "x" }] }).map((t) => t.name)).toEqual(["a"])
    expect(parseTools({})).toEqual([])
  })
})
