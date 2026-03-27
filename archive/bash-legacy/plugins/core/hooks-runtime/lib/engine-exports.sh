#!/usr/bin/env bash
# OML Hooks Runtime - 引擎导出接口
# 为插件提供简化的引擎 API

set -euo pipefail

# 重新导出核心函数（简化命名）
oml_init_hooks() {
    oml_hooks_engine_init "$@"
}

oml_add_hook() {
    oml_hook_add "$@"
}

oml_remove_hook() {
    oml_hook_remove "$@"
}

oml_trigger_hooks() {
    oml_hook_trigger "$@"
}

oml_hooks_status() {
    oml_hooks_engine_status "$@"
}

# 插件便捷函数
# 用法：plugin_hook_pre <target> <handler> [priority]
plugin_hook_pre() {
    local target="$1"
    local handler="$2"
    local priority="${3:-0}"
    oml_hook_add "pre" "$target" "$handler" "$priority"
}

# 用法：plugin_hook_post <target> <handler> [priority]
plugin_hook_post() {
    local target="$1"
    local handler="$2"
    local priority="${3:-0}"
    oml_hook_add "post" "$target" "$handler" "$priority"
}

# 用法：plugin_trigger <target> [args]
plugin_trigger() {
    local target="$1"
    shift || true
    oml_hook_trigger "$target" "$@"
}

# 用法：plugin_trigger_pre <target> [args]
plugin_trigger_pre() {
    local target="$1"
    shift || true
    oml_hooks_dispatch "${target}:pre" "$@"
}

# 用法：plugin_trigger_post <target> [args]
plugin_trigger_post() {
    local target="$1"
    shift || true
    oml_hooks_dispatch "${target}:post" "$@"
}
