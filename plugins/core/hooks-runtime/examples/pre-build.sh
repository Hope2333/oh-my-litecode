#!/usr/bin/env bash
# 示例：Build Pre-hook
# 在构建开始前执行

set -euo pipefail

echo "[HOOK] Pre-build check starting..."

# 检查必要依赖
check_dependencies() {
    local deps=("git" "make")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[HOOK] ERROR: Missing dependencies: ${missing[*]}"
        return 1
    fi

    echo "[HOOK] Dependencies check passed"
    return 0
}

# 备份当前状态
backup_state() {
    local backup_dir="${HOME}/.oml/hooks/backups"
    mkdir -p "$backup_dir"

    local backup_file="${backup_dir}/pre-build-$(date +%s).tar.gz"

    # 备份重要配置
    if [[ -d "${HOME}/.oml" ]]; then
        tar -czf "$backup_file" -C "${HOME}" ".oml" 2>/dev/null || true
        echo "[HOOK] State backed up to: $backup_file"
    fi
}

# 主逻辑
main() {
    local build_target="${1:-default}"

    echo "[HOOK] Build target: $build_target"

    check_dependencies || exit 1
    backup_state

    echo "[HOOK] Pre-build check completed successfully"
}

main "$@"
