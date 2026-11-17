#!/usr/bin/env bun
// bench/prompt —— 空闲会话系统提示体积基准（公理 A9：以实测 token 为准）。
// 退出码：0 = ≤8192 tok（pass）；1 = 超限（fail）。
import { measureReport } from "../packages/cli/src/commands/measure.ts"
import { DEFAULT_BUDGET_TOKENS } from "@oml/core"

const limit = DEFAULT_BUDGET_TOKENS

try {
  const report = await measureReport(limit)
  const { totalTokens, budget } = report
  console.log(`prompt_tokens=${totalTokens} limit=${budget.limit} status=${budget.status}`)
  // 超限 → exit 1（CI 门禁）
  process.exit(totalTokens > limit ? 1 : 0)
} catch (err) {
  // 底层 @oml/core 缺实现时报告到 stderr，不静默吞错
  console.error(`bench:prompt 失败: ${err instanceof Error ? err.message : String(err)}`)
  process.exit(1)
}
