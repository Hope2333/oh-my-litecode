# Qwen Code Extensions

本目录包含符合 Qwen Code 官方规范的扩展。

## 可用扩展

### qwen-session-manager

Session 管理 TUI 和 CLI 工具。

**功能:**
- 交互式 curses TUI 界面
- 浏览、删除、批量删除会话
- 查看会话详情和最近消息

**安装:**
```bash
# 开发模式 (符号链接)
qwen extensions link /home/miao/develop/oh-my-litecode/extensions/qwen-session-manager

# 或从本地路径安装
qwen extensions install /home/miao/develop/oh-my-litecode/extensions/qwen-session-manager
```

**使用:**
```
/session tui          # 启动 TUI
/session list         # 列出会话
/session delete <id>  # 删除会话
/session clear        # 清空所有
/session info <id>    # 查看详情
/session help         # 帮助
```

**TUI 快捷键:**
| 键 | 功能 |
|----|------|
| ↑/k, ↓/j | 导航 |
| Enter | 查看详情 |
| d | 删除 |
| m | 多选模式 |
| x | 标记/取消 |
| D | 批量删除 |
| r | 刷新 |
| C | 清空所有 |
| ? | 帮助 |
| q | 退出 |

## 扩展结构

```
extension-name/
├── qwen-extension.json    # 必需：扩展配置
├── QWEN.md                # 可选：上下文文档
├── commands/              # 可选：自定义命令 (TOML)
│   └── command.toml
└── scripts/               # 可选：辅助脚本
    └── helper.py
```

## qwen-extension.json 格式

```json
{
  "name": "my-extension",
  "version": "1.0.0",
  "description": "扩展描述",
  "author": "作者名",
  "commands": "commands",
  "contextFileName": "QWEN.md"
}
```

## 开发流程

1. 创建扩展目录和 `qwen-extension.json`
2. 添加命令到 `commands/` 目录 (TOML 格式)
3. 使用 `qwen extensions link` 链接到开发目录
4. 测试扩展功能
5. 发布到 GitHub 供他人安装

## 参考文档

- [Qwen Code 扩展官方文档](https://qwenlm.github.io/qwen-code-docs/zh/developers/extensions/extension/)
- [Qwen Code CLI 文档](https://qwenlm.github.io/qwen-code-docs/)
