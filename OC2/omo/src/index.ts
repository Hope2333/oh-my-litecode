/**
 * OC2（OpenCode 2.x）前线 —— 插件入口，**V2 理论兼容插件**。
 *
 * 官方 V1→V2 映射要求双形态：V2 用 `Plugin.define({id,setup(ctx)})` 的默认导出对象，
 * V1 用 `server(input)` 兼容入口（1.18.29+ 支持）。两种形态都只做翻译与委托，
 * 业务逻辑全部在 OC1 的 `createHostCore`（A4 单一写入者）。
 *
 * 本机装不上 `@opencode/plugin` 2.x，故 `Plugin` / `Oc2Context` 来自本地
 * structural types（v2-types.ts）；V2 domain 签名未真机验证，setup 中的 ctx 调用
 * 均为理论映射，签名不确定处抛 informative throw。
 *
 * 运行时只导出 default 一个对象（官方双形态 {id,setup,server}）：V1 真机约束
 * 「多导出一个运行时值就可能被加载器丢弃」在此同样适用。测试要 createOmoHost /
 * createOc2Host 时直接从各自 host.ts 导入，不经本入口。
 */
import type { Hooks } from "@opencode-ai/plugin"
import { createOc2Host } from "./host.ts"
import { clientFromContext } from "./client-v2.ts"
import { bridgeHooks } from "./bridge.ts"
import { Plugin, type Oc2Context } from "./v2-types.ts"

const OmoPlugin = {
  ...Plugin.define({
    id: "oml.oc2",
    async setup(ctx: Oc2Context) {
      const hooks = await createOc2Host({
        directory: ctx.location.directory,
        client: clientFromContext(ctx),
      })
      return bridgeHooks(ctx, hooks)
    },
  }),
  /** V1 兼容入口：仍返回 V1 Hooks，供 1.x 加载器调用。 */
  async server(input: unknown): Promise<Hooks> {
    return createOc2Host(input)
  },
}

export default OmoPlugin
