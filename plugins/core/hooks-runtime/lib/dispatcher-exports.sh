#!/usr/bin/env bash
# OML Hooks Runtime - 分发器导出接口
# 为插件提供简化的分发器 API

set -euo pipefail

# 重新导出核心函数（简化命名）
oml_dispatch_hooks() {
    oml_hooks_dispatch "$@"
}

oml_dispatch_single_hook() {
    oml_hooks_dispatch_single "$@"
}

# 插件便捷函数
# 用法：plugin_dispatch <event> [args] [--options]
plugin_dispatch() {
    oml_hooks_dispatch "$@"
}

# 用法：plugin_dispatch_sync <event> [args]
plugin_dispatch_sync() {
    oml_hooks_dispatch "$@" --stop-on-error
}

# 用法：plugin_dispatch_async <event> [args]
plugin_dispatch_async() {
    oml_hooks_dispatch "$@" --parallel --async
}
