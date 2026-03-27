#!/usr/bin/env bash
# OML Hooks Runtime - 事件总线导出接口
# 为插件提供简化的事件总线 API

set -euo pipefail

# 重新导出核心函数（简化命名）
oml_emit_event() {
    oml_event_emit "$@"
}

oml_on_event() {
    oml_event_on "$@"
}

oml_once_event() {
    oml_event_once "$@"
}

oml_off_event() {
    oml_event_off "$@"
}

# 插件便捷函数
# 用法：plugin_emit <plugin_name> <event_type> [payload]
plugin_emit() {
    local plugin_name="$1"
    local event_type="$2"
    shift 2 || true

    oml_event_emit "plugin:${plugin_name}:${event_type}" "$@"
}

# 用法：plugin_on <plugin_name> <event_type> <handler>
plugin_on() {
    local plugin_name="$1"
    local event_type="$2"
    local handler="$3"

    oml_event_on "plugin:${plugin_name}:${event_type}" "$handler"
}
