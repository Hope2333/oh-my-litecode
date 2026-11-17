/**
 * TUI 子代理折叠状态行（纯函数）。
 *
 * 用户要的效果（原话样例）：
 *   Sisyphus-Junior 任务 — t11 批量编辑与父/子范围
 *   ↳ Bash cd /home/... && grep ...  本轮用了 N 次工具 ↓新增 X.XK ✏累计 Y.YK
 *   出错时当前工具段显示失败码（一般 3 位）+ 重试倒计时
 *
 * 边界（公理 A2：写清楚谁负责什么）：
 *   - OML 负责**内容**：每任务一行机器可读状态（任务名、最近工具/命令头、
 *     本轮工具次数、新增 token（下载侧）、累计读取 token、失败码）。
 *   - 宿主 TUI 负责**呈现**：折叠/展开 UI、重试倒计时（只有宿主知道下次重试
 *     何时发生，OML 插件层拿不到宿主定时器）。倒计时留占位，宿主可填。
 */

/** 1500 → "1.5K"，2_400_000 → "2.4M"，999 → "999"。 */
export function compactTok(n: number | undefined): string {
  if (n === undefined) return "—"
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`
  return String(n)
}

/** 命令头：取第一条命令行前 60 字符，去换行，截断加省略号。 */
export function commandHead(cmd: string | undefined, max = 60): string {
  if (cmd === undefined || cmd === "") return ""
  const head = (cmd.split("\n")[0] ?? "").trim()
  return head.length > max ? `${head.slice(0, max)}…` : head
}

export interface StatusLineInput {
  /** 代理名，缺省 "任务" */
  agent?: string
  /** 任务 id（t11） */
  id: string
  /** 任务名/描述（截断） */
  name?: string
  /** 本轮用了多少次工具 */
  toolUses?: number
  /** 本轮新增（下载侧）token，原始数 */
  newTokens?: number
  /** 累计读取 token，原始数 */
  cumTokens?: number
  /** 当前/最近工具名（Bash/Read/…） */
  tool?: string
  /** bash 类工具用的命令头 */
  commandHead?: string
  /** 出错：失败码（一般 3 位）；倒计时若宿主可感知则填 */
  error?: { code?: string; countdown?: number }
}

/** 生成折叠状态行（1–2 行）。宿主 TUI 拿到的就是这两行。 */
export function formatStatusLine(x: StatusLineInput): string {
  const title = `${x.agent ?? "任务"} ${x.id}${x.name !== undefined && x.name !== "" ? " " + x.name : ""}`
  let line = "↳"
  const bits: string[] = []
  if (x.tool !== undefined || x.commandHead !== "") {
    bits.push([x.tool ?? "", x.commandHead ?? ""].filter(Boolean).join(" "))
  } else {
    bits.push("—")
  }
  if (x.toolUses !== undefined) bits.push(`×${x.toolUses}`)
  bits.push(`↓${compactTok(x.newTokens)}`)
  bits.push(`✏${compactTok(x.cumTokens)}`)
  line += " " + bits.join(" ")
  if (x.error !== undefined) {
    const code = x.error.code !== undefined ? String(x.error.code) : "ERR"
    line += ` ✗${code}`
    if (x.error.countdown !== undefined) line += ` 重试${x.error.countdown}s`
  }
  return `${title}\n${line}`
}
