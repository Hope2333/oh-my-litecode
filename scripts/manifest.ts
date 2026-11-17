#!/usr/bin/env bun
/**
 * 零增长门的基线：把「当前有哪些源文件、内容哈希是多少」固化成 manifest.json。
 *
 * 为什么不用 `git diff --cached HEAD`：仓库零提交时它 exit 128，旧实现只看以 A 开头的行，
 * 于是 added.length === 0 永远成立 → 门禁永远 PASS。基线必须是一份真实文件，且缺失时
 * 门禁要能报「无法判定」。
 */
import { readdirSync, readFileSync, statSync } from "node:fs"
import { createHash } from "node:crypto"
import { join, relative, sep } from "node:path"

const SKIP_DIRS = new Set(["node_modules", ".git", "dist", "build", ".oml-check-surface", ".cache", ".opencode-dream"])
const SKIP_FILES = new Set(["manifest.json", "bun.lock", "bun.lockb"])

export async function buildManifest(root: string): Promise<Record<string, string>> {
  const out: Record<string, string> = {}
  const walk = (dir: string): void => {
    let entries: string[]
    try {
      entries = readdirSync(dir)
    } catch {
      return
    }
    for (const name of entries.sort()) {
      if (SKIP_DIRS.has(name)) continue
      const full = join(dir, name)
      let st
      try {
        st = statSync(full)
      } catch {
        continue
      }
      if (st.isDirectory()) {
        walk(full)
        continue
      }
      if (!st.isFile()) continue
      if (SKIP_FILES.has(name)) continue
      if (name.endsWith(".tmp") || name.endsWith(".log")) continue
      const rel = relative(root, full).split(sep).join("/")
      out[rel] = createHash("sha256").update(readFileSync(full)).digest("hex").slice(0, 16)
    }
  }
  walk(root)
  return out
}

if (import.meta.main) {
  const root = join(import.meta.dir, "..")
  const files = await buildManifest(root)
  await Bun.write(join(root, "manifest.json"), `${JSON.stringify({ generatedAt: new Date().toISOString(), files }, null, 2)}\n`)
  console.log(`manifest.json 已写入：${Object.keys(files).length} 个文件`)
}
