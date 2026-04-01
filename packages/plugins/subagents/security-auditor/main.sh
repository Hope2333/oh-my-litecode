#!/usr/bin/env bash
# Security-auditor Subagent - Main Entry Point
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

show_help() {
    cat <<HELP
Security-auditor Subagent v0.2.0
Usage: oml subagent security-auditor <command>

Commands:
  help    Show this help message

For full functionality, use the TypeScript API:
  import { Security-auditorAgent } from '@oml/plugin-security-auditor'
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
