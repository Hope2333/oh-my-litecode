#!/usr/bin/env bash
# 示例：Plugin Install Hook
# 在插件安装时执行

set -euo pipefail

echo "[HOOK] Plugin install hook starting..."

# 验证插件元数据
validate_plugin() {
    local plugin_dir="${1:-}"

    if [[ -z "$plugin_dir" ]]; then
        echo "[HOOK] ERROR: Plugin directory not specified"
        return 1
    fi

    if [[ ! -f "${plugin_dir}/plugin.json" ]]; then
        echo "[HOOK] ERROR: plugin.json not found in $plugin_dir"
        return 1
    fi

    echo "[HOOK] Plugin metadata validated"
    return 0
}

# 创建插件配置
setup_config() {
    local plugin_name="${1:-unknown}"
    local config_dir="${HOME}/.oml/plugins/${plugin_name}"

    mkdir -p "$config_dir"

    local config_file="${config_dir}/config.json"
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" <<EOF
{
  "enabled": true,
  "settings": {}
}
EOF
        echo "[HOOK] Config created for plugin: $plugin_name"
    fi
}

# 主逻辑
main() {
    local plugin_name="${1:-unknown}"
    local plugin_dir="${2:-}"

    echo "[HOOK] Installing plugin: $plugin_name"

    validate_plugin "$plugin_dir" || exit 1
    setup_config "$plugin_name"

    echo "[HOOK] Plugin install hook completed"
}

main "$@"
