# 任务：持久化键值存储

实现 `src/store.ts`，导出：

```ts
export function createStore(file: string): {
  get(key: string): string | undefined
  set(key: string, value: string): void
  del(key: string): boolean
  save(): void          // 原子写盘
  load(): void          // 从盘读回，文件不存在则不报错
}
```

要求：

1. `set` 后 `get` 立刻可见；`del` 返回是否真的删掉了。
2. `save()` 用临时文件 + rename，避免半写。
3. `load()` 在文件不存在时静默成功。
4. 写测试 `tests/store.test.ts`，覆盖上面 4 条 + 「重开后数据仍在」，至少 5 个 case。
5. `bun test` 全绿。
