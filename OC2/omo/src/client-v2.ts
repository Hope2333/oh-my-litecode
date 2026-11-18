/**
 * OC2（OpenCode 2.x）ctx-backed TaskClient。
 *
 * 真机 2.3.0 证据（docs/bench/oc2-realmachine-2026-11-18.md）：
 *   - setup ctx **没有 ctx.client**，真实 API 是 `ctx.session.*`。
 *   - session 方法全是 1 参 RPC 包装 `(i)=>...`，zod decode 后**直接返回解码 body**
 *     （无 V1 的 `{data:}` 外壳，但仍兼容两种形状）。
 *   - 没有 messages / abort / delete：lastAssistantText→session.get、abort→session.interrupt、
 *     delete→session.remove、rename→session.update。
 *
 * 本文件只做形状翻译（A4 单一写入者）。**构造时不访问/校验任何 session 方法的存在性**，
 * 确保插件 setup 能完成；某个方法真被调用且其能力缺失时才 informative throw（不伪装成功）。
 */
import type { PromptResult, TaskClient } from "../../../OC/omo/src/client.ts"
import type { Oc2Context, V2SessionDomain } from "./v2-types.ts"

function sig(what: string): Error {
  return new Error(`OC2：ctx.session.${what} 不可用（真机 2.3.0 未提供，或其返回形状无法安全归一），拒绝伪装成功`)
}

/** 每次调用时读取 session domain；构造期不访问/校验任何方法。 */
function sessionOf(ctx: Oc2Context): V2SessionDomain {
  const session = ctx.session
  if (session === undefined || session === null || typeof session !== "object") {
    throw sig("domain 未就绪")
  }
  return session
}

/** 取真正的返回载荷：兼容 `{data:X}` 与直接 `X` 两种外壳。 */
function dataOf(res: unknown): unknown {
  if (res === null || typeof res !== "object") return res
  const obj = res as Record<string, unknown>
  if ("data" in obj) return obj["data"]
  return obj
}

/** 把返回载荷归一成对象（数组/原始值返回 {}，由调用方按需另取）。 */
function bodyOf(res: unknown): Record<string, unknown> {
  const value = dataOf(res)
  return value !== null && typeof value === "object" ? (value as Record<string, unknown>) : {}
}

/** 从返回体里取会话 id。 */
function readId(res: unknown): string | undefined {
  const id = bodyOf(res)["id"]
  return typeof id === "string" && id !== "" ? id : undefined
}

/** parts（text part）→ 纯文本，顺带统计 tool part 数。 */
function partsText(parts: unknown): { text: string; toolUses: number | undefined } {
  if (!Array.isArray(parts)) return { text: "", toolUses: undefined }
  const texts: string[] = []
  let toolUses = 0
  for (const p of parts) {
    if (p === null || typeof p !== "object") continue
    const part = p as Record<string, unknown>
    if (part["type"] === "text" && typeof part["text"] === "string") texts.push(part["text"])
    if (part["type"] === "tool") toolUses += 1
  }
  return { text: texts.join("\n").trim(), toolUses }
}

/** prompt 返回 → PromptResult 载荷（text / tokens / toolUses）。 */
function readPrompt(res: unknown): { text: string; toolUses: number | undefined; tokens: PromptResult["tokens"] } | undefined {
  const body = bodyOf(res)
  const parts = body["parts"]
  if (!Array.isArray(parts)) return undefined
  const { text, toolUses } = partsText(parts)
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
  return { text, toolUses, tokens }
}

/** 从 messages 数组里取最后一条 assistant 的文本（V1 形状兼容）。 */
function lastAssistantFromMessages(list: unknown): string | undefined {
  if (!Array.isArray(list)) return undefined
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const entry = list[i]
    if (entry === null || typeof entry !== "object") continue
    const obj = entry as Record<string, unknown>
    const info = obj["info"]
    const infoObj = info !== null && typeof info === "object" ? (info as Record<string, unknown>) : {}
    if (infoObj["role"] !== "assistant") continue
    const t = partsText(obj["parts"]).text
    if (t !== "") return t
  }
  return ""
}

/** session.get 返回 → 最后一条 assistant 文本（兼容直接 parts/text 与 V1 messages 数组）。 */
function readAssistantText(res: unknown): string | undefined {
  const raw = dataOf(res)
  // 返回体本身就是 messages 数组（V1 形状）。
  if (Array.isArray(raw)) return lastAssistantFromMessages(raw)
  const body = bodyOf(res)
  if (typeof body["text"] === "string" && body["text"] !== "") return body["text"]
  if (Array.isArray(body["parts"])) {
    const t = partsText(body["parts"]).text
    if (t !== "") return t
  }
  // 嵌套 parts：body.info.parts / body.message.parts。
  const info = body["info"]
  const infoObj = info !== null && typeof info === "object" ? (info as Record<string, unknown>) : {}
  const message = body["message"]
  const messageObj = message !== null && typeof message === "object" ? (message as Record<string, unknown>) : {}
  for (const src of [infoObj, messageObj]) {
    if (Array.isArray(src["parts"])) {
      const t = partsText(src["parts"]).text
      if (t !== "") return t
    }
  }
  if (Array.isArray(body["messages"])) {
    const t = lastAssistantFromMessages(body["messages"])
    if (t !== undefined) return t
  }
  return undefined
}

function errorText(res: unknown): string | undefined {
  const top: Record<string, unknown> = res !== null && typeof res === "object" ? (res as Record<string, unknown>) : {}
  for (const obj of [top, bodyOf(res)]) {
    const err = obj["error"]
    if (err === undefined) continue
    if (typeof err === "string") return err
    if (typeof err === "object" && err !== null && "message" in err) {
      const m = (err as Record<string, unknown>)["message"]
      if (typeof m === "string") return m
    }
    return JSON.stringify(err)
  }
  return undefined
}

/**
 * 由 V2 上下文的 `ctx.session.*` 构建 TaskClient。
 *
 * 构造期只读 ctx 引用、不校验任何 session 方法；缺失能力在对应方法被调用时才 throw。
 */
export function clientFromContext(ctx: Oc2Context): TaskClient {
  return {
    async createSession({ parentID, title, directory }) {
      const session = sessionOf(ctx)
      if (typeof session.create !== "function") throw sig("create")
      const res = await session.create({
        ...(parentID ? { parentID } : {}),
        title,
        directory,
        // V1 兼容形状（zod 通常会剥掉多余字段，真机确认后可收敛）。
        body: parentID ? { parentID, title } : { title },
        query: { directory },
      })
      const err = errorText(res)
      if (err !== undefined) throw new Error(`session.create 失败: ${err}`)
      const id = readId(res)
      if (id === undefined) throw sig("create 的返回形状（未找到 id）")
      return { id }
    },

    async renameSession({ sessionId, title, directory }) {
      const session = sessionOf(ctx)
      if (typeof session.update !== "function") throw sig("update")
      const res = await session.update({
        sessionID: sessionId,
        id: sessionId,
        title,
        ...(directory === undefined ? {} : { directory }),
        path: { id: sessionId },
        body: { title },
        query: { directory },
      })
      const err = errorText(res)
      if (err !== undefined) throw new Error(`session.update 改名失败: ${err}`)
    },

    async promptSession({ sessionId, agent, model, variant, text }) {
      const session = sessionOf(ctx)
      if (typeof session.prompt !== "function") throw sig("prompt")
      const body: Record<string, unknown> = {
        ...(agent ? { agent } : {}),
        ...(model ? { model } : {}),
        ...(variant ? { variant } : {}),
        parts: [{ type: "text", text }],
      }
      const res = await session.prompt({
        sessionID: sessionId,
        id: sessionId,
        ...body,
        path: { id: sessionId },
        body,
      })
      const err = errorText(res)
      if (err !== undefined) return { text: "", error: err }
      const got = readPrompt(res)
      if (got === undefined) throw sig("prompt 的返回形状（未找到 parts）")
      return {
        text: got.text,
        ...(got.tokens === undefined ? {} : { tokens: got.tokens }),
        ...(got.toolUses === undefined ? {} : { toolUses: got.toolUses }),
      }
    },

    // 真机没有 session.abort，只有 session.interrupt —— 缺失时 informative throw（与其余方法一致，不静默 no-op）。
    async abortSession({ sessionId }) {
      const session = sessionOf(ctx)
      if (typeof session.interrupt !== "function") throw sig("interrupt")
      await session.interrupt({ sessionID: sessionId, id: sessionId, path: { id: sessionId } })
    },

    // 真机没有 session.messages，改用 session.get 并从返回体取 parts/text。
    async lastAssistantText({ sessionId }) {
      const session = sessionOf(ctx)
      if (typeof session.get !== "function") throw sig("get")
      const res = await session.get({ sessionID: sessionId, id: sessionId, path: { id: sessionId } })
      const text = readAssistantText(res)
      if (text === undefined) throw sig("get 的返回形状（未找到 parts/text）")
      return text
    },

    async listSessions() {
      const session = sessionOf(ctx)
      if (typeof session.list !== "function") throw sig("list")
      const res = await session.list({})
      const raw = dataOf(res)
      if (!Array.isArray(raw)) throw sig("list 的返回形状（不是数组）")
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

    // 真机没有 session.delete，改用 session.remove。
    async deleteSession({ sessionId, directory }) {
      const session = sessionOf(ctx)
      if (typeof session.remove !== "function") throw sig("remove")
      const res = await session.remove({
        sessionID: sessionId,
        id: sessionId,
        path: { id: sessionId },
        ...(directory === undefined ? {} : { query: { directory }, directory }),
      })
      const err = errorText(res)
      if (err !== undefined) throw new Error(`session.remove 失败: ${err}`)
    },
  }
}
