# 工程哲学融入方案：从视频材料到 OML 能力

> Prometheus 格式。指导哲学=马列毛，但哲学用于**取舍判断**，不贴口号。
> 用户核心诉求（m02228）：「让模型在什么时候利用能力，放着不用终成摆设；模型要区分场景在合适时机启用」。
> 用户总纲（m02252）：「融入下面这些能力并达到具备，指导哲学仍是马列毛」。

## 目标
把视频材料里的十余项能力，按「是否直击 OML 主要矛盾」分级融入；全局能力进内核，专业能力做按需 skill，带争议项按反修立场最小化或拒绝。**具备 = 有代码、有测试、有验收命令、有记账**，不是挂名。

## 现状证据（盘点结论，路径:行号）
- 已有底座：压缩 `compress/store.ts:15-29`（编号锚点/分块/decompact，自述吸收 DCP+acp）、compaction hook `OC/omo/src/host.ts:689-702`；技能发现四层 `skills/{scan,index-gen,select,usage}.ts`；ACP 路由 `acp.ts:47-60`；规则纪律 `prompt/build.ts:25-50`（WORK_RULES 8 条）+ `worldview.ts:15-29` + `review/slop.ts`；配置装配 `config/schema.ts`（18 段）+ `prompt/build.ts:126-136`（section 顺序）；常驻能力目录 `capabilities/manifest.ts:25-34`。
- 真新增：PTY 控制、视频/文本蒸馏生成 skill、插件市场热榜、用量看板、逆向接口。
- 红线：A7 零遥测属公理（`config/schema.ts:159-160` 拒绝 telemetry=true；`docs/design/plugin-absorption.md:23` 明确拒绝 token-monitor）。

## 取舍判断（马列毛用于此处，非口号）

**主要矛盾**：不是「插件不够多」，而是两条——(1) 能力放着不用成摆设（用户上一轮亲口说的）；(2) token 浪费在表格/日志/接口返回的大量重复冗余。一切取舍看是否击中这两条。

| 素材能力 | 判断 | 依据（具体，非口号） |
|---|---|---|
| Ponytail KISS+YAGNI | **融入内核纪律层（第一批）** | OML 已有 WORK_RULES + 反 slop + 自力更生「能删就删」，KISS/YAGNI 是同一判断的命名化，补齐即可，几乎零成本。直击「半拉子工程/过度设计」 |
| Ponytail 任务完成度检查 | **融入内核纪律层（第一批）** | 与 OML「验收不可跳过、没跑不说完成」完全同构，补一条完成度自查 |
| token fold（无损折叠/预算帽/本地打码） | **TS 重写入核（第一批）** | 直击主要矛盾(2)。算法是纯文本处理，不重；已证本地计算非瓶颈，无需引入 Rust 二进制（自力更生/零运行时依赖）。本地运行+密钥打码与 A7 兼容 |
| opencode-pty（PTY，覆盖 OC1+OC2） | **新增模块（第一批或第二批）** | 我自己做 TUI 验证时全程手搓 tmux，这是真实刚需，不是玩具。封装后 OML 可自验渲染/操控会话 |
| DCP 分块压缩 | **扩展已有（第一批顺带）** | compress 已有会话区间压缩；视频里的 DCP 强调「工具返回分块 + @b13 锚点」，OML 锚点机制已有，扩展压缩对象到 tool result 即可 |
| Context7 / ACP | **已有，不重做** | 已实现并验证（见提交 62aa98e / acp.ts） |
| 仓颉Skill（视频蒸馏） | **专业按需 skill（第三批）** | 依赖外部模型(longcad2.5)+视频下载，不该进内核。做成 skill 骨架/接口，用时加载——这正是用户自己分的「专业按需」 |
| REA + Craft anything（逆向） | **专业按需接口（第三批）** | 专业领域工具，OML 只留占位接口 + 发现指引，不内置实现 |
| WakeTime 用量看板 | **反修：最小化或拒绝（见决策点）** | 用户自己视频里定性「玩具/锦上添花」；免费版收数据、付费解锁归档=行为数据变现，与 A7 零遥测直接冲突。若要，只做纯本地、opt-in、不上传、无花哨看板的最小统计 |
| OpenDock 插件热榜 | **拒绝照搬（指标崇拜）** | star/下载量排名≠质量（名头冒充真理）；OML 已有 catalog digest 自检 + suggestMcp 关键词推荐，够用。不追热榜 |

## 范围与分级
- **第一批（全局纪律层，直接击中主要矛盾）**：KISS/YAGNI + 完成度检查命名化进 prompt 纪律层；token fold 纯 TS 无损折叠模块；DCP 的 tool-result 分块扩展。
- **第二批（能力底座）**：PTY 封装模块（覆盖 OC1+OC2 的会话验证/操控）。
- **第三批（专业按需 skill）**：仓颉/逆向的 skill 骨架 + 发现指引。
- **不做/最小化**：WakeTime 看板、OpenDock 热榜（见决策点）。

## 步骤（第一批，Prometheus 六条硬规则）
1. 纪律层：在 `prompt/build.ts` 的 WORK_RULES 增补 KISS/YAGNI/完成度三条（带具体自查问句），不新增 section → 验收：`prompt/build.test.ts` 断言含三条 + budget 门仍 pass。
2. token fold：新增 `packages/core/src/tokenfold/fold.ts`（纯函数：重复字段提取表头、无损编码/还原、预算帽、密钥打码）+ 测试 → 验收：`bun test packages/core/src/tokenfold/` 0 fail；还原往返 100%。
3. tool-result 分块：扩展 compress 支持对单条工具返回按锚点分块 → 验收：`compress` 测试增例。
4. 记账 + manifest + 全量验收 → 验收：`bun test` 0 fail、`bun run check` 7/7、zero-growth 已记账。
5. 提交 master。

## 依赖顺序
1→3 可并行（不同文件）；2 独立；4 依赖前三步定稿；5 最后。

## 回滚
每批单 commit。回滚 = `git revert <sha>`；批次开始前基线 `git rev-parse HEAD` 记为 sha。

## 风险
- **预算门**：纪律层加 prompt 会涨 token（当前 3258/8192）——失败信号 budget>8192；三条自查控制在 ~120 tok。
- **零遥测红线**：token fold 的「密钥打码」是本地处理，不得加任何上传；WakeTime 若做必须 opt-in 且纯本地——失败信号：出现任何网络请求/telemetry 字段。
- **Rust 诱惑**：token fold 原文是 Rust，但本地计算非瓶颈，引入二进制违背零运行时依赖——守住 TS 重写。

## 自检
- [x] 每条判断指到证据/具体依据
- [x] 每步有验收命令
- [x] 边界写明（零遥测/零运行时依赖/不追热榜）
- [x] 回滚可执行
- [x] 哲学用于取舍非口号
- [x] 规模匹配（先规划第一批，分批交付）
