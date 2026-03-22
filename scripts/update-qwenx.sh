#!/data/data/com.termux/files/usr/bin/bash
#
# qwenx 更新到 OML 插件系统
#
# 使用方法：
#   bash update-qwenx-to-oml.sh
#
# 此脚本将：
# 1. 备份现有配置
# 2. 更新 qwenx 命令到 OML 系统
# 3. 迁移配置和密钥
# 4. 验证更新成功
#

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 路径定义
OML_ROOT="${OML_ROOT:-$HOME/develop/oh-my-litecode}"
QWENX_FAKE_HOME="$HOME/.local/home/qwenx"
QWENX_BACKUP="$HOME/.local/home/qwenx.backup.$(date +%Y%m%d_%H%M%S)"
USR_BIN="/data/data/com.termux/files/usr/bin"

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

# 检查 OML 是否存在
check_oml_installed() {
    if [[ ! -d "$OML_ROOT" ]]; then
        log_error "OML 未安装：$OML_ROOT"
        log_info "请先安装 OML:"
        echo "  git clone https://github.com/your-org/oh-my-litecode.git $OML_ROOT"
        exit 1
    fi
    
    if [[ ! -f "$OML_ROOT/oml" ]]; then
        log_error "OML 主文件不存在"
        exit 1
    fi
    
    log_success "OML 已安装：$OML_ROOT"
}

# 备份现有配置
backup_qwenx() {
    log_info "备份现有 qwenx 配置..."
    
    if [[ -d "$QWENX_FAKE_HOME" ]]; then
        cp -r "$QWENX_FAKE_HOME" "$QWENX_BACKUP"
        log_success "配置已备份到：$QWENX_BACKUP"
    else
        log_warning "qwenx 配置目录不存在：$QWENX_FAKE_HOME"
    fi
    
    # 备份 /usr/bin/qwenx
    if [[ -f "$USR_BIN/qwenx" ]]; then
        cp "$USR_BIN/qwenx" "$USR_BIN/qwenx.backup.$(date +%Y%m%d_%H%M%S)"
        log_success "qwenx 命令已备份"
    fi
}

# 迁移配置
migrate_config() {
    log_info "迁移配置到 OML 系统..."
    
    # 创建 OML 配置目录
    mkdir -p "$HOME/.oml"
    mkdir -p "$QWENX_FAKE_HOME/.qwen"
    mkdir -p "$QWENX_FAKE_HOME/.qwenx/secrets"
    
    # 迁移 settings.json (如果存在)
    local settings_file="$QWENX_FAKE_HOME/.qwen/settings.json"
    if [[ -f "$settings_file" ]]; then
        log_info "保留现有 settings.json"
    else
        # 创建默认配置
        cat > "$settings_file" << 'EOF'
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
        log_success "创建默认 settings.json"
    fi
    
    # 迁移 Context7 密钥 (如果存在)
    local ctx7_keys="$QWENX_FAKE_HOME/.qwenx/secrets/context7.keys"
    if [[ -f "$ctx7_keys" ]]; then
        log_info "保留现有 Context7 密钥"
    else
        log_success "Context7 密钥目录已准备"
    fi
    
    # 设置权限
    chmod 700 "$QWENX_FAKE_HOME/.qwenx/secrets" 2>/dev/null || true
    chmod 600 "$ctx7_keys" 2>/dev/null || true
    
    log_success "配置迁移完成"
}

# 更新 qwenx 命令
update_qwenx_command() {
    log_info "更新 qwenx 命令到 OML 系统..."
    
    # 创建新的 qwenx 包装脚本
    cat > "$USR_BIN/qwenx" << 'QWENX_WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
#
# qwenx - OML Qwen Agent 包装器
# 此脚本将 qwenx 命令重定向到 OML 系统
#

set -euo pipefail

# OML 根目录
OML_ROOT="${OML_ROOT:-$HOME/develop/oh-my-litecode}"

# Fake HOME 设置
export _REALHOME="${HOME}"
export REALHOME="${HOME}"
export _FAKEHOME="${HOME}/.local/home/qwenx"
export HOME="${_FAKEHOME}"

# 环境变量
export QWEN_API_KEY="${QWEN_API_KEY:-}"
export QWEN_BASE_URL="${QWEN_BASE_URL:-}"
export CONTEXT7_API_KEY="${CONTEXT7_API_KEY:-}"

# 检查 OML 是否存在
if [[ ! -f "${OML_ROOT}/oml" ]]; then
    echo "Error: OML not found at ${OML_ROOT}" >&2
    echo "Please install OML or set OML_ROOT environment variable" >&2
    exit 1
fi

# 主函数
main() {
    # 特殊命令处理
    case "${1:-}" in
        --oml-help)
            "${OML_ROOT}/oml" --help
            return 0
            ;;
        --oml-version)
            "${OML_ROOT}/oml" version
            return 0
            ;;
        --migrate)
            echo "Migration is now handled automatically"
            return 0
            ;;
    esac
    
    # 默认：调用 OML qwen 插件
    exec "${OML_ROOT}/oml" qwen "$@"
}

main "$@"
QWENX_WRAPPER

    # 设置可执行权限
    chmod +x "$USR_BIN/qwenx"
    
    log_success "qwenx 命令已更新"
}

# 启用 OML 插件
enable_oml_plugins() {
    log_info "启用 OML 插件..."
    
    # 确保插件目录存在
    if [[ -d "$OML_ROOT/plugins/agents/qwen" ]]; then
        log_success "Qwen Agent 插件已安装"
    else
        log_warning "Qwen Agent 插件未找到"
    fi
    
    # 初始化 Task Registry
    if [[ -f "$OML_ROOT/core/task-registry.sh" ]]; then
        source "$OML_ROOT/core/task-registry.sh"
        oml_task_registry_init 2>/dev/null || true
        log_success "Task Registry 已初始化"
    fi
    
    # 初始化 Session 管理
    if [[ -f "$OML_ROOT/core/session-manager.sh" ]]; then
        log_success "Session Manager 已安装"
    fi
    
    # 初始化 Hooks 引擎
    if [[ -f "$OML_ROOT/core/hooks-engine.sh" ]]; then
        log_success "Hooks Engine 已安装"
    fi
}

# 验证更新
verify_update() {
    log_info "验证更新..."
    
    # 测试 qwenx 命令
    if qwenx --help >/dev/null 2>&1; then
        log_success "qwenx 命令工作正常"
    else
        log_error "qwenx 命令测试失败"
        return 1
    fi
    
    # 测试 OML 命令
    if "$OML_ROOT/oml" --help >/dev/null 2>&1; then
        log_success "OML 命令工作正常"
    else
        log_error "OML 命令测试失败"
        return 1
    fi
    
    # 测试平台检测
    local platform
    platform=$("$OML_ROOT/oml" platform detect 2>/dev/null) || true
    if [[ -n "$platform" ]]; then
        log_success "平台检测正常：$platform"
    fi
    
    # 测试插件列表
    local plugin_count
    plugin_count=$("$OML_ROOT/oml" plugins list 2>/dev/null | wc -l) || true
    if [[ "$plugin_count" -gt 0 ]]; then
        log_success "插件系统正常：$plugin_count 个插件"
    fi
    
    log_success "验证完成"
}

# 显示更新后信息
show_post_update_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  qwenx 已更新到 OML 系统！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "📍 安装信息:"
    echo "   OML 目录：$OML_ROOT"
    echo "   qwenx 命令：$USR_BIN/qwenx"
    echo "   配置目录：$QWENX_FAKE_HOME"
    echo "   备份位置：$QWENX_BACKUP"
    echo ""
    echo "🚀 快速开始:"
    echo ""
    echo "  1. 测试 qwenx:"
    echo -e "     ${BLUE}qwenx \"你好\"${NC}"
    echo ""
    echo "  2. 查看 OML 帮助:"
    echo -e "     ${BLUE}qwenx --oml-help${NC}"
    echo -e "     ${BLUE}oml --help${NC}"
    echo ""
    echo "  3. 查看版本:"
    echo -e "     ${BLUE}qwenx --oml-version${NC}"
    echo ""
    echo "  4. 管理插件:"
    echo -e "     ${BLUE}oml plugins list${NC}"
    echo -e "     ${BLUE}oml plugins info qwen${NC}"
    echo ""
    echo "  5. Context7 密钥管理:"
    echo -e "     ${BLUE}oml qwen ctx7 list${NC}"
    echo -e "     ${BLUE}oml qwen ctx7 set \"key@alias\"${NC}"
    echo ""
    echo "📚 文档:"
    echo "   - 快速开始：cat $OML_ROOT/QUICKSTART.md"
    echo "   - 完整文档：cat $OML_ROOT/README-OML.md"
    echo "   - Arch 部署：cat $OML_ROOT/README-ARCH-QWENX.md"
    echo ""
    echo "🔧 新功能:"
    echo "   - Session 管理：oml session <command>"
    echo "   - Worker 池：oml worker <command>"
    echo "   - Hooks 系统：oml hooks <command>"
    echo "   - 插件系统：oml plugins <command>"
    echo ""
    echo -e "${GREEN}========================================${NC}"
}

# 主函数
main() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  qwenx 更新到 OML 系统${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    check_oml_installed
    backup_qwenx
    migrate_config
    update_qwenx_command
    enable_oml_plugins
    verify_update
    show_post_update_info
}

# 运行主函数
main "$@"
