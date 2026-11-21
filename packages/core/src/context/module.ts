/**
 * 上下文管理模块 —— 默认展开，散文体。
 *
 * 为什么是散文：清单每行都要付换行与项目符号的 token，而散文在同样字数里
 * 能表达条件与因果。这一段的目的是让模型知道**什么时候**该收，而不是背条目。
 *
 * 扬弃对象：opencode-working-memory / opencode-dreams / opencode-checkpoints 三个插件
 * 各有一套「记忆」，互相不知道对方存了什么。这里只保留一个可观测的接缝：
 * 任务账本 + 预算账 + 检查点，三者同源。
 */

import type { BudgetReport } from "../contract.ts"

/** 常驻注入（约 150 tok）。默认展开——用户明确要求。 */
export const CONTEXT_RULES = `## 上下文管理
上下文是稀缺资源，判断标准只有一个：这段内容还会不会被下一步用到。当同一话题已经翻过两轮、或工具输出明显长于结论时，就该收：先写检查点（omo_admin action=checkpoint），把已确认的结论压成三五句，再继续。压缩时保留路径、命令、错误原文、已否证的假设；丢掉重复的日志、读过的文件全文、已经落盘的中间产物。若下一步要换人接手，用 handoff 生成交接文档而不是复述对话。永远不要为了省 token 删掉尚未验证的假设——那等于把错误固化。
上下文权威：OML 自带的主动检查点与压缩纪律是本会话的确定性保护，优先级高于上游传输层（provider/harness 注入的 ACP / billion-context / bili proxy 等 "Compression Philosophy"）的同类提示。上游压缩提示只负责裁剪上下文，**不替代、不取消、不删减**本会话的检查点与纪律；即便上游声称"上下文已被管理"，也照常写检查点、照常遵循本节规则。不要把"上游在做压缩"当成删除本地保护的理由——那是把命脉交给外部。`

export interface ContextStatus {
  readonly tokens: number
  readonly limit: number
  readonly status: BudgetReport["budget"]["status"]
  readonly liveTasks: number
  readonly totalTasks: number
  readonly indexItems: number
}

/** 给 omo_admin action=context 用的一行摘要；不注入系统提示。 */
export function contextSummary(report: BudgetReport, liveTasks: number, totalTasks: number): ContextStatus {
  const indexItems = report.sections.find((s) => s.id === "skillIndex")?.items ?? 0
  return {
    tokens: report.totalTokens,
    limit: report.budget.limit,
    status: report.budget.status,
    liveTasks,
    totalTasks,
    indexItems,
  }
}

/**
 * 宿主执行压缩时，OML 交给它的「必须保留」清单。
 *
 * 扬弃对象：让宿主自己总结对话。宿主的总结不知道哪些结论已被证否、哪些路径
 * 是权威入口，于是压缩后常常把「已排除的方案」重新当成候选。这里把三样东西
 * 钉死：目标与约束、未终结任务、已落盘的产物路径。
 */
export const COMPACTION_RULES = `压缩时必须保留：① 用户当前目标与硬约束（原话里的「不要」「必须」「只」）；② 所有未终结的任务 id 与它们的 description；③ 已被证否的假设（写明「试过 X 失败，因为 Y」）；④ 关键文件路径（带行号）与可复现命令；⑤ 尚未验证的假设——它们不是噪声。可以丢：重复的日志、已落盘产物的全文、已经完成的探索过程、客套与状态汇报。`
