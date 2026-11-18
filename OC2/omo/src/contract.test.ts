/**
 * 契约一致性测试 —— OC（V1 函数插件）与 OC2（V2 对象插件）能力等价。
 *
 * V2 形态下 OC2 default 是 `{id, setup, server}` 对象，OC default 仍是函数，
 * 故旧的「default 都是函数 / arity 相同」断言已过时。本测试改为断言：
 * 1. OC2 default 是对象且 id==="oml.oc2"，setup / server 都是函数；
 * 2. OC default 仍是函数（V1 形态不变）；
 * 3. 两前线能力等价 —— OC2 声明的 6 个工具名 == OC host 实际注册的工具名。
 *
 * 若 OC 前线索引尚未实现 → 相关断言 skip 并打印原因（不得 fail）。
 */

import { describe, it, expect } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import * as oc2 from "../src/index.ts"
import { createOmoHost } from "../../../OC/omo/src/host.ts"
import { ALL_V2_TOOL_NAMES } from "./bridge.ts"

const OC_INDEX_PATH = "../../../OC/omo/src/index.ts"

interface FrontlineNamespace {
  default?: unknown
  [key: string]: unknown
}

async function loadOc(): Promise<FrontlineNamespace | null> {
  try {
    return (await import(/* @vite-ignore */ OC_INDEX_PATH)) as FrontlineNamespace
  } catch {
    return null
  }
}

describe("OC / OC2 前线契约一致性（V2 理论插件）", () => {
  it("OC2 default 是 V2 定义对象（id/setup/server），OC default 仍是 V1 函数", async () => {
    const oc = await loadOc()
    if (!oc) {
      console.warn(`[契约测试] 跳过 OC 侧断言：${OC_INDEX_PATH} 尚未实现。`)
    } else {
      expect(typeof oc["default"]).toBe("function")
    }

    const def = oc2.default as unknown as Record<string, unknown>
    expect(typeof def).toBe("object")
    expect(def !== null).toBe(true)
    expect(def["id"]).toBe("oml.oc2")
    expect(typeof def["setup"]).toBe("function")
    expect(typeof def["server"]).toBe("function")
  })

  it("OC2 运行时只导出 default 一个值（V1 真机约束：多导出一个值可能被加载器丢弃）", () => {
    expect(Object.keys(oc2)).toEqual(["default"])
  })

  it("两前线能力等价：OC2 的 6 个工具名 == OC host 实际工具名", async () => {
    const dir = mkdtempSync(join(tmpdir(), "oc2-contract-"))
    try {
      const ocInput = { directory: dir, client: {} } as unknown as Parameters<typeof createOmoHost>[0]
      const ocHooks = await createOmoHost(
        ocInput,
        { config: {}, skillRoots: [], stateDir: join(dir, "state") },
      )
      const ocToolNames = Object.keys(ocHooks.tool ?? {}).sort()
      const expected: string[] = [...ALL_V2_TOOL_NAMES].sort()
      expect(expected).toEqual(ocToolNames)
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})
