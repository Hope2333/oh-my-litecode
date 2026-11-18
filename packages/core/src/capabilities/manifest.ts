/**
 * 常驻能力目录 —— 一张精简清单，让模型自己判断场景并取用能力。
 *
 * 病根：旧能力提示全是「命中正则才出」的纯函数，模型看不到目录、不会主动用，
 * 场景判断交给了正则而不是模型。本模块把判断权交还模型：能力常驻在 system
 * 提示里，正则提示只作为「明确命中才补一句」的强化（不改它们）。
 *
 * 纯函数、零 IO：只生成文本，开关由 config 决定，装配由 prompt/build.ts 负责。
 */

/** 一条能力的描述：何时用（scene）、怎么调（how）。id 为稳定短名，供 disabled 过滤。 */
export interface CapabilityDescriptor {
  /** 稳定短名，例如 "context7"；仅用于过滤与 compact 模式 */
  id: string
  /** 什么时候用这个能力（模型据此自己判断场景） */
  scene: string
  /** 具体怎么调，命令串与真实工具一致 */
  how: string
}

/**
 * 全部内置能力。每条一句话；命令串必须与真实工具名/参数一致，
 * 否则模型照着调用会失败（证据先于结论）。
 */
export const CAPABILITIES: readonly CapabilityDescriptor[] = [
  { id: "context7", scene: "查库/框架文档与 API", how: "omo_admin action=mcp op=enable target=context7；omo_mcp call 查文档" },
  { id: "eigenflux", scene: "外部事实/找 agent/广播", how: "omo_mcp call 走 agent 网络；写操作先授权" },
  { id: "model", scene: "热切 agent/类别模型档", how: "omo_admin action=model op=set" },
  { id: "vision", scene: "图/PDF 看不见", how: "换视觉模型（omo_admin action=model op=set）或 look" },
  { id: "team", scene: "多层/并行任务组队", how: "omo_task（kind=team）派组；omo_channel 横向通信" },
  { id: "pa", scene: "删/改他人会话", how: "omo_admin action=pa op=request 先取授权" },
  { id: "compress", scene: "上下文到 85%/检查点", how: "omo_admin action=checkpoint 落盘；compress 压缩已消费区间" },
  { id: "skill", scene: "技能详情", how: "skill(name) 直载正文" },
] as const

export interface CapabilityManifestOptions {
  /** full=场景+调法；compact=短名+调法，每条约半行。默认 full。 */
  mode?: "full" | "compact"
  /** 按 id 屏蔽的能力，默认不屏蔽。 */
  disabled?: readonly string[]
}

const HEADER = "## 可用能力（按需启用，默认不启用以省 token）"

/**
 * 生成能力目录文本。纯函数：不改 CAPABILITIES、不读配置/文件/环境。
 */
export function buildCapabilityManifest(opts: CapabilityManifestOptions = {}): string {
  const mode = opts.mode ?? "full"
  const disabled = new Set(opts.disabled ?? [])
  const lines = CAPABILITIES.filter((c) => !disabled.has(c.id)).map((c) =>
    mode === "compact" ? `- ${c.id} → ${c.how}` : `- ${c.scene} → ${c.how}`,
  )
  return `${HEADER}\n${lines.join("\n")}`
}
