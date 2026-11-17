import { describe, expect, test } from "bun:test"
import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import {
  addTask,
  concurrencyReason,
  emptyStore,
  expire,
  isTerminal,
  liveChildren,
  loadTasks,
  nextTaskId,
  pruneTerminal,
  runningCount,
  saveTasks,
  transition,
  type TaskRecord,
  type TaskStore,
} from "./store.ts"

function must<T extends { ok: boolean }>(r: T): Extract<T, { ok: true }> {
  if (!r.ok) throw new Error(`预期成功，实际失败：${JSON.stringify(r)}`)
  return r as Extract<T, { ok: true }>
}

function seed(): { store: TaskStore; root: string; task: TaskRecord } {
  const a = must(addTask(emptyStore(), { description: "根", category: "deep-low", now: 1000 }))
  return { store: a.store, root: a.task.id, task: a.task }
}

describe("addTask", () => {
  test("首个任务 t1、pending、depth 0", () => {
    const { task } = seed()
    expect(task.id).toBe("t1")
    expect(task.status).toBe("pending")
    expect(task.depth).toBe(0)
    expect(task.parentId).toBeNull()
  })

  test("编号单调递增，prune 之后也不回退（BUG-2）", () => {
    const a = must(addTask(emptyStore(), { description: "a", category: "quick" }))
    const b = must(addTask(a.store, { description: "b", category: "quick" }))
    expect(nextTaskId(b.store)).toBe("t3")
    // 两个任务都终结后 prune 掉全部存活记录，编号仍不得回退到 t1。
    let s = must(transition(b.store, "t1", "running")).store
    s = must(transition(s, "t1", "done")).store
    s = must(transition(s, "t2", "running")).store
    s = must(transition(s, "t2", "done")).store
    const pruned = pruneTerminal(s, 0)
    expect(Object.keys(pruned.tasks)).toEqual([])
    expect(nextTaskId(pruned)).toBe("t3")
    const c = must(addTask(pruned, { description: "c", category: "quick" }))
    expect(c.task.id).toBe("t3")
  })

  test("prune 不留下 parentId 指向已删父任务的孤儿（BUG-1）", () => {
    let s = must(addTask(emptyStore(), { description: "root", category: "quick" })).store
    s = must(addTask(s, { description: "child", category: "quick", parentId: "t1" })).store
    s = must(transition(s, "t1", "running")).store
    s = must(transition(s, "t1", "done")).store
    const pruned = pruneTerminal(s, 0)
    expect(pruned.tasks["t1"]).toBeDefined() // 有活孩子的终态父任务被保护
    expect(pruned.tasks["t2"]?.parentId).toBe("t1")
  })

  test("深度上限生效", () => {
    const { store, root } = seed()
    const c1 = must(addTask(store, { description: "子", category: "quick", parentId: root, maxDepth: 2 }))
    const c2 = must(addTask(c1.store, { description: "孙", category: "quick", parentId: c1.task.id, maxDepth: 2 }))
    const c3 = addTask(c2.store, { description: "曾孙", category: "quick", parentId: c2.task.id, maxDepth: 2 })
    expect(c3.ok).toBe(false)
    if (!c3.ok) expect(c3.reason).toContain("超过上限 2")
  })

  test("父任务不存在或已终结时拒绝派生", () => {
    const { store, root } = seed()
    const missing = addTask(store, { description: "x", category: "quick", parentId: "t99" })
    expect(missing.ok).toBe(false)
    const run = must(transition(store, root, "running", { now: 1 }))
    const done = must(transition(run.store, root, "done", { now: 2 }))
    const after = addTask(done.store, { description: "x", category: "quick", parentId: root })
    expect(after.ok).toBe(false)
    if (!after.ok) expect(after.reason).toContain("已终结")
  })
})

describe("transition", () => {
  test("合法路径 pending → running → done", () => {
    const { store, root } = seed()
    const r = must(transition(store, root, "running", { now: 2, sessionId: "ses_1" }))
    expect(r.task.status).toBe("running")
    expect(r.task.sessionId).toBe("ses_1")
    const d = must(transition(r.store, root, "done", { result: "ok", now: 3 }))
    expect(d.task.status).toBe("done")
    expect(d.task.result).toBe("ok")
  })

  test("非法迁移被拒绝，状态不变", () => {
    const { store, root } = seed()
    const bad = transition(store, root, "done")
    expect(bad.ok).toBe(false)
    if (!bad.ok) expect(bad.reason).toContain("非法迁移 pending → done")
    expect((store.tasks[root] as { status: string }).status).toBe("pending")
  })

  test("done 可被 resume 回到 running，但 attempts 递增且旧错误留在 lastError", () => {
    const { store, root } = seed()
    const r = must(transition(store, root, "running"))
    const f = must(transition(r.store, root, "failed", { error: "网络超时" }))
    const back = transition(f.store, root, "running")
    expect(back.ok).toBe(true)
    if (back.ok) {
      expect(back.task.attempts).toBe(2)
      expect(back.task.lastError).toBe("网络超时")
      expect(back.task.error).toBeUndefined()
      expect(back.task.status).toBe("running")
    }
  })

  test("cancelled 是永久终态：不能回到 running", () => {
    const { store, root } = seed()
    const r = must(transition(store, root, "running"))
    const c = must(transition(r.store, root, "cancelled"))
    const back = transition(c.store, root, "running")
    expect(back.ok).toBe(false)
  })

  test("不存在的任务返回原因", () => {
    const r = transition(emptyStore(), "t42", "running")
    expect(r.ok).toBe(false)
    if (!r.ok) expect(r.reason).toContain("不存在")
  })
})

describe("聚合查询", () => {
  test("liveChildren 只含未终结者", () => {
    const { store, root } = seed()
    const c = must(addTask(store, { description: "子", category: "quick", parentId: root, now: 1001 }))
    const d = must(transition(c.store, c.task.id, "running", { now: 1002 }))
    expect(liveChildren(d.store, root).map((t) => t.id)).toEqual([c.task.id])
    const e = must(transition(d.store, c.task.id, "done", { now: 1003 }))
    expect(liveChildren(e.store, root)).toEqual([])
    expect(isTerminal("done")).toBe(true)
    expect(isTerminal("running")).toBe(false)
  })

  test("并发闸门按 running 计数", () => {
    const { store, root } = seed()
    expect(concurrencyReason(store, 1)).toBeNull()
    const r = must(transition(store, root, "running"))
    expect(runningCount(r.store)).toBe(1)
    expect(concurrencyReason(r.store, 1)).toContain("并发已达上限 1")
  })
})

describe("回收", () => {
  test("超时未完成标为 failed 并写明原因", () => {
    const { store, root } = seed()
    const r = must(transition(store, root, "running", { now: 1000 }))
    const out = expire(r.store, 5000, 1000)
    const t = out.tasks[root]
    expect(t?.status).toBe("failed")
    expect(t?.error).toContain("超时")
  })

  test("未超时的任务不动", () => {
    const { store, root } = seed()
    expect(expire(store, 1500, 1000).tasks[root]?.status).toBe("pending")
  })

  test("pruneTerminal 只保留最近 keep 个终态", () => {
    let store = emptyStore()
    const ids: string[] = []
    for (let i = 0; i < 4; i++) {
      const a = must(addTask(store, { description: `t${i}`, category: "quick", now: i }))
      const r = must(transition(a.store, a.task.id, "running", { now: i }))
      const d = must(transition(r.store, a.task.id, "done", { now: 100 + i }))
      store = d.store
      ids.push(a.task.id)
    }
    const pruned = pruneTerminal(store, 2)
    expect(Object.keys(pruned.tasks).sort()).toEqual(ids.slice(2).sort())
  })
})

describe("持久化", () => {
  test("保存后能读回，且不残留 .tmp", async () => {
    const dir = await mkdtemp(join(tmpdir(), "oml-tasks-"))
    try {
      const path = join(dir, "tasks.json")
      const { store } = seed()
      await saveTasks(store, path)
      const back = await loadTasks(path)
      expect(back.tasks["t1"]?.description).toBe("根")
      expect(await readdir(dir)).toEqual(["tasks.json"])
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("resume 时不丢失本轮 error，也不残留上一轮 result（BUG-3/4）", () => {
    let s = must(addTask(emptyStore(), { description: "r", category: "quick" })).store
    s = must(transition(s, "t1", "running")).store
    s = must(transition(s, "t1", "done", { result: "OLD" })).store
    const back = transition(s, "t1", "running", { error: "E2" })
    expect(back.ok).toBe(true)
    if (!back.ok) return
    expect(back.task.lastError).toBe("E2")
    expect(back.task.error).toBeUndefined()
    expect(back.task.result).toBeUndefined()
  })

  test("未知 status 的脏任务不抛 TypeError，loadTasks 丢弃它（BUG-5）", async () => {
    const dirty = {
      version: 1,
      tasks: {
        t1: { id: "t1", parentId: null, depth: 0, description: "z", category: "quick", status: "completed", createdAt: 1, updatedAt: 1 },
      },
    }
    const r = transition(dirty as unknown as TaskStore, "t1", "running")
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.reason).toContain("状态非法")

    const dir = await mkdtemp(join(tmpdir(), "oml-tasks-"))
    try {
      const p = join(dir, "dirty.json")
      await writeFile(p, JSON.stringify(dirty))
      const loaded = await loadTasks(p)
      expect(Object.keys(loaded.tasks)).toEqual([])
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("lastId 跨 save/load 保留（BUG-2 持久化）", async () => {
    let s = must(addTask(emptyStore(), { description: "a", category: "quick" })).store
    s = must(addTask(s, { description: "b", category: "quick" })).store
    const dir = await mkdtemp(join(tmpdir(), "oml-tasks-"))
    try {
      const p = join(dir, "tasks.json")
      await saveTasks(s, p)
      const loaded = await loadTasks(p)
      expect(loaded.lastId).toBe(2)
      expect(nextTaskId(loaded)).toBe("t3")
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })

  test("文件缺失或损坏 → 空状态，不抛错", async () => {
    const dir = await mkdtemp(join(tmpdir(), "oml-tasks-"))
    try {
      expect(await loadTasks(join(dir, "missing.json"))).toEqual(emptyStore())
      const bad = join(dir, "bad.json")
      await writeFile(bad, "{ not json")
      expect(await loadTasks(bad)).toEqual(emptyStore())
      const wrongVer = join(dir, "wrongver.json")
      await writeFile(wrongVer, JSON.stringify({ version: 2, tasks: {} }))
      expect(await loadTasks(wrongVer)).toEqual(emptyStore())
    } finally {
      await rm(dir, { recursive: true, force: true })
    }
  })
})
