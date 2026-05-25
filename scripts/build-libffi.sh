#!/usr/bin/env bash
# ==============================================================================
# Script: build-libffi.sh
# Purpose: Build libffi (static library) for iOS arm64.
# Requires: LIBFFI_VER (set in environment or common-env.sh)
# ==============================================================================

set -euxo pipefail

# Load common environment variables and toolchain settings
# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

LIBFFI_PREFIX="$DEPS/libffi-ios"
LIBFFI_MARKER="$LIBFFI_PREFIX/.ios-no-cfi"

# ------------------------------------------------------------------------------
# Check for Existing Build
# ------------------------------------------------------------------------------
# Only reuse cache if it was built with CFI disabled.
if [ -f "$LIBFFI_PREFIX/usr/local/lib/libffi.a" ] && [ -f "$LIBFFI_MARKER" ]; then
  echo "Info: no-CFI libffi already built. Skipping..."
  exit 0
fi

rm -rf "$LIBFFI_PREFIX"
mkdir -p "$DEPS"
cd "$DEPS"

# ------------------------------------------------------------------------------
# Download Source
# ------------------------------------------------------------------------------
rm -rf "libffi-${LIBFFI_VER}" "libffi-${LIBFFI_VER}.tar.gz"

for i in 1 2 3 4 5; do
  curl --fail --location --show-error -LO \
    "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VER}/libffi-${LIBFFI_VER}.tar.gz" && break || {
    echo "Error: Download failed (attempt $i). Retrying in 3s..." >&2
    sleep 3
  }
done

[ -f "libffi-${LIBFFI_VER}.tar.gz" ] || {
  echo "Error: libffi tarball missing." >&2
  exit 1
}

tar xf "libffi-${LIBFFI_VER}.tar.gz"
cd "libffi-${LIBFFI_VER}"

# ------------------------------------------------------------------------------
# Configure
# ------------------------------------------------------------------------------
./configure \
  --host="${HOST_TRIPLE}" \
  --prefix=/usr/local \
  --disable-shared \
  --enable-static

# ------------------------------------------------------------------------------
# Patch generated config
# ------------------------------------------------------------------------------
# Xcode 16.x / iPhoneOS 18.x assembler rejects some libffi 3.4.4 aarch64 CFI
# expressions. Configure enables HAVE_AS_CFI_PSEUDO_OP, so disable it in the
# generated config header used by this build.
echo "===== Disable libffi CFI after configure ====="

CONFIG_H="aarch64-apple-darwin/fficonfig.h"
test -f "$CONFIG_H"

python3 - <<'PY'
from pathlib import Path

p = Path("aarch64-apple-darwin/fficonfig.h")
s = p.read_text()

old = "#define HAVE_AS_CFI_PSEUDO_OP 1"
new = "/* #undef HAVE_AS_CFI_PSEUDO_OP */"

if old not in s:
    print("Info: HAVE_AS_CFI_PSEUDO_OP was not enabled in generated fficonfig.h")
else:
    s = s.replace(old, new)
    p.write_text(s)
    print("Patched generated fficonfig.h: disabled HAVE_AS_CFI_PSEUDO_OP")
PY

echo "===== Check generated fficonfig.h ====="
grep -n "HAVE_AS_CFI_PSEUDO_OP" "$CONFIG_H" || true

if grep -q '^#define HAVE_AS_CFI_PSEUDO_OP 1' "$CONFIG_H"; then
  echo "ERROR: HAVE_AS_CFI_PSEUDO_OP is still enabled in $CONFIG_H" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Build and Install
# ------------------------------------------------------------------------------
make -j"${JOBS}"

make install DESTDIR="$LIBFFI_PREFIX"

test -f "$LIBFFI_PREFIX/usr/local/lib/libffi.a"
touch "$LIBFFI_MARKER"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
cd "$DEPS"
rm -rf "libffi-${LIBFFI_VER}" "libffi-${LIBFFI_VER}.tar.gz"