#!/usr/bin/env bash
# Docker-setup Skill - Main Entry Point
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

show_help() {
    cat <<HELP
Docker-setup Skill v0.2.0
Usage: oml skill docker-setup <command>

Commands:
  help    Show this help message

For full functionality, use the TypeScript API:
  import { Docker-setupAgent } from '@oml/plugin-docker-setup'
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
