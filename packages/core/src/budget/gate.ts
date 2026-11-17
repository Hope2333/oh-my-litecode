/**
 * 上下文预算门禁：拼装 + 落盘审计。
 * 行为：
 *   1) 调 assemble(prompt.sections, opts.limit ?? DEFAULT_BUDGET_TOKENS)；
 *   2) status 为 "truncated" 或 "fail" 时，把 warnings 追加写入 logPath
 *      （默认 <stateDir>/budget.log），目录递归创建，每条前加 ISO 时间戳；
 *   3) 写盘失败不抛出，返回 written=false（系统不能因日志挂掉）；
 *   4) status 为 "pass" 时不写盘，written=false。
 */
import { mkdir, appendFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { SystemPrompt } from "../contract.ts"
import { DEFAULT_BUDGET_TOKENS } from "../contract.ts"
import { statePath } from "../paths.ts"
import { assemble } from "./assemble.ts"
import type { AssembleResult } from "./assemble.ts"

export interface GateOptions {
  limit?: number
  logPath?: string
}

export interface GateResult extends AssembleResult {
  written: boolean
}

function defaultLogPath(): string {
  return statePath("budget.log")
}

/** 追加审计日志；任何失败都吞掉，绝不让门禁因日志挂掉。 */
async function appendWarnings(logPath: string, warnings: string[]): Promise<boolean> {
  try {
    await mkdir(dirname(logPath), { recursive: true })
    const stamp = new Date().toISOString()
    const body = warnings.map((w) => `${stamp} ${w}`).join("\n") + "\n"
    await appendFile(logPath, body, "utf8")
    return true
  } catch {
    return false
  }
}

/** 预算门禁：超预算即落盘留痕（反修：不隐瞒矛盾）。 */
export async function gate(prompt: SystemPrompt, opts?: GateOptions): Promise<GateResult> {
  const limit = opts?.limit ?? DEFAULT_BUDGET_TOKENS
  const logPath = opts?.logPath ?? defaultLogPath()
  const result = assemble(prompt.sections, limit)
  const status = result.report.budget.status
  if (status === "truncated" || status === "fail") {
    const written = await appendWarnings(logPath, result.report.warnings)
    return { ...result, written }
  }
  return { ...result, written: false }
}
