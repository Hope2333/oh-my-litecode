# OML 统一安装/更新入口计划

**版本**: 1.0.0  
**日期**: 2026-03-23  
**状态**: 📋 规划阶段

---

## 📋 项目概述

### 目标

创建 OML 的统一安装和更新入口，实现：
1. **自动识别多系统** (Termux/Arch/Debian/macOS)
2. **一键安装/更新**
3. **自更新能力**
4. **SuperTUI 交互界面**

### 子项目

| 项目 | 说明 | 优先级 |
|------|------|--------|
| **oml install** | 统一安装入口 | ⭐⭐⭐⭐⭐ |
| **oml update** | 统一更新入口 | ⭐⭐⭐⭐⭐ |
| **oml qwen** | Qwenx 部署和更新 | ⭐⭐⭐⭐ |
| **oml supertui** | TUI 交互系统 | ⭐⭐⭐ |

---

## 🎯 需求分析

### 1. 系统识别

**支持系统**:
- ✅ Termux (Android)
- ✅ Arch Linux
- ✅ Debian/Ubuntu
- ✅ macOS
- ⚠️ 其他 Linux 发行版

**识别内容**:
- 系统类型
- 包管理器 (pacman/apt/brew)
- Shell 类型 (bash/zsh)
- Python/Node.js 版本
- 现有 OML 安装状态

### 2. 安装功能

**基础安装**:
- 克隆仓库
- 设置 PATH
- 安装依赖
- 初始化配置

**选择性安装**:
- Qwen Agent
- MCP 服务
- 插件系统
- SuperTUI

### 3. 更新功能

**自更新**:
- 检查新版本
- 拉取最新代码
- 迁移配置
- 清理缓存

**组件更新**:
- 插件更新
- MCP 服务更新
- 依赖更新

### 4. Qwenx 部署

**oml qwen 命令**:
- 预览本机 qwenx 配置
- 管理 skills/agents
- 连接 OML 云项目
- 一键部署/更新

### 5. SuperTUI

**对标 nmtui**:
- 文本用户界面
- 键盘导航
- 实时状态显示
- 快速配置

---

## 🏗️ 架构设计

### 目录结构

```
oml/
├── bin/
│   ├── oml-install.sh      # 主安装脚本
│   ├── oml-update.sh       # 主更新脚本
│   └── oml-supertui        # SuperTUI 入口
├── lib/
│   ├── system-detect.sh    # 系统识别
│   ├── package-manager.sh  # 包管理器抽象
│   ├── config-migrate.sh   # 配置迁移
│   └── tui-lib.sh          # TUI 库
├── modules/
│   ├── core.sh             # 核心模块
│   ├── qwen.sh             # Qwenx 模块
│   ├── plugins.sh          # 插件模块
│   └── supertui.sh         # SuperTUI 模块
└── scripts/
    ├── self-update.sh      # 自更新脚本
    └── post-install.sh     # 安装后脚本
```

### 命令结构

```bash
# 安装
oml install [options]
oml install qwen           # 安装 Qwenx
oml install plugins        # 安装插件

# 更新
oml update [options]
oml update self            # 自更新
oml update plugins         # 更新插件
oml update qwen            # 更新 Qwenx

# 管理
oml status               # 查看状态
oml config               # 配置管理
oml supertui             # 启动 TUI
```

---

## 📝 实施计划

### Phase 1: 基础框架 (2 天)

#### Day 1: 系统识别和包管理器

- [ ] 创建 `lib/system-detect.sh`
  - 识别系统类型
  - 检测包管理器
  - 检测 Shell 环境
  - 检测依赖版本

- [ ] 创建 `lib/package-manager.sh`
  - 统一包管理接口
  - 支持 pacman/apt/brew
  - 依赖安装函数

#### Day 2: 安装脚本框架

- [ ] 创建 `bin/oml-install.sh`
  - 主安装逻辑
  - 选项解析
  - 进度显示
  - 错误处理

- [ ] 创建 `scripts/post-install.sh`
  - PATH 设置
  - 配置初始化
  - 依赖检查

### Phase 2: 更新功能 (2 天)

#### Day 3: 自更新系统

- [ ] 创建 `scripts/self-update.sh`
  - 版本检查
  - Git 拉取
  - 配置迁移
  - 回滚机制

- [ ] 创建 `lib/config-migrate.sh`
  - 配置版本检测
  - 自动迁移
  - 备份恢复

#### Day 4: 组件更新

- [ ] 创建 `oml update plugins`
  - 插件版本检查
  - 批量更新
  - 依赖处理

- [ ] 创建 `oml update qwen`
  - Qwenx 更新
  - 配置保留

### Phase 3: Qwenx 部署 (2 天)

#### Day 5: Qwenx 管理

- [ ] 创建 `modules/qwen.sh`
  - 预览.qwen 目录
  - 管理 skills/agents
  - 连接云项目

- [ ] 创建 `oml qwen` 命令
  - 部署向导
  - 一键更新
  - 配置同步

#### Day 6: 云项目连接

- [ ] 云项目接口
  - API 封装
  - 认证处理
  - 数据同步

### Phase 4: SuperTUI (3 天)

#### Day 7-8: TUI 库

- [ ] 创建 `lib/tui-lib.sh`
  - 基础 UI 组件
  - 键盘导航
  - 颜色主题
  - 对话框系统

#### Day 9: SuperTUI 实现

- [ ] 创建 `bin/oml-supertui`
  - 主界面
  - 功能菜单
  - 状态显示
  - 快速配置

### Phase 5: 测试和文档 (1 天)

#### Day 10: 测试和文档

- [ ] 跨平台测试
- [ ] 编写文档
- [ ] 示例脚本

---

## 🔧 技术细节

### 1. 系统识别实现

```bash
#!/usr/bin/env bash
# lib/system-detect.sh

detect_system() {
    if [[ -d "/data/data/com.termux/files/usr" ]]; then
        SYSTEM="termux"
        PKG_MANAGER="pkg"
    elif [[ -f "/etc/arch-release" ]]; then
        SYSTEM="arch"
        PKG_MANAGER="pacman"
    elif [[ -f "/etc/debian_version" ]]; then
        SYSTEM="debian"
        PKG_MANAGER="apt"
    elif [[ "$(uname)" == "Darwin" ]]; then
        SYSTEM="macos"
        PKG_MANAGER="brew"
    else
        SYSTEM="unknown"
        PKG_MANAGER=""
    fi
}
```

### 2. 包管理器抽象

```bash
#!/usr/bin/env bash
# lib/package-manager.sh

pkg_install() {
    local packages=("$@")
    
    case "$PKG_MANAGER" in
        pkg)
            pkg install -y "${packages[@]}"
            ;;
        pacman)
            sudo pacman -S --noconfirm "${packages[@]}"
            ;;
        apt)
            sudo apt install -y "${packages[@]}"
            ;;
        brew)
            brew install "${packages[@]}"
            ;;
    esac
}
```

### 3. SuperTUI 界面

```
┌─────────────────────────────────────┐
│       OML SuperTUI v1.0.0          │
├─────────────────────────────────────┤
│  [●] Install OML                   │
│  [ ] Update OML                    │
│  [ ] Manage Plugins                │
│  [ ] Qwenx Deployment              │
│  [ ] Configuration                 │
│  [ ] Exit                          │
├─────────────────────────────────────┤
│  Status: Ready                     │
│  System: Termux (aarch64)          │
│  Version: 0.8.0                    │
└─────────────────────────────────────┘
```

---

## 📊 验收标准

### 安装功能

- [ ] 支持 4+ 系统
- [ ] 一键安装
- [ ] 依赖自动安装
- [ ] 配置自动初始化

### 更新功能

- [ ] 自更新正常
- [ ] 配置迁移无误
- [ ] 回滚机制有效
- [ ] 组件更新正常

### Qwenx 部署

- [ ] 预览.qwen 目录
- [ ] 管理 skills/agents
- [ ] 连接云项目
- [ ] 一键部署

### SuperTUI

- [ ] TUI 界面正常
- [ ] 键盘导航流畅
- [ ] 实时状态显示
- [ ] 快速配置可用

---

## 📚 相关文档

- [安装指南](docs/INSTALL.md)
- [更新指南](docs/UPDATE.md)
- [SuperTUI 使用](docs/SUPERTUI.md)
- [Qwenx 部署](docs/QWEN-DEPLOY.md)

---

**制定者**: OML Team  
**日期**: 2026-03-23  
**状态**: 📋 待审批
