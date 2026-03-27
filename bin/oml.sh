#!/usr/bin/env bash
# OML Shell Compatibility Layer
# 
# This script provides backward compatibility for shell-based OML commands
# by wrapping the new TypeScript implementation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OML_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if Node.js is available
if ! command -v node >/dev/null 2>&1; then
    echo "Error: Node.js is required but not installed." >&2
    echo "Please install Node.js 20+ from https://nodejs.org/" >&2
    exit 1
fi

# Check if TypeScript build exists
OML_CLI="$OML_ROOT/packages/cli/dist/bin/oml.js"

if [[ ! -f "$OML_CLI" ]]; then
    echo "Error: OML CLI not found. Please run 'npm run build' first." >&2
    exit 1
fi

# Execute TypeScript CLI
exec node "$OML_CLI" "$@"
