/**
 * EigenFlux 主动使用提示 —— 纯函数，零 IO（质量探测 P·EigenFlux 落地）。
 *
 * 目的：让会话在「符合需求时」主动想到 EigenFlux，而不是等用户显式点名。
 * 边界（来自 neko-eigenflux 技能红线）：
 *   - 只读检索（search/recommend/feed）可主动提示；
 *   - 写操作（发消息/广播/发布）必须每次先取得用户明确授权；
 *   - 心跳周期**不主动触发**——本机是 terminal 宿主、调度器 status:unknown，
 *     技能要求「持久化验证过的调度器才跑心跳」，会话内跑属违规。
 *
 * 命中才出、预算外追加区：与 host.ts 的 visionHint / mcpHint 同一模式。
 * 判定是纯字符串匹配，零模型调用、零成本；漏判可恢复（用户仍可显式点名）。
 */

/** 只读检索触发词：外部事实 / 最新 / 调研 / 有没有现成的。 */
const READONLY_PATTERNS: readonly RegExp[] = [
  /(外部事实|联网|网络上?|最新|现成|有没有.*(服务|方案|实现|工具)|行业动态|前沿|别人怎么|社区里有|调研|检索.*网络|搜.*网络)/,
  /\b(search|latest|web|online|up[- ]to[- ]date|research)\b/i,
]

/** 写操作触发词：找 agent / 联系 / 发消息 / 广播 / 发布 / 里程碑。 */
const WRITE_PATTERNS: readonly RegExp[] = [
  /(找.*agent|联系.*agent|给.*发消息|私信|回复.*(agent|广播|feed)|广播|发布.*(网络|平台|到网络)|分享.*网络|里程碑|通知.*agent|加好友|朋友圈)/,
  /\b(broadcast|publish|dm|message .*agent|notify .*agent)\b/i,
]

/** 心跳触发词——命中也只提示「不主动跑」，绝不触发。 */
const HEARTBEAT_PATTERN = /(心跳|heartbeat|定时检查|自动检查)/i

export interface EigenFluxHintOptions {
  /** 总开关，默认开（尊重「能关就关」）。 */
  enabled?: boolean
}

/** 任务文本是否命中「只读检索」场景。 */
export function wantsReadonly(text: string): boolean {
  return READONLY_PATTERNS.some((re) => re.test(text))
}

/** 任务文本是否命中「写操作」场景。 */
export function wantsWrite(text: string): boolean {
  return WRITE_PATTERNS.some((re) => re.test(text))
}

/**
 * 命中才返回提示文本；否则返回空串（host 据此决定是否注入）。
 * 写操作提示内嵌「先取得用户授权」红线，心跳提示明确「会话内不主动跑」。
 */
export function eigenfluxHint(taskText: string, opts: EigenFluxHintOptions = {}): string {
  if (opts.enabled === false || taskText.trim() === "") return ""
  const parts: string[] = []

  if (wantsReadonly(taskText)) {
    parts.push(
      "本机已接入 EigenFlux agent 网络。查外部事实/最新/现成方案可走只读检索：" +
        "`eigenflux search/recommend/feed poll`（只读，不发布）。操作规范见技能 neko-eigenflux。",
    )
  }
  if (wantsWrite(taskText)) {
    parts.push(
      "涉及发消息/广播/发布的动作走 EigenFlux（ef-communication / ef-broadcast），" +
        "**每次发布或对外发送前必须先取得用户明确授权**；不代处理邮箱/OTP。",
    )
  }
  if (HEARTBEAT_PATTERN.test(taskText)) {
    parts.push(
      "EigenFlux 心跳需持久化调度器驱动，本机 terminal 宿主未验证，**会话内不主动跑心跳**。" +
        "如需常驻由用户另行配置。",
    )
  }

  if (parts.length === 0) return ""
  return `\n## EigenFlux 可用能力\n- ${parts.join("\n- ")}`
}
