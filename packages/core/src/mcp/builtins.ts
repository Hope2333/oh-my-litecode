/**
 * OML 内置 MCP def —— 不写宿主 opencode.json。
 *
 * 消灭的矛盾：原版 OMO 的 Context7 是把 upstash 远程文档检索 MCP 当作「运行时注入的
 * 内置 MCP」接进宿主，于是宿主 opencode.json 常驻一个 MCP 条目、每个工具 schema
 * 又被宿主无条件注入（本机实测 4 个 MCP ≈ 27K tok）。这里把 def 收进 OML 内置模块，
 * 经 hostMcpDefs() merge 进目录：宿主配置永远看不到它，默认禁用，按需经 omo_mcp 调用。
 *
 * 反修定位：context7 = 官方文档证据层，结论须与本机包内源码/实测交叉验证，权威≠真理。
 * 记账：零新 tool / 零新 action / 零运行时依赖 / 零常驻 MCP（默认禁用）。
 */

import type { McpDef } from "./catalog.ts"

/**
 * 内置 def 常量。context7 默认禁用、无硬编码 key；API key 在 builtinMcpDefs() 里按环境
 * 注入，因此这份常量可以安全地被任意读取/快照，不会被运行时状态污染。
 */
export const BUILTIN_MCP_DEFS: Record<string, McpDef> = {
  context7: {
    type: "remote",
    url: "https://mcp.context7.com/mcp",
    enabled: false,
  },
}

/** 常见占位串：命中一律当「无 key」（无 key 也能用 context7 的公共限额）。 */
const PLACEHOLDER_API_KEYS = new Set([
  "your api key",
  "your-api-key",
  "your_api_key",
  "yourapikey",
  "api key",
  "api-key",
  "api_key",
  "your key",
  "placeholder",
  "changeme",
])

/**
 * 清洗 CONTEXT7_API_KEY：trim；空串 / 占位串 / 被引号或尖括号包裹的占位 → null。
 * 真 key（即使带空白）返回去空白后的值。无 key 返回 null——调用方据此省略 Authorization。
 */
export function normalizeContext7ApiKey(raw?: string): string | null {
  if (raw === undefined) return null
  let key = raw.trim()
  if (key === "") return null

  // 常见占位写法："abc" / 'abc' / <abc> / <your-api-key>
  const wrapped =
    (key.startsWith('"') && key.endsWith('"')) ||
    (key.startsWith("'") && key.endsWith("'")) ||
    (key.startsWith("<") && key.endsWith(">"))
  if (wrapped) key = key.slice(1, -1).trim()

  if (key === "" || PLACEHOLDER_API_KEYS.has(key.toLowerCase())) return null
  return key
}

/**
 * 返回带 key 清洗的内置 def 副本，**不修改** BUILTIN_MCP_DEFS 常量。
 * 有 key 时给 context7 加 `Authorization: Bearer <key>`；没有则保持原样（无 headers）。
 * env 可注入以便测试，默认读 process.env。
 */
export function builtinMcpDefs(env: NodeJS.ProcessEnv = process.env): Record<string, McpDef> {
  const apiKey = normalizeContext7ApiKey(env["CONTEXT7_API_KEY"])
  const defs: Record<string, McpDef> = {}
  for (const [id, def] of Object.entries(BUILTIN_MCP_DEFS)) {
    defs[id] = { ...def, ...(def.headers === undefined ? {} : { headers: { ...def.headers } }) }
  }
  if (apiKey !== null && defs["context7"] !== undefined) {
    defs["context7"] = { ...defs["context7"], headers: { Authorization: `Bearer ${apiKey}` } }
  }
  return defs
}
