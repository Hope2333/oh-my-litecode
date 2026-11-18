---
name: neko-pty
description: PTY/交互式 TUI 控制规范——用 tmux 真机验证 OpenCode 插件渲染、/sessions、ctrl+p、快捷键，以及需要常驻交互进程的场景。当用户要求 TUI 目视确认、PTY 验证、交互式终端测试、抓屏确认面板渲染，或要操控一个长时间运行的 REPL/服务器时读它。
---

# Neko PTY 控制规范

> 目的：把「真机 TUI 验证」从每次手搓 tmux，变成可复用的固定流程。所有踩过的坑都写在这里，
> 不要重新试错。零运行时依赖，只需 `tmux`。

## 0. 铁律（先看）
1. **只碰 `oml-` 前缀会话**：`pty.sh` 强制会话名以 `oml-` 开头，`stop` 拒杀其它会话。
   **绝不 kill 生产服务器**（本机 4096 等是生产，与 tmux 会话无关）。
2. **本机 TERM 为空**：必须在启动命令内联 `TERM=xterm-256color`，否则 TUI 不渲染/乱码。助手已自动处理。
3. **leader 组合键必须分两次发**：`C-x` 发一次 → sleep → 再发组合键。一次 `send` 两个键会丢。用 `pty.sh leader <s> <key>`。
4. **输入行有字时斜杠命令无效**：`/sessions`、`/` 命令要求输入行为空，否则文本被当普通输入。助手 `cmd` 先发 `Escape` 清行。
5. **收尾必清理**：验证完 `stop` 掉自己的会话，别留僵尸。生产服务器全程不动。

## 1. 助手脚本
位置：`OC/omo/skills/neko-pty/pty.sh`（仓库内，随 OML 内置技能分发）。

```
pty.sh start   <oml-session> <dir> [prog]     # 默认 prog=opencode，自动 TERM=xterm-256color
pty.sh send    <oml-session> <key>...         # tmux 键名：Enter Down C-c C-x 等
pty.sh lit     <oml-session> <text>           # 字面文本（含 / 空格）
pty.sh leader  <oml-session> <key>            # C-x → sleep → key
pty.sh cmd     <oml-session> <slash-cmd>      # Escape 清行 → 输入 → Enter
pty.sh nav     <oml-session> <rows>           # /sessions → ↓N → Enter
pty.sh capture <oml-session> [lines]          # 抓屏（可只取末尾 N 行）
pty.sh wait    <oml-session> <pattern> [secs] # 轮询抓屏直到出现 pattern
pty.sh stop    <oml-session>                  # 只杀 oml- 会话
pty.sh list                                   # 列出 oml- 会话
```

自检（不碰 opencode，用 bash 验证机制）：
```bash
bash OC/omo/skills/neko-pty/pty.sh start oml-selftest /tmp bash
bash OC/omo/skills/neko-pty/pty.sh wait oml-selftest '$' 5
bash OC/omo/skills/neko-pty/pty.sh lit oml-selftest 'echo OK'
bash OC/omo/skills/neko-pty/pty.sh send oml-selftest Enter
bash OC/omo/skills/neko-pty/pty.sh capture oml-selftest | grep OK
bash OC/omo/skills/neko-pty/pty.sh stop oml-selftest
```

## 2. OC1（宿主 1.19.3）TUI 验证配方
```bash
S=oml-verify1
pty.sh start "$S" /home/miao                       # 会话须在子会话所在目录（多为 /home/miao）
pty.sh wait "$S" 'Welcome' 12                       # 等首屏

# 验证 /sessions 页面（带标题的会话列表）
pty.sh cmd "$S" "/sessions"
pty.sh capture "$S"                                # 应见 Sessions / Search / 会话列表

# 打开一个有子会话的富会话，验侧栏面板
pty.sh nav "$S" 3                                  # /sessions → ↓3 → Enter
pty.sh capture "$S"                                # 应见 fork 面板：Token Cache / SubAgent 树

# 验证 ctrl+p 命令面板
pty.sh leader "$S" "C-p"                           # 或 send C-p（leader 视版本）
pty.sh lit "$S" "SubAgent"; sleep 1
pty.sh capture "$S"                                # 应见 fork 注册的命令

# 验证 ctrl+x ↓ 原生 view-subagents
pty.sh leader "$S" "Down"
pty.sh capture "$S"                                # footer: Subagent (N of N) Parent/Prev/Next

# 收尾
pty.sh stop "$S"
```
**外部插件 TUI 配置**：面板经 `~/.config/opencode/tui.json`（宿主级）与项目 `.opencode/tui.json` 的
`plugin` 数组加载（本机两文件均列 `opencode-visual-cache`、`opencode-subagent-magazine`）。
临时注册本地 fork 时改 `file:///...` 绝对目录路径；**验证后必须恢复原内容**。

## 3. OC2（2.3.0）真机验证配方
OC2 是独立 ELF（`/tmp/oc2-bin/@opencode-cli-linux-x64/package/bin/opencode`，自带 Bun，不依赖系统 node）。
```bash
S=oml-verify2
# 隔离环境，绝不污染生产 1.19.x
export OPENCODE_CONFIG_DIR=/tmp/oc2-verify
export OPENCODE_TEST_HOME=/tmp/oc2-verify/home
pty.sh start "$S" /tmp/oc2-verify \
  '/tmp/oc2-bin/@opencode-cli-linux-x64/package/bin/opencode'
pty.sh wait "$S" 'Welcome' 12
pty.sh capture "$S"
pty.sh stop "$S"
```
**OC2 坑**：
- 配置键 `plugin` 被归一为 `plugins`；本地插件路径**必须是目录**（含 package.json + index.ts），
  指向 `.ts` 文件会 WARN `plugin path must be a directory` 且**静默不加载**。
- V2 入口是 `Plugin.define({id,setup})` 对象导出，函数导出在 2.3.0 被拒。
- 模型不可用时插件加载测试仍可做（setup 在会话启动前发生）。
- 证据落 `docs/bench/oc2-realmachine-*.md`。

## 4. 常见失败与处置
| 症状 | 原因 | 处置 |
|---|---|---|
| TUI 不渲染/乱码 | TERM 空 | 确认内联 `TERM=xterm-256color`（助手已做） |
| 组合键无效 | 一次发了两个键 | 用 `leader` 分两次 |
| `/sessions` 变成普通文本 | 输入行非空 | `cmd` 先 Escape 清行 |
| 面板不显示 | 会话无子会话 / sidebar 未开 / 未载入富会话 | 用 `nav` 载入有子会话的会话 |
| OC2 插件静默不加载 | 路径指向文件 | 改成目录 + package.json |
| 抓屏是旧 transcript | Down 当普通滚动，leader 未 arm | 重发 leader，确认 footer 出现 Subagent |
| `check` 偶发 6/7 | 并行测试写共享 MCP 目录竞态 | **串行复跑**，非产品 bug |

## 5. 与 OML 的关系
- 这是内置技能，随 `OC/omo/skills/` 分发，由 `host.ts` 的 `builtinSkills` 根自动扫描发现。
- 验证对象：A 路线 fork 插件（packages/tui-plugins/）、B 路线会话树（packages/tui-shell/）、OC2 V2 插件。
- 每次真机验证结果要落 `docs/bench/*.md` 并更新 BUDGET 记账；未验证项如实写进 README，不宣称可用。
