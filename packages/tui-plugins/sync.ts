/**
 * OML TUI fork 部署器：bundle/(上游原样) → patch → verify → 写 live cache dist/tui.js。
 *
 * 用法：
 *   bun packages/tui-plugins/sync.ts --check    只校验，不写盘
 *   bun packages/tui-plugins/sync.ts            应用到 live cache（写前备份 .oml-orig）
 *   bun packages/tui-plugins/sync.ts --revert   从 .oml-orig 还原上游
 *
 * 安全约束：
 *   - 只写 ~/.cache/opencode/packages/<name>/node_modules/<name>/dist/tui.js 一个文件。
 *   - 写前先备份上游到 tui.js.oml-orig（若不存在），备份存在则不覆盖（保留最初上游）。
 *   - verify 失败拒写（补丁锚点漂移时宁可不写）。
 *   - 幂等：已是 OML fork 时跳过（除非 --force）。
 */

import { readFile, writeFile, access, copyFile } from "node:fs/promises"
import { join } from "node:path"
import { homedir } from "node:os"
import { patchMagazine, patchVisualCache, verifyPatch, PATCH_META } from "./patch.ts"

type Kind = "magazine" | "visual-cache"

const args = new Set(process.argv.slice(2))
const checkOnly = args.has("--check")
const revert = args.has("--revert")
const force = args.has("--force")

const pluginDir = (kind: Kind): string => {
  const npm = PATCH_META[kind].npm
  return join(homedir(), ".cache", "opencode", "packages", npm, "node_modules", npm, "dist")
}

const bundleDir: Record<Kind, string> = {
  magazine: "subagent-magazine",
  "visual-cache": "visual-cache",
}
const bundlePath = (kind: Kind): string => join(import.meta.dir, bundleDir[kind], "bundle", "tui.js")

async function exists(p: string): Promise<boolean> {
  try {
    await access(p)
    return true
  } catch {
    return false
  }
}

async function processOne(kind: Kind): Promise<void> {
  const target = join(pluginDir(kind), "tui.js")
  const backup = `${target}.oml-orig`
  const patch = kind === "magazine" ? patchMagazine : patchVisualCache

  if (revert) {
    if (!(await exists(backup))) {
      console.log(`[${kind}] 无备份 ${backup}，跳过还原`)
      return
    }
    await copyFile(backup, target)
    console.log(`[${kind}] 已从 .oml-orig 还原上游`)
    return
  }

  const original = await readFile(bundlePath(kind), "utf8")
  const { src, changes } = patch(original)
  const verify = verifyPatch(kind, src)
  if (!verify.ok) {
    console.error(`[${kind}] 补丁校验失败，拒写：${verify.problems.join("; ")}`)
    process.exitCode = 1
    return
  }

  const targetExists = await exists(target)
  const targetSrc = targetExists ? await readFile(target, "utf8") : ""
  const appliedMarker = kind === "magazine" ? "oml_subagent_magazine" : "oml_cache_panel"
  const alreadyApplied = targetSrc.includes(appliedMarker)

  if (checkOnly) {
    console.log(
      `[${kind}] --check | 变更计数=${JSON.stringify(changes)} | 目标存在=${targetExists} | 已应用=${alreadyApplied} | 校验=${verify.ok ? "OK" : "FAIL"}`,
    )
    return
  }

  if (alreadyApplied && !force) {
    console.log(`[${kind}] 已是 OML fork，跳过（--force 强制重写）`)
    return
  }

  if (targetExists && !(await exists(backup))) {
    await copyFile(target, backup)
    console.log(`[${kind}] 已备份上游 → ${backup}`)
  }

  await writeFile(target, src, "utf8")
  console.log(`[${kind}] 已写入 OML fork → ${target}（${src.length} bytes）`)
}

async function main(): Promise<void> {
  console.log(`sync ${revert ? "--revert" : checkOnly ? "--check" : "--apply"} | home=${homedir()}`)
  for (const kind of ["magazine", "visual-cache"] as const) {
    try {
      await processOne(kind)
    } catch (e) {
      console.error(`[${kind}] 失败：${e instanceof Error ? e.message : String(e)}`)
      process.exitCode = 1
    }
  }
}

await main()
