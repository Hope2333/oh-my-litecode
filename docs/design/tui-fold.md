# TUI 子代理折叠内置内容（规格 + OML 的责任边界）

## 用户要的效果（原话样例，保留）

> Sisyphus-Junior Task — t11 批量编辑与父/子范围
> ↳ Bash cd /home/miao/Projects/NekoOLMR && grep -n "^\.ctrl…" webui/app.css | head -40 …
> 转为使用了几次工具 本轮↓新增（下载）token 数量（K）、✏ 总 tokens 读取（累计）（K/M）、
> 当前工具、或 bash 工具使用的命令头。若是出错则是当前工具部分显示失败码（一般 3 位）
> + 重试倒计时。

## 责任切分（A4 单一写入者：谁画 UI 谁负责 UI）

| 层 | 负责 | 不负责 |
|---|---|---|
| 宿主 TUI | 折叠/展开的渲染、倒计时（只有宿主知道下次重试时刻） | — |
| OML `status-line`（`packages/core/src/tasks/status-line.ts`） | 内容：一行一子代理的机器可读状态（任务名、最近工具/命令头、本轮工具次数、↓新增 K、✏累计 K/M、失败码） | 渲染 |

OML 侧已落地（206 测试全绿）：

- `PromptResult` 扩 `tokens?: {input, output}` + `toolUses?`（宿主 SDK 返回才透传，**没给就不造假**）；
- `omo_task` 的 run / resume / team / status 四个动作的结果里都带折叠行：
  - run/resume：正文后追加 `formatStatusLine(...)`；
  - team：每个成员结果一行（`↳ <agent> <role> ×N ↓X.XK ✏Y.YK`，失败带 `✗<code>`）；
  - status：返回**单一 JSON** `{ tasks, statusLines }`（不再是 JSON+散行，TUI 好解析）；
- 失败码从错误文本正则抽 3 位（`/\\b([45]\\d\\d)\\b/`，只认 4xx/5xx，抽不到就不显示，不编造）。

## 已知限制（写明白，不粉饰）

1. **重试倒计时 OML 拿不到**：宿主的重试定时器在宿主进程里，插件层无 API。
   状态行留了 `countdown?` 字段占位，宿主 TUI 若实现折叠 UI 可自行填。
2. 「当前工具」只有任务**结束后**的最终统计（本轮工具次数/最后失败工具）；
   实时「此刻正在跑哪个工具」需要宿主 TUI 读子会话的 part 流——那是宿主特性。
3. 宿主若不透传 `info.tokens`（旧版 SDK），`↓/✏` 显示 `—`，不报错。
