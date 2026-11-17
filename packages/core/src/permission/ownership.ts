/**
 * 会话所有权账本 —— 谁能删/改写会话的裁决依据。
 *
 * 背景：宿主 SDK 的 Session 没有「谁创建的」字段（live 4096 实测字段见
 * docs/plan/pa-permissions.md）。OML 创建的会话自己登记，没登记的一律 unknown。
 * unknown = 可能是人类在 TUI 里建的 → 删除/改写必须走 PA（见 pa.ts）。
 *
 * 账本落盘，跨 OML 进程重启仍在（这点很关键： Sessions 比插件进程活得久）。
 * 原子写，复用 usage/tasks 的 tmp→rename 模式。
 */

import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { statePath } from "../paths.ts"

export type OwnerKind = "oml" | "human" | "unknown"

export interface OwnershipEntry {
  id: string
  owner: OwnerKind
  directory: string
  parentID?: string
  createdAt: number
  /** 人可读的来源说明；oml 会话写标题，便于 PA 面板展示。 */
  note?: string
}

export type OwnershipLedger = Record<string, OwnershipEntry>

let saveSeq = 0

/** 账本文件路径，可由调用方注入以便测试隔离。 */
export function ownershipPath(path: string = statePath("session-owners.json")): string {
  return path
}

export async function loadOwnership(path: string = ownershipPath()): Promise<OwnershipLedger> {
  try {
    const raw = await readFile(path, "utf8")
    const parsed = JSON.parse(raw) as unknown
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return {}
    const out: OwnershipLedger = {}
    for (const [key, v] of Object.entries(parsed as Record<string, unknown>)) {
      if (v === null || typeof v !== "object") continue
      const e = v as Partial<OwnershipEntry>
      if (typeof e.id !== "string" || e.id !== key) continue
      if (e.owner !== "oml" && e.owner !== "human" && e.owner !== "unknown") continue
      out[key] = {
        id: e.id,
        owner: e.owner,
        directory: typeof e.directory === "string" ? e.directory : "",
        ...(typeof e.parentID === "string" ? { parentID: e.parentID } : {}),
        createdAt: typeof e.createdAt === "number" ? e.createdAt : 0,
        ...(typeof e.note === "string" ? { note: e.note } : {}),
      }
    }
    return out
  } catch {
    return {}
  }
}

export async function saveOwnership(ledger: OwnershipLedger, path: string = ownershipPath()): Promise<void> {
  const write = async (): Promise<void> => {
    await mkdir(dirname(path), { recursive: true })
    const tmp = `${path}.${process.pid}.${++saveSeq}.tmp`
    await writeFile(tmp, `${JSON.stringify(ledger, null, 2)}\n`, "utf8")
    await rename(tmp, path)
  }
  try {
    await write()
  } catch (err) {
    if ((err as { code?: string }).code !== "ENOENT") throw err
    await write()
  }
}

/** OML 创建会话后登记。纯函数返回新账本。 */
export function registerOmlSession(
  ledger: OwnershipLedger,
  input: { id: string; directory: string; parentID?: string; title?: string },
): OwnershipLedger {
  return {
    ...ledger,
    [input.id]: {
      id: input.id,
      owner: "oml",
      directory: input.directory,
      ...(input.parentID === undefined ? {} : { parentID: input.parentID }),
      createdAt: Date.now(),
      ...(input.title === undefined ? {} : { note: input.title }),
    },
  }
}

/**
 * 裁决会话归属。
 * - 账本里登记过 → 用账本值
 * - 未登记 → unknown（可能是人类建的；删除/改写需 PA）
 */
export function classifyOwner(ledger: OwnershipLedger, sessionId: string): OwnerKind {
  return ledger[sessionId]?.owner ?? "unknown"
}

/** 是否 OML 自己创建（唯一可不经 PA 删除的类别）。 */
export function isOmlOwned(ledger: OwnershipLedger, sessionId: string): boolean {
  return classifyOwner(ledger, sessionId) === "oml"
}

/**
 * 把宿主 session.list 的全部会话与账本对账：
 * 账本里没有的 → unknown（可能是人类在 TUI 里建的），批量补登以便 PA 面板提示。
 * 纯函数：返回「新账本」和「本次新发现的 unknown id 列表」。
 */
export function reconcileWithHost(
  ledger: OwnershipLedger,
  sessions: ReadonlyArray<{ id: string; directory?: string; parentID?: string | null; title?: string }>,
): { ledger: OwnershipLedger; newUnknown: string[] } {
  let next = ledger
  const newUnknown: string[] = []
  for (const s of sessions) {
    if (next[s.id] !== undefined) continue
    newUnknown.push(s.id)
    next = {
      ...next,
      [s.id]: {
        id: s.id,
        owner: "unknown",
        directory: s.directory ?? "",
        ...(s.parentID == null ? {} : { parentID: s.parentID }),
        createdAt: 0, // 宿主 time.created 可后续补；对账阶段只求标记归属
        ...(s.title === undefined ? {} : { note: s.title }),
      },
    }
  }
  return { ledger: next, newUnknown }
}

/** 账本里显式标为 unknown 的条目（对账补登后即在此）。 */
export function unknownSessions(ledger: OwnershipLedger): OwnershipEntry[] {
  return Object.values(ledger).filter((e) => e.owner === "unknown")
}
