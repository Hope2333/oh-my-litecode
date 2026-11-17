import { describe, expect, test } from "bun:test"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  loadOwnership,
  saveOwnership,
  registerOmlSession,
  classifyOwner,
  isOmlOwned,
  reconcileWithHost,
  unknownSessions,
  type OwnershipLedger,
} from "./ownership.ts"

describe("所有权账本", () => {
  test("OML 创建的会话登记为 oml，可不经 PA 删除", () => {
    let ledger: OwnershipLedger = {}
    ledger = registerOmlSession(ledger, { id: "s1", directory: "/a", parentID: "p", title: "子任务" })
    expect(classifyOwner(ledger, "s1")).toBe("oml")
    expect(isOmlOwned(ledger, "s1")).toBe(true)
    expect(ledger["s1"]?.note).toBe("子任务")
  })

  test("未登记的会话判为 unknown（可能是人类建的）", () => {
    expect(classifyOwner({}, "human-session")).toBe("unknown")
    expect(isOmlOwned({}, "human-session")).toBe(false)
  })

  test("对账：host 有而账本无的会话补登为 unknown，重复对账幂等", () => {
    const first = reconcileWithHost({}, [
      { id: "h1", directory: "/home/miao", title: "OML/OMO" },
      { id: "h2", parentID: null },
    ])
    expect(first.newUnknown.sort()).toEqual(["h1", "h2"])
    expect(classifyOwner(first.ledger, "h1")).toBe("unknown")
    expect(unknownSessions(first.ledger).length).toBe(2)

    const second = reconcileWithHost(first.ledger, [{ id: "h1" }, { id: "h2" }])
    expect(second.newUnknown).toEqual([])
    expect(second.ledger).toEqual(first.ledger)
  })

  test("已登记的 oml 会话对账后不被覆盖", () => {
    let ledger = registerOmlSession({}, { id: "s1", directory: "/a" })
    const r = reconcileWithHost(ledger, [{ id: "s1" }])
    expect(r.newUnknown).toEqual([])
    expect(classifyOwner(r.ledger, "s1")).toBe("oml")
  })

  test("save/load 往返一致，原子写无残留 tmp", async () => {
    const dir = await mkdtemp(join(tmpdir(), "oml-own-"))
    const file = join(dir, "owners.json")
    try {
      let ledger = registerOmlSession({}, { id: "s1", directory: "/a" })
      ledger = reconcileWithHost(ledger, [{ id: "h1", directory: "/b" }]).ledger
      await saveOwnership(ledger, file)
      expect(await loadOwnership(file)).toEqual(ledger)
      const { readdir, readFile } = await import("node:fs/promises")
      expect((await readdir(dir)).some((e) => e.endsWith(".tmp"))).toBe(false)
      expect(await readFile(file, "utf8")).not.toContain("\0")
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("损坏 JSON 返回空账本（容错，不抛）", async () => {
    const dir = await mkdtemp(join(tmpdir(), "oml-own-"))
    const file = join(dir, "owners.json")
    try {
      const { writeFile } = await import("node:fs/promises")
      await writeFile(file, "{bad json", "utf8")
      expect(await loadOwnership(file)).toEqual({})
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })
})
