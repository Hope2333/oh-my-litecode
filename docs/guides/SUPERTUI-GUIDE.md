# OML SuperTUI 使用指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

SuperTUI 是 OML 的文本用户界面，灵感来自 nmtui。

---

## 🚀 快速开始

### 启动 SuperTUI

```bash
oml supertui
```

### 界面预览

```
╔═══════════════════════════════════════╗
║     OML SuperTUI v0.2.0               ║
╚═══════════════════════════════════════╝

System: termux (aarch64)
OML Root: ~/develop/oh-my-litecode

┌───────────── Main Menu ─────────────┐
│ [●] Install OML                     │
│ [ ] Update OML                      │
│ [ ] Manage Plugins                  │
│ [ ] Qwenx Deployment                │
│ [ ] Configuration                   │
│ [ ] System Info                     │
│ [ ] Exit                            │
└──────────────────────────────────────┘

↑↓ Navigate | Enter Select | Esc Exit
```

---

## 🎮 操作指南

### 键盘快捷键

| 键 | 功能 |
|----|------|
| **↑/↓** | 导航菜单项 |
| **Enter** | 选择/确认 |
| **Esc** | 返回/退出 |
| **Q** | 退出 |
| **H** | 显示帮助 |

### 鼠标支持

- 点击菜单项选择
- 点击按钮执行

---

## 🎨 主题系统

### 查看可用主题

```bash
oml tui theme list
```

### 切换主题

```bash
# 使用暗色主题
oml tui theme use dark

# 使用默认主题
oml tui theme use default
```

### 创建自定义主题

```bash
oml tui theme create mytheme
```

### 导出主题

```bash
oml tui theme export
```

---

## 📋 功能菜单

### Install OML

- 安装 OML
- 选择安装路径
- 选择组件

### Update OML

- 更新 OML 核心
- 更新插件
- 更新所有

### Manage Plugins

- 列出插件
- 启用/禁用插件
- 安装新插件

### Qwenx Deployment

- 部署 Qwenx
- 配置 Qwenx
- 查看状态

### Configuration

- 编辑配置文件
- 查看配置
- 重置配置

### System Info

- 系统信息
- OML 状态
- 性能指标

---

## 🔧 高级用法

### 后台运行

```bash
# 启动后台 TUI
oml supertui --background
```

### 指定配置

```bash
oml supertui --config /path/to/config
```

### 调试模式

```bash
oml supertui --debug
```

---

## ❓ 常见问题

### Q: TUI 显示乱码？

**A**: 检查终端编码设置
```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

### Q: 键盘无响应？

**A**: 检查终端输入模式
```bash
# 重置终端
reset
```

### Q: 如何退出 TUI？

**A**: 按 `Esc` 或选择 `Exit` 菜单项

---

## 📚 相关文档

- [API 参考](../api/API-REFERENCE.md)
- [插件开发指南](guides/PLUGIN-DEV-GUIDE.md)
- [故障排查](guides/TROUBLESHOOTING.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
