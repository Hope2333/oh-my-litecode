# OML 安装和更新指南

**版本**: 1.0.0  
**日期**: 2026-03-23

---

## 📖 简介

OML 提供统一的安装和更新入口，自动识别多系统并一键完成部署。

### 支持系统

| 系统 | 包管理器 | 状态 |
|------|---------|------|
| **Termux** (Android) | pkg | ✅ |
| **Arch Linux** | pacman | ✅ |
| **Debian/Ubuntu** | apt | ✅ |
| **RHEL/Fedora** | dnf | ✅ |
| **macOS** | brew | ✅ |

---

## 🚀 快速安装

### 方法 1: 一键安装（推荐）

```bash
# Termux/Linux
curl -fsSL https://raw.githubusercontent.com/your-org/oh-my-litecode/main/bin/oml-install.sh | bash

# 或使用 wget
wget -qO- https://raw.githubusercontent.com/your-org/oh-my-litecode/main/bin/oml-install.sh | bash
```

### 方法 2: 手动安装

```bash
# 克隆仓库
git clone https://github.com/your-org/oh-my-litecode.git ~/develop/oh-my-litecode

# 运行安装脚本
cd ~/develop/oh-my-litecode
bash bin/oml-install.sh
```

### 方法 3: 自定义安装

```bash
# 自定义安装路径
bash bin/oml-install.sh --root /opt/oml

# 自定义分支
bash bin/oml-install.sh --branch develop
```

---

## 🔄 更新 OML

### 检查更新

```bash
oml update check
```

### 更新 OML 核心

```bash
oml update self
```

### 更新插件

```bash
oml update plugins
```

### 更新所有内容

```bash
oml update all
```

### 查看状态

```bash
oml update status
```

---

## 📋 安装步骤详解

### 1. 系统检测

安装脚本会自动检测：
- 系统类型 (Termux/Arch/Debian/macOS)
- 包管理器 (pkg/pacman/apt/dnf/brew)
- Shell 类型 (bash/zsh)
- 架构 (x86_64/aarch64/arm)

### 2. 依赖安装

自动安装以下依赖：
- git
- bash
- python3
- curl
- wget (部分系统)
- jq (部分系统)

### 3. PATH 设置

自动添加到 `~/.bashrc` 或 `~/.zshrc`：
```bash
export PATH="$HOME/develop/oh-my-litecode:$PATH"
```

### 4. 配置初始化

创建 `~/.oml/config.json`：
```json
{
  "version": "1.0.0",
  "installed_at": "2026-03-23T10:00:00+08:00",
  "branch": "main",
  "system": "termux"
}
```

---

## ⚙️ 配置管理

### 配置位置

```
~/.oml/
├── config.json          # 主配置
├── backups/             # 配置备份
│   └── 20260323_120000/
└── cache/               # 缓存
```

### 备份配置

```bash
# 手动备份
oml update self

# 自动备份（更新时）
# 更新前会自动备份到 ~/.oml/backups/
```

### 恢复配置

```bash
# 从备份恢复
cp ~/.oml/backups/20260323_120000/config.json ~/.oml/config.json
```

---

## ❓ 常见问题

### Q: 安装失败怎么办？

**A**: 
```bash
# 1. 检查依赖
pkg update && pkg upgrade  # Termux
sudo apt update            # Debian

# 2. 手动安装依赖
bash bin/oml-install.sh

# 3. 查看日志
cat ~/.oml/install.log
```

### Q: 如何卸载 OML？

**A**: 
```bash
# 1. 删除安装目录
rm -rf ~/develop/oh-my-litecode

# 2. 删除配置
rm -rf ~/.oml

# 3. 清理 PATH
# 编辑 ~/.bashrc 或 ~/.zshrc，删除 OML 相关行
```

### Q: 如何切换分支？

**A**: 
```bash
cd ~/develop/oh-my-litecode
git checkout develop
git pull origin develop
```

### Q: 更新后配置丢失？

**A**: 
```bash
# 从备份恢复
ls ~/.oml/backups/
cp ~/.oml/backups/<timestamp>/config.json ~/.oml/config.json
```

---

## 🔧 高级用法

### 离线安装

```bash
# 1. 在有网络的机器上下载
git clone https://github.com/your-org/oh-my-litecode.git

# 2. 复制到离线机器
scp -r oh-my-litecode user@offline-machine:~/develop/

# 3. 运行安装
bash bin/oml-install.sh
```

### 批量部署

```bash
#!/bin/bash
# deploy.sh

OML_ROOT="/opt/oml"
OML_BRANCH="main"

bash bin/oml-install.sh --root "$OML_ROOT" --branch "$OML_BRANCH"
```

### CI/CD集成

```yaml
# .github/workflows/install.yml
name: Install Test

on: push

jobs:
  install:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install OML
        run: bash bin/oml-install.sh
      - name: Verify
        run: oml --help
```

---

## 📚 相关文档

- [安装计划](OML-INSTALLER-PLAN.md)
- [快速开始](../QUICKSTART.md)
- [完整文档](../README-OML.md)

---

**维护者**: OML Team  
**许可**: MIT
