# OML SuperTUI 使用指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

OML SuperTUI 提供两种界面：
1. **基础版** - 使用 ANSI 转义码
2. **增强版** - 使用 ncurses (dialog/whiptail)

---

## 🚀 快速开始

### 安装依赖

```bash
# Arch Linux
sudo pacman -S dialog

# Debian/Ubuntu
sudo apt install dialog

# Termux
pkg install dialog
```

### 启动 SuperTUI

```bash
# 基础版
oml supertui

# 增强版 (推荐)
oml supertui-enhanced
```

---

## 🎮 基础版 SuperTUI

### 启动

```bash
oml supertui
```

### 操作

| 键 | 功能 |
|----|------|
| **↑/↓** | 导航菜单项 |
| **Enter** | 选择/确认 |
| **Esc/Q** | 返回/退出 |

### 界面预览

```
╔═══════════════════════════════════════╗
║     OML SuperTUI v1.0.0               ║
╚═══════════════════════════════════════╝

System: arch (x86_64)

┌───────────── Main Menu ─────────────┐
│ [●] Install OML                     │
│ [ ] Update OML                      │
│ [ ] Manage Plugins                  │
│ [ ] Qwenx Deployment                │
│ [ ] Exit                            │
└──────────────────────────────────────┘
```

---

## 🎮 增强版 SuperTUI (推荐)

### 启动

```bash
oml supertui-enhanced
```

### 主菜单

```
┌────────────────────────────────────────┐
│        OML SuperTUI v0.2.0             │
├────────────────────────────────────────┤
│ Select an option:                      │
│                                        │
│ 1. Install OML                         │
│ 2. Update OML                          │
│ 3. Manage Plugins                      │
│ 4. Qwenx Deployment                    │
│ 5. Configuration                       │
│ 6. System Info                         │
│ 7. Plugins List                        │
│ 8. Skills List                         │
│ 9. Subagents List                      │
│ 10. Performance                        │
│ 11. Cloud Sync                         │
│ 12. Exit                               │
└────────────────────────────────────────┘
```

### 命令行选项

```bash
# 直接访问功能
oml supertui-enhanced --menu      # 主菜单
oml supertui-enhanced --install   # 安装
oml supertui-enhanced --update    # 更新
oml supertui-enhanced --plugins   # 插件管理
oml supertui-enhanced --qwenx     # Qwenx 部署
oml supertui-enhanced --config    # 配置编辑
oml supertui-enhanced --system    # 系统信息
oml supertui-enhanced --help      # 帮助
```

---

## 📋 功能说明

### 1. Install OML

**功能**: 安装 OML

**选项**:
- Standard Installation - 标准安装
- Install with Qwenx - 带 Qwenx 安装
- Custom Installation - 自定义安装

### 2. Update OML

**功能**: 更新 OML

**选项**:
- Update OML Core - 更新核心
- Update Plugins - 更新插件
- Update All - 更新所有

### 3. Manage Plugins

**功能**: 管理插件

**选项**:
- List All Plugins - 列出所有插件
- List MCP Services - 列出 MCP
- List Subagents - 列出 Subagents
- List Skills - 列出 Skills

### 4. Qwenx Deployment

**功能**: Qwenx 部署

**选项**:
- Deploy Qwenx - 部署
- Update Qwenx - 更新
- Qwenx Status - 状态

### 5. Configuration

**功能**: 编辑配置文件

**编辑器**: nano 或 vi

### 6. System Info

**功能**: 显示系统信息

**信息**:
- System
- Architecture
- Package Manager
- Shell
- OS
- Git
- Python
- Node.js

### 7-9. Lists

**功能**: 列出插件/Skills/Subagents

**显示**: 名称和描述

### 10. Performance

**功能**: 性能工具

**选项**:
- Run Benchmark - 运行基准
- View Monitor Status - 查看监控
- Optimize Startup - 优化启动

### 11. Cloud Sync

**功能**: 云同步

**选项**:
- Initialize - 初始化
- Authenticate - 认证
- Pull - 拉取
- Push - 推送

---

## 🔧 故障排查

### 问题 1: dialog/whiptail 未安装

**错误**: `Neither dialog nor whiptail found`

**解决**:
```bash
# Arch
sudo pacman -S dialog

# Debian/Ubuntu
sudo apt install dialog

# Termux
pkg install dialog
```

### 问题 2: 权限错误

**错误**: `Permission denied`

**解决**:
```bash
chmod +x ~/develop/oh-my-litecode/bin/oml-supertui*
```

### 问题 3: 显示乱码

**解决**:
```bash
# 设置 UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

---

## 📊 对比

| 特性 | 基础版 | 增强版 |
|------|--------|--------|
| **依赖** | 无 | dialog/whiptail |
| **界面** | ANSI 转义码 | ncurses |
| **导航** | ↑↓ Enter Esc | Tab Enter Esc |
| **参数** | 无 | 支持 |
| **推荐** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

---

## 📚 相关文档

- [API 参考](docs/api/API-REFERENCE.md)
- [Arch 部署指南](docs/ARCH-DEPLOY-GUIDE.md)
- [最佳实践](docs/guides/BEST-PRACTICES.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
