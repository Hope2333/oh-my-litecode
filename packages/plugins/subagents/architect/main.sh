#!/usr/bin/env bash
# Architect Subagent - Main Entry Point
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

show_help() {
    cat <<HELP
Architect Subagent v0.2.0
Usage: oml subagent architect <command>

Commands:
  help    Show this help message

For full functionality, use the TypeScript API:
  import { ArchitectAgent } from '@oml/plugin-architect'
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
