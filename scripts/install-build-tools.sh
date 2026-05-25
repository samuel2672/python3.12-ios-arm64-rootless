#!/usr/bin/env bash
# ==============================================================================
# Script: install-build-tools.sh
# Purpose: Install required build tools via Homebrew (macOS).
# Usage: Run on the CI runner or local macOS machine.
# ==============================================================================

set -euxo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

FORMULAE=(
  dpkg
  ldid-procursus
  autoconf
  automake
  libtool
  pkg-config
  coreutils
  gnu-sed
  cmake
  nasm
  yasm
  git
  wget
  gpatch
)

for f in "${FORMULAE[@]}"; do
  if brew list --formula "${f}" >/dev/null 2>&1; then
    echo "Info: ${f} is already installed. Skipping..."
  else
    brew install "${f}"
  fi
done

echo "Info: Tool versions"
command -v dpkg-deb
command -v ldid
command -v gsed
dpkg-deb --version | head -1
gsed --version | head -1