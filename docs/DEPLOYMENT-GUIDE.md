# OML 多平台部署指南

**版本**: 0.2.0
**最后更新**: 2026-03-23
**支持平台**: Termux (Android), Arch Linux, Debian, Ubuntu, Fedora, RHEL, openSUSE, Alpine

---

## 📋 平台支持矩阵

| 平台 | 包管理器 | 安装脚本 | 状态 |
|------|---------|---------|------|
| **Termux (Android)** | pacman/pkg | `scripts/update-qwenx.sh` | ✅ 完整支持 |
| **Arch Linux** | pacman | `scripts/install-archlinux.sh` | ✅ 完整支持 |
| **Manjaro** | pacman | `scripts/install-archlinux.sh` | ✅ 完整支持 |
| **EndeavourOS** | pacman | `scripts/install-archlinux.sh` | ✅ 完整支持 |
| **Debian** | apt | `scripts/install-gnulinux.sh` | ✅ 完整支持 |
| **Ubuntu** | apt | `scripts/install-gnulinux.sh` | ✅ 完整支持 |
| **Linux Mint** | apt | `scripts/install-gnulinux.sh` | ✅ 完整支持 |
| **Pop!_OS** | apt | `scripts/install-gnulinux.sh` | ✅ 完整支持 |
| **Fedora** | dnf | `scripts/install-gnulinux.sh` | ✅ 完整支持 |
| **RHEL/CentOS** | dnf/yum | `scripts/install-gnulinux.sh` | ✅ 完整支持 |
| **openSUSE** | zypper | `scripts/install-gnulinux.sh` | ✅ 完整支持 |
| **Alpine Linux** | apk | `scripts/install-gnulinux.sh` | ✅ 完整支持 |

---

## 🚀 快速安装

### 方法一：自动安装脚本（推荐）

#### GNU/Linux 通用
```bash
# 一键安装（支持 Arch/Debian/Ubuntu/Fedora/RHEL/openSUSE/Alpine）
curl -fsSL https://raw.githubusercontent.com/Hope2333/oh-my-litecode/main/scripts/install-gnulinux.sh | sudo bash
```

#### Arch Linux 专用
```bash
# Arch Linux / Manjaro / EndeavourOS
curl -fsSL https://raw.githubusercontent.com/Hope2333/oh-my-litecode/main/scripts/install-archlinux.sh | sudo bash
```

#### Termux
```bash
# Termux (Android)
pkg update && pkg upgrade
pkg install git bash nodejs python jq curl wget zstd
git clone https://github.com/Hope2333/oh-my-litecode.git ~/develop/oh-my-litecode
bash ~/develop/oh-my-litecode/scripts/update-qwenx.sh
```

### 方法二：手动安装

#### 1. 安装依赖

```bash
# Arch Linux / Manjaro / EndeavourOS
sudo pacman -Syu git bash nodejs npm python python-pip jq curl wget zstd

# Debian / Ubuntu / Linux Mint
sudo apt update && sudo apt upgrade -y
sudo apt install -y git bash nodejs npm python3 python3-pip jq curl wget zstd

# Fedora / RHEL / CentOS
sudo dnf install -y git bash nodejs npm python3 python3-pip jq curl wget zstd

# openSUSE
sudo zypper install -y git bash nodejs npm python3 python3-pip jq curl wget zstd

# Alpine Linux
sudo apk add --no-cache git bash nodejs npm python3 py3-pip jq curl wget zstd
```

#### 2. 克隆仓库

```bash
git clone https://github.com/Hope2333/oh-my-litecode.git ~/develop/oh-my-litecode
cd ~/develop/oh-my-litecode
```

#### 3. 配置环境变量

```bash
# 添加到 ~/.bashrc
cat >> ~/.bashrc << 'EOF'

# OML (Oh-My-Litecode) 配置
export OML_HOME="$HOME/.oml"
export OML_BIN="$OML_HOME/bin"
export PATH="$HOME/develop/oh-my-litecode:$OML_BIN:$PATH"
EOF

source ~/.bashrc
```

#### 4. 创建符号链接

```bash
# 系统级安装（需要 sudo）
sudo ln -sf ~/develop/oh-my-litecode/oml /usr/local/bin/oml
sudo ln -sf ~/develop/oh-my-litecode/oml /usr/local/bin/qwenx
```

#### 5. 配置 qwenx

```bash
# 创建配置目录
mkdir -p ~/.local/home/qwenx/.qwen
mkdir -p ~/.local/home/qwenx/.qwenx/secrets

# 创建默认配置
cat > ~/.local/home/qwenx/.qwen/settings.json << 'EOF'
{
  "mcp": {
    "allowed": ["context7", "grep-app", "websearch"],
    "excluded": []
  },
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "protocol": "mcp",
      "enabled": true
    },
    "grep-app": {
      "command": "bash",
      "args": ["/home/YOUR_USERNAME/develop/oh-my-litecode/plugins/mcps/grep-app/main.sh", "mcp-stdio"],
      "protocol": "mcp",
      "enabled": true
    },
    "websearch": {
      "command": "bash",
      "args": ["/home/YOUR_USERNAME/develop/oh-my-litecode/plugins/mcps/websearch/main.sh", "mcp-stdio"],
      "protocol": "mcp",
      "enabled": true
    }
  }
}
EOF
```

#### 6. 安装 System Skills

```bash
# 创建 skills 目录
sudo mkdir -p /usr/lib/opencode/system-skills
sudo mkdir -p /usr/share/opencode

# 复制 skill manifests（如果有 opencode-termux）
if [[ -d ~/develop/opencode-termux/packaging/manifests/system-skills ]]; then
    sudo cp ~/develop/opencode-termux/packaging/manifests/system-skills/*.json /usr/lib/opencode/system-skills/
    sudo cp ~/develop/opencode-termux/packaging/manifests/system-skills/blocklist.json /usr/share/opencode/system-skills-registry.json
fi
```

---

## 🔧 平台检测

### 使用 platform.sh

```bash
# 检测平台
source ~/develop/oh-my-litecode/core/platform.sh
oml_platform_detect

# 获取平台家族
oml_platform_family

# 获取包管理器
oml_pkgmgr_detect

# 检查依赖
oml_check_deps git nodejs python3

# 安装依赖
oml_install_deps git nodejs python3
```

### 使用 oml 命令

```bash
# 检测平台
oml platform detect

# 查看平台信息
oml platform info

# 健康检查
oml platform doctor
```

---

## 📁 目录结构

```
~/develop/oh-my-litecode/
├── oml                          # 主 CLI 入口
├── core/
│   ├── platform.sh              # 平台检测与适配 ⭐
│   ├── plugin-loader.sh         # 插件加载
│   ├── session-manager.sh       # Session 管理
│   ├── hooks-engine.sh          # Hooks 引擎
│   └── pool-manager.sh          # Worker 池管理
├── plugins/
│   ├── agents/                  # Agent 插件
│   ├── subagents/               # Subagent 插件
│   ├── mcps/                    # MCP 插件
│   └── core/                    # 核心插件
├── scripts/
│   ├── install-archlinux.sh     # Arch 安装脚本
│   ├── install-gnulinux.sh      # GNU/Linux 通用安装脚本 ⭐
│   └── update-qwenx.sh          # qwenx 更新脚本
├── docs/
│   ├── oml/                     # OML 文档
│   └── DEPLOYMENT-GUIDE.md      # 部署指南 ⭐
└── tests/                       # 测试套件
```

---

## ⚙️ 配置说明

### 环境变量

```bash
# OML 配置
export OML_HOME="$HOME/.oml"
export OML_BIN="$OML_HOME/bin"
export PATH="$HOME/develop/oh-my-litecode:$OML_BIN:$PATH"

# Qwen API 配置
export QWEN_API_KEY="sk-your-api-key"
export QWEN_BASE_URL="https://api.example.com/v1"

# Context7 API 配置
export CONTEXT7_API_KEY="ctx7sk-your-key"

# Exa API 配置（WebSearch MCP）
export EXA_API_KEY="exa-your-key"
```

### 配置文件

| 文件 | 位置 | 说明 |
|------|------|------|
| `settings.json` | `~/.local/home/qwenx/.qwen/` | qwenx 主配置 |
| `opencode.json` | `~/.config/opencode/` | opencode 配置 |
| `oh-my-opencode.json` | `~/.config/opencode/` | oh-my-opencode 配置 |
| `system-skills-registry.json` | `/usr/share/opencode/` | System Skills 注册表 |

---

## 🔍 故障排查

### 问题 1: 平台检测失败

```bash
# 检查 /etc/os-release
cat /etc/os-release

# 手动指定平台
export OML_PLATFORM="gnu-linux"
```

### 问题 2: 包管理器检测失败

```bash
# 查看可用包管理器
which apt dnf yum pacman zypper apk 2>/dev/null

# 手动指定
export OML_PKGMGR="apt"
```

### 问题 3: qwenx 命令找不到

```bash
# 检查 PATH
echo $PATH | grep oh-my-litecode

# 重新创建符号链接
sudo ln -sf ~/develop/oh-my-litecode/oml /usr/local/bin/qwenx
```

### 问题 4: MCP 服务未连接

```bash
# 检查配置
cat ~/.local/home/qwenx/.qwen/settings.json

# 重启 qwenx
pkill -f qwen
qwenx "test"
```

---

## 📊 平台特性对比

| 特性 | Termux | Arch | Debian | Fedora | openSUSE |
|------|--------|------|--------|--------|----------|
| **包管理器** | pacman/pkg | pacman | apt | dnf | zypper |
| **Prefix** | `/data/data/com.termux/files/usr` | `/usr` | `/usr` | `/usr` | `/usr` |
| **Fake HOME** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **System Skills** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **MCP Services** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Worker Pool** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Hooks System** | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 🔗 相关文档

- [快速开始](../QUICKSTART.md)
- [完整使用指南](./oml/USER-GUIDE.md)
- [架构概览](./oml/ARCHITECTURE-OVERVIEW.md)
- [QWEN.md](../QWEN.md) - 项目上下文

---

## 🆘 获取帮助

- **GitHub Issues**: https://github.com/Hope2333/oh-my-litecode/issues
- **讨论区**: https://github.com/Hope2333/oh-my-litecode/discussions
- **文档**: https://github.com/Hope2333/oh-my-litecode/tree/main/docs

---

**维护者**: OML Team
**许可**: MIT License
