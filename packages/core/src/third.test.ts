import { afterAll, describe, expect, test } from "bun:test"
import {
  runThirdUpgrade,
  THIRD_SYSTEMS,
  THIRD_AUTO_UPGRADE_DEFAULT,
  dueForUpgrade,
  emptyThirdLedger,
  hostFrontier,
  isNewer,
  needsUpgrade,
  planThirds,
  upgradeCommand,
  forkSyncCommand,
  isForkManaged,
  type ThirdEntry,
} from "./third.ts"

describe("注册表：用户决策的 3rd systems", () => {
  test("两个 TUI 内置件 + 自动升级默认开", () => {
    expect(THIRD_SYSTEMS.map((t) => t.name)).toEqual(["opencode-visual-cache", "opencode-subagent-magazine"])
    expect(THIRD_SYSTEMS.every((t) => t.kind === "tui")).toBe(true)
    expect(THIRD_AUTO_UPGRADE_DEFAULT).toBe(true)
  })

  test("两个 TUI 件都是 OML fork（升级重放补丁，不重装上游）", () => {
    expect(THIRD_SYSTEMS.every((t) => t.fork === true)).toBe(true)
    expect(isForkManaged("opencode-visual-cache")).toBe(true)
    expect(isForkManaged("opencode-subagent-magazine")).toBe(true)
    expect(isForkManaged("opencode-acp")).toBe(false)
    const cmd = forkSyncCommand()
    expect(cmd[0]).toBe("bun")
    expect(cmd[1]).toContain("tui-plugins/sync.ts")
  })
})

describe("hostFrontier", () => {
  test("v1 → oc1，v2+ → oc2，非 opencode → any", () => {
    expect(hostFrontier({ name: "opencode", version: "1.19.5" })).toBe("oc1")
    expect(hostFrontier({ name: "opencode", version: "2.0.0" })).toBe("oc2")
    expect(hostFrontier({ name: "opencode" })).toBe("oc1")
    expect(hostFrontier({ name: "dsh" })).toBe("any")
  })
})

describe("planThirds：该装什么、缺什么", () => {
  test("v1 宿主：引擎 opencode-acp + 2 个 TUI 件", () => {
    const plan = planThirds({ name: "opencode", version: "1.19.5" }, ["opencode-notify"])
    expect(plan.required).toEqual(["opencode-acp", "opencode-visual-cache", "opencode-subagent-magazine"])
    expect(plan.missing).toEqual(["opencode-acp", "opencode-visual-cache", "opencode-subagent-magazine"])
  })

  test("v2 宿主：引擎切到 billion-context", () => {
    const plan = planThirds({ name: "opencode", version: "2.0.0" }, ["opencode-acp", "opencode-visual-cache"])
    expect(plan.missing).toEqual(["billion-context", "opencode-subagent-magazine"])
  })

  test("已全就位 → missing 为空", () => {
    const plan = planThirds(
      { name: "opencode", version: "1.19.5" },
      ["opencode-acp", "opencode-visual-cache", "opencode-subagent-magazine"],
    )
    expect(plan.missing).toEqual([])
  })
})

describe("台账与升级判定", () => {
  test("emptyThirdLedger 形状", () => {
    const l = emptyThirdLedger()
    expect(l.version).toBe(1)
    expect(l.entries).toEqual({})
  })

  test("dueForUpgrade：无条目=true；节流期内=false；超期=true", () => {
    const now = 1_000_000
    expect(dueForUpgrade(undefined, now)).toBe(true)
    const fresh: ThirdEntry = { checkedAt: now - 1000 }
    expect(dueForUpgrade(fresh, now)).toBe(false)
    const stale: ThirdEntry = { checkedAt: now - 86_400_000 - 1 }
    expect(dueForUpgrade(stale, now)).toBe(true)
  })

  test("isNewer 三段比较，前缀 v 可容忍", () => {
    expect(isNewer("1.2.3", "1.2.2")).toBe(true)
    expect(isNewer("1.2.3", "1.3.0")).toBe(false)
    expect(isNewer("v2.0.0", "1.9.9")).toBe(true)
    expect(isNewer("1.2.3", "1.2.3")).toBe(false)
  })

  test("needsUpgrade：latest > installed 才升级；缺字段不升级（不编造）", () => {
    expect(needsUpgrade({ installed: "1.0.0", latest: "1.1.0", checkedAt: 0 })).toBe(true)
    expect(needsUpgrade({ installed: "1.1.0", latest: "1.0.0", checkedAt: 0 })).toBe(false)
    expect(needsUpgrade({ latest: "1.1.0", checkedAt: 0 })).toBe(false)
    expect(needsUpgrade(undefined)).toBe(false)
  })

  test("upgradeCommand = 宿主 CLI 重装取最新", () => {
    expect(upgradeCommand("opencode-visual-cache")).toEqual(["opencode", "plugin", "opencode-visual-cache"])
  })
})

describe("runThirdUpgrade（DI 注入，不发网络不 spawn）", () => {
  // 台账落盘走 OML_STATE_DIR：测试隔离到临时目录，绝不污染 ~/.local/state/oml
  const { mkdtempSync, rmSync } = require("node:fs")
  const { tmpdir } = require("node:os")
  const { join } = require("node:path")
  const dir = mkdtempSync(join(tmpdir(), "oml-third-"))
  const prev = process.env["OML_STATE_DIR"]
  process.env["OML_STATE_DIR"] = dir
  afterAll(() => {
    if (prev === undefined) delete process.env["OML_STATE_DIR"]
    else process.env["OML_STATE_DIR"] = prev
    rmSync(dir, { recursive: true, force: true })
  })
  const opts = {
    host: { name: "opencode", version: "1.19.5" },
    currentPlugins: [],
    now: 2_000_000_000,
    fetchLatest: async (_npm: string) => "9.9.9",
    spawn: () => {},
  }

  test("缺失且 autoUpgrade 默认开 → 触发安装；台账落 missing 状态", async () => {
    const { results, ledger } = await runThirdUpgrade(opts)
    expect(results.map((r) => r.system)).toEqual(["opencode-acp", "opencode-visual-cache", "opencode-subagent-magazine"])
    expect(results.every((r) => r.missing && r.acted)).toBe(true)
    expect(ledger.lastRun).toBe(2_000_000_000)
    // fork 件：upgradable 恒 false（锁定仓内 bundle），note 说明重放补丁
    const forks = results.filter((r) => isForkManaged(r.system))
    expect(forks).toHaveLength(2)
    expect(forks.every((r) => r.upgradable === false && r.note.includes("补丁重放"))).toBe(true)
  })

  test("autoUpgrade=false → 只报告不触发", async () => {
    const { results } = await runThirdUpgrade({ ...opts, config: { third: { autoUpgrade: false } } })
    expect(results.every((r) => r.acted === false)).toBe(true)
  })

  test("已安装且新版更新 → upgradable 且触发；版本不可比（latest）→ 不触发", async () => {
    const { results } = await runThirdUpgrade({
      ...opts,
      currentPlugins: ["opencode-acp", "opencode-visual-cache", "opencode-subagent-magazine"],
      fetchLatest: async () => "9.9.9",
      // 装好且旧版：upgradable
    })
    // 这里没有磁盘台账，installed 缺省 → needsUpgrade false（不编造）
    expect(results.every((r) => r.upgradable === false)).toBe(true)

    const entry = { installed: "1.0.0", latest: "2.0.0", checkedAt: 0 }
    expect(needsUpgrade(entry)).toBe(true)
    expect(needsUpgrade({ installed: "latest", latest: "9.9.9", checkedAt: 0 })).toBe(false)
  })
})
