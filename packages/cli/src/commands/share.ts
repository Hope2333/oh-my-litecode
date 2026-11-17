/**
 * `omo share` —— 经验包的导出/导入（「串联」的本地端）。
 *
 * 只做文件交换，不联网：包可以放在 U 盘、git 仓、内网共享盘，或者由别的程序
 * 通过 HTTP 转发。本命令不引入任何传输依赖，也不产生遥测。
 *
 * 与 A4 的关系：导入**不覆盖**本地——同 id 不同摘要只记 skipped，冲突留给人看。
 */

import { readFile, writeFile, mkdir } from "node:fs/promises"
import { dirname, resolve } from "node:path"
import { hostname } from "node:os"
import {
  createBundle,
  loadCompress,
  loadMemory,
  mergeBundle,
  parseBundle,
  renderBundle,
  saveCompress,
  saveMemory,
  statePath,
  type CompressStore,
  type ExperienceSkill,
  type MemoryStore,
} from "@oml/core"

function flag(args: readonly string[], name: string): string | undefined {
  const i = args.indexOf(`--${name}`)
  return i === -1 ? undefined : args[i + 1]
}

function defaultOut(): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 15)
  return statePath("share", `experience-${stamp}.json`)
}

/** 只导出已有内容的摘要，不导出原文/会话；技能索引来自调用方（宿主扫描）。 */
async function collect(skills: readonly ExperienceSkill[]) {
  const compress: CompressStore = await loadCompress()
  const memory: MemoryStore = await loadMemory()
  return {
    blocks: Object.values(compress.blocks),
    memories: Object.values(memory.memories),
    skills,
  }
}

export async function runShare(argv: readonly string[]): Promise<number> {
  const sub = argv[0]
  const rest = argv.slice(1)

  if (sub === "export") {
    const from = flag(rest, "from") ?? hostname()
    const out = resolve(flag(rest, "out") ?? defaultOut())
    const { blocks, memories, skills } = await collect([])
    const bundle = createBundle({ from, blocks, memories, skills })
    await mkdir(dirname(out), { recursive: true })
    await writeFile(out, `${JSON.stringify(bundle, null, 2)}\n`, "utf8")
    console.log(
      `已导出经验包：${out}\n  压缩块 ${bundle.blocks.length} / 记忆 ${bundle.memories.length} / 技能 ${bundle.skills.length}\n` +
        `  交给别人：omo share import <文件>（对方先看一眼 renderBundle 摘要再导入）`,
    )
    return 0
  }

  if (sub === "import") {
    const file = rest.find((a) => !a.startsWith("--"))
    if (file === undefined) {
      console.error("用法：omo share import <经验包.json> [--dry-run]")
      return 2
    }
    const dryRun = rest.includes("--dry-run")
    let remote
    try {
      remote = parseBundle(await readFile(resolve(file), "utf8"))
    } catch (err) {
      console.error(`经验包无法导入：${err instanceof Error ? err.message : String(err)}`)
      return 1
    }
    console.log(renderBundle(remote))

    const compress = await loadCompress()
    const memory = await loadMemory()
    const local = createBundle({
      from: hostname(),
      blocks: Object.values(compress.blocks),
      memories: Object.values(memory.memories),
      skills: [],
    })
    const merged = mergeBundle(local, remote)

    if (dryRun) {
      console.log(`[dry-run] 将新增 块 ${merged.stats.blocks} / 记忆 ${merged.stats.memories} / 技能 ${merged.stats.skills}，跳过 ${merged.stats.skipped}`)
      return 0
    }

    const blocks: CompressStore["blocks"] = {}
    for (const b of merged.bundle.blocks) blocks[b.id] = b
    await saveCompress({ ...compress, seq: compress.seq, blocks })
    const memories: MemoryStore["memories"] = {}
    for (const m of merged.bundle.memories) memories[m.id] = m
    await saveMemory({ ...memory, memories })

    console.log(
      `已合并：块 +${merged.stats.blocks} / 记忆 +${merged.stats.memories} / 技能 +${merged.stats.skills}，跳过 ${merged.stats.skipped}（本地优先，冲突未覆盖）`,
    )
    return 0
  }

  console.error("用法：omo share export [--out <文件>] [--from <名字>] | omo share import <文件> [--dry-run]")
  return 2
}
