#!/usr/bin/env bun
// omo main —— CLI 入口。零依赖，手写 argv 解析（公理 A7：自力更生）。
import { runMcp } from "./commands/mcp.ts"
import { runMeasure } from "./commands/measure.ts"
import { runAudit } from "./commands/audit.ts"
import { runSlim } from "./commands/slim.ts"
import { runZhengfeng } from "./commands/zhengfeng.ts"
import { runConfig, runSkills, runTasks } from "./commands/inspect.ts"
import { runDoctor, runInstall } from "./commands/host.ts"
import { runGoal, runHandoff, runSlop, runStop } from "./commands/session.ts"
import { runShare } from "./commands/share.ts"
import { runSettings, runUpgrade } from "./commands/third.ts"

const HELP = `omo — OML 编排层命令行（度量 / 审计 / 瘦身 / 整风）

用法:
  omo measure [--json] [--limit N]   度量空闲会话系统提示注入量
  omo skills [查询...] [--limit=N]   按任务检索技能（真实技能根）
  omo audit [--skills] [--structure] 审计技能命中与结构超限（无参数 = 全开）
  omo slim [--dry-run] [--apply]     列出/清理配置备份（默认 dry-run，显式 --apply 才删）
  omo tasks [--all]                  查看任务账本
  omo mcp [list|sync|enable <id>|disable <id>]  MCP 目录（全量登记、默认禁用）
  omo config [目录]                  显示生效配置及来源
  omo zhengfeng [--out PATH]         生成整风报告 markdown
  omo doctor [--json]                诊断宿主足迹（OML/技能/MCP/插件）并给建议
  omo install [--apply]              把 OML 接入 OpenCode（默认 dry-run）
  omo goal [set <文本>|show|clear]  目标账本（进系统提示 memory 段）
  omo stop                           中止所有未终结任务（账本保留）
  omo handoff [--print]              生成交接文档（默认写 <stateDir>/handoff/）
  omo share export|import          经验包（压缩块/记忆/技能）导出与合并
  omo help                           显示本帮助
`

async function main(): Promise<number> {
  const argv = process.argv.slice(2)
  const cmd = argv[0]
  const rest = argv.slice(1)

  switch (cmd) {
    case "measure":
      return runMeasure(rest)
    case "audit":
      return runAudit(rest)
    case "slim":
      return runSlim(rest)
    case "skills":
      return runSkills(rest)
    case "tasks":
      return runTasks(rest)
    case "config":
      return runConfig(rest)
    case "zhengfeng":
      return runZhengfeng(rest)
    case "doctor":
      return runDoctor(rest)
    case "install":
      return runInstall(rest)
    case "mcp":
      return runMcp(rest)
    case "goal":
      return runGoal(rest)
    case "stop":
      return runStop(rest)
    case "share":
      return runShare(rest)
    case "handoff":
      return runHandoff(rest)
    case "settings":
      return runSettings(rest)
    case "upgrade":
      return runUpgrade(rest)
    case "slop":
      return runSlop(rest)
    case "help":
    case "--help":
    case "-h":
    case undefined:
      console.log(HELP)
      return 0
    default:
      console.error(`omo: 未知命令 "${String(cmd)}"`)
      console.error(HELP)
      return 2
  }
}

main()
  .then((code) => process.exit(code))
  .catch((err: unknown) => {
    // 顶层兜底：不静默吞错，错误走 stderr
    console.error(`omo: 未捕获错误: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}`)
    process.exit(1)
  })
