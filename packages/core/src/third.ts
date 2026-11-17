/**
 * 3rd systems —— 内置三方系统管理（注册表 + 台账 + 升级判定）。
 *
 * 用户决策（2026-11）：OML 内置一组「3rd systems」作为依赖：
 *   - ACP 压缩引擎：按路由表挂（v1→opencode-acp，v2/dsh/未来→billion-context），
 *     一次只挂一个（引擎互斥）；
 *   - TUI 内置功能：opencode-visual-cache、opencode-subagent-magazine（可共存，
 *     主要服务 TUI 环境；GUI 场景用户可经 oml.json 的 disabled_* 关掉）。
 * 版本自动升级默认开启；台账落在 <stateDir>/third.json。
 *
 * 消灭的矛盾：「三方组件该装哪些、什么版本、要不要升级」散落各宿主各配置里，
 * 无单一事实源。这里就是那个源：注册表（该装谁）+ 台账（现在什么状态）。
 */

import { readFile, writeFile, mkdir } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { statePath } from "./paths.ts"
import { pickAcp, hasAcpPlugin, majorOf, type AcpHost } from "./acp.ts"

/** 内置 3rd systems 注册表（引擎外的 TUI 内置件）。 */
export interface ThirdSystem {
  /** opencode 插件标识（npm 包名） */
  name: string
  /** acp = 压缩引擎（互斥，按宿主路由二选一）；tui = TUI 功能插件（可共存） */
  kind: "acp" | "tui"
  /** npm 包名（与 name 相同时可省） */
  npm?: string
  /** OML 维护的 fork：升级 = 重放 OML 补丁，绝不 `opencode plugin` 重装上游（会冲掉补丁） */
  fork?: boolean
}

export const THIRD_SYSTEMS: readonly ThirdSystem[] = [
  { name: "opencode-visual-cache", kind: "tui", fork: true },
  { name: "opencode-subagent-magazine", kind: "tui", fork: true },
]

/** 仓库根（packages/core/src → ../../..），用于定位 fork 部署器。 */
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..")

/** fork 管理系统的升级命令：重放 OML 补丁（幂等），不碰上游安装。 */
export function forkSyncCommand(): string[] {
  return ["bun", resolve(REPO_ROOT, "packages", "tui-plugins", "sync.ts")]
}

/** 该系统是否由 OML fork 管理。 */
export function isForkManaged(name: string): boolean {
  return THIRD_SYSTEMS.find((t) => t.name === name)?.fork === true
}

/** 自动升级默认开（用户决策）。 */
export const THIRD_AUTO_UPGRADE_DEFAULT = true

/** 把宿主名映射到服务前线：opencode v1 → oc1，v2+ → oc2，其他（dsh/未来）→ any。 */
export function hostFrontier(host: AcpHost): "oc1" | "oc2" | "any" {
  if (host.name !== "opencode") return "any"
  const major = majorOf(host.version)
  return major === undefined || major <= 1 ? "oc1" : "oc2"
}

export interface ThirdPlan {
  /** 该宿主应就位的全部 3rd systems（含路由选定的 ACP 引擎） */
  required: string[]
  /** 插件列表里缺的（按注册表顺序） */
  missing: string[]
  /** 人话说明（doctor/upgrade 打印） */
  note: string
}

/** 纯函数：给定宿主与当前插件列表，算出该装什么、缺什么。 */
export function planThirds(host: AcpHost, currentPlugins: readonly string[]): ThirdPlan {
  const frontier = hostFrontier(host)
  const acp = pickAcp(host)
  const required: string[] = [acp.plugin, ...THIRD_SYSTEMS.map((t) => t.name)]
  const missing = required.filter((name) => !hasAcpPlugin(currentPlugins, name))
  return {
    required,
    missing,
    note: `宿主 ${host.name} v${host.version ?? "?"} → 前线 ${frontier}；引擎 ${acp.plugin}（${acp.reason}）`,
  }
}

// ---------------------------------------------------------------- 台账

export interface ThirdEntry {
  installed?: string
  latest?: string
  /** 上次检查的 epoch ms */
  checkedAt: number
  upgradedAt?: number
  auto?: boolean
}

export interface ThirdLedger {
  version: 1
  entries: Record<string, ThirdEntry>
  /** 上次自动检查/升级的 epoch ms（24h 节流的依据） */
  lastRun?: number
}

export function emptyThirdLedger(): ThirdLedger {
  return { version: 1, entries: {} }
}

/** host 自动检查的节流门：ledger 上次运行距今是否超过节流期。 */
export function autoCheckDue(ledger: ThirdLedger, now: number, throttleMs = 86_400_000): boolean {
  return dueForUpgrade({ checkedAt: ledger.lastRun ?? 0 }, now, throttleMs)
}

export function thirdLedgerPath(): string {
  return statePath("third.json")
}

export async function loadThirdLedger(): Promise<ThirdLedger> {
  try {
    const raw = await readFile(thirdLedgerPath(), "utf8")
    const parsed = JSON.parse(raw) as ThirdLedger
    if (parsed.version !== 1 || typeof parsed.entries !== "object" || parsed.entries === null) {
      return emptyThirdLedger()
    }
    return parsed
  } catch {
    return emptyThirdLedger()
  }
}

export async function saveThirdLedger(ledger: ThirdLedger): Promise<void> {
  const path = thirdLedgerPath()
  await mkdir(statePath(), { recursive: true })
  const tmp = `${path}.${process.pid}.tmp`
  await writeFile(tmp, JSON.stringify(ledger, null, 2), "utf8")
  try {
    await import("node:fs/promises").then((fs) => fs.rename(tmp, path))
  } catch {
    await readFile(path, "utf8").catch(() => "")
    await writeFile(path, JSON.stringify(ledger, null, 2), "utf8")
  }
}

/** 纯函数：该不该做升级检查（首次或超过节流期）。默认 24h。 */
export function dueForUpgrade(entry: ThirdEntry | undefined, now: number, throttleMs = 86_400_000): boolean {
  if (entry === undefined) return true
  return now - entry.checkedAt >= throttleMs
}

/** 纯函数：naive 语义化比较，a 比 b 新返回 true。
 * 「latest」这类非数字版本判不出新旧 → false（宁可漏报不误装）。 */
export function isNewer(a: string, b: string): boolean {
  const pa = a.replace(/^[^0-9]*/, "").split(".").map((x) => Number.parseInt(x, 10))
  const pb = b.replace(/^[^0-9]*/, "").split(".").map((x) => Number.parseInt(x, 10))
  if (pa.length === 0 || pb.length === 0 || pa.some((x) => Number.isNaN(x)) || pb.some((x) => Number.isNaN(x))) {
    return false
  }
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const x = pa[i] ?? 0
    const y = pb[i] ?? 0
    if (x > y) return true
    if (x < y) return false
  }
  return false
}

/** 纯函数：台账里这一条是否需要升级。 */
export function needsUpgrade(entry: ThirdEntry | undefined): boolean {
  if (entry === undefined) return false
  if (entry.installed === undefined || entry.latest === undefined) return false
  return isNewer(entry.latest, entry.installed)
}

/** 装/升命令（宿主 CLI）。升级 = 重新安装同名插件取最新版。 */
export function upgradeCommand(name: string): string[] {
  return ["opencode", "plugin", name]
}

// ---------------------------------------------------------------- 升级执行（IO 层）

import { homedir } from "node:os"
import { readdir } from "node:fs/promises"
import { join } from "node:path"

export interface ThirdUpgradeResult {
  system: string
  installed?: string
  latest?: string
  missing: boolean
  upgradable: boolean
  /** 是否真的触发了装/升（auto 关闭或 dry-run 时为 false） */
  acted: boolean
  note: string
}

export interface ThirdUpgradeOptions {
  /** oml.json 的 third 键（autoUpgrade 默认 true） */
  config?: { third?: { autoUpgrade?: boolean } }
  /** 宿主（决定 ACP 引擎走哪个） */
  host: AcpHost
  /** 当前宿主插件列表（算 missing；拿不到就传空数组） */
  currentPlugins?: string[]
  now?: number
  /** 触发装/升的命令执行器（默认 fire-and-forget spawn） */
  spawn?: (cmd: string[]) => void
  /** 查 npm 最新版本的网络函数（默认 fetch，10s 超时） */
  fetchLatest?: (npm: string) => Promise<string | undefined>
}

/** 宿主 OpenCode 的插件缓存：~/.cache/opencode/packages/<name>@<version>/package.json */
async function installedFromDisk(name: string): Promise<string | undefined> {
  const base = join(homedir(), ".cache", "opencode", "packages")
  let entries: string[]
  try {
    entries = await readdir(base)
  } catch {
    return undefined
  }
  const match = entries.filter((e) => e === name || e.startsWith(`${name}@`)).sort()
  for (const e of match.reverse()) {
    const m = e.match(/@([^@]+)$/)
    const suffix = m?.[1]
    // opencode 用 @latest 目录装包：目录名不是版本，读里面的 package.json。
    if (suffix !== undefined && suffix !== "latest" && /^\d/.test(suffix)) return suffix
    try {
      const raw = await readFile(join(base, e, "package.json"), "utf8")
      const pkg = JSON.parse(raw) as { version?: string }
      if (typeof pkg.version === "string" && pkg.version !== "" && pkg.version !== "latest") return pkg.version
    } catch {
      // 目录半残，继续找上一个
    }
  }
  return undefined
}

/**
 * 跑一遍 3rd systems 检查/升级。
 * 网络失败不炸：该条 latest 记 undefined、note 说明，其余照常。
 */
export async function runThirdUpgrade(opts: ThirdUpgradeOptions): Promise<{ results: ThirdUpgradeResult[]; ledger: ThirdLedger }> {
  const auto = opts.config?.third?.autoUpgrade !== false
  const now = opts.now ?? Date.now()
  const plan = planThirds(opts.host, opts.currentPlugins ?? [])
  const ledger = await loadThirdLedger()
  const fetchLatest =
    opts.fetchLatest ??
    (async (npm: string): Promise<string | undefined> => {
      try {
        const res = await fetch(`https://registry.npmjs.org/${encodeURIComponent(npm)}/latest`, {
          signal: AbortSignal.timeout(10_000),
        })
        if (!res.ok) return undefined
        const body = (await res.json()) as { version?: string }
        return body.version
      } catch {
        return undefined
      }
    })
  const spawn =
    opts.spawn ??
    ((cmd: string[]) => {
      // 默认 fire-and-forget：子进程失败不影响调用方（宿主会话）。
      void (async () => {
        const cp = await import("node:child_process")
        const proc = cp.spawn(cmd[0] ?? "", cmd.slice(1), { stdio: "ignore", detached: true })
        proc.unref()
      })().catch(() => {})
    })

  const results: ThirdUpgradeResult[] = []
  for (const system of plan.required) {
    const missing = plan.missing.includes(system)
    const forkManaged = isForkManaged(system)
    const entry = ledger.entries[system]
    const installed = (await installedFromDisk(system)) ?? entry?.installed
    const npm = THIRD_SYSTEMS.find((t) => t.name === system)?.npm ?? system
    const latest = (await fetchLatest(npm)) ?? entry?.latest
    // fork 版固定到仓内 bundle：不追 npm 新版（追新版会重装上游、冲掉补丁）。
    // fork 的「升级」= 重放 OML 补丁（幂等自愈），命令走 forkSyncCommand。
    const upgradable = forkManaged ? false : !missing && needsUpgrade({ installed, latest, checkedAt: 0 } as ThirdEntry)
    const cmd = forkManaged ? forkSyncCommand() : upgradeCommand(system)
    const shouldAct = forkManaged ? auto : auto && (missing || upgradable)
    let acted = false
    if (shouldAct) {
      spawn(cmd)
      acted = true
    }
    ledger.entries[system] = {
      ...(entry ?? {}),
      ...(installed === undefined ? {} : { installed }),
      ...(latest === undefined ? {} : { latest }),
      checkedAt: now,
      auto,
      ...(acted ? { upgradedAt: now } : {}),
    }
    results.push({
      system,
      ...(installed === undefined ? {} : { installed }),
      ...(latest === undefined ? {} : { latest }),
      missing,
      upgradable,
      acted,
      note: forkManaged
        ? acted
          ? `OML fork：已触发补丁重放（${cmd.join(" ")}），版本锁定仓内 bundle`
          : `OML fork：版本锁定仓内 bundle（autoUpgrade 关，未重放补丁）`
        : missing
          ? (acted ? `未安装 → 已触发安装（${cmd.join(" ")}）` : "未安装" + (auto ? "；autoUpgrade 关闭？" : ""))
          : upgradable
            ? acted
              ? `${installed ?? "?"} → ${latest ?? "?"}，已触发升级`
              : `可升级 ${installed ?? "?"} → ${latest ?? "?"}（未触发：autoUpgrade 关）`
            : latest === undefined
              ? `${installed ?? "?"}（最新版检查失败：离线或网络受限）`
              : `${installed ?? "?"}（已是最新，或版本不可比（latest 目录）保守不触发）`,
    })
  }
  ledger.lastRun = now
  await saveThirdLedger(ledger)
  return { results, ledger }
}
