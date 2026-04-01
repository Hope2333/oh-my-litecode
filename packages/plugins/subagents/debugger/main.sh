#!/usr/bin/env bash
# Debugger Subagent - Main Entry Point
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

show_help() {
    cat <<HELP
Debugger Subagent v0.2.0
Usage: oml subagent debugger <command>

Commands:
  help    Show this help message

For full functionality, use the TypeScript API:
  import { DebuggerAgent } from '@oml/plugin-debugger'
HELP
}

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        help|--help|-h) show_help ;;
        *) echo -e "${RED}Unknown command: $cmd${NC}"; show_help; exit 1 ;;
    esac
}

main "$@"
