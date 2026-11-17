/**
 * 代理间通信通道 —— 纯消息板内核。
 *
 * 频道按 teamId 隔离；消息由某个 role（from）发给另一个 role（to）或广播（to="*"）。
 * createBoard / post / read / list / prune 均为**纯函数**：返回新对象，不修改入参，
 * 与 skills/usage.ts 的 recordHit 风格一致。
 *
 * 并发边界（已知，不在本层解决）：
 *   多个进程同时 post 到同一个 channels.json 是「读-改-写」序列。saveBoard 的
 *   tmp→rename 只保证**单次写**原子，不保证跨进程合并；最后写入者覆盖先前写入
 *   （lost update）。单 team 会话内顺序 post 不丢；跨进程并发窗口是明确记录的边界，
 *   真正的多进程协调留给上层。
 */

import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { statePath } from "../paths.ts"

/** 消息种类：普通消息 / 认领 / 结果。 */
export type ChannelKind = "msg" | "claim" | "result"

/** 一条频道消息。 */
export interface ChannelMessage {
  id: string
  channel: string
  from: string
  to: string
  body: string
  ts: number
  kind: ChannelKind
}

/** 整块消息板：channelId → 消息数组（数组按 ts 追加顺序保留）。 */
export interface ChannelBoard {
  channels: Record<string, ChannelMessage[]>
}

/** 状态文件名（经 statePath 解析为绝对路径）。 */
export const CHANNEL_PATH = "channels.json"

/** 消息板默认路径：<stateDir>/channels.json。 */
export function boardPath(): string {
  return statePath(CHANNEL_PATH)
}

/** 创建空板。 */
export function createBoard(): ChannelBoard {
  return { channels: {} }
}

/**
 * 进程内消息 id 序号。id 前缀带 ts，降低多进程碰撞概率；
 * 但跨进程并发仍是上面声明的已知边界。
 */
let messageSeq = 0

/** post 的输入：除 id/ts 外必填，二者可注入以便测试与确定性重放。 */
export type PostInput = Omit<ChannelMessage, "id" | "ts"> & { id?: string; ts?: number }

/** post 的返回：新板 + 落定后的消息。 */
export type PostResult = { board: ChannelBoard; message: ChannelMessage }

/**
 * 追加一条消息。未注入 id 时生成 `m-<ts>-<seq>`，未注入 ts 时取 Date.now()。
 * 纯函数：返回新板与新数组，原板原数组不变。
 */
export function post(board: ChannelBoard, msg: PostInput): PostResult {
  const ts = msg.ts ?? Date.now()
  const message: ChannelMessage = {
    id: msg.id ?? `m-${ts}-${++messageSeq}`,
    channel: msg.channel,
    from: msg.from,
    to: msg.to,
    body: msg.body,
    ts,
    kind: msg.kind,
  }
  const prev = board.channels[message.channel] ?? []
  return {
    board: {
      channels: {
        ...board.channels,
        [message.channel]: [...prev, message],
      },
    },
    message,
  }
}

/**
 * 读取某频道的消息。
 * - since 游标：只返回 ts > since 的消息（不传则返回全部）。
 * - to：传入时只返回发给该 role 或广播（to="*"）的消息；不传则返回该频道全部消息。
 *
 * 返回的是新数组；不修改板。
 */
export function read(
  board: ChannelBoard,
  channel: string,
  since?: number,
  to?: string,
): ChannelMessage[] {
  const msgs = board.channels[channel] ?? []
  return msgs.filter(
    (m) => (since === undefined || m.ts > since) && (to === undefined || m.to === to || m.to === "*"),
  )
}

/** 列出所有频道 id，字典序。返回新数组。 */
export function list(board: ChannelBoard): string[] {
  return Object.keys(board.channels).sort((a, b) => a.localeCompare(b))
}

/**
 * 按时间裁剪：删除 ts < olderThanTs 的消息，变空的频道键一并移除。
 * 返回新板；不修改入参。
 */
export function prune(board: ChannelBoard, olderThanTs: number): ChannelBoard {
  const channels: Record<string, ChannelMessage[]> = {}
  for (const [id, msgs] of Object.entries(board.channels)) {
    const kept = msgs.filter((m) => m.ts >= olderThanTs)
    if (kept.length > 0) channels[id] = kept
  }
  return { channels }
}

/** 形状守卫：单条消息字段是否合法。 */
function isChannelMessage(v: unknown): v is ChannelMessage {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return false
  const o = v as Record<string, unknown>
  return (
    typeof o.id === "string" &&
    typeof o.channel === "string" &&
    typeof o.from === "string" &&
    typeof o.to === "string" &&
    typeof o.body === "string" &&
    typeof o.ts === "number" &&
    (o.kind === "msg" || o.kind === "claim" || o.kind === "result")
  )
}

/** 形状守卫：整块板是否合法。 */
function isBoard(v: unknown): v is ChannelBoard {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return false
  const channels = (v as Record<string, unknown>).channels
  if (typeof channels !== "object" || channels === null || Array.isArray(channels)) return false
  for (const val of Object.values(channels as Record<string, unknown>)) {
    if (!Array.isArray(val) || !val.every(isChannelMessage)) return false
  }
  return true
}

/** 读板。文件不存在 / JSON 损坏 / 形状非法 → 返回空板（与 usage.ts 降级策略一致）。 */
export async function loadBoard(path: string = boardPath()): Promise<ChannelBoard> {
  try {
    const parsed: unknown = JSON.parse(await readFile(path, "utf8"))
    return isBoard(parsed) ? parsed : createBoard()
  } catch {
    return createBoard()
  }
}

/** 并发写序号：独立 tmp 名避免互抢 rename。 */
let boardSaveSeq = 0

/**
 * 原子写：tmp 名带 process.pid + 自增 seq → rename；ENOENT 时重建父目录再写一次。
 * 照抄 skills/usage.ts:71 的 saveUsage 范式（裸 writeFile 曾损坏过本机状态文件）。
 */
export async function saveBoard(board: ChannelBoard, path: string = boardPath()): Promise<void> {
  const write = async (): Promise<void> => {
    await mkdir(dirname(path), { recursive: true })
    const tmp = `${path}.${process.pid}.${++boardSaveSeq}.tmp`
    await writeFile(tmp, `${JSON.stringify(board, null, 2)}\n`, "utf8")
    await rename(tmp, path)
  }
  try {
    await write()
  } catch (err) {
    // 状态目录被外部删除时重建一次；仍失败才抛出。
    if ((err as { code?: string }).code !== "ENOENT") throw err
    await write()
  }
}
