#!/usr/bin/env bash
#
# OML (Oh-My-Litecode) GNU/Linux 通用安装脚本
# 支持：Arch Linux, Debian, Ubuntu, Fedora, openSUSE, Manjaro, EndeavourOS 等
#
# 使用方法：
#   curl -fsSL https://raw.githubusercontent.com/Hope2333/oh-my-litecode/main/scripts/install-gnulinux.sh | bash
#
# 或手动安装：
#   bash install-gnulinux.sh
#

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warning "建议以 root 用户运行此脚本 (sudo)"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 检测系统
detect_system() {
    if [[ -f /etc/arch-release ]]; then
        SYSTEM="arch"
        PKGMGR="pacman"
        log_info "检测到 Arch Linux"
    elif [[ -f /etc/manjaro-release ]]; then
        SYSTEM="manjaro"
        PKGMGR="pacman"
        log_info "检测到 Manjaro"
    elif [[ -f /etc/endeavouros-release ]]; then
        SYSTEM="endeavouros"
        PKGMGR="pacman"
        log_info "检测到 EndeavourOS"
    elif [[ -f /etc/debian_version ]]; then
        SYSTEM="debian"
        PKGMGR="apt"
        log_info "检测到 Debian/Ubuntu"
    elif [[ -f /etc/ubuntu-release ]]; then
        SYSTEM="ubuntu"
        PKGMGR="apt"
        log_info "检测到 Ubuntu"
    elif [[ -f /etc/linuxmint-release ]]; then
        SYSTEM="linuxmint"
        PKGMGR="apt"
        log_info "检测到 Linux Mint"
    elif [[ -f /etc/fedora-release ]]; then
        SYSTEM="fedora"
        PKGMGR="dnf"
        log_info "检测到 Fedora"
    elif [[ -f /etc/redhat-release ]]; then
        SYSTEM="rhel"
        if command -v dnf >/dev/null 2>&1; then
            PKGMGR="dnf"
        else
            PKGMGR="yum"
        fi
        log_info "检测到 RHEL/CentOS"
    elif [[ -f /etc/os-release ]]; then
        # 通过 os-release 检测
        source /etc/os-release
        case "$ID" in
            arch|manjaro|endeavouros)
                SYSTEM="$ID"
                PKGMGR="pacman"
                log_info "检测到 Arch-based: $ID"
                ;;
            debian|ubuntu|linuxmint|pop)
                SYSTEM="$ID"
                PKGMGR="apt"
                log_info "检测到 Debian-based: $ID"
                ;;
            fedora|rhel|centos|opensuse-leap|opensuse-tumbleweed)
                SYSTEM="$ID"
                if [[ "$ID" == "fedora" ]]; then
                    PKGMGR="dnf"
                elif command -v dnf >/dev/null 2>&1; then
                    PKGMGR="dnf"
                else
                    PKGMGR="yum"
                fi
                log_info "检测到 RHEL-based: $ID"
                ;;
            *)
                SYSTEM="unknown"
                PKGMGR="unknown"
                log_warning "未知系统：$ID，尝试使用通用安装"
                ;;
        esac
    else
        SYSTEM="unknown"
        PKGMGR="unknown"
        log_warning "无法检测系统类型，尝试使用通用安装"
    fi
}

# 安装依赖
install_dependencies() {
    log_info "更新系统..."
    
    case "$PKGMGR" in
        pacman)
            pacman -Syu --noconfirm
            log_info "安装基础依赖..."
            pacman -S --noconfirm \
                git \
                bash \
                nodejs \
                npm \
                python \
                python-pip \
                jq \
                curl \
                wget \
                zstd
            ;;
        apt)
            apt-get update
            apt-get upgrade -y
            log_info "安装基础依赖..."
            apt-get install -y \
                git \
                bash \
                nodejs \
                npm \
                python3 \
                python3-pip \
                jq \
                curl \
                wget \
                zstd
            ;;
        dnf)
            dnf upgrade -y
            log_info "安装基础依赖..."
            dnf install -y \
                git \
                bash \
                nodejs \
                npm \
                python3 \
                python3-pip \
                jq \
                curl \
                wget \
                zstd
            ;;
        yum)
            yum upgrade -y
            log_info "安装基础依赖..."
            yum install -y \
                git \
                bash \
                nodejs \
                npm \
                python3 \
                python3-pip \
                jq \
                curl \
                wget \
                zstd
            ;;
        *)
            log_warning "未知包管理器，请手动安装依赖：git, bash, nodejs, npm, python3, jq, curl, wget"
            return 1
            ;;
    esac

    log_success "依赖安装完成"
}

# 创建用户（如果需要）
create_user_if_needed() {
    if [[ -n "${OML_USER:-}" ]]; then
        local username="$OML_USER"
    else
        local username="qwen"
    fi

    if ! id -u "$username" >/dev/null 2>&1; then
        log_info "创建 $username 用户..."
        useradd -m -s /bin/bash "$username"
        log_success "$username 用户创建完成"
    else
        log_info "$username 用户已存在"
    fi
}

# 克隆仓库
clone_repository() {
    local target_dir="${1:-/home/qwen/develop/oh-my-litecode}"
    local repo_url="${OML_REPO:-https://github.com/Hope2333/oh-my-litecode.git}"

    if [[ -d "$target_dir" ]]; then
        log_warning "目录已存在：$target_dir"
        read -p "是否删除并重新克隆？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$target_dir"
        else
            log_info "使用现有目录"
            return
        fi
    fi

    log_info "克隆 OML 仓库到 $target_dir..."
    mkdir -p "$(dirname "$target_dir")"
    git clone "$repo_url" "$target_dir"
    log_success "仓库克隆完成"
}

# 配置环境变量
setup_environment() {
    local username="${OML_USER:-qwen}"
    local home_dir="/home/$username"
    
    log_info "配置环境变量..."

    cat >> "$home_dir/.bashrc" << 'EOF'

# OML (Oh-My-Litecode) 配置
export OML_HOME="$HOME/.oml"
export OML_BIN="$OML_HOME/bin"
export PATH="$HOME/develop/oh-my-litecode:$OML_BIN:$PATH"

# Qwen API 配置（请替换为实际密钥）
# export QWEN_API_KEY="sk-your-api-key"
# export QWEN_BASE_URL="https://api.example.com/v1"

# Context7 API 配置（可选）
# export CONTEXT7_API_KEY="ctx7sk-your-key"
EOF

    chown "$username:$username" "$home_dir/.bashrc"
    log_success "环境变量配置完成"
}

# 安装 qwenx
install_qwenx() {
    log_info "安装 qwenx..."

    # 创建符号链接
    ln -sf /home/qwen/develop/oh-my-litecode/oml /usr/local/bin/oml
    ln -sf /home/qwen/develop/oh-my-litecode/oml /usr/local/bin/qwenx

    log_success "qwenx 安装完成"
}

# 配置 qwenx
configure_qwenx() {
    local username="${OML_USER:-qwen}"
    local home_dir="/home/$username"
    
    log_info "配置 qwenx..."

    # 创建配置目录
    mkdir -p "$home_dir/.local/home/qwenx/.qwen"
    mkdir -p "$home_dir/.local/home/qwenx/.qwenx/secrets"

    # 创建默认配置
    cat > "$home_dir/.local/home/qwenx/.qwen/settings.json" << 'EOF'
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
      "enabled": true,
      "trust": false,
      "excludeTools": []
    },
    "grep-app": {
      "command": "bash",
      "args": ["/home/qwen/develop/oh-my-litecode/plugins/mcps/grep-app/main.sh", "mcp-stdio"],
      "protocol": "mcp",
      "enabled": true,
      "trust": false,
      "excludeTools": []
    },
    "websearch": {
      "command": "bash",
      "args": ["/home/qwen/develop/oh-my-litecode/plugins/mcps/websearch/main.sh", "mcp-stdio"],
      "protocol": "mcp",
      "enabled": true,
      "trust": false,
      "excludeTools": []
    }
  },
  "modelProviders": {
    "openai": []
  },
  "model": {
    "id": "default",
    "name": "Default Model"
  }
}
EOF

    # 设置权限
    chown -R "$username:$username" "$home_dir/.local"

    log_success "qwenx 配置完成"
}

# 安装 system skills
install_system_skills() {
    local username="${OML_USER:-qwen}"
    local home_dir="/home/$username"
    local oml_dir="$home_dir/develop/oh-my-litecode"
    
    log_info "安装 System Skills..."

    # 创建 skills 目录
    mkdir -p /usr/lib/opencode/system-skills
    mkdir -p /usr/share/opencode

    # 复制 skill manifests
    if [[ -d "$oml_dir/../opencode-termux/packaging/manifests/system-skills" ]]; then
        cp "$oml_dir/../opencode-termux/packaging/manifests/system-skills"/*.json /usr/lib/opencode/system-skills/
        cp "$oml_dir/../opencode-termux/packaging/manifests/system-skills/blocklist.json" /usr/share/opencode/system-skills-registry.json
        log_success "System Skills 安装完成"
    else
        log_warning "opencode-termux 未找到，跳过 System Skills 安装"
    fi
}

# 运行健康检查
run_healthcheck() {
    local username="${OML_USER:-qwen}"
    
    log_info "运行健康检查..."

    su - "$username" -c "
        cd ~/develop/oh-my-litecode
        ./oml platform doctor
    "

    log_success "健康检查完成"
}

# 显示完成信息
show_completion_message() {
    local username="${OML_USER:-qwen}"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  OML/qwenx 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "📍 安装位置：/home/$username/develop/oh-my-litecode"
    echo "🔧 命令位置：/usr/local/bin/oml, /usr/local/bin/qwenx"
    echo ""
    echo "🚀 快速开始："
    echo ""
    echo "  1. 切换到 $username 用户："
    echo -e "     ${BLUE}su - $username${NC}"
    echo ""
    echo "  2. 验证安装："
    echo -e "     ${BLUE}oml --help${NC}"
    echo -e "     ${BLUE}qwenx --help${NC}"
    echo ""
    echo "  3. 配置 API 密钥（可选）："
    echo -e "     ${BLUE}export QWEN_API_KEY=\"sk-your-key\"${NC}"
    echo -e "     ${BLUE}oml qwen ctx7 set \"your-key@alias\"${NC}"
    echo ""
    echo "  4. 开始使用："
    echo -e "     ${BLUE}qwenx \"你好，请帮我写一个 Python 函数\"${NC}"
    echo ""
    echo "📚 文档："
    echo "   - 快速开始：cat ~/develop/oh-my-litecode/QUICKSTART.md"
    echo "   - 完整文档：cat ~/develop/oh-my-litecode/README-OML.md"
    echo "   - 平台指南：cat ~/develop/oh-my-litecode/docs/oml/DEPLOYMENT-GUIDE.md"
    echo ""
    echo "🔧 已安装组件："
    echo "   - OML Core v0.1.0-alpha"
    echo "   - qwenx Agent (qwenx compatibility layer)"
    echo "   - MCP Services: context7, grep-app, websearch"
    echo "   - System Skills (opencode-termux)"
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

# 主函数
main() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  OML (Oh-My-Litecode) 安装脚本${NC}"
    echo -e "${BLUE}  GNU/Linux 通用版${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_root
    detect_system
    install_dependencies
    create_user_if_needed
    clone_repository
    setup_environment
    install_qwenx
    configure_qwenx
    install_system_skills
    run_healthcheck
    show_completion_message
}

# 运行主函数
main "$@"
