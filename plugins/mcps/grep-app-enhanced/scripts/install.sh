#!/usr/bin/env bash
#
# install.sh - Grep App Enhanced 安装脚本
#
# 该脚本用于安装 grep-app-enhanced MCP 服务器及其依赖
#
# 用法:
#   ./install.sh              # 基本安装
#   ./install.sh --dev        # 安装开发依赖
#   ./install.sh --force      # 强制重新安装
#   ./install.sh --help       # 显示帮助
#
# 环境变量:
#   PYTHON          - Python 解释器路径 (默认：python3)
#   PIP             - pip 命令 (默认：pip3)
#   VENV_DIR        - 虚拟环境目录 (默认：.venv)
#   INSTALL_DEV     - 是否安装开发依赖 (默认：false)
#
# Author: Oh My LiteCode Team
#

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 显示帮助
show_help() {
    cat << EOF
Grep App Enhanced 安装脚本

用法: $(basename "$0") [选项]

选项:
    --dev           安装开发依赖 (pytest, mypy, black 等)
    --force         强制重新安装，覆盖现有安装
    --no-venv       不使用虚拟环境，直接安装到系统
    --python PATH   指定 Python 解释器路径
    --help          显示此帮助信息

示例:
    $(basename "$0")                    # 基本安装
    $(basename "$0") --dev              # 安装开发环境
    $(basename "$0") --python python3   # 指定 Python 版本

环境变量:
    PYTHON          Python 解释器路径 (默认：python3)
    PIP             pip 命令 (默认：pip3)
    VENV_DIR        虚拟环境目录 (默认：.venv)
EOF
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."

    local python_cmd="${PYTHON:-python3}"
    local pip_cmd="${PIP:-pip3}"

    if ! command -v "$python_cmd" &> /dev/null; then
        log_error "未找到 Python 3，请安装 Python 3.10 或更高版本"
        exit 1
    fi

    local python_version
    python_version=$("$python_cmd" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    
    if [[ "$python_version" < "3.10" ]]; then
        log_error "Python 版本过低 ($python_version)，需要 Python 3.10 或更高版本"
        exit 1
    fi

    log_success "Python $python_version 已安装"

    if ! command -v "$pip_cmd" &> /dev/null; then
        log_warning "未找到 pip，尝试使用 python -m pip"
        pip_cmd="$python_cmd -m pip"
    fi

    log_success "pip 已准备"
}

# 创建虚拟环境
create_venv() {
    local use_venv="$1"
    local venv_dir="${VENV_DIR:-.venv}"

    if [[ "$use_venv" == "false" ]]; then
        log_info "跳过虚拟环境创建，将安装到系统环境"
        return 0
    fi

    if [[ -d "$venv_dir" ]] && [[ "$FORCE_INSTALL" != "true" ]]; then
        log_info "虚拟环境已存在：$venv_dir"
        return 0
    fi

    if [[ -d "$venv_dir" ]] && [[ "$FORCE_INSTALL" == "true" ]]; then
        log_info "删除现有虚拟环境..."
        rm -rf "$venv_dir"
    fi

    log_info "创建虚拟环境：$venv_dir"
    python3 -m venv "$venv_dir"

    # 激活虚拟环境
    # shellcheck disable=SC1091
    source "$venv_dir/bin/activate"
    log_success "虚拟环境已创建并激活"
}

# 升级 pip
upgrade_pip() {
    log_info "升级 pip..."
    pip install --upgrade pip setuptools wheel > /dev/null 2>&1
    log_success "pip 已升级"
}

# 安装依赖
install_dependencies() {
    local install_dev="$1"

    log_info "安装项目依赖..."

    if [[ "$install_dev" == "true" ]]; then
        pip install -e ".[dev]"
        log_success "项目依赖和开发依赖已安装"
    else
        pip install -e "."
        log_success "项目依赖已安装"
    fi
}

# 检查 gh CLI
check_gh_cli() {
    if command -v gh &> /dev/null; then
        log_success "GitHub CLI (gh) 已安装"
        gh --version | head -1
    else
        log_warning "GitHub CLI (gh) 未安装"
        log_info "如需使用 GitHub 集成功能，请安装 gh CLI:"
        log_info "  macOS:  brew install gh"
        log_info "  Linux:  sudo apt install gh  # 或通过 GitHub  releases 安装"
    fi
}

# 检查 git
check_git() {
    if command -v git &> /dev/null; then
        log_success "Git 已安装"
        git --version
    else
        log_error "Git 未安装，请安装 Git 后重试"
        exit 1
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."

    if python3 -c "import grep_app_enhanced" 2>/dev/null; then
        local version
        version=$(python3 -c "from grep_app_enhanced import __version__; print(__version__)")
        log_success "grep-app-enhanced v$version 安装成功"
    else
        log_error "安装验证失败"
        exit 1
    fi

    # 检查 MCP 服务器
    if python3 -c "from grep_app_enhanced.mcp_server import main" 2>/dev/null; then
        log_success "MCP 服务器模块可用"
    else
        log_warning "MCP 服务器模块可能有问题"
    fi
}

# 显示安装后信息
show_post_install() {
    echo ""
    log_success "安装完成!"
    echo ""
    echo "使用方法:"
    echo "  1. 激活虚拟环境 (如果使用了虚拟环境):"
    echo "     source .venv/bin/activate"
    echo ""
    echo "  2. 运行 MCP 服务器:"
    echo "     grep-app-enhanced"
    echo ""
    echo "  3. 或者使用 Python 直接运行:"
    echo "     python -m grep_app_enhanced.mcp_server"
    echo ""
    echo "配置选项 (环境变量):"
    echo "  GREP_APP_CACHE_DIR   - 缓存目录"
    echo "  GREP_APP_DB_PATH     - 数据库路径"
    echo "  GITHUB_TOKEN         - GitHub API Token"
    echo "  GREP_APP_MAX_WORKERS - 最大工作线程数"
    echo ""

    if ! command -v gh &> /dev/null; then
        echo "提示：安装 GitHub CLI 以启用完整的 GitHub 集成功能"
        echo "  https://cli.github.com/"
        echo ""
    fi
}

# 主函数
main() {
    local install_dev="${INSTALL_DEV:-false}"
    local use_venv="true"
    local python_path=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dev)
                install_dev="true"
                shift
                ;;
            --force)
                FORCE_INSTALL="true"
                shift
                ;;
            --no-venv)
                use_venv="false"
                shift
                ;;
            --python)
                python_path="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项：$1"
                show_help
                exit 1
                ;;
        esac
    done

    # 设置 Python 路径
    if [[ -n "$python_path" ]]; then
        export PYTHON="$python_path"
    fi

    echo ""
    echo "========================================"
    echo "  Grep App Enhanced 安装程序"
    echo "========================================"
    echo ""

    # 执行安装步骤
    check_dependencies
    check_git
    create_venv "$use_venv"
    upgrade_pip
    install_dependencies "$install_dev"
    check_gh_cli
    verify_installation
    show_post_install
}

# 运行主函数
main "$@"
