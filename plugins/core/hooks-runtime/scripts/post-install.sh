#!/usr/bin/env bash
# OML Hooks Runtime - Post-install Hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing hooks-runtime plugin..."

# 初始化 Hooks 引擎
if [[ -f "${SCRIPT_DIR}/../../core/hooks-engine.sh" ]]; then
    source "${SCRIPT_DIR}/../../core/hooks-engine.sh"
    oml_hooks_engine_init
fi

echo "hooks-runtime plugin installed successfully!"
