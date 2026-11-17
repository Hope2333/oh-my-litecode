/**
 * OMO 插件入口（OpenCode 1.x）。
 *
 * **真机教训（1.19.3）**：插件模块的每一个运行时导出都必须是函数。
 * 只要存在一个非函数导出（例如常量字符串），加载器就报
 * `Plugin export is not a function` 并把整个插件丢弃。
 * 因此这里**只**导出 default 一个函数；标记、工厂、类型全部留在 host.ts。
 */
import type { Plugin } from "@opencode-ai/plugin"
import { createOmoHost } from "./host.ts"

const OmoPlugin: Plugin = async (input) => createOmoHost(input)

export default OmoPlugin
