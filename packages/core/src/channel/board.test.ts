/** 纯消息板内核测试：post/read/list/prune 的纯函数语义 + 原子持久化往返与降级。 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test"
import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import {
  CHANNEL_PATH,
  boardPath,
  createBoard,
  post,
  read,
  list,
  prune,
  loadBoard,
  saveBoard,
  type ChannelBoard,
  type PostInput,
} from "./board.ts"

/** 便捷构造一条输入消息。 */
function input(overrides: Partial<PostInput> = {}): PostInput {
  return {
    channel: "team-a",
    from: "impl",
    to: "*",
    body: "hello",
    kind: "msg",
    ...overrides,
  }
}

describe("CHANNEL_PATH / boardPath / createBoard", () => {
  test("CHANNEL_PATH 为 channels.json，boardPath 落在状态目录", () => {
    expect(CHANNEL_PATH).toBe("channels.json")
    expect(boardPath()).toMatch(/\.local[/\\]state[/\\]oml[/\\]channels\.json$/)
  })

  test("createBoard 返回空板", () => {
    expect(createBoard()).toEqual({ channels: {} })
  })
})

describe("post（纯函数）", () => {
  test("生成 id 与 ts，返回新板/新消息，不修改入参", () => {
    const board = createBoard()
    const before = JSON.stringify(board)
    const { board: next, message } = post(board, input({ body: "first" }))

    expect(JSON.stringify(board)).toBe(before) // 入参未变
    expect(next).not.toBe(board)
    expect(message.id).toMatch(/^m-\d+-\d+$/)
    expect(typeof message.ts).toBe("number")
    expect(message.body).toBe("first")
    expect(message.kind).toBe("msg")
    expect(next.channels["team-a"]).toEqual([message])
  })

  test("注入的 id/ts 被原样采用", () => {
    const { message } = post(createBoard(), input({ id: "fixed-id", ts: 12345 }))
    expect(message.id).toBe("fixed-id")
    expect(message.ts).toBe(12345)
  })

  test("多次 post 顺序追加，前一次消息保留且不丢", () => {
    const a = post(createBoard(), input({ ts: 1, body: "a" }))
    const b = post(a.board, input({ ts: 2, body: "b", kind: "claim" }))
    const c = post(b.board, input({ ts: 3, body: "c", kind: "result" }))

    expect(a.board.channels["team-a"]).toHaveLength(1) // 历史板未被改写
    expect(c.board.channels["team-a"]?.map((m) => m.body)).toEqual(["a", "b", "c"])
    expect(new Set(c.board.channels["team-a"]?.map((m) => m.id)).size).toBe(3)
  })

  test("不同频道彼此隔离", () => {
    const a = post(createBoard(), input({ channel: "team-a", ts: 1 }))
    const b = post(a.board, input({ channel: "team-b", ts: 2 }))
    expect(b.board.channels["team-a"]).toHaveLength(1)
    expect(b.board.channels["team-b"]).toHaveLength(1)
  })
})

describe("read（since 游标 / to 定向 / 广播）", () => {
  function seeded(): ChannelBoard {
    let board = createBoard()
    board = post(board, input({ id: "m1", ts: 100, from: "impl", to: "*", body: "broadcast" })).board
    board = post(board, input({ id: "m2", ts: 200, from: "impl", to: "review", body: "to-review" })).board
    board = post(board, input({ id: "m3", ts: 300, from: "review", to: "impl", body: "to-impl" })).board
    return board
  }

  test("不传 since/to 返回频道全部", () => {
    expect(read(seeded(), "team-a").map((m) => m.id)).toEqual(["m1", "m2", "m3"])
  })

  test("since 游标：只返回 ts > since 的消息（严格大于）", () => {
    expect(read(seeded(), "team-a", 100).map((m) => m.id)).toEqual(["m2", "m3"])
    expect(read(seeded(), "team-a", 200).map((m) => m.id)).toEqual(["m3"])
    expect(read(seeded(), "team-a", 300)).toEqual([])
  })

  test("to 定向 + 广播：发给指定 role 及 to='*' 的都可见", () => {
    expect(read(seeded(), "team-a", undefined, "review").map((m) => m.id)).toEqual(["m1", "m2"])
    expect(read(seeded(), "team-a", undefined, "impl").map((m) => m.id)).toEqual(["m1", "m3"])
    // 无人认领的 role 也能看到广播
    expect(read(seeded(), "team-a", undefined, "ghost").map((m) => m.id)).toEqual(["m1"])
  })

  test("since 与 to 可叠加", () => {
    expect(read(seeded(), "team-a", 100, "review").map((m) => m.id)).toEqual(["m2"])
  })

  test("不存在的频道返回空数组", () => {
    expect(read(createBoard(), "missing")).toEqual([])
  })
})

describe("list", () => {
  test("列出全部频道 id（字典序）", () => {
    let board = post(createBoard(), input({ channel: "team-b", ts: 1 })).board
    board = post(board, input({ channel: "team-a", ts: 2 })).board
    board = post(board, input({ channel: "team-c", ts: 3 })).board
    expect(list(board)).toEqual(["team-a", "team-b", "team-c"])
  })

  test("空板返回空列表", () => {
    expect(list(createBoard())).toEqual([])
  })
})

describe("prune（纯函数）", () => {
  test("删除 ts < olderThanTs 的消息，边界值保留", () => {
    let board = createBoard()
    board = post(board, input({ id: "old", ts: 100 })).board
    board = post(board, input({ id: "edge", ts: 200 })).board
    board = post(board, input({ id: "new", ts: 300 })).board
    const before = JSON.stringify(board)

    const pruned = prune(board, 200)
    expect(JSON.stringify(board)).toBe(before) // 入参未变
    expect(pruned.channels["team-a"]?.map((m) => m.id)).toEqual(["edge", "new"])
  })

  test("裁剪后为空的频道键被移除", () => {
    let board = post(createBoard(), input({ channel: "team-old", ts: 100 })).board
    board = post(board, input({ channel: "team-live", ts: 300 })).board
    const pruned = prune(board, 200)
    expect(list(pruned)).toEqual(["team-live"])
  })
})

describe("loadBoard / saveBoard 往返", () => {
  let dir: string
  let file: string

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "oml-channel-"))
    file = join(dir, "nested", "sub", CHANNEL_PATH) // 多层路径，验证递归建目录
  })
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true })
  })

  test("saveBoard → loadBoard 往返一致", async () => {
    let board = post(createBoard(), input({ id: "x", ts: 1, channel: "team-a", kind: "msg" })).board
    board = post(board, input({ id: "y", ts: 2, channel: "team-b", kind: "result" })).board
    await saveBoard(board, file)
    expect(await loadBoard(file)).toEqual(board)
  })

  test("saveBoard 原子写：无残留 tmp，连续两次写后内容完整无 NUL", async () => {
    const a = post(createBoard(), input({ id: "a", ts: 1 })).board
    const b = post(createBoard(), input({ id: "b", ts: 2 })).board
    await saveBoard(a, file)
    await saveBoard(b, file)
    const entries = await readdir(dirname(file))
    expect(entries.some((e) => e.endsWith(".tmp"))).toBe(false)
    const raw = await readFile(file, "utf8")
    expect(raw).not.toContain("\0")
    expect(await loadBoard(file)).toEqual(b)
  })

  test("loadBoard 对不存在的文件返回空板", async () => {
    expect(await loadBoard(join(dir, "nope.json"))).toEqual(createBoard())
  })

  test("loadBoard 对损坏 JSON 返回空板", async () => {
    const bad = join(dir, "bad.json")
    await writeFile(bad, "{ not valid json ]", "utf8")
    expect(await loadBoard(bad)).toEqual(createBoard())
  })

  test("loadBoard 对形状非法的文件返回空板", async () => {
    const bad = join(dir, "shape.json")
    await writeFile(bad, JSON.stringify({ channels: { "team-a": [{ id: 1 }] } }), "utf8")
    expect(await loadBoard(bad)).toEqual(createBoard())
  })
})
