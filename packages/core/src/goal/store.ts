/**
 * 目标账本：一个时刻只有一个目标。
 *
 * 扬弃对象：原 goal 插件在 OpenCode 1.19 上全部 hook 失败
 * （`context.command.list is not a function` / `context.session.hook` undefined），
 * 实际零功能却占一个插件位。这里用 30 行文件替代它。
 *
 * 判据（A8 精兵简政）：目标只需要三个动作——设、看、清；不需要自动续跑。
 */

import { existsSync } from "node:fs"
import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import { statePath } from "../paths.ts"

export interface Goal {
  readonly text: string
  readonly createdAt: number
  readonly updatedAt: number
}

export function goalPath(): string {
  return statePath("goal.json")
}

export async function loadGoal(path = goalPath()): Promise<Goal | null> {
  if (!existsSync(path)) return null
  try {
    const raw: unknown = JSON.parse(await readFile(path, "utf8"))
    if (typeof raw !== "object" || raw === null) return null
    const o = raw as Record<string, unknown>
    if (typeof o["text"] !== "string" || o["text"].trim() === "") return null
    return {
      text: o["text"],
      createdAt: typeof o["createdAt"] === "number" ? o["createdAt"] : Date.now(),
      updatedAt: typeof o["updatedAt"] === "number" ? o["updatedAt"] : Date.now(),
    }
  } catch {
    return null
  }
}

export async function saveGoal(text: string, path = goalPath(), now = Date.now()): Promise<Goal> {
  const trimmed = text.trim()
  if (trimmed === "") throw new Error("目标不能为空")
  const prev = await loadGoal(path)
  const goal: Goal = { text: trimmed, createdAt: prev?.createdAt ?? now, updatedAt: now }
  await mkdir(dirname(path), { recursive: true })
  const tmp = `${path}.${process.pid}.tmp`
  await writeFile(tmp, `${JSON.stringify(goal, null, 2)}\n`, "utf8")
  await rename(tmp, path)
  return goal
}

export async function clearGoal(path = goalPath()): Promise<boolean> {
  if (!existsSync(path)) return false
  await unlink(path)
  return true
}
