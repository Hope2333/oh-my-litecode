/**
 * 运行时状态目录。一个函数，所有模块共用——避免「预算日志在 omo/、任务状态在别处」。
 *
 * 旧 OMO 的状态在 ~/.local/state/omo/。OML 读它一次做迁移，之后只写自己的目录，
 * 这样两套系统并存期间不会互相覆盖。
 */

import { homedir } from "node:os"
import { join } from "node:path"

export function stateDir(env: Record<string, string | undefined> = process.env): string {
  const override = env["OML_STATE_DIR"]
  return override !== undefined && override !== "" ? override : join(homedir(), ".local", "state", "oml")
}

/** OMO 遗留目录，只读。 */
export function legacyStateDir(): string {
  return join(homedir(), ".local", "state", "omo")
}

export function statePath(...parts: string[]): string {
  return join(stateDir(), ...parts)
}
