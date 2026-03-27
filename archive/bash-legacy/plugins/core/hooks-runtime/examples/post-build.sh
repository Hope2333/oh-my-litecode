#!/usr/bin/env bash
# 示例：Build Post-hook
# 在构建完成后执行

set -euo pipefail

echo "[HOOK] Post-build tasks starting..."

# 发送通知
send_notification() {
    local status="${1:-success}"
    local message="${2:-Build completed}"

    echo "[HOOK] Notification: $message ($status)"

    # 这里可以集成实际的通知服务
    # 例如：发送 Slack 消息、邮件等
}

# 清理临时文件
cleanup_temp() {
    local temp_dir="${HOME}/.oml/tmp"

    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"/*
        echo "[HOOK] Temp files cleaned"
    fi
}

# 更新构建历史
update_history() {
    local history_file="${HOME}/.oml/hooks/build-history.json"
    local timestamp
    timestamp="$(date -Iseconds)"

    mkdir -p "$(dirname "$history_file")"

    python3 - "$history_file" "$timestamp" <<'PY'
import json
import sys
from datetime import datetime

history_file = sys.argv[1]
timestamp = sys.argv[2]

history = []
try:
    with open(history_file, 'r') as f:
        history = json.load(f)
except:
    pass

history.append({
    'timestamp': timestamp,
    'status': 'success'
})

# 保留最近 100 条记录
history = history[-100:]

with open(history_file, 'w') as f:
    json.dump(history, f, indent=2)
PY

    echo "[HOOK] Build history updated"
}

# 主逻辑
main() {
    local build_status="${1:-success}"
    local build_target="${2:-default}"

    echo "[HOOK] Build target: $build_target, Status: $build_status"

    if [[ "$build_status" == "success" ]]; then
        send_notification "success" "Build '$build_target' completed successfully"
        cleanup_temp
        update_history
    else
        send_notification "failed" "Build '$build_target' failed"
    fi

    echo "[HOOK] Post-build tasks completed"
}

main "$@"
