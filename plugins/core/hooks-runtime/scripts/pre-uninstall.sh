#!/usr/bin/env bash
# OML Hooks Runtime - Pre-uninstall Hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Uninstalling hooks-runtime plugin..."

# 清理 Hooks 配置（可选）
# rm -rf "${HOME}/.oml/hooks" 2>/dev/null || true

echo "hooks-runtime plugin uninstalled."
