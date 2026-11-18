/**
 * OC2（OpenCode 2.x）ctx-backed TaskClient。
 *
 * 把 V2 `ctx.client.session.*`（官方迁移文档未给出精确签名，本机也装不上 2.x）
 * 映射到 OC/omo 定义的窄接口 `TaskClient`，供 `createHostCore` 复用——业务逻辑
 * 全部留在 OC1，本文件只做形状翻译（A4 单一写入者）。
 *
 * 所有调用均为**理论映射**：方法缺失或返回形状无法确认时抛 informative throw，
 * 写明「OC2 理论插件：ctx.X 签名待真机确认」，绝不返回空字符串/空数组伪装成功。
 */
import type { PromptResult, TaskClient } from "../../../OC/omo/src/client.ts"
import type { Oc2Context, V2HostClient } from "./v2-types.ts"

function sig(what: string): Error {
  return new Error(`OC2 理论插件：ctx.client.${what} 签名待真机确认 —— 方法缺失或返回形状无法安全归一，拒绝伪装成功`)
}

/** 从 `res.data?.id` / `res.id` 里取会话 id（V1 SDK 与 V2 domain 两种可能形状）。 */
function readId(res: unknown): string | undefined {
  if (res === null || typeof res !== "object") return undefined
  const obj = res as Record<string, unknown>
  const data = obj["data"]
  const dataObj = data !== null && typeof data === "object" ? (data as Record<string, unknown>) : {}
  const id = dataObj["id"] ?? obj["id"]
  return typeof id === "string" && id !== "" ? id : undefined
}

/** 从 parts 里取纯文本（text part 拼接），兼容 `res.data?.parts` / `res.parts`。 */
function readText(res: unknown): { text: string; toolUses: number | undefined; tokens: PromptResult["tokens"] } | undefined {
  if (res === null || typeof res !== "object") return undefined
  const obj = res as Record<string, unknown>
  const data = obj["data"]
  const body = data !== null && typeof data === "object" ? (data as Record<string, unknown>) : obj
  const parts = body["parts"]
  if (!Array.isArray(parts)) return undefined
  const texts: string[] = []
  let toolUses = 0
  for (const p of parts) {
    if (p === null || typeof p !== "object") continue
    const part = p as Record<string, unknown>
    if (part["type"] === "text" && typeof part["text"] === "string") texts.push(part["text"])
    if (part["type"] === "tool") toolUses += 1
  }
  const info = body["info"]
  const infoObj = info !== null && typeof info === "object" ? (info as Record<string, unknown>) : {}
  const t = infoObj["tokens"]
  const tokObj = t !== null && typeof t === "object" ? (t as Record<string, unknown>) : {}
  const tokens: PromptResult["tokens"] =
    typeof tokObj["input"] === "number" || typeof tokObj["output"] === "number"
      ? {
          ...(typeof tokObj["input"] === "number" ? { input: tokObj["input"] as number } : {}),
          ...(typeof tokObj["output"] === "number" ? { output: tokObj["output"] as number } : {}),
        }
      : undefined
  return { text: texts.join("\n").trim(), toolUses, tokens }
}

/** 从 messages 列表里取最后一条 assistant 的文本。 */
function lastAssistantText(list: unknown): string | undefined {
  if (!Array.isArray(list)) return undefined
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const entry = list[i]
    if (entry === null || typeof entry !== "object") continue
    const obj = entry as Record<string, unknown>
    const info = obj["info"]
    const infoObj = info !== null && typeof info === "object" ? (info as Record<string, unknown>) : {}
    if (infoObj["role"] !== "assistant") continue
    const got = readText({ data: obj })
    if (got !== undefined && got.text !== "") return got.text
  }
  return ""
}

function errorText(res: unknown): string | undefined {
  if (res === null || typeof res !== "object") return undefined
  const obj = res as Record<string, unknown>
  const err = obj["error"]
  if (err === undefined) return undefined
  if (typeof err === "string") return err
  if (typeof err === "object" && err !== null && "message" in err) {
    const m = (err as Record<string, unknown>)["message"]
    if (typeof m === "string") return m
  }
  return JSON.stringify(err)
}

/**
 * 由 V2 上下文构建 TaskClient。
 *
 * @param ctx V2 插件上下文；`ctx.client` 缺失即抛 informative throw（理论插件不伪装成功）。
 */
export function clientFromContext(ctx: Oc2Context): TaskClient {
  const client: V2HostClient | undefined = ctx.client
  if (client === undefined || typeof client !== "object") {
    throw new Error("OC2 理论插件：ctx.client 签名待真机确认 —— 上下文未提供 client，无法构建 TaskClient（未伪装成功）")
  }
  const session = client.session

  return {
    async createSession({ parentID, title, directory }) {
      const create = session?.create
      if (typeof create !== "function") throw sig("session.create")
      // 理论映射：V2 可能沿用 V1 SDK 的 {body,query} 形状，也可能直接收扁平字段；
      // 这里一并给出（多余字段被忽略），真机确认后收敛为单一形状。
      const res = await create({
        body: parentID ? { parentID, title } : { title },
        query: { directory },
        parentID,
        title,
        directory,
      })
      const err = errorText(res)
      if (err !== undefined) throw new Error(`session.create 失败: ${err}`)
      const id = readId(res)
      if (id === undefined) throw sig("session.create 的返回形状（未找到 id）")
      return { id }
    },

    async renameSession({ sessionId, title, directory }) {
      const update = session?.update
      if (typeof update !== "function") throw sig("session.update")
      const res = await update({
        path: { id: sessionId },
        body: { title },
        query: { directory },
      })
      const err = errorText(res)
      if (err !== undefined) throw new Error(`session.update 改名失败: ${err}`)
    },

    async promptSession({ sessionId, agent, model, variant, text }) {
      const prompt = session?.prompt
      if (typeof prompt !== "function") throw sig("session.prompt")
      const body: Record<string, unknown> = {
        ...(agent ? { agent } : {}),
        ...(model ? { model } : {}),
        ...(variant ? { variant } : {}),
        parts: [{ type: "text", text }],
      }
      const res = await prompt({ path: { id: sessionId }, body })
      const err = errorText(res)
      if (err !== undefined) return { text: "", error: err }
      const got = readText(res)
      if (got === undefined) throw sig("session.prompt 的返回形状（未找到 parts）")
      return {
        text: got.text,
        ...(got.tokens === undefined ? {} : { tokens: got.tokens }),
        ...(got.toolUses === undefined ? {} : { toolUses: got.toolUses }),
      }
    },

    async abortSession({ sessionId }) {
      const abort = session?.abort
      if (typeof abort !== "function") throw sig("session.abort")
      await abort({ path: { id: sessionId } })
    },

    async lastAssistantText({ sessionId }) {
      const messages = session?.messages
      if (typeof messages !== "function") throw sig("session.messages")
      const res = await messages({ path: { id: sessionId } })
      const list = (res as Record<string, unknown> | null)?.["data"] ?? res
      const text = lastAssistantText(list)
      if (text === undefined) throw sig("session.messages 的返回形状（不是消息数组）")
      return text
    },

    async listSessions() {
      const list = session?.list
      if (typeof list !== "function") throw sig("session.list")
      const res = await list({})
      const raw = (res as Record<string, unknown> | null)?.["data"] ?? res
      if (!Array.isArray(raw)) throw sig("session.list 的返回形状（不是数组）")
      return raw.map((entry) => {
        const info = entry !== null && typeof entry === "object" ? (entry as Record<string, unknown>) : {}
        const tokens = info["tokens"]
        const tokObj = tokens !== null && typeof tokens === "object" ? (tokens as Record<string, unknown>) : {}
        const cache = tokObj["cache"]
        const cacheObj = cache !== null && typeof cache === "object" ? (cache as Record<string, unknown>) : {}
        return {
          id: String(info["id"] ?? ""),
          ...(typeof info["title"] === "string" ? { title: info["title"] as string } : {}),
          ...(typeof info["directory"] === "string" ? { directory: info["directory"] as string } : {}),
          ...(typeof info["parentID"] === "string" ? { parentID: info["parentID"] as string } : {}),
          ...(typeof cacheObj["read"] === "number"
            ? { tokens: { cache: { read: cacheObj["read"] as number } } }
            : {}),
        }
      })
    },

    async deleteSession({ sessionId, directory }) {
      const remove = session?.delete
      if (typeof remove !== "function") throw sig("session.delete")
      const res = await remove({
        path: { id: sessionId },
        ...(directory === undefined ? {} : { query: { directory } }),
      })
      const err = errorText(res)
      if (err !== undefined) throw new Error(`session.delete 失败: ${err}`)
    },
  }
}
