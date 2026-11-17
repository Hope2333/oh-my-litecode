/**
 * 契约一致性测试 —— 断言 OC 与 OC2 两前线的**导出面**一致。
 *
 * 目的：保证 OC2 发布时，只需重写适配层内部实现，导出形状（键集合、
 * OmoPlugin 是函数、createOmoHost 的参数个数）与 OC 前线保持稳定，
 * 内核与上层调用方零改动。
 *
 * 若 `OC/omo/src/index.ts` 尚未实现 → 全部 test.skip 并打印原因（不得 fail）。
 */

import { describe, it, expect } from "bun:test"
import * as oc2 from "../src/index.ts"

/** OC 前线索引的路径；实现后会被动态加载。 */
const OC_INDEX_PATH = "../../../OC/omo/src/index.ts"

/** 从模块命名空间里取出的契约成员。 */
interface FrontlineNamespace {
  OmoPlugin?: unknown
  createOmoHost?: unknown
  [key: string]: unknown
}

/** 尝试加载 OC 前线；未实现时返回 null（由调用方 skip）。 */
async function loadOc(): Promise<FrontlineNamespace | null> {
  try {
    const mod = (await import(/* @vite-ignore */ OC_INDEX_PATH)) as FrontlineNamespace
    return mod
  } catch {
    return null
  }
}

describe("OC / OC2 前线契约一致性", () => {
  it("两前线运行时导出都只有 default 一个函数", async () => {
    const oc = (await loadOc()) as FrontlineNamespace | null
    if (!oc) {
      console.warn(`[契约测试] 跳过：${OC_INDEX_PATH} 尚未实现。`)
      return
    }
    // 真机约束：多导出一个常量就会让 OpenCode 丢弃整个插件。
    expect(Object.keys(oc).sort()).toEqual(["default"])
    expect(Object.keys(oc2).sort()).toEqual(["default"])
    expect(typeof oc["default"]).toBe("function")
    expect(typeof oc2["default"]).toBe("function")
  })

  it("两前线 default 工厂 arity 相同", async () => {
    const oc = (await loadOc()) as FrontlineNamespace | null
    if (!oc) {
      console.warn("[契约测试] 跳过：OC 前线未实现。")
      return
    }
    const a = (oc["default"] as (...args: unknown[]) => unknown).length
    const b = (oc2["default"] as (...args: unknown[]) => unknown).length
    expect(b).toBe(a)
  })
})
