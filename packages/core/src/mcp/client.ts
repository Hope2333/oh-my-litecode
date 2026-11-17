/**
 * 最小 MCP 客户端：按需拉起、用完销毁。
 *
 * 为什么要自己实现而不是靠宿主：宿主在启动时加载 MCP 并把工具 schema 全量注入，
 * 「禁用」要重启宿主才生效。OML 要的是「现在要用 blender，用一次就还回去」，
 * 所以把服务器当成**子进程**管：initialize → tools/list → tools/call → close。
 *
 * 只实现 MCP 协议的最小闭合集：initialize / notifications/initialized /
 * tools/list / tools/call。不做 resources / prompts / sampling——用不到的协议面是负债。
 */

import type { McpDef } from "./catalog.ts"

export interface McpToolInfo {
  name: string
  description?: string
  inputSchema?: unknown
}

export interface McpSession {
  readonly id: string
  listTools(): Promise<McpToolInfo[]>
  callTool(name: string, args: unknown): Promise<unknown>
  close(): Promise<void>
}

export interface ConnectOptions {
  /** 单次 JSON-RPC 超时（默认 15s；冷启动慢的服务器可调大） */
  timeoutMs?: number
}

export class McpError extends Error {}

interface Transport {
  request(method: string, params?: unknown): Promise<unknown>
  notify(method: string): void
  close(): Promise<void>
}

interface Pending {
  resolve(value: unknown): void
  reject(err: Error): void
  timer: ReturnType<typeof setTimeout>
}

function frame(obj: unknown): string {
  return `${JSON.stringify(obj)}\n`
}

export function parseTools(result: unknown): McpToolInfo[] {
  const tools = (result as { tools?: unknown } | undefined)?.tools
  if (!Array.isArray(tools)) return []
  const out: McpToolInfo[] = []
  for (const raw of tools) {
    if (typeof raw !== "object" || raw === null) continue
    const t = raw as { name?: unknown; description?: unknown; inputSchema?: unknown }
    if (typeof t.name !== "string") continue
    out.push({
      name: t.name,
      ...(typeof t.description === "string" ? { description: t.description } : {}),
      ...(t.inputSchema === undefined ? {} : { inputSchema: t.inputSchema }),
    })
  }
  return out
}

/** stdio 传输：newline-delimited JSON-RPC。 */
function stdioTransport(id: string, def: McpDef, timeoutMs: number): Transport {
  const command = def.command ?? []
  if (command.length === 0) throw new McpError(`MCP ${id} 没有 command`)
  const proc = Bun.spawn([...command], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, ...(def.environment ?? {}) },
  })

  const pending = new Map<number, Pending>()
  let nextId = 1
  let buffer = ""
  let closed = false

  const failAll = (err: Error): void => {
    for (const p of pending.values()) {
      clearTimeout(p.timer)
      p.reject(err)
    }
    pending.clear()
  }

  void (async () => {
    const decoder = new TextDecoder()
    try {
      for await (const chunk of proc.stdout) {
        buffer += decoder.decode(chunk as Uint8Array, { stream: true })
        let index = buffer.indexOf("\n")
        while (index !== -1) {
          const line = buffer.slice(0, index).trim()
          buffer = buffer.slice(index + 1)
          index = buffer.indexOf("\n")
          if (line === "") continue
          let msg: { id?: number; result?: unknown; error?: { message?: string } }
          try {
            msg = JSON.parse(line) as typeof msg
          } catch {
            continue // 服务器往 stdout 打日志是常态，不当错误
          }
          if (msg.id === undefined) continue // 通知忽略
          const p = pending.get(msg.id)
          if (p === undefined) continue
          pending.delete(msg.id)
          clearTimeout(p.timer)
          if (msg.error !== undefined) p.reject(new McpError(`MCP ${id}: ${msg.error.message ?? "未知错误"}`))
          else p.resolve(msg.result)
        }
      }
    } catch {
      // 进程被杀时读循环结束，统一交给 failAll
    }
    failAll(new McpError(`MCP ${id} 提前退出（exit ${proc.exitCode ?? "?"}）`))
  })()

  const write = (payload: string): void => {
    proc.stdin.write(payload)
    proc.stdin.flush()
  }

  return {
    request(method, params) {
      if (closed) return Promise.reject(new McpError(`MCP ${id} 已关闭`))
      const idNum = nextId++
      return new Promise<unknown>((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(idNum)
          reject(new McpError(`MCP ${id} ${method} 超时 ${timeoutMs}ms`))
        }, timeoutMs)
        pending.set(idNum, { resolve, reject, timer })
        try {
          write(frame({ jsonrpc: "2.0", id: idNum, method, ...(params === undefined ? {} : { params }) }))
        } catch (err) {
          clearTimeout(timer)
          pending.delete(idNum)
          reject(new McpError(`MCP ${id} 写入失败: ${err instanceof Error ? err.message : String(err)}`))
        }
      })
    },
    notify(method) {
      try {
        write(frame({ jsonrpc: "2.0", method }))
      } catch {
        // 通知失败不影响主流程
      }
    },
    async close() {
      if (closed) return
      closed = true
      try {
        proc.stdin.end()
      } catch {
        // 已关闭
      }
      proc.kill()
      const timer = setTimeout(() => proc.kill(9), 300)
      await proc.exited
      clearTimeout(timer)
      failAll(new McpError(`MCP ${id} 已关闭`))
    },
  }
}

/** streamable-HTTP 传输：POST JSON-RPC；服务器给 mcp-session-id 就带回。 */
function httpTransport(id: string, def: McpDef, timeoutMs: number): Transport {
  const url = def.url
  if (url === undefined || url === "") throw new McpError(`MCP ${id} 没有 url`)
  let sessionId: string | undefined
  let nextId = 1

  const post = async (body: unknown, expectResponse: boolean): Promise<unknown> => {
    const headers: Record<string, string> = {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      ...(def.headers ?? {}),
      ...(sessionId === undefined ? {} : { "mcp-session-id": sessionId }),
    }
    const res = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    })
    const sid = res.headers.get("mcp-session-id")
    if (sid !== null) sessionId = sid
    if (!expectResponse) return undefined
    if (!res.ok) throw new McpError(`MCP ${id} HTTP ${res.status}`)
    const text = await res.text()
    const payload = text.includes("data:") ? (text.split("data:").pop() ?? "").trim() : text.trim()
    if (payload === "") return undefined
    const parsed = JSON.parse(payload) as { result?: unknown; error?: { message?: string } }
    if (parsed.error !== undefined) throw new McpError(`MCP ${id}: ${parsed.error.message ?? "未知错误"}`)
    return parsed.result
  }

  return {
    request(method, params) {
      return post({ jsonrpc: "2.0", id: nextId++, method, ...(params === undefined ? {} : { params }) }, true)
    },
    notify(method) {
      void post({ jsonrpc: "2.0", method }, false).catch(() => undefined)
    },
    async close() {
      // 无长连接可关；会话由服务器超时回收
    },
  }
}

/**
 * 连接一个 MCP 服务器并完成握手。
 *
 * 握手失败立刻 close，不留孤儿进程——进程泄漏和目录泄漏一样，会变成僵尸农场。
 */
export async function connectMcp(id: string, def: McpDef, opts: ConnectOptions = {}): Promise<McpSession> {
  const timeoutMs = opts.timeoutMs ?? 15_000
  const transport = def.type === "remote" ? httpTransport(id, def, timeoutMs) : stdioTransport(id, def, timeoutMs)
  try {
    await transport.request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "oml", version: "0.1.0" },
    })
    transport.notify("notifications/initialized")
    return {
      id,
      async listTools() {
        return parseTools(await transport.request("tools/list"))
      },
      async callTool(name, args) {
        return await transport.request("tools/call", { name, arguments: args ?? {} })
      },
      async close() {
        await transport.close()
      },
    }
  } catch (err) {
    await transport.close()
    throw err
  }
}

/** 渲染 tools/call 的返回：MCP 的 content 是数组，直接 JSON 化给模型看。 */
export function renderCallResult(result: unknown): string {
  const content = (result as { content?: unknown } | undefined)?.content
  if (Array.isArray(content)) {
    const parts: string[] = []
    for (const item of content) {
      if (typeof item !== "object" || item === null) continue
      const c = item as { type?: unknown; text?: unknown; data?: unknown; mimeType?: unknown }
      if (c.type === "text" && typeof c.text === "string") parts.push(c.text)
      else if (c.type === "image") parts.push(`[图片 ${String(c.mimeType ?? "?")}，${String(c.data).length} B]`)
      else parts.push(JSON.stringify(item))
    }
    return parts.join("\n")
  }
  return JSON.stringify(result)
}
