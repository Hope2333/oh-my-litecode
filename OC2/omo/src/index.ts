/**
 * OC2（OpenCode 2.x）前线 —— 插件入口。
 *
 * 与 OC 前线同一条真机约束（1.19.3 实测）：插件模块的每个运行时导出都必须
 * 是函数，多一个字符串常量就会被整体丢弃。故这里只导出 default。
 */

import type { Hooks } from "@opencode-ai/plugin"
import { createOc2Host } from "./host.ts"

const OmoPlugin = async (input: unknown): Promise<Hooks> => createOc2Host(input)

export default OmoPlugin
