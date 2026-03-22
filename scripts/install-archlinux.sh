#!/usr/bin/env bash
#
# OML (Oh-My-Litecode) Arch Linux 安装脚本
# 支持：Arch Linux / Manjaro / EndeavourOS
#
# 使用方法：
#   curl -fsSL https://raw.githubusercontent.com/your-org/oh-my-litecode/main/scripts/install-archlinux.sh | bash
#
# 或手动安装：
#   bash install-archlinux.sh
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
        log_info "检测到 Arch Linux"
    elif [[ -f /etc/manjaro-release ]]; then
        SYSTEM="manjaro"
        log_info "检测到 Manjaro"
    elif [[ -f /etc/endeavouros-release ]]; then
        SYSTEM="endeavouros"
        log_info "检测到 EndeavourOS"
    else
        log_error "不支持的系统，仅支持 Arch Linux / Manjaro / EndeavourOS"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    log_info "更新系统..."
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
        wget

    log_success "依赖安装完成"
}

# 创建用户（如果需要）
create_user_if_needed() {
    if ! id -u qwen >/dev/null 2>&1; then
        log_info "创建 qwen 用户..."
        useradd -m -s /bin/bash qwen
        log_success "qwen 用户创建完成"
    else
        log_info "qwen 用户已存在"
    fi
}

# 克隆仓库
clone_repository() {
    local target_dir="${1:-/home/qwen/develop/oh-my-litecode}"
    
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
    git clone https://github.com/your-org/oh-my-litecode.git "$target_dir"
    log_success "仓库克隆完成"
    
    # 设置权限
    chown -R qwen:qwen "$(dirname "$target_dir")"
}

# 配置环境变量
setup_environment() {
    log_info "配置环境变量..."
    
    cat >> /home/qwen/.bashrc << 'EOF'

# OML (Oh-My-Litecode) 配置
export OML_HOME="$HOME/.oml"
export OML_BIN="$OML_HOME/bin"
export PATH="$HOME/develop/oh-my-litecode:$OML_BIN:$PATH"

# Qwen API 配置（请替换为实际密钥）
# export QWEN_API_KEY="sk-your-api-key"
# export QWEN_BASE_URL="https://api.example.com/v1"
EOF

    chown qwen:qwen /home/qwen/.bashrc
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
    log_info "配置 qwenx..."
    
    # 创建配置目录
    mkdir -p /home/qwen/.local/home/qwenx/.qwen
    mkdir -p /home/qwen/.local/home/qwenx/.qwenx/secrets
    
    # 创建默认配置
    cat > /home/qwen/.local/home/qwenx/.qwen/settings.json << 'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "protocol": "mcp",
      "enabled": true,
      "trust": false
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
    chown -R qwen:qwen /home/qwen/.local
    
    log_success "qwenx 配置完成"
}

# 运行健康检查
run_healthcheck() {
    log_info "运行健康检查..."
    
    su - qwen -c "
        cd ~/develop/oh-my-litecode
        ./oml platform doctor
    "
    
    log_success "健康检查完成"
}

# 显示完成信息
show_completion_message() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  OML/qwenx 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "📍 安装位置：/home/qwen/develop/oh-my-litecode"
    echo "🔧 命令位置：/usr/local/bin/oml, /usr/local/bin/qwenx"
    echo ""
    echo "🚀 快速开始："
    echo ""
    echo "  1. 切换到 qwen 用户："
    echo -e "     ${BLUE}su - qwen${NC}"
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
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

# 主函数
main() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  OML (Oh-My-Litecode) 安装脚本${NC}"
    echo -e "${BLUE}  Arch Linux / Manjaro / EndeavourOS${NC}"
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
    run_healthcheck
    show_completion_message
}

# 运行主函数
main "$@"
