#!/usr/bin/env bash
#
# setup-zstd.sh - ZSTD 扩展安装脚本
#
# 该脚本用于安装和配置 ZSTD 压缩库，这是 grep-app-enhanced
# 压缩数据库功能的依赖项.
#
# 用法:
#   ./setup-zstd.sh              # 基本安装
#   ./setup-zstd.sh --check      # 仅检查状态
#   ./setup-zstd.sh --uninstall  # 卸载 ZSTD
#   ./setup-zstd.sh --help       # 显示帮助
#
# 支持的平台:
#   - macOS (Homebrew)
#   - Ubuntu/Debian (apt)
#   - CentOS/RHEL (yum/dnf)
#   - Arch Linux (pacman)
#   - Termux (pkg)
#
# Author: Oh My LiteCode Team
#

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
ZSTD 扩展安装脚本

用法: $(basename "$0") [选项]

选项:
    --check         仅检查 ZSTD 安装状态
    --uninstall     卸载 ZSTD
    --force         强制重新安装
    --help          显示此帮助信息

平台自动检测:
    脚本会自动检测操作系统并选择合适的包管理器

手动安装:
    macOS:    brew install zstd
    Ubuntu:   sudo apt install zstd libzstd-dev
    CentOS:   sudo yum install zstd libzstd-devel
    Arch:     sudo pacman -S zstd
    Termux:   pkg install zstd libzstd
EOF
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "$ID"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    elif command -v pkg &> /dev/null; then
        echo "termux"
    else
        echo "unknown"
    fi
}

# 检测包管理器
detect_package_manager() {
    if command -v apt &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v brew &> /dev/null; then
        echo "brew"
    elif command -v pkg &> /dev/null; then
        echo "pkg"
    else
        echo "unknown"
    fi
}

# 检查 ZSTD 是否已安装
check_zstd() {
    log_info "检查 ZSTD 安装状态..."

    local zstd_installed=false
    local python_zstd_installed=false

    # 检查系统 ZSTD
    if command -v zstd &> /dev/null; then
        zstd_installed=true
        local version
        version=$(zstd --version 2>&1 | head -1)
        log_success "系统 ZSTD 已安装：$version"
    else
        log_warning "系统 ZSTD 未安装"
    fi

    # 检查 Python zstandard 包
    if python3 -c "import zstandard" 2>/dev/null; then
        python_zstd_installed=true
        local py_version
        py_version=$(python3 -c "import zstandard; print(zstandard.ZSTD_VERSION)" 2>/dev/null || echo "unknown")
        log_success "Python zstandard 包已安装：$py_version"
    else
        log_warning "Python zstandard 包未安装"
    fi

    if [[ "$zstd_installed" == "true" ]] && [[ "$python_zstd_installed" == "true" ]]; then
        log_success "ZSTD 已完全安装"
        return 0
    else
        log_info "ZSTD 未完全安装，需要安装缺失的组件"
        return 1
    fi
}

# 安装系统 ZSTD
install_system_zstd() {
    local os
    os=$(detect_os)
    local pm
    pm=$(detect_package_manager)

    log_info "检测到操作系统：$os"
    log_info "检测到包管理器：$pm"

    case "$pm" in
        apt)
            log_info "使用 apt 安装 ZSTD..."
            sudo apt update
            sudo apt install -y zstd libzstd-dev
            ;;
        dnf)
            log_info "使用 dnf 安装 ZSTD..."
            sudo dnf install -y zstd libzstd-devel
            ;;
        yum)
            log_info "使用 yum 安装 ZSTD..."
            sudo yum install -y zstd libzstd-devel
            ;;
        pacman)
            log_info "使用 pacman 安装 ZSTD..."
            sudo pacman -S --noconfirm zstd
            ;;
        brew)
            log_info "使用 brew 安装 ZSTD..."
            brew install zstd
            ;;
        pkg)
            log_info "使用 pkg 安装 ZSTD (Termux)..."
            pkg update
            pkg install -y zstd libzstd
            ;;
        *)
            log_error "不支持的包管理器：$pm"
            log_info "请手动安装 ZSTD:"
            log_info "  https://facebook.github.io/zstd/"
            return 1
            ;;
    esac

    log_success "系统 ZSTD 安装完成"
}

# 安装 Python zstandard 包
install_python_zstd() {
    log_info "安装 Python zstandard 包..."

    # 尝试多种 pip 命令
    local pip_cmd=""
    for cmd in pip3 pip "python3 -m pip" "python -m pip"; do
        if command -v $cmd &> /dev/null 2>&1 || [[ "$cmd" == *"python"* ]]; then
            if $cmd --version &> /dev/null 2>&1; then
                pip_cmd="$cmd"
                break
            fi
        fi
    done

    if [[ -z "$pip_cmd" ]]; then
        log_error "未找到 pip"
        return 1
    fi

    log_info "使用 pip 命令：$pip_cmd"
    $pip_cmd install --upgrade zstandard

    log_success "Python zstandard 包安装完成"
}

# 卸载 ZSTD
uninstall_zstd() {
    local pm
    pm=$(detect_package_manager)

    log_info "卸载 ZSTD..."

    case "$pm" in
        apt)
            sudo apt remove -y zstd libzstd-dev
            ;;
        dnf)
            sudo dnf remove -y zstd libzstd-devel
            ;;
        yum)
            sudo yum remove -y zstd libzstd-devel
            ;;
        pacman)
            sudo pacman -R --noconfirm zstd
            ;;
        brew)
            brew uninstall zstd
            ;;
        pkg)
            pkg uninstall -y zstd libzstd
            ;;
        *)
            log_warning "无法自动卸载，请手动移除"
            ;;
    esac

    # 卸载 Python 包
    if python3 -c "import zstandard" 2>/dev/null; then
        pip3 uninstall -y zstandard 2>/dev/null || true
    fi

    log_success "ZSTD 卸载完成"
}

# 验证安装
verify_installation() {
    log_info "验证安装..."

    # 验证系统 ZSTD
    if command -v zstd &> /dev/null; then
        zstd --version
        log_success "系统 ZSTD 验证通过"
    else
        log_error "系统 ZSTD 验证失败"
        return 1
    fi

    # 验证 Python 包
    if python3 -c "import zstandard; print('zstandard version:', zstandard.__version__)" 2>/dev/null; then
        log_success "Python zstandard 验证通过"
    else
        log_error "Python zstandard 验证失败"
        return 1
    fi

    # 测试压缩功能
    log_info "测试压缩功能..."
    echo "test data" | zstd -1 > /tmp/zstd_test.zst
    zstd -d /tmp/zstd_test.zst -c
    rm -f /tmp/zstd_test.zst
    log_success "压缩功能测试通过"

    return 0
}

# 主函数
main() {
    local action="install"
    local force=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                action="check"
                shift
                ;;
            --uninstall)
                action="uninstall"
                shift
                ;;
            --force)
                force=true
                shift
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

    echo ""
    echo "========================================"
    echo "  ZSTD 扩展安装程序"
    echo "========================================"
    echo ""

    case "$action" in
        check)
            if check_zstd; then
                exit 0
            else
                exit 1
            fi
            ;;
        uninstall)
            uninstall_zstd
            exit 0
            ;;
        install)
            # 检查是否已安装
            if check_zstd && [[ "$force" == "false" ]]; then
                log_success "ZSTD 已安装，无需重复安装"
                exit 0
            fi

            # 安装系统 ZSTD
            if ! command -v zstd &> /dev/null; then
                install_system_zstd
            fi

            # 安装 Python 包
            if ! python3 -c "import zstandard" 2>/dev/null; then
                install_python_zstd
            fi

            # 验证安装
            verify_installation

            echo ""
            log_success "ZSTD 安装完成!"
            echo ""
            echo "现在可以安装 grep-app-enhanced:"
            echo "  pip install -e ."
            echo ""
            ;;
    esac
}

# 运行主函数
main "$@"
