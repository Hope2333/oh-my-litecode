#!/usr/bin/env bash
# AI-LTC Bridge Deploy Script
# Usage: ./scripts/deploy-bridge.sh [install|update|check]
#
# install: Install bridge package and dependencies
# update:  Update bridge to latest version
# check:   Check bridge health (config, version, state file)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OML_ROOT="${SCRIPT_DIR}/.."
BRIDGE_DIR="${OML_ROOT}/packages/bridge"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
	echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
	echo -e "${BLUE}║  AI-LTC Bridge Deploy                 ║${NC}"
	echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
	echo ""
}

print_success() {
	echo -e "  ${GREEN}✓ $1${NC}"
}

print_error() {
	echo -e "  ${RED}✗ $1${NC}"
}

print_info() {
	echo -e "  ${YELLOW}ℹ $1${NC}"
}

cmd_install() {
	echo -e "${BLUE}[install]${NC} Installing bridge package and dependencies..."
	echo ""

	ERRORS=0

	# Check node_modules exists at root
	if [[ ! -d "${OML_ROOT}/node_modules" ]]; then
		print_info "Installing root dependencies..."
		(cd "${OML_ROOT}" && npm install) || ERRORS=$((ERRORS + 1))
	else
		print_success "Root dependencies already installed"
	fi

	# Install bridge dependencies
	print_info "Installing bridge dependencies..."
	(cd "${BRIDGE_DIR}" && npm install) || ERRORS=$((ERRORS + 1))

	# Build bridge
	print_info "Building bridge..."
	(cd "${BRIDGE_DIR}" && npm run build) || ERRORS=$((ERRORS + 1))

	# Verify build output
	if [[ -f "${BRIDGE_DIR}/dist/index.js" ]]; then
		print_success "Bridge build output verified"
	else
		print_error "Bridge build output not found at dist/index.js"
		ERRORS=$((ERRORS + 1))
	fi

	# Run architecture check
	print_info "Running architecture contract check..."
	if node "${OML_ROOT}/scripts/check-architecture-contract.mjs"; then
		print_success "Architecture contract check passed"
	else
		print_error "Architecture contract check failed"
		ERRORS=$((ERRORS + 1))
	fi

	echo ""
	if [[ $ERRORS -eq 0 ]]; then
		print_success "Bridge installation complete"
		exit 0
	else
		print_error "Bridge installation failed with $ERRORS error(s)"
		exit 1
	fi
}

cmd_update() {
	echo -e "${BLUE}[update]${NC} Updating bridge to latest version..."
	echo ""

	ERRORS=0

	# Clean previous build
	if [[ -d "${BRIDGE_DIR}/dist" ]]; then
		print_info "Cleaning previous build..."
		(cd "${BRIDGE_DIR}" && npm run clean)
	fi

	# Reinstall dependencies
	print_info "Reinstalling bridge dependencies..."
	(cd "${BRIDGE_DIR}" && npm install) || ERRORS=$((ERRORS + 1))

	# Rebuild
	print_info "Rebuilding bridge..."
	(cd "${BRIDGE_DIR}" && npm run build) || ERRORS=$((ERRORS + 1))

	# Run version check
	print_info "Running version compatibility check..."
	if node "${OML_ROOT}/scripts/check-bridge-version.mjs"; then
		print_success "Version compatibility check passed"
	else
		print_error "Version compatibility check failed"
		ERRORS=$((ERRORS + 1))
	fi

	# Run tests
	print_info "Running bridge tests..."
	if (cd "${BRIDGE_DIR}" && npm test); then
		print_success "Bridge tests passed"
	else
		print_error "Bridge tests failed"
		ERRORS=$((ERRORS + 1))
	fi

	echo ""
	if [[ $ERRORS -eq 0 ]]; then
		print_success "Bridge update complete"
		exit 0
	else
		print_error "Bridge update failed with $ERRORS error(s)"
		exit 1
	fi
}

cmd_check() {
	echo -e "${BLUE}[check]${NC} Checking bridge health..."
	echo ""

	ERRORS=0

	# Check config exists
	if [[ -f "${OML_ROOT}/.ai/system/ai-ltc-config.json" ]]; then
		print_success "AI-LTC config exists"
	else
		print_error "AI-LTC config not found at .ai/system/ai-ltc-config.json"
		ERRORS=$((ERRORS + 1))
	fi

	# Check version compatibility
	print_info "Running version compatibility check..."
	if node "${OML_ROOT}/scripts/check-bridge-version.mjs"; then
		: # Already printed by script
	else
		ERRORS=$((ERRORS + 1))
	fi

	# Check bridge build output
	if [[ -f "${BRIDGE_DIR}/dist/index.js" ]]; then
		print_success "Bridge build output exists"
	else
		print_error "Bridge build output not found — run 'deploy-bridge.sh install' first"
		ERRORS=$((ERRORS + 1))
	fi

	# Check bridge package.json
	if [[ -f "${BRIDGE_DIR}/package.json" ]]; then
		bridge_version=$(grep '"version"' "${BRIDGE_DIR}/package.json" | cut -d'"' -f4)
		print_success "Bridge package.json found (v${bridge_version})"
	else
		print_error "Bridge package.json not found"
		ERRORS=$((ERRORS + 1))
	fi

	echo ""
	if [[ $ERRORS -eq 0 ]]; then
		print_success "Bridge health check passed"
		exit 0
	else
		print_error "Bridge health check failed with $ERRORS issue(s)"
		exit 1
	fi
}

# ── Main ─────────────────────────────────────────────────────────────
print_header

case "${1:-}" in
install)
	cmd_install
	;;
update)
	cmd_update
	;;
check)
	cmd_check
	;;
*)
	echo "Usage: $0 [install|update|check]"
	echo ""
	echo "Commands:"
	echo "  install  Install bridge package and dependencies"
	echo "  update   Update bridge to latest version"
	echo "  check    Check bridge health (config, version, state file)"
	exit 1
	;;
esac
