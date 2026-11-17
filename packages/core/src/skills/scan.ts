/**
 * 惰性技能索引 —— 扫描层。
 *
 * 职责：把磁盘上分散的 SKILL.md 收敛成 SkillMeta 列表（按 name 去重、字典序）。
 * 容错：单个文件读取/解析失败只跳过该文件，绝不中断整体扫描。
 */

import { readFile, readdir } from "node:fs/promises"
import { basename, dirname, join } from "node:path"
import { homedir } from "node:os"
import type { SkillMeta } from "../contract.ts"

/** 递归查找的最大目录深度（root 本身为第 0 层） */
const MAX_DEPTH = 6

/** 需要跳过的目录名 */
const SKIP_DIRS: ReadonlySet<string> = new Set(["node_modules", ".git"])

/**
 * 从一段 Markdown 源码中解析 `---` 包裹的 YAML frontmatter 里的 name / description。
 * 支持：单行值（带/不带引号）、多行块 `>`（折叠为空格）与 `|`（保留换行）。
 * 缺 frontmatter 或字段缺失时，对应字段不出现在返回值中。
 */
export function parseFrontmatter(src: string): { name?: string; description?: string } {
  const result: { name?: string; description?: string } = {}
  const lines = src.split(/\r?\n/)

  // 必须以 `---` 起始，否则视为无 frontmatter
  if (lines[0]?.trim() !== "---") return result

  // 找到闭合的 `---`
  let endIdx = -1
  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === "---") {
      endIdx = i
      break
    }
  }
  if (endIdx === -1) return result

  const fmLines = lines.slice(1, endIdx)
  let i = 0
  while (i < fmLines.length) {
    const line = fmLines[i] as string
    const kv = /^([A-Za-z0-9_-]+)[ \t]*:[ \t]?(.*)$/.exec(line)
    if (!kv) {
      i++
      continue
    }
    const key = kv[1] as string
    // 只关心这两个字段，其余跳过（避免误吞多行块）
    if (key !== "name" && key !== "description") {
      i++
      continue
    }
    let value = (kv[2] ?? "").trim()

    // 多行块标记：> | 及其 chomping 变体
    if (/^[>|][+-]?$/.test(value)) {
      const literal = value.startsWith("|")
      i++
      const blockLines: string[] = []
      let baseIndent = -1
      while (i < fmLines.length) {
        const l = fmLines[i] as string
        if (l.trim() === "") {
          blockLines.push("")
          i++
          continue
        }
        const indent = l.length - l.trimStart().length
        if (baseIndent === -1) baseIndent = indent
        // 缩进小于块基准缩进 → 块结束
        if (indent < baseIndent) break
        blockLines.push(l.slice(baseIndent))
        i++
      }
      // `|` 保留换行；`>` 折叠为空格
      value = (literal ? blockLines.join("\n") : blockLines.join(" ")).trim()
    } else {
      i++
    }

    value = stripQuotes(value)
    if (key === "name") result.name = value
    else result.description = value
  }
  return result
}

/** 去掉成对的首尾引号（"..." 或 '...'） */
function stripQuotes(s: string): string {
  if (s.length >= 2) {
    const a = s[0]
    const b = s[s.length - 1]
    if ((a === '"' && b === '"') || (a === "'" && b === "'")) return s.slice(1, -1)
  }
  return s
}

/**
 * 扫描多个技能根目录，递归查找 SKILL.md（深度 ≤6），跳过 node_modules / .git。
 * name 缺省回退为父目录名；按 name 去重（先出现者胜）；按 name 字典序返回。
 * 单个文件读取/解析失败时跳过该文件，不中断整体。
 */
export async function scanSkills(roots: string[]): Promise<SkillMeta[]> {
  const byName = new Map<string, SkillMeta>()
  for (const root of roots) {
    const files = await findSkillFiles(root)
    for (const file of files) {
      try {
        const src = await readFile(file, "utf8")
        const fm = parseFrontmatter(src)
        const name = fm.name && fm.name.length > 0 ? fm.name : basename(dirname(file))
        // 先出现者胜：同名只保留首次
        if (byName.has(name)) continue
        byName.set(name, {
          name,
          description: fm.description ?? "",
          root,
          file,
        })
      } catch {
        // 容错：损坏文件/目录跳过
      }
    }
  }
  return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name))
}

/** 递归收集某根目录下所有 SKILL.md 绝对路径（广度优先，深度 ≤MAX_DEPTH，跳过 SKIP_DIRS）
 *  广度优先保证浅层（顶层）技能先被发现，去重时顶层定义优先于 vendored 深层副本。 */
async function findSkillFiles(root: string): Promise<string[]> {
  const out: string[] = []
  const queue: { dir: string; depth: number }[] = [{ dir: root, depth: 0 }]
  while (queue.length > 0) {
    const { dir, depth } = queue.shift() as { dir: string; depth: number }
    let entries
    try {
      entries = await readdir(dir, { withFileTypes: true })
    } catch {
      continue // 目录不存在或不可读
    }
    // 按 name 排序，保证「先出现者胜」的遍历顺序可复现（readdir 顺序本不确定）
    entries.sort((a, b) => a.name.localeCompare(b.name))
    for (const e of entries) {
      if (SKIP_DIRS.has(e.name)) continue
      const full = join(dir, e.name)
      if (e.isDirectory()) {
        if (depth < MAX_DEPTH) queue.push({ dir: full, depth: depth + 1 })
      } else if (e.isFile() && e.name === "SKILL.md") {
        out.push(full)
      }
    }
  }
  return out
}

/** 本机默认的 4 个技能根目录（按优先级） */
export function defaultSkillRoots(): string[] {
  const home = homedir()
  return [
    join(home, ".agents", "skills"),
    join(home, ".claude", "skills"),
    join(home, ".config", "opencode", "skills"),
    join(home, ".cache", "opencode", "skills"),
  ]
}
