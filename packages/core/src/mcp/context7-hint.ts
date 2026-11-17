/**
 * Context7 提示 —— 纯函数，零 IO（沿用 eigenflux/hint.ts 的「命中才出、预算外追加区」模式）。
 *
 * 目的：让会话在遇到「库/框架文档、API 用法、官方 docs」类问题时想到走 Context7 证据层，
 * 而不是凭记忆编造 API。反修纪律：官方文档只是证据，不是真理——结论必须与本机包内源码
 * 或实测交叉验证，权威≠真理。默认禁用，按需 enable；零新 tool / 零新 action / 零成本判定。
 */

const DOC_PATTERNS: readonly RegExp[] = [
  // 中文：库/框架/sdk/组件 + 文档/用法/API；或 查/看/读 + 文档
  /(库|框架|sdk|组件|package).{0,12}(文档|怎么用|如何使用|用法|api)/i,
  /(文档|怎么用|如何使用|用法|api).{0,12}(库|框架|sdk|组件|package)/i,
  /\bapi\s*(用法|文档|参考)/i,
  /(官方|权威|最新).{0,4}(文档|docs)/i,
  /(查|看|读|翻|找).{0,8}(文档|docs)/i,
  // 英文
  /\b(official\s*docs?|documentation|api\s*reference)\b/i,
  /\bhow\s+to\s+use\b/i,
  /\b(library|framework|sdk|package).{0,24}\b(docs?|documentation|api|usage)\b/i,
  /\bcontext7\b/i,
]

/** 是否命中「库/框架文档 / API 用法 / 官方 docs」场景。纯字符串匹配。 */
export function wantsContext7Docs(taskText: string): boolean {
  return DOC_PATTERNS.some((re) => re.test(taskText))
}

export interface Context7HintOptions {
  /** 总开关，默认开（尊重「能关就关」）。 */
  enabled?: boolean
}

/**
 * 命中才返回提示文本；否则返回空串（host 据此决定是否注入，空闲 0 tok）。
 */
export function context7Hint(taskText: string, opts: Context7HintOptions = {}): string {
  if (opts.enabled === false || taskText.trim() === "") return ""
  if (!wantsContext7Docs(taskText)) return ""
  return (
    "\n## 文档证据（Context7）\n- " +
    "库/框架文档问题用 `omo_mcp call context7`（先 `resolve-library-id` 再 `query-docs`）；" +
    "context7 是官方文档证据层，结论须与本机包内源码/实测交叉验证，权威≠真理；" +
    "默认禁用，先 `omo_admin action=mcp op=enable target=context7`。"
  )
}
