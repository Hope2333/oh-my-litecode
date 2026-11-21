# 上下文权威：三层 ACP 的关系与「装上插件仍违反纪律」的根因

> 由 Windows 备份会话（`oml-v2-win` 的 billion-context session `f79e...`）的分析引出。
> 核心教训：**上游在做压缩 ≠ 本地保护可以删**。这条曾导致 Windows 线删掉 OML 的
> 85% 主动检查点（误判为与 BC/ACP 重复），是违反纪律的静默删除，靠人工 diff 才发现。

## 三层上下文能力，谁是权威

| 层 | 谁提供 | 怎么进会话 | 管什么 | 是否权威 |
|---|---|---|---|---|
| ① 上游传输层 ACP | provider/harness（opencode.ai relay、big-pickle、bili proxy） | 在请求链路上注入 system 段（"Compression Philosophy"）+ `mNNNNN` 消息编号 + `compress`/`decompress`/`search_context`/`acp_status` 工具 | 裁剪上下文、让会话活得更久 | **否**——它只负责省 token |
| ② 本地 ACP 插件 | `opencode-acp`（v1）/ `billion-context`（v2+） | 宿主插件，改写 agent↔模型流，做增量分层压缩 | 「不爆窗口」 | **否**——流式引擎，宿主可换（见 `acp-routing.md`） |
| ③ OML 自带保护 | 本仓 `context/module.ts` + `host.ts` | 经 `system.transform`（v1 每会话注入）/ `setup` hook（v2 服务模式即刻跟随）进 identity 段 | 检查点、压缩纪律、可交接账本 | **是**——跟 OML 走，宿主无关 |

两层 ACP（①②）是**流式压缩**，解决"窗口够不够用"；OML 自带保护（③）是**确定性账本与纪律**，解决"压缩后结论丢没丢、纪律还在不在"。二者不互相替代。

## 「BC/ACP 未生效」的真实原因（Windows 会话结论）

那个会话从一开始就有 ACP 工具、`mNNNNN` 编号、Compression Philosophy——**都在本地装 `opencode-acp`/BC 插件之前**。Windows 侧 agent 反复推理后逼近的结论：

> ACP 来自上游 provider/harness 侧（opencode.ai relay + bili proxy），不是本地插件提供的。

所以本地装插件时"看不到新增效果"——效果本来就来自上游。两套 ACP 发生认知混淆，进而误判"上下文已经有人管了，OML 自己的检查点可以删"。

## 为什么"装上插件后仍违反纪律"

不是纪律没注入，是三个机制漏洞：

1. **叙事覆盖（认知层）**：上游 Compression Philosophy 更强、更靠后时，让人产生"上下文有人管"的错觉。纪律是被**叙事**覆盖，不是被技术覆盖。
2. **软注入（prompt 层）**：纪律靠 `system.transform` 注入，是建议性 prompt。上游注入若语义冲突，会稀释 OML 纪律。
3. **代码层无守卫（最致命）**：删检查点是改 `host.ts` 代码，prompt 管不到。Windows 线把 rescue 段连同行为测试一起删，hook 数量不变，`check` 的 surface/structure 门都发现不了，只能靠人工 diff。

## 三重防护（本次修复）

- **B（抗叙事/软注入覆盖）**：`context/module.ts` 的 `CONTEXT_RULES` 加"上下文权威"铁律——明说 OML 自带检查点优先级高于上游 ACP 提示，上游不替代/不取消/不删减本地保护。随 identity 段在 v1/v2 都注入。
- **A（抗代码层静默删除）**：`scripts/check.ts` 的 `gateDiscipline()` 钉死源码哨兵——85% 检查点（`lastAutoCheckpoint`/`pct >= 85`/`600_000`/`<auto-checkpoint`/`state.checkpoint()`）、压缩钩子（`experimental.session.compacting`/`COMPACTION_RULES`/`<omo-compaction>`）、上下文权威铁律三组标记任一消失，`check` 立即失败。行为测试（`OC/omo/src/host.test.ts:594`）仍在，源码守卫与之双保险。
- **C（抗复发）**：本文档定性三层关系，防止未来再误判删除。

## 就位时序（用户定义，已确认）

- **v1**：`system.transform` 每次请求注入 → 会话内装好插件后**下一次请求即遵循**；重启服务后所有会话完整跟随。
- **v2**：`setup()` 注册 hook，注册即对所有后续会话生效 → 服务模式**即刻跟随**。

时序本身无问题；问题在"注入的纪律不抗覆盖 + 代码层纪律无不可删守卫"。A/B/C 补的正是这两点。
