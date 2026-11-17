/**
 * 联网检索：Gemini Google Search grounding。
 *
 * 约束（实测）：本机直连 generativelanguage.googleapis.com 超时，必须走本地代理。
 * 代理地址默认 http://127.0.0.1:7890，OML_HTTPS_PROXY=none 可关闭。
 * 无密钥时不报错崩，返回可读的失败原因——检索不可用不该让整个会话失败。
 */

import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

const KEY_FILE = join(homedir(), ".secrets", "gemini-api-key")
const MODEL = "gemini-2.5-flash"

async function apiKey(): Promise<string | null> {
  if (process.env["GEMINI_API_KEY"] !== undefined && process.env["GEMINI_API_KEY"] !== "") {
    return process.env["GEMINI_API_KEY"]
  }
  try {
    const text = await readFile(KEY_FILE, "utf8")
    const key = text.trim()
    return key === "" ? null : key
  } catch {
    return null
  }
}

export function proxyUrl(): string | undefined {
  const raw = process.env["OML_HTTPS_PROXY"]
  if (raw === "none") return undefined
  return raw !== undefined && raw !== "" ? raw : "http://127.0.0.1:7890"
}

interface GroundingChunk {
  web?: { uri?: string; title?: string }
}

interface GeminiResponse {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> }
    groundingMetadata?: { groundingChunks?: GroundingChunk[] }
  }>
  error?: { message?: string }
}

export async function searchWeb(
  query: string,
  count: number,
): Promise<{ ok: true; text: string } | { ok: false; error: string }> {
  const key = await apiKey()
  if (key === null) return { ok: false, error: "缺少 GEMINI_API_KEY（可写 ~/.secrets/gemini-api-key）" }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${encodeURIComponent(key)}`
  const proxy = proxyUrl()
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: query }] }],
        tools: [{ google_search: {} }],
      }),
      signal: AbortSignal.timeout(25_000),
      ...(proxy === undefined ? {} : { proxy }),
    })
    if (!res.ok) return { ok: false, error: `HTTP ${res.status} ${(await res.text()).slice(0, 200)}` }
    const data = (await res.json()) as GeminiResponse
    if (data.error?.message !== undefined) return { ok: false, error: data.error.message }
    const first = data.candidates?.[0]
    const answer = (first?.content?.parts ?? []).map((p) => p.text ?? "").join("").trim()
    const sources = (first?.groundingMetadata?.groundingChunks ?? [])
      .map((c) => c.web)
      .filter((w): w is { uri: string; title?: string } => typeof w?.uri === "string")
      .slice(0, count)
    const lines = sources.map((w, i) => `${i + 1}. ${w.title ?? w.uri}\n   ${w.uri}`)
    return {
      ok: true,
      text: [answer === "" ? "（无正文，只有来源）" : answer, lines.length === 0 ? "" : `\n来源：\n${lines.join("\n")}`]
        .filter((s) => s !== "")
        .join("\n"),
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    return { ok: false, error: `${message}（代理：${proxy ?? "直连"}）` }
  }
}
