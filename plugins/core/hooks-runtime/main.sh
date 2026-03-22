#!/usr/bin/env bash
# OML Hooks Runtime Plugin - 主入口
# 提供 Hooks 运行时的 CLI 接口

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && cd .. && pwd)"
CORE_DIR="${PLUGIN_DIR}/../../core"

# 源核心模块
for module in platform event-bus hooks-registry hooks-dispatcher hooks-engine; do
    if [[ -f "${CORE_DIR}/${module}.sh" ]]; then
        source "${CORE_DIR}/${module}.sh"
    fi
done

# ============================================================================
# 插件命令
# ============================================================================

# 初始化运行时
cmd_init() {
    local force="${1:-false}"

    echo "Initializing Hooks Runtime..."

    if [[ "$force" == "--force" || "$force" == "-f" ]]; then
        echo "Force re-initialization..."
        rm -rf "${HOME}/.oml/hooks" 2>/dev/null || true
    fi

    oml_hooks_engine_init

    echo ""
    echo "Hooks Runtime initialized successfully!"
    echo ""
    echo "Quick start:"
    echo "  oml hooks add pre build:start /path/to/hook.sh"
    echo "  oml hooks trigger build:start"
    echo "  oml hooks status"
}

# 列出 Hooks
cmd_list() {
    local event_filter="${1:-}"
    local status_filter="${2:-all}"
    local format="${3:-plain}"

    echo "Registered Hooks:"
    echo ""
    oml_hooks_list "$event_filter" "$status_filter" "$format"
}

# 触发事件
cmd_trigger() {
    local event="$1"
    shift || true

    echo "Triggering event: $event"
    echo ""

    oml_hook_trigger "$event" "$@"
    local result=$?

    echo ""
    if [[ $result -eq 0 ]]; then
        echo "Event triggered successfully"
    else
        echo "Event triggered with errors (exit code: $result)"
    fi

    return $result
}

# 注册 Hook
cmd_register() {
    local hook_type="${1:-pre}"
    local target="$2"
    local handler="$3"
    local priority="${4:-0}"

    if [[ -z "$target" || -z "$handler" ]]; then
        echo "Usage: oml hooks-runtime register <type> <target> <handler> [priority]"
        echo ""
        echo "Types: pre, post, around"
        echo "Example: oml hooks-runtime register pre build:start /path/to/hook.sh 10"
        return 1
    fi

    oml_hook_add "$hook_type" "$target" "$handler" "$priority"
}

# 显示状态
cmd_status() {
    echo "=== Hooks Runtime Status ==="
    echo ""

    echo "Engine Status:"
    oml_hooks_engine_status
    echo ""

    echo "Registry Stats:"
    oml_hooks_registry_stats
    echo ""

    echo "Dispatcher Status:"
    oml_hooks_dispatcher_status
}

# 运行示例
cmd_example() {
    local example="${1:-basic}"

    case "$example" in
        basic)
            cat <<'EOF'
# 基本使用示例

# 1. 初始化
oml hooks-runtime init

# 2. 注册 Pre-hook
oml hooks-runtime register pre build:start ./examples/pre-build.sh 10

# 3. 注册 Post-hook
oml hooks-runtime register post build:complete ./examples/post-build.sh 5

# 4. 触发事件
oml hooks-runtime trigger build:start

# 5. 查看状态
oml hooks-runtime status
EOF
            ;;
        advanced)
            cat <<'EOF'
# 高级使用示例

# 1. 带超时的触发
oml hooks-runtime trigger build:start --timeout 60

# 2. 遇到错误立即停止
oml hooks-runtime trigger deploy:start --stop-on-error

# 3. 并行执行所有 Hooks
oml hooks-runtime trigger test:run --parallel

# 4. 非阻塞模式
oml hooks-runtime trigger async:event --async

# 5. Around Hook 执行
oml hooks around-exec git:commit git commit -m "message"

# 6. 批量注册
cat > hooks-config.json <<'JSON'
{
  "hooks": [
    {"name": "pre-build", "event": "build:pre", "handler": "/path/to/pre.sh", "priority": 10},
    {"name": "post-build", "event": "build:post", "handler": "/path/to/post.sh", "priority": 5}
  ]
}
JSON
oml hooks batch-register hooks-config.json
EOF
            ;;
        plugin)
            cat <<'EOF'
# 插件集成示例

# 在插件中集成 Hooks

# 1. 在 plugin.json 中声明 hooks
{
  "hooks": {
    "post_install": "scripts/post-install.sh",
    "pre_uninstall": "scripts/pre-uninstall.sh"
  }
}

# 2. 在 main.sh 中触发事件
source /path/to/core/hooks-engine.sh

plugin_install() {
    oml_hook_trigger "plugin:install" "$PLUGIN_NAME"
    # ... 安装逻辑
    oml_hook_trigger "plugin:installed" "$PLUGIN_NAME"
}

# 3. 用户可以注册自定义 Hook
oml hooks add pre plugin:install ./backup-config.sh
oml hooks add post plugin:installed ./notify-success.sh
EOF
            ;;
        *)
            echo "Unknown example: $example"
            echo "Available: basic, advanced, plugin"
            return 1
            ;;
    esac
}

# 帮助信息
cmd_help() {
    cat <<EOF
OML Hooks Runtime Plugin (v0.1.0)

用法：oml hooks-runtime <command> [args]

命令:
  init [-f|--force]           初始化运行时
  list [event] [status] [fmt] 列出 Hooks
  trigger <event> [args]      触发事件
  register <type> <target> <handler> [priority]
                              注册 Hook
  status                      显示运行时状态
  example [name]              显示使用示例
  help                        显示帮助

事件类型:
  pre     - 在目标操作之前执行
  post    - 在目标操作之后执行
  around  - 包围目标操作（pre + post）

触发选项:
  --timeout <seconds>    超时时间（默认：30s）
  --stop-on-error        遇到错误立即停止
  --parallel             并行执行所有 Hooks
  --async                非阻塞模式

示例:
  oml hooks-runtime init
  oml hooks-runtime register pre build:start ./hook.sh 10
  oml hooks-runtime trigger build:start --timeout 60
  oml hooks-runtime list build enabled
  oml hooks-runtime status
  oml hooks-runtime example advanced
EOF
}

# ============================================================================
# 主入口
# ============================================================================
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        init)
            cmd_init "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        trigger)
            cmd_trigger "$@"
            ;;
        register)
            cmd_register "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        example)
            cmd_example "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Use 'oml hooks-runtime help' for usage"
            return 1
            ;;
    esac
}

# 仅当直接执行时运行 main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
