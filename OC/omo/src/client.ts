/**
 * 窄客户端：把 @opencode-ai/sdk 的宽泛形状收敛成 OML 实际用到的四件事。
 *
 * 存在的理由：直接在宿主里对 SDK 做结构化断言，会在 SDK 小版本漂移时静默失效。
 * 这里只保留 create/prompt/abort/messages，映射函数在编译期校验字段。
 */
import type { PluginInput } from "@opencode-ai/plugin"

export type PromptResult = {
  /** 子会话本次回复的纯文本（多段 text 拼接）。 */
  text: string
  /** 是否出错；出错时 text 通常为空。 */
  error?: string
  /** 本次回复的 token 用量（宿主返回才有；缺省 undefined）。 */
  tokens?: { input?: number; output?: number }
  /** 本次回复用了多少个工具 part（宿主返回才有）。 */
  toolUses?: number
}

export type TaskClient = {
  createSession(input: { parentID?: string; title: string; directory: string }): Promise<{ id: string }>
  /** resume 时可选改名：把隶属链/标题刷新到已有子会话上。 */
  renameSession(input: { sessionId: string; title: string; directory: string }): Promise<void>
  promptSession(input: {
    sessionId: string
    agent?: string
    model?: { providerID: string; modelID: string }
    /** 推理等级（宿主 model variant）；缺省=宿主默认 */
    variant?: string
    text: string
  }): Promise<PromptResult>
  abortSession(input: { sessionId: string }): Promise<void>
  lastAssistantText(input: { sessionId: string }): Promise<string>
  /** 列出全部会话（跨目录），供所有权对账与 PA 面板。 */
  listSessions(): Promise<Array<{
    id: string
    title?: string
    directory?: string
    parentID?: string | null
    tokens?: { cache?: { read?: number } }
    turns?: number
  }>>
  /** 删除会话及其数据。调用方必须先通过 PA 授权裁决。 */
  deleteSession(input: { sessionId: string; directory?: string }): Promise<void>
}

function textOf(parts: ReadonlyArray<{ type: string }> | undefined): string {
  if (!parts) return ""
  const out: string[] = []
  for (const p of parts) {
    if (p.type === "text" && "text" in p && typeof p.text === "string") out.push(p.text)
  }
  return out.join("\n").trim()
}

/** 把真实 SDK 客户端映射成 TaskClient。 */
export function sdkTaskClient(client: PluginInput["client"]): TaskClient {
  return {
    async createSession({ parentID, title, directory }) {
      const res = await client.session.create({
        body: parentID ? { parentID, title } : { title },
        query: { directory },
      })
      const id = res.data?.id
      if (!id) throw new Error("session.create 未返回会话 id")
      return { id }
    },

    async renameSession({ sessionId, title, directory }) {
      const res = await client.session.update({
        path: { id: sessionId },
        body: { title },
        query: { directory },
      })
      if (res.error !== undefined) throw new Error(`session.update 改名失败: ${summarize(res.error)}`)
    },

    async promptSession({ sessionId, agent, model, variant, text }) {
      // 宿主 1.19 的 prompt body 支持 variant（SDK 旧类型没跟上，故用变量绕开字面量检查）。
      const body = {
        ...(agent ? { agent } : {}),
        ...(model ? { model } : {}),
        ...(variant ? { variant } : {}),
        parts: [{ type: "text" as const, text }],
      }
      const res = await client.session.prompt({ path: { id: sessionId }, body })
      if (res.error !== undefined) {
        return { text: "", error: summarize(res.error) }
      }
      // token/工具用量：宿主给了就透传给状态行，没给就缺省——绝不为凑数造假。
      const info = (res.data as { info?: { tokens?: Record<string, unknown> } } | undefined)?.info
      const t = info?.tokens
      const tokens =
        typeof t?.input === "number" || typeof t?.output === "number"
          ? {
              ...(typeof t?.input === "number" ? { input: t.input } : {}),
              ...(typeof t?.output === "number" ? { output: t.output } : {}),
            }
          : undefined
      const parts = res.data?.parts
      const toolUses = Array.isArray(parts) ? parts.filter((p) => p.type === "tool").length : undefined
      return {
        text: textOf(res.data?.parts),
        ...(tokens === undefined ? {} : { tokens }),
        ...(toolUses === undefined ? {} : { toolUses }),
      }
    },

    async abortSession({ sessionId }) {
      await client.session.abort({ path: { id: sessionId } })
    },

    async lastAssistantText({ sessionId }) {
      const res = await client.session.messages({ path: { id: sessionId } })
      const list = res.data
      if (!Array.isArray(list)) return ""
      for (let i = list.length - 1; i >= 0; i -= 1) {
        const entry = list[i]
        if (!entry || entry.info.role !== "assistant") continue
        const t = textOf(entry.parts)
        if (t !== "") return t
      }
      return ""
    },

    async listSessions() {
      const res = await client.session.list({})
      const list = res.data
      if (!Array.isArray(list)) return []
      return list.map((s) => {
        const info = s as unknown as {
          id: string
          title?: string
          directory?: string
          parentID?: string | null
          tokens?: { cache?: { read?: number } }
        }
        return {
          id: info.id,
          ...(typeof info.title === "string" ? { title: info.title } : {}),
          ...(typeof info.directory === "string" ? { directory: info.directory } : {}),
          ...(info.parentID == null ? {} : { parentID: info.parentID }),
          ...(info.tokens?.cache?.read === undefined ? {} : { tokens: { cache: { read: info.tokens.cache.read } } }),
        }
      })
    },

    async deleteSession({ sessionId, directory }) {
      const res = await client.session.delete({
        path: { id: sessionId },
        ...(directory === undefined ? {} : { query: { directory } }),
      })
      if (res.error !== undefined) throw new Error(`session.delete 失败: ${summarize(res.error)}`)
    },
  }
}

function summarize(error: unknown): string {
  if (typeof error === "string") return error
  if (typeof error === "object" && error !== null && "message" in error) {
    const m = error.message
    if (typeof m === "string") return m
  }
  return JSON.stringify(error)
}
