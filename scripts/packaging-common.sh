#!/usr/bin/env bash
# Common packaging utilities for Termux packages
# Usage: source this file from other packaging scripts

# Termux standard paths
TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
TERMUX_BIN="$TERMUX_PREFIX/bin"
TERMUX_LIB="$TERMUX_PREFIX/lib"

# Standard architecture mapping
get_arch() {
	local arch="${1:-aarch64}"
	case "$arch" in
	arm64 | aarch64) echo "aarch64" ;;
	arm | armhf) echo "arm" ;;
	x86_64 | amd64) echo "x86_64" ;;
	i386 | i686 | x86) echo "i686" ;;
	*) echo "$arch" ;;
	esac
}

# Create DEBIAN control file
# Args: pkgname, version, arch, description, depends, maintainer
write_deb_control() {
	local control_dir="$1"
	local pkgname="$2"
	local version="$3"
	local arch="$4"
	local description="$5"
	local depends="${6:-}"
	local maintainer="${7:-Hope2333}"

	cat >"$control_dir/control" <<EOF
Package: $pkgname
Version: $version
Architecture: $arch
Maintainer: $maintainer
Section: utils
Priority: optional
Description: $description
EOF

	if [[ -n "$depends" ]]; then
		echo "Depends: $depends" >>"$control_dir/control"
	fi
}

# Calculate and add installed size to control
add_installed_size() {
	local control_dir="$1"
	local pkg_root="$2"
	local size
	size=$(du -sk "$pkg_root" 2>/dev/null | cut -f1)
	echo "Installed-Size: $size" >>"$control_dir/control"
}

# Create standard postinst script
write_postinst() {
	local postinst="$1"
	local pkgname="$2"
	local binary_name="${3:-$pkgname}"

	cat >"$postinst" <<'POSTINST'
#!/data/data/com.termux/files/usr/bin/bash
set -e
POSTINST

	if [[ -n "$pkgname" ]]; then
		cat >>"$postinst" <<EOF
echo "$pkgname for Termux installed!"
echo "Usage: $binary_name --version"
EOF
	fi

	echo "exit 0" >>"$postinst"
	chmod 755 "$postinst"
}

# Create launcher wrapper script for glibc-runner
create_grun_launcher() {
	local launcher="$1"
	local target="$2"

	cat >"$launcher" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LAUNCHER
	echo "exec grun \"$target\" \"\$@\"" >>"$launcher"
	chmod 755 "$launcher"
}

# Create direct launcher (no glibc-runner)
create_direct_launcher() {
	local launcher="$1"
	local target="$2"

	cat >"$launcher" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LAUNCHER
	echo "exec \"$target\" \"\$@\"" >>"$launcher"
	chmod 755 "$launcher"
}

# Validate required commands
require_commands() {
	local missing=()
	for cmd in "$@"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "Error: Missing required commands: ${missing[*]}"
		return 1
	fi
	return 0
}

# Safe cleanup function
cleanup() {
	local dir="$1"
	if [[ -d "$dir" ]]; then
		rm -rf "$dir"
	fi
}
