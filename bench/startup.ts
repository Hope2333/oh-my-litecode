#!/usr/bin/env bun
// bench/startup —— 内核冷启动延迟基准（目标 p95 ≤100ms）。
// 反复动态 import("@oml/core") 20 次，报告 p50 / p95 毫秒；p95 >100ms → exit 1。
const RUNS = 20
const P95_BUDGET_MS = 100

/** 计算百分位（最近秩法）。 */
function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0
  const idx = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)
  return sorted[Math.max(0, idx)]!
}

const samples: number[] = []
for (let i = 0; i < RUNS; i++) {
  const t0 = performance.now()
  await import("@oml/core")
  samples.push(performance.now() - t0)
}

samples.sort((a, b) => a - b)
const p50 = percentile(samples, 50)
const p95 = percentile(samples, 95)

console.log(`startup runs=${RUNS} p50=${p50.toFixed(2)}ms p95=${p95.toFixed(2)}ms budget=${P95_BUDGET_MS}ms`)
if (p95 > P95_BUDGET_MS) {
  console.error(`bench:startup 失败: p95 ${p95.toFixed(2)}ms 超过 ${P95_BUDGET_MS}ms`)
  process.exit(1)
}
process.exit(0)

export {}
