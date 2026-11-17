# MCP 动态装载（全量登记 / 默认禁用 / 按需拉起）

## 问题

宿主在启动时加载 `opencode.json` 的每个 MCP，并把它全部工具 schema 注入系统提示。
实测 4 个 MCP（blender / codegraph / unreal / ocr-tools）约占 **9.5K tok**；旧 8 个时约 27K。
「禁用」如果只改标志位，必须重启宿主才生效——这不是动态，只是延迟。

## 方案：OML 自己当 MCP 客户端

```
宿主 opencode.json          OML 目录                调用路径
mcp[id].enabled = false  →  <stateDir>/mcp.json  →  omo_mcp action=call
（零 schema 注入）           （登记/复核/使用统计）      （子进程拉起 → 调用 → 销毁）
```

- `packages/core/src/mcp/catalog.ts`：目录、指纹、自检、建议、回写宿主配置
- `packages/core/src/mcp/client.ts`：最小 MCP 客户端（stdio + streamable-HTTP），
  协议面只做 `initialize / notifications/initialized / tools/list / tools/call`
- `omo_mcp`（3 个 action）：`tools` 看工具、`call` 现场调用、`sync` 对齐宿主
- `omo_admin action=mcp`（4 个 op）：`show / sync / enable / disable`
- `omo mcp list|sync|enable <id>|disable <id>`：同一策略的终端入口

## 自检规则（用户要求「更新或新装时自己维护条目」）

| 情况 | 动作 |
|---|---|
| 新服务器 | 登记为 `enabled:false` + `needsReview:true`；系统提示只加一行待复核提示 |
| 定义变化（digest 不同） | 同样降级为禁用 + 待复核，并清空工具缓存 |
| 从宿主配置消失 | 保留条目，标 `missing:true`，不静默删除 |
| 启动时 | 自动对齐一次（fire-and-forget），有变化才 `console.warn` |
| 会话中 | `status` 动作给出「启用 N/M + 待复核列表」 |

digest 只覆盖真正影响行为的字段：`type / command / url / environment / headers`，
且值统一转字符串（`9876` 与 `"9876"` 视为同一定义）——否则 OML 自己回写一次
`enabled` 就会误判「定义变了」，把服务器踢回复核队列。

## 代理怎么知道该启用什么

- `omo_admin action=status` 的 `## MCP` 段：启用数量、待复核名单。
- 有待复核时，系统提示里只加 **一行**（不列全部工具）：
  `## MCP 待复核 - blender-mcp、ocr-tools：默认禁用且不进提示。需要时 omo_admin action=mcp op=enable target=<id>，用完 op=disable；调用走 omo_mcp action=call。`
- `suggestMcp(query, catalog, defs)` 给出候选（按 id / command / 缓存工具名匹配），
  供代理自己判断，不自动启用。

## 实测

| 指标 | 值 |
|---|---|
| 宿主 MCP 状态（改造后） | `codegraph` 启用；`blender-mcp / unreal-engine / ocr-tools` 禁用待复核 |
| 首轮 `tokens.input`（同一提示词/模型） | **19,344**（改造前 21,452 → −9.8%） |
| `omo_mcp action=tools server=codegraph` | 真实拉起 codegraph 子进程，返回其工具清单（`codegraph_explore` 等） |
| `omo mcp sync` 幂等 | 第一次「变化 1」（digest 算法修正），第二次「未变 4」 |

## 边界（不要说过头）

1. **宿主侧禁用的收益要重启才兑现**；本会话内的收益来自 OML 不再把它们的工具写进提示，
   以及 `omo_mcp` 只在你调用时拉起进程。
2. 冷启动有成本（进程 spawn + 握手，实测 codegraph <1s）；高频使用的服务器应保持
   `enabled:true` 让宿主常驻，或用 `call` 连续调用（每次一次 spawn，未做连接池）。
3. `remote`（streamable-HTTP）已实现但**未对真实远端验证**；当前 4 个 MCP 都是 local。
4. `omo_mcp` 的返回截断在 20,000 字符，超长结果需要缩小参数重取。

## 复现

```bash
bun run omo mcp sync                    # 对齐宿主配置，新增一律待复核
bun run omo mcp enable codegraph        # 回写宿主（自动备份 .bak-mcp-<ts>）
bun run omo mcp list                    # 看目录
# 会话内
omo_admin action=status                 # 看 ## MCP 段
omo_mcp action=tools server=codegraph
omo_mcp action=call server=codegraph tool=codegraph_explore args='{"query":"..."}'
```
