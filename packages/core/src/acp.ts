/**
 * ACP/压缩路由（纯函数，零 IO）。
 *
 * 消灭的矛盾：宿主侧长会话压缩路由「各宿主各维护一份、谁也不知道该装哪个」。
 * 路由策略是**人的决策**（谁定的、为什么定），固化成代码后 doctor/install
 * 只需查表，不再每次靠记忆。
 *
 * 路由表（2026-11 定的策略，改策略改这里并写理由）：
 *   - OpenCode 1.x      → `opencode-acp`（宿主原生 ACP 生态，v1 硬带）
 *   - OpenCode 2.x      → `billion-context`（多宿主模型驱动分层压缩，v2 无原生 ACP）
 *   - dsh / dsh-codex / 未来宿主 → `billion-context`（它自己声明支持 20+ 宿主）
 *
 * 与 OML 自身 `compress/store.ts` 的分工（不重复造轮子）：
 *   - 宿主 ACP 插件 = **流式引擎**：在 agent 与模型 API 之间做前缀缓存友好的
 *     增量分层压缩，管「会话活多久」。
 *   - OML compress = **账本**：把已消费区间折成 bN 块供 handoff/恢复，
 *     管「交给人或下一个会话时给什么」。引擎可换宿主，账本跟着 OML 走。
 */

export type AcpPlugin = "opencode-acp" | "billion-context"

export interface AcpHost {
  /** 宿主名：opencode / dsh / dsh-codex / …（未知值走未来宿主默认） */
  name: string
  /** 宿主版本，如 "1.19.3"；未知宿主可不填 */
  version?: string
}

export interface AcpDecision {
  plugin: AcpPlugin
  /** 人话理由：doctor 直接打印，install 写进 oml.json 注释位 */
  reason: string
}

/** 从 "1.19.3" / "v2.0.0-rc" / 垃圾值里取主版本号；取不到返回 undefined。 */
export function majorOf(version: string | undefined): number | undefined {
  if (version === undefined) return undefined
  const m = version.match(/(\d+)/)
  return m ? Number(m[1]) : undefined
}

/**
 * 查表定 ACP 插件。纯函数，可测。
 * 未知宿主（dsh codex、未来者）默认走 billion-context——它的卖点就是
 * 「20+ 宿主通用」，未来宿主大概率也在名单里。
 */
export function pickAcp(host: AcpHost): AcpDecision {
  const major = majorOf(host.version)
  if (host.name === "opencode") {
    if (major === undefined || major <= 1) {
      return { plugin: "opencode-acp", reason: `OpenCode v${major ?? "1"}（v1 硬带 opencode-acp）` }
    }
    return { plugin: "billion-context", reason: `OpenCode v${major}（v2 用 billion-context）` }
  }
  // dsh / dsh-codex / 未来宿主
  return {
    plugin: "billion-context",
    reason: `宿主 ${host.name}${host.version === undefined ? "" : " v" + host.version}（非 OpenCode v1，统一走 billion-context）`,
  }
}

/** 已装的插件列表里有没有这个 ACP 插件（做前缀匹配，容忍 "@scope/acp-x" 变体）。 */
export function hasAcpPlugin(plugins: readonly string[], name: string): boolean {
  return plugins.some((p) => p === name || p.endsWith(`/${name}`) || p.startsWith(name))
}
