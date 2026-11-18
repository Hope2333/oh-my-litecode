/**
 * OC2（OpenCode 2.x）插件上下文的最小 structural types。
 *
 * 本机装不上 `@opencode/plugin` 2.x（node 损坏 libada.so.3、npm 不可达），
 * 故这里按官方 V1→V2 迁移文档（opencode.ai/docs/build/plugins/migrate-v1）
 * 用鸭子类型自述 V2 domain API。字段**宽松但真实**：真机签名一旦确认，
 * 只需收紧本文件，bridge.ts / client-v2.ts 的翻译逻辑不动（A4 单一写入者）。
 *
 * 所有 V2 调用都是**理论映射**，未真机验证；签名不确定处由调用方抛
 * informative throw，绝不伪装成功。
 */

/** V2 tool / event 的通用 part（V1 Part 的宽松超集）。 */
export interface V2Part {
  type: string
  [key: string]: unknown
}

/** V2 `event.system` 的元素：官方文档为 `{type:"text", text:string}`。 */
export interface V2SystemPart {
  type: "text"
  text: string
}

/** context / prompt / compaction 三种 session hook 共用的宽松事件。 */
export interface V2HookEvent {
  sessionID?: string
  messageID?: string
  agent?: string
  model?: { providerID?: string; modelID?: string }
  variant?: string
  parts?: V2Part[]
  message?: unknown
  /** `ctx.session.hook("context")` 的事件载荷（对象数组）。 */
  system?: V2SystemPart[]
  /** `ctx.session.hook("compaction")` 的事件载荷（对象数组或字符串数组，形状待真机确认）。 */
  context?: V2SystemPart[] | string[]
  prompt?: string
  [key: string]: unknown
}

/** `ctx.permission.hook("evaluate")` 的事件载荷。 */
export interface V2PermissionEvent {
  sessionID?: string
  type?: string
  pattern?: string
  status: "ask" | "deny" | "allow"
  [key: string]: unknown
}

/** `ctx.event.subscribe()` 流式推送的事件（V1 Event 的宽松超集）。 */
export interface V2Event {
  type: string
  properties?: Record<string, unknown>
  [key: string]: unknown
}

/** 注册/transform 的返回：可返回 cleanup 函数。 */
export type V2Cleanup = () => void
export type V2Registration = void | V2Cleanup | Promise<void | V2Cleanup>

/** `editor.add()` 注册的单个工具定义（V2 用 JSON Schema，execute 返回 `{content}`）。 */
export interface V2ToolRegistration {
  name: string
  description: string
  input: Record<string, unknown>
  execute(args: Record<string, unknown>, ctx?: V2ToolContext): Promise<{ content: string }>
}

/** V2 工具执行上下文（V1 ToolContext 的宽松投影）。 */
export interface V2ToolContext {
  sessionID?: string
  messageID?: string
  agent?: string
  directory?: string
  worktree?: string
  abort?: AbortSignal
  metadata?(input: { title?: string; metadata?: Record<string, unknown> }): void
  ask?(input: { permission: string; patterns: string[]; always: string[]; metadata: Record<string, unknown> }): Promise<void>
}

export interface V2ToolEditor {
  add(def: V2ToolRegistration): void
  remove?(name: string): void
  [key: string]: unknown
}

/** V2 host client 的会话操作（对应 V1 SDK client.session，形状待真机确认）。 */
export interface V2HostClient {
  session?: {
    create?(input: Record<string, unknown>): Promise<unknown>
    update?(input: Record<string, unknown>): Promise<unknown>
    prompt?(input: Record<string, unknown>): Promise<unknown>
    abort?(input: Record<string, unknown>): Promise<unknown>
    messages?(input: Record<string, unknown>): Promise<unknown>
    list?(input: Record<string, unknown>): Promise<unknown>
    delete?(input: Record<string, unknown>): Promise<unknown>
    [key: string]: unknown
  }
  [key: string]: unknown
}

export interface V2ToolDomain {
  transform(editor: (editor: V2ToolEditor) => void | Promise<void>): V2Registration
}
export interface V2SessionDomain {
  hook(
    name: "prompt" | "context" | "compaction",
    handler: (event: V2HookEvent) => void | Promise<void>,
  ): V2Registration
}
export interface V2PermissionDomain {
  hook(
    name: "evaluate",
    handler: (event: V2PermissionEvent) => void | Promise<void>,
  ): V2Registration
}
export interface V2AgentDomain {
  transform(editor: (agents: Record<string, unknown>) => void | Promise<void>): V2Registration
}
export interface V2EventStream {
  [Symbol.asyncIterator](): AsyncIterator<V2Event>
}
export interface V2EventDomain {
  subscribe(options?: { signal?: AbortSignal }): V2EventStream | Promise<V2EventStream>
}
export interface V2Location {
  directory: string
  worktree?: string
}

/** OC2 插件上下文的最小结构（真机多余字段忽略）。 */
export interface Oc2Context {
  location: V2Location
  client?: V2HostClient
  options?: Record<string, unknown>
  storage?: Record<string, unknown>
  tool: V2ToolDomain
  session: V2SessionDomain
  permission: V2PermissionDomain
  agent: V2AgentDomain
  event: V2EventDomain
  [key: string]: unknown
}

export interface V2PluginDefinition {
  id: string
  setup?: (ctx: Oc2Context) => void | V2Cleanup | Promise<void | V2Cleanup>
  effect?: (ctx: Oc2Context) => void | V2Cleanup | Promise<void | V2Cleanup>
  [key: string]: unknown
}

/**
 * `Plugin.define` 恒等助手：只做类型约束、原样返回，不 import `@opencode/plugin`。
 * 真机装得上 2.x 时可替换为官方实现，调用方零改动。
 */
export const Plugin = {
  define<T extends V2PluginDefinition>(def: T): T {
    return def
  },
}
