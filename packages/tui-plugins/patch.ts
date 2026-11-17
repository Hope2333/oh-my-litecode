/**
 * OML fork 补丁：把上游 opencode TUI 插件的 prebuilt bundle 变成 OML 维护版。
 *
 * 纯函数，无 IO、无网络，便于测试与复现。sync.ts 负责读 bundle/ → apply → 写 live cache。
 *
 * 设计约束（用户 B 路线决策）：
 *   - 不改插件的 slot id / npm 名 → tui.json 与宿主 loader 仍认得，测试断言不动。
 *   - KV 前缀隔离是「幽灵会话」修复的核心：旧 subagent_magazine.session_data 是
 *     2026-11-12 TUI「Session not found」残留源；换前缀后永远不再读到旧残留。
 *   - 只迁移「用户设置」（lang/order/...），绝不迁 session_data —— 迁它等于把幽灵搬回来。
 *   - clearedIds / prune 逻辑一字不改（仍在 bundle 内，防幽灵的第二道闸）。
 *   - running 版本（magazine 1.5.2 / visual-cache 1.6.2）无 dbSync 开关，故不处理。
 */

export interface PatchResult {
  src: string
  /** 实际落地的替换计数（用于测试与幂等判定） */
  changes: Record<string, number>
}

/** 替换全部出现次数，返回次数（用于断言，不静默漏改）。 */
function replaceAll(src: string, from: string, to: string): { src: string; count: number } {
  const count = src.split(from).length - 1
  return { src: src.split(from).join(to), count }
}

const MAG_LEGACY_PREFIX = "subagent_magazine"
const MAG_NEW_PREFIX = "oml_subagent_magazine"
const VC_LEGACY_PREFIX = "cache_panel"
const VC_NEW_PREFIX = "oml_cache_panel"

/** 迁移块：只拷贝用户偏好键，显式排除 session_data。 */
const MAG_MIGRATION = `
  // ---- OML fork: 仅迁移用户设置，绝不迁 session_data（幽灵会话残留源）----
  try {
    const __omlLegacyPrefix = "${MAG_LEGACY_PREFIX}";
    const __omlSettings = ["lang", "max_entries", "order", "scroll_mode", "open", "ttl_days"];
    for (const __k of __omlSettings) {
      const __fresh = \`\${KV_PREFIX}.\${__k}\`;
      if (api.kv.get(__fresh, null) == null) {
        const __old = api.kv.get(\`\${__omlLegacyPrefix}.\${__k}\`, null);
        if (__old != null) api.kv.set(__fresh, __old);
      }
    }
  } catch {}
  // ---- end OML fork ----
`

/**
 * Magazine 补丁：KV 前缀隔离 + 设置迁移 + fork 版本标记。
 * 幂等：已是新前缀时 prefix 替换计数为 0，迁移块不重复注入。
 */
export function patchMagazine(input: string): PatchResult {
  let src = input
  const changes: Record<string, number> = {}

  // 1) 前缀声明（仅 1 处）
  let r = replaceAll(src, `var KV_PREFIX = "${MAG_LEGACY_PREFIX}";`, `var KV_PREFIX = "${MAG_NEW_PREFIX}";`)
  src = r.src
  changes["mag.prefixDecl"] = r.count

  // 2) 注入迁移块（紧跟 tui 入口，仅在新前缀且未注入过时）
  const anchor = "var tui = async (api) => {"
  const alreadyMigrated = src.includes("__omlLegacyPrefix")
  if (changes["mag.prefixDecl"] > 0 && src.includes(anchor) && !alreadyMigrated) {
    r = replaceAll(src, anchor, anchor + MAG_MIGRATION)
    src = r.src
    changes["mag.migration"] = r.count
  } else {
    changes["mag.migration"] = 0
  }

  // 4) fork 版本标记（toast），仅替换展示字符串，不动 id
  r = replaceAll(src, "opencode-subagent-magazine v${PLUGIN_VERSION}", "OML fork · subagent-magazine v${PLUGIN_VERSION}")
  src = r.src
  changes["mag.versionToast"] = r.count

  return { src, changes }
}

/**
 * Visual-cache 补丁：KV 前缀隔离（3 处 KV_PREFIX + 1 处 .session 字面量）。
 * 幂等：已是新前缀时各计数为 0。
 */
export function patchVisualCache(input: string): PatchResult {
  let src = input
  const changes: Record<string, number> = {}

  let r = replaceAll(src, `const KV_PREFIX = "${VC_LEGACY_PREFIX}";`, `const KV_PREFIX = "${VC_NEW_PREFIX}";`)
  src = r.src
  changes["vc.prefixDecl"] = r.count

  r = replaceAll(src, `api.kv.set("${VC_LEGACY_PREFIX}.session", "")`, `api.kv.set("${VC_NEW_PREFIX}.session", "")`)
  src = r.src
  changes["vc.sessionKey"] = r.count

  return { src, changes }
}

/** 校验补丁是否达到预期（用于 sync 在写盘前 self-check，失败即拒写）。 */
export function verifyPatch(kind: "magazine" | "visual-cache", output: string): { ok: boolean; problems: string[] } {
  const problems: string[] = []
  if (kind === "magazine") {
    if (output.includes(`var KV_PREFIX = "${MAG_LEGACY_PREFIX}";`)) problems.push("magazine 仍是旧前缀")
    if (!output.includes(`var KV_PREFIX = "${MAG_NEW_PREFIX}";`)) problems.push("magazine 缺新前缀")
    if (!output.includes("__omlLegacyPrefix")) problems.push("magazine 缺设置迁移块")
    if (!output.includes(".session_data")) problems.push("magazine session_data 读写路径丢失（防幽灵闸失效）")
    if (!output.includes('id: "opencode-subagent-magazine"')) problems.push("magazine slot id 被改（会破坏 loader）")
    if (!output.includes("clearedIds")) problems.push("magazine clearedIds 防幽灵逻辑丢失")
  } else {
    if (output.includes(`"${VC_LEGACY_PREFIX}.session"`)) problems.push("visual-cache 仍有旧 session key")
    if (output.includes(`const KV_PREFIX = "${VC_LEGACY_PREFIX}";`)) problems.push("visual-cache 仍有旧前缀")
    if (!output.includes('id: "opencode-visual-cache"')) problems.push("visual-cache slot id 被改")
  }
  return { ok: problems.length === 0, problems }
}

export const PATCH_META = {
  magazine: { legacyPrefix: MAG_LEGACY_PREFIX, newPrefix: MAG_NEW_PREFIX, upstreamVersion: "1.5.2", npm: "opencode-subagent-magazine" },
  "visual-cache": { legacyPrefix: VC_LEGACY_PREFIX, newPrefix: VC_NEW_PREFIX, upstreamVersion: "1.6.2", npm: "opencode-visual-cache" },
} as const
