#!/usr/bin/env bash
# OML Hooks Runtime - 注册表导出接口
# 为插件提供简化的注册表 API

set -euo pipefail

# 重新导出核心函数（简化命名）
oml_register_hook() {
    oml_hook_register "$@"
}

oml_unregister_hook() {
    oml_hook_unregister "$@"
}

oml_enable_hook() {
    oml_hook_enable "$@"
}

oml_disable_hook() {
    oml_hook_disable "$@"
}

oml_get_hooks() {
    oml_hooks_get_for_event "$@"
}

# 插件便捷函数
# 用法：plugin_register_hook <name> <event> <handler> [priority]
plugin_register_hook() {
    local name="$1"
    local event="$2"
    local handler="$3"
    local priority="${4:-0}"

    oml_hook_register "$name" "$event" "$handler" "$priority"
}

# 用法：plugin_unregister_hook <name>
plugin_unregister_hook() {
    local name="$1"
    oml_hook_unregister "$name"
}

# 用法：plugin_list_hooks [event]
plugin_list_hooks() {
    local event="${1:-}"
    oml_hooks_list "$event" "all" "plain"
}
