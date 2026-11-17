// omo slim —— 配置备份瘦身（公理 A10：零增长，C4：配置漂移）。
// 消灭的矛盾：C4「~50 个 .bak 说明配置长期在打补丁而非收敛」。
// 安全硬要求：默认 dry-run 只打印；必须显式 --apply 才删除，且删除前打印完整清单。
import { readdir, stat, rm } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

/** 匹配三类备份/损坏文件。 */
function isSlimTarget(name: string): boolean {
  return (
    name.startsWith("opencode.json.bak-") ||
    name.startsWith("oh-my-openagent.json.bak") ||
    name.includes(".broken-")
  )
}

/** 解析 slim 参数并执行。返回退出码。 */
export async function runSlim(args: string[]): Promise<number> {
  let apply = false
  for (const a of args) {
    if (a === "--apply") apply = true
    else if (a === "--dry-run") {
      /* 显式 dry-run，等同默认行为 */
    } else {
      console.error(`omo slim: 未知参数 ${String(a)}`)
      return 2
    }
  }

  const dir = join(homedir(), ".config", "opencode")

  // 列出目录下所有匹配文件（只看顶层，不递归），带大小
  let entries: string[]
  try {
    const dirents = await readdir(dir, { withFileTypes: true })
    entries = dirents.filter((d) => d.isFile() && isSlimTarget(d.name)).map((d) => d.name)
  } catch (err) {
    // 配置目录不存在 → 优雅降级，无文件可清
    console.error(
      `omo slim: 无法读取 ${dir}: ${err instanceof Error ? err.message : String(err)}`,
    )
    return 0
  }
  entries.sort()

  // 统计字节数
  let totalBytes = 0
  const sized: Array<{ name: string; bytes: number }> = []
  for (const name of entries) {
    try {
      const s = await stat(join(dir, name))
      totalBytes += s.size
      sized.push({ name, bytes: s.size })
    } catch {
      sized.push({ name, bytes: 0 })
    }
  }

  // 打印完整清单（无论 dry-run 还是 apply，删除前都要可见）
  console.log(`omo slim — 扫描 ${dir}`)
  console.log("─".repeat(56))
  if (sized.length === 0) {
    console.log("  没有发现备份/损坏文件，无需清理。")
    return 0
  }
  for (const it of sized) {
    console.log(`  ${it.name}  (${it.bytes} B)`)
  }
  console.log("─".repeat(56))
  console.log(`  共 ${sized.length} 个文件，合计 ${totalBytes} 字节`)

  if (!apply) {
    console.log("\n[dry-run] 未删除任何文件。确认无误后加 --apply 执行删除。")
    return 0
  }

  // 显式 --apply：执行删除，报告释放字节数
  let freed = 0
  let failed = 0
  for (const it of sized) {
    try {
      await rm(join(dir, it.name), { force: true })
      freed += it.bytes
    } catch (err) {
      failed++
      console.error(`omo slim: 删除失败 ${it.name}: ${err instanceof Error ? err.message : String(err)}`)
    }
  }
  console.log(`\n[apply] 已删除 ${sized.length - failed}/${sized.length} 个文件，释放 ${freed} 字节。`)
  return failed > 0 ? 1 : 0
}
