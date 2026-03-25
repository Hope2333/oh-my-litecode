# OML Arch Linux 部署指南

**版本**: 0.2.0  
**日期**: 2026-03-23

---

## 📖 概述

本指南帮助在 Arch Linux 上快速部署 OML。

---

## 🚀 快速部署 (3 步)

### 步骤 1: 安装依赖

```bash
# 更新系统
sudo pacman -Syu

# 安装基础依赖
sudo pacman -S --noconfirm git bash python python-pip nodejs npm curl jq
```

### 步骤 2: 克隆并安装 OML

```bash
# 克隆仓库
git clone https://github.com/Hope2333/oh-my-litecode.git ~/develop/oh-my-litecode
cd ~/develop/oh-my-litecode

# 运行安装脚本
bash bin/oml-install.sh
```

### 步骤 3: 验证安装

```bash
# 刷新环境变量
source ~/.bashrc

# 验证 OML
oml --help

# 查看状态
oml update status
```

---

## 📋 详细部署

### 前置要求

| 组件 | 版本 | 安装命令 |
|------|------|---------|
| Git | 最新 | `sudo pacman -S git` |
| Bash | 5.0+ | `sudo pacman -S bash` |
| Python | 3.10+ | `sudo pacman -S python python-pip` |
| Node.js | 18+ | `sudo pacman -S nodejs npm` |
| Curl | 最新 | `sudo pacman -S curl` |
| JQ | 最新 | `sudo pacman -S jq` |

### 安装 OML

```bash
# 1. 创建开发目录
mkdir -p ~/develop
cd ~/develop

# 2. 克隆仓库
git clone https://github.com/Hope2333/oh-my-litecode.git
cd oh-my-litecode

# 3. 设置权限
chmod +x bin/*.sh lib/*.sh modules/*.sh
chmod +x plugins/*/*/main.sh

# 4. 添加到 PATH
echo '' >> ~/.bashrc
echo '# OML (Oh My Litecode)' >> ~/.bashrc
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc

# 5. 使配置生效
source ~/.bashrc
```

### 安装 Python 依赖

```bash
# 安装 MCP 依赖
pip install --user mcp pydantic httpx

# 安装其他依赖
pip install --user requests
```

### 安装 Node.js 依赖

```bash
# 安装 Context7 MCP
npm install -g @upstash/context7-mcp
```

---

## 🔧 配置

### 初始化配置

```bash
# 创建配置目录
mkdir -p ~/.oml

# 创建配置文件
cat > ~/.oml/config.json <<EOF
{
  "version": "0.2.0",
  "installed_at": "$(date -Iseconds)",
  "branch": "main",
  "system": "arch"
}
EOF
```

### 验证版本一致性

```bash
# 运行版本检查
./scripts/verify-version.sh
```

**预期输出**:
```
╔═══════════════════════════════════════╗
║  OML Version Consistency Checker      ║
╚═══════════════════════════════════════╝

Checking core version...
  Core: ✓ 0.2.0

Checking plugin versions...
  qwen: ✓
  build: ✓
  ... (all plugins)

✓ Version consistency check passed
```

---

## 🎯 预期成果

### 安装后可用功能

#### 1. 核心命令

```bash
# 查看帮助
oml --help

# 更新 OML
oml update all

# 查看状态
oml update status
```

#### 2. MCP 服务 (13 个)

```bash
# 列出 MCP
oml plugins list mcps

# 使用 MCP
oml mcp context7 query "Python tutorial"
oml mcp grep-app search "async def"
oml mcp filesystem list ~/
```

#### 3. Subagents (12 个)

```bash
# 列出 Subagents
oml plugins list subagents

# 使用 Subagent
oml subagent researcher search_web "AI trends"
oml subagent tester generate_tests ./src
```

#### 4. Skills (20 个)

```bash
# 列出 Skills
oml plugins list skills

# 使用 Skill
oml skill code-review review_code ./src/main.py
oml skill security-scan scan_vulnerabilities ./src
```

#### 5. SuperTUI

```bash
# 启动 TUI
oml supertui
```

**预期界面**:
```
╔═══════════════════════════════════════╗
║     OML SuperTUI v0.2.0               ║
╚═══════════════════════════════════════╝

System: arch (x86_64)
OML Root: ~/develop/oh-my-litecode

┌───────────── Main Menu ─────────────┐
│ [●] Install OML                     │
│ [ ] Update OML                      │
│ [ ] Manage Plugins                  │
│ [ ] Qwenx Deployment                │
│ [ ] Exit                            │
└──────────────────────────────────────┘
```

---

## 🧪 验证测试

### 运行测试套件

```bash
# 核心功能测试
bash bin/oml-install.sh --help
bash bin/oml-update.sh help

# 插件测试
for plugin in plugins/mcps/*/; do
    if [[ -f "${plugin}tests/test-*.sh" ]]; then
        bash "${plugin}tests/test-*.sh"
    fi
done
```

### 性能基准

```bash
# 运行性能基准
oml perf benchmark
```

**预期输出**:
```
╔═══════════════════════════════════════╗
║     OML Performance Benchmark         ║
╚═══════════════════════════════════════╝

Startup Time: ~200ms
Status: Good

Cache: Initialized
Memory Usage: ~80MB
```

---

## 🔍 故障排查

### 问题 1: 命令找不到

```bash
# 检查 PATH
echo $PATH | grep oh-my-litecode

# 手动添加 PATH
export PATH="$HOME/develop/oh-my-litecode:$PATH"

# 永久添加
echo 'export PATH="$HOME/develop/oh-my-litecode:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 问题 2: 权限错误

```bash
# 修复权限
chmod +x ~/develop/oh-my-litecode/bin/*.sh
chmod +x ~/develop/oh-my-litecode/lib/*.sh
chmod +x ~/develop/oh-my-litecode/modules/*.sh
chmod +x ~/develop/oh-my-litecode/plugins/*/*/main.sh
```

### 问题 3: 依赖缺失

```bash
# 重新安装依赖
sudo pacman -S --noconfirm git bash python python-pip nodejs npm curl jq

# 重新安装 Python 依赖
pip install --user mcp pydantic httpx requests
```

---

## 📚 后续步骤

### 1. 配置 Qwenx

```bash
# 部署 Qwenx
oml qwen deploy

# 添加 API Key
oml qwen-key add sk-xxxxx work

# 切换 Key
oml qwen-key use 0
```

### 2. 配置云同步

```bash
# 初始化云同步
oml cloud init

# 认证
oml cloud auth

# 同步
oml cloud sync pull
```

### 3. 使用 SuperTUI

```bash
# 启动 TUI
oml supertui

# 切换主题
oml tui theme use dark
```

---

## 📊 部署检查清单

- [ ] 系统更新完成
- [ ] 依赖安装完成
- [ ] 仓库克隆完成
- [ ] PATH 配置完成
- [ ] Python 依赖安装完成
- [ ] Node.js 依赖安装完成
- [ ] 版本检查通过
- [ ] 基本命令测试通过
- [ ] SuperTUI 启动成功

---

## 🔗 相关文档

- [API 参考](docs/api/API-REFERENCE.md)
- [快速开始](QUICKSTART.md)
- [使用指南](README-OML.md)

---

**维护者**: OML Team  
**版本**: 0.2.0
