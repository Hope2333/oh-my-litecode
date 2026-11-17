# 长任务 A/B：中断 + 恢复（评审遗留项）

## 为什么单造一个基准

`ab-task.md` 里的 5 个任务都在 30–60 秒内收尾，**根本用不上恢复**，所以它们只能证明
「便宜」，证明不了 checkpoint/handoff 有没有用。这个基准在固定时间点 SIGKILL 掉进程，
再用**同一句恢复提示词**开新会话收尾。

## 方法

- 任务：实现持久化 KV（`createStore(file)` 的 get/set/del/save/load）+ ≥5 个测试 + `bun test` 全绿。
- 验收 `bench/tasks/06-store/verify.ts`：跑测试 + 独立进程探针（set/get 一致、del 返回值正确、重开后数据仍在、load 缺文件不报错）。
- 两个阶段：阶段 1 跑满 `--kill` 毫秒后 `kill(9)`；阶段 2 用固定恢复提示词再跑，允许跑到结束。
- 两边给同一个环境变量 `OML_STATE_DIR=<work>/.oml-state`：OML 会往里写滚动检查点/任务账本，OMO 不认识它。恢复提示词里两边都被告知「若工作区有 .oml-state/ 就先读」。
- 模型 `bailing/Ling-3.0-flash`、`--agent sisyphus`、同 fixture、同提示词。唯一变量是装哪个插件。

## 结果

| kill 预算 | OML | OML 总输入 | OMO | OMO 总输入 |
|---|---|---|---|---|
| 12s | ✗ 探针失败 | 71,421 | ✗ 探针失败 | 198,421 |
| 20s | ✗ 测试未通过 | 67,268 | ✓ | 98,516 |
| 30s | ✓（**没被杀**，自己跑完了） | 75,243 | ✓（被杀后恢复） | 184,788 |

数字来源：12s 两组、20s OMO、30s OMO 在 `docs/bench/long-ab-*.json`；20s OML 与 30s OML
来自当次终端输出（同 label 文件被后续运行覆盖，属基准脚本缺陷，已记在下面「已知缺陷」）。

## 怎么读（结论对我方不利的部分照写）

1. **没有证据表明 OML 的恢复能力更强。** 20s 档 OML 失败、OMO 成功；12s 档两边都失败。
   我加了「滚动检查点」（每轮用户发言落盘一次，不依赖模型自觉），它确实产生了文件
   （`stateAfterKill=true`），但**产生了文件 ≠ 恢复成功**——模型读了也没把活干对。
2. **有证据表明 OML 更省。** 同档位输入 token：12s 档 71K vs 198K（2.8×）；30s 档 75K vs 185K（2.5×）。
   20s 档是唯一 OMO 更省的格子（98K vs 67K），因为 OML 那一次没做成。
3. **单次跑方差极大。** OMO 同一个任务在 20s/30s 两档分别是 98K 与 185K，说明这里的数字
   只能当量级看，不能当精确比较。要出显著性结论需要 N≥5 次重复。
4. **30s 档最值得注意**：OML 在预算内自己完成了，OMO 被切断后才靠恢复收尾。若「固定墙钟预算内
   自主完成率」是切换判据，这一档支持 OML；但样本只有 1 次。

## 已知缺陷（下次改）

- 同一个 `--label` 会覆盖上一次 JSON → 应带 kill 值进文件名。
- 阶段 1 只有 `step-finish` 事件能计数，被杀时最后一步的 token 会丢，故 phase1 数字偏低。
- 探针 API 由 README 钉死，模型的自由发挥空间小；真实长任务更开放，恢复难度更高。

## 复现

```bash
bun bench/ab-long.ts --label oml --kill 20000
mv ~/.config/opencode/plugin/omo.ts /tmp/omo.ts.off
bun bench/ab-long.ts --label omo --kill 20000 --config /tmp/omo-only.json
cp /tmp/omo.ts.off ~/.config/opencode/plugin/omo.ts   # 务必恢复
```
