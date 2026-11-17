/**
 * PA（Permission Authorization）待批队列 —— v1 插件钩子塞不进「工作说明」，
 * 故自建队列：Agent 提交带说明的请求，人类在会话系统提示里看到并在授权时裁决。
 *
 * 分级（用户 2026-11-17 定）：
 *   - 读/响应/交互 → 默认放行（不进此队列）
 *   - 删/改写固有（human/unknown 归属）会话 → 必须 PA，授权后可写
 *   - 高价值未明归属会话（Read 100M tok+ / Turn 16+）→ 删除前必须带非空说明，
 *     防止误删重要总会话（人类可能建的总会话 cache.read 达 1.1B）。
 *
 * 状态机：pending → approved | denied | expired。纯函数 + 原子落盘。
 */

import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { statePath } from "../paths.ts"
import type { OwnerKind } from "./ownership.ts"

export type PaOperation = "delete" | "write"
export type PaStatus = "pending" | "approved" | "denied" | "expired"

export interface PaRequest {
  id: string
  sessionId: string
  sessionTitle?: string
  operation: PaOperation
  owner: OwnerKind
  /** Agent 写的工作说明：为什么删/改写这个会话。高价值未明归属时必填。 */
  reason: string
  /** 高价值标记（Read 100M tok+ / Turn 16+），供人类重点审视。 */
  highValue: boolean
  status: PaStatus
  createdAt: number
  resolvedAt?: number
  /** 防误删校验：批准时记录的归属快照，避免对账变化后误放行。 */
  ownerAtRequest: OwnerKind
}

export type PaQueue = Record<string, PaRequest>

let saveSeq = 0

/** 常量：高价值阈值（来自用户描述 "Read: 100M tok+" / "Turn #16+"）。 */
export const HIGH_VALUE_CACHE_READ_TOKENS = 100_000_000
export const HIGH_VALUE_TURNS = 16
/** 待批过期时间（24h）——防止陈旧请求永久挂起。 */
export const PA_TTL_MS = 24 * 60 * 60 * 1000

export function paPath(path: string = statePath("pending-pa.json")): string {
  return path
}

export async function loadPa(path: string = paPath()): Promise<PaQueue> {
  try {
    const raw = await readFile(path, "utf8")
    const parsed = JSON.parse(raw) as unknown
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return {}
    const out: PaQueue = {}
    for (const [key, v] of Object.entries(parsed as Record<string, unknown>)) {
      if (v === null || typeof v !== "object") continue
      const r = v as Partial<PaRequest>
      if (typeof r.id !== "string" || r.id !== key) continue
      if (typeof r.sessionId !== "string") continue
      if (r.operation !== "delete" && r.operation !== "write") continue
      if (r.status !== "pending" && r.status !== "approved" && r.status !== "denied" && r.status !== "expired") continue
      out[key] = {
        id: r.id,
        sessionId: r.sessionId,
        ...(typeof r.sessionTitle === "string" ? { sessionTitle: r.sessionTitle } : {}),
        operation: r.operation,
        owner: (r.owner === "oml" || r.owner === "human" || r.owner === "unknown") ? r.owner : "unknown",
        reason: typeof r.reason === "string" ? r.reason : "",
        highValue: r.highValue === true,
        status: r.status,
        createdAt: typeof r.createdAt === "number" ? r.createdAt : 0,
        ...(typeof r.resolvedAt === "number" ? { resolvedAt: r.resolvedAt } : {}),
        ownerAtRequest: (r.ownerAtRequest === "oml" || r.ownerAtRequest === "human" || r.ownerAtRequest === "unknown") ? r.ownerAtRequest : "unknown",
      }
    }
    return out
  } catch {
    return {}
  }
}

export async function savePa(queue: PaQueue, path: string = paPath()): Promise<void> {
  const write = async (): Promise<void> => {
    await mkdir(dirname(path), { recursive: true })
    const tmp = `${path}.${process.pid}.${++saveSeq}.tmp`
    await writeFile(tmp, `${JSON.stringify(queue, null, 2)}\n`, "utf8")
    await rename(tmp, path)
  }
  try {
    await write()
  } catch (err) {
    if ((err as { code?: string }).code !== "ENOENT") throw err
    await write()
  }
}

/** 会话 token 快照（来自 session.list 的 tokens 字段）。 */
export interface SessionValue {
  cacheReadTokens?: number
  turns?: number
}

/** 高价值判定：Read 100M tok+ 或 Turn 16+。 */
export function isHighValue(v: SessionValue): boolean {
  return (v.cacheReadTokens ?? 0) >= HIGH_VALUE_CACHE_READ_TOKENS || (v.turns ?? 0) >= HIGH_VALUE_TURNS
}

/** 是否需要强制工作说明：高价值 且 归属不明（unknown/human，非 oml）。 */
export function needsJustification(owner: OwnerKind, highValue: boolean): boolean {
  return highValue && owner !== "oml"
}

export type SubmitResult =
  | { ok: true; queue: PaQueue; request: PaRequest }
  | { ok: false; error: string }

/**
 * 提交 PA 请求。校验：
 *   - oml 自创会话不需要 PA（直接放行，调用方不该进这里；进也拒绝避免误用）
 *   - 高价值未明归属必须有非空 reason
 */
export function submitPa(
  queue: PaQueue,
  input: {
    id: string
    sessionId: string
    sessionTitle?: string
    operation: PaOperation
    owner: OwnerKind
    reason: string
    value: SessionValue
  },
  now: number = Date.now(),
): SubmitResult {
  if (input.owner === "oml") {
    return { ok: false, error: "OML 自创会话无需 PA，请勿提交" }
  }
  const highValue = isHighValue(input.value)
  if (needsJustification(input.owner, highValue) && input.reason.trim() === "") {
    return {
      ok: false,
      error: `会话 ${input.sessionId} 为高价值（Read ${input.value.cacheReadTokens ?? 0} tok / Turn ${input.value.turns ?? 0}）且归属不明，删除前必须说明它做了什么（reason 非空）`,
    }
  }
  const request: PaRequest = {
    id: input.id,
    sessionId: input.sessionId,
    ...(input.sessionTitle === undefined ? {} : { sessionTitle: input.sessionTitle }),
    operation: input.operation,
    owner: input.owner,
    reason: input.reason.trim(),
    highValue,
    status: "pending",
    createdAt: now,
    ownerAtRequest: input.owner,
  }
  return { ok: true, queue: { ...queue, [input.id]: request }, request }
}

/** 批准/否决。只有 pending 可流转；防重复裁决。 */
export function resolvePa(
  queue: PaQueue,
  id: string,
  decision: "approved" | "denied",
  now: number = Date.now(),
): PaQueue {
  const r = queue[id]
  if (r === undefined || r.status !== "pending") return queue
  return { ...queue, [id]: { ...r, status: decision, resolvedAt: now } }
}

/** 过期清理：pending 且超过 TTL 的标 expired。 */
export function expirePa(queue: PaQueue, now: number = Date.now()): PaQueue {
  let changed = false
  const out: PaQueue = {}
  for (const [k, r] of Object.entries(queue)) {
    if (r.status === "pending" && now - r.createdAt > PA_TTL_MS) {
      out[k] = { ...r, status: "expired", resolvedAt: now }
      changed = true
    } else {
      out[k] = r
    }
  }
  return changed ? out : queue
}

/** 取待批列表（供系统提示注入）。 */
export function pendingPa(queue: PaQueue): PaRequest[] {
  return Object.values(queue).filter((r) => r.status === "pending")
}

/** 是否已有针对某会话的已批准请求（删除/改写前复查）。 */
export function isAuthorized(queue: PaQueue, sessionId: string, operation: PaOperation): boolean {
  return Object.values(queue).some(
    (r) => r.sessionId === sessionId && r.operation === operation && r.status === "approved",
  )
}
