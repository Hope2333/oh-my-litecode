/**
 * OC2（OpenCode 2.x）插件上下文的最小 structural types。
 *
 * 真机 2.3.0 证据（docs/bench/oc2-realmachine-2026-11-18.md）确认：
 *   - setup ctx 没有 `ctx.client`，会话 API 全在 `ctx.session.*`；
 *   - `session.create/update/prompt/get/list/remove/interrupt` 都是 1 参 RPC 包装，
 *     返回解码后的 body（无 `{data:}` 外壳，翻译层仍兼容两种形状）；
 *   - `session.hook` 3 参；没有 `messages/abort/delete`（用 `get/interrupt/remove` 代替）。
 * 字段保持**宽松**：RPC 方法声明为可选，使仅注册 hook 的 fake ctx（如 bridge.test.ts）
 * 仍可编译；client-v2.ts 在调用时才校验能力并 informative throw（A4 单一写入者）。
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

/**
 * 旧版「V1 SDK 风格 client」的会话形状（保留仅为兼容历史 ctx.client 字段类型）。
 * 真机 2.3.0 的 setup ctx **没有 `ctx.client`**；clientFromContext 已改读 `ctx.session.*`，
 * 不再依赖本接口。签名未真机核实，故全部可选。
 */
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
  /** 真机签名是 3 参 (name, handler, opts)；bridge.ts 用 2 参，故第 3 参可选。 */
  hook(
    name: "prompt" | "context" | "compaction",
    handler: (event: V2HookEvent) => void | Promise<void>,
    options?: Record<string, unknown>,
  ): V2Registration
  // 真机确认的 1 参 RPC 包装：内部 zod decode，返回解码 body（Promise<unknown>）。
  // 声明为可选：仅注册 hook 的 fake ctx 无需提供；能力缺失由 client-v2.ts 调用时抛 informative throw。
  create?(input: Record<string, unknown>): Promise<unknown>
  update?(input: Record<string, unknown>): Promise<unknown>
  prompt?(input: Record<string, unknown>): Promise<unknown>
  get?(input: Record<string, unknown>): Promise<unknown>
  list?(input: Record<string, unknown>): Promise<unknown>
  remove?(input: Record<string, unknown>): Promise<unknown>
  interrupt?(input: Record<string, unknown>): Promise<unknown>
  /**
   * Windows 线真机观察：2.x `session.prompt` 的返回体可能不含最终 assistant 文本，
   * 答复要等异步生成后从 `session.context` 读；`session.wait` 用于等待生成完成。
   * 两者均为可选能力，缺失时 client-v2.ts 的兜底路径直接跳过后抛 informative throw。
   */
  context?(input: Record<string, unknown>): Promise<unknown>
  wait?(input: Record<string, unknown>): Promise<unknown>
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
