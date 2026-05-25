#!/usr/bin/env bash
# ==============================================================================
# Script: build-compression-libs.sh
# Purpose: Build zlib, bzip2 and xz/liblzma for iOS arm64 rootless CPython.
# ==============================================================================

set -euxo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

ZLIB_VER="${ZLIB_VER:-1.3.1}"
BZIP2_VER="${BZIP2_VER:-1.0.8}"
XZ_VER="${XZ_VER:-5.4.7}"

ZLIB_PREFIX="$DEPS/zlib-ios/usr/local"
BZIP2_PREFIX="$DEPS/bzip2-ios/usr/local"
XZ_PREFIX="$DEPS/xz-ios/usr/local"

mkdir -p "$BUILD" "$DEPS"
cd "$BUILD"

# ------------------------------------------------------------------------------
# zlib
# ------------------------------------------------------------------------------

if [ -f "$ZLIB_PREFIX/lib/libz.a" ] && [ -f "$ZLIB_PREFIX/include/zlib.h" ]; then
  echo "Info: zlib already built: $ZLIB_PREFIX"
else
  rm -rf "zlib-${ZLIB_VER}" "zlib-${ZLIB_VER}.tar.gz"

  for i in 1 2 3 4 5; do
    curl --fail --location --show-error -L \
      "https://zlib.net/fossils/zlib-${ZLIB_VER}.tar.gz" \
      -o "zlib-${ZLIB_VER}.tar.gz" && break || {
      echo "Warning: zlib download failed attempt $i. Retrying in 3s..." >&2
      sleep 3
    }
  done

  test -f "zlib-${ZLIB_VER}.tar.gz"
  tar xf "zlib-${ZLIB_VER}.tar.gz"
  cd "zlib-${ZLIB_VER}"

  CHOST="$HOST_TRIPLE" \
  CC="$CC" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS -fPIC" \
  ./configure \
    --static \
    --prefix="$ZLIB_PREFIX"

  make -j"$JOBS" libz.a
  make install

  cd "$BUILD"
fi

test -f "$ZLIB_PREFIX/lib/libz.a"
test -f "$ZLIB_PREFIX/include/zlib.h"

echo "===== zlib artifacts ====="
file "$ZLIB_PREFIX/lib/libz.a" || true
lipo -info "$ZLIB_PREFIX/lib/libz.a" || true
ls -l "$ZLIB_PREFIX/include/zlib.h"

# ------------------------------------------------------------------------------
# bzip2
# ------------------------------------------------------------------------------

if [ -f "$BZIP2_PREFIX/lib/libbz2.a" ] && [ -f "$BZIP2_PREFIX/include/bzlib.h" ]; then
  echo "Info: bzip2 already built: $BZIP2_PREFIX"
else
  rm -rf "bzip2-${BZIP2_VER}" "bzip2-${BZIP2_VER}.tar.gz"

  for i in 1 2 3 4 5; do
    curl --fail --location --show-error -L \
      "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VER}.tar.gz" \
      -o "bzip2-${BZIP2_VER}.tar.gz" && break || {
      echo "Warning: bzip2 download failed attempt $i. Retrying in 3s..." >&2
      sleep 3
    }
  done

  test -f "bzip2-${BZIP2_VER}.tar.gz"
  tar xf "bzip2-${BZIP2_VER}.tar.gz"
  cd "bzip2-${BZIP2_VER}"

  make clean || true

  make -j"$JOBS" libbz2.a \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    CFLAGS="$CFLAGS -fPIC -Wall -Winline -O2 -D_FILE_OFFSET_BITS=64"

  mkdir -p "$BZIP2_PREFIX/include" "$BZIP2_PREFIX/lib"
  cp -f bzlib.h "$BZIP2_PREFIX/include/bzlib.h"
  cp -f libbz2.a "$BZIP2_PREFIX/lib/libbz2.a"
  "$RANLIB" "$BZIP2_PREFIX/lib/libbz2.a" || true

  cd "$BUILD"
fi

test -f "$BZIP2_PREFIX/lib/libbz2.a"
test -f "$BZIP2_PREFIX/include/bzlib.h"

echo "===== bzip2 artifacts ====="
file "$BZIP2_PREFIX/lib/libbz2.a" || true
lipo -info "$BZIP2_PREFIX/lib/libbz2.a" || true
ls -l "$BZIP2_PREFIX/include/bzlib.h"

# ------------------------------------------------------------------------------
# xz / liblzma
# ------------------------------------------------------------------------------

if [ -f "$XZ_PREFIX/lib/liblzma.a" ] && [ -f "$XZ_PREFIX/include/lzma.h" ]; then
  echo "Info: xz/liblzma already built: $XZ_PREFIX"
else
  rm -rf "xz-${XZ_VER}" "xz-${XZ_VER}.tar.gz"

  for i in 1 2 3 4 5; do
    curl --fail --location --show-error -L \
      "https://tukaani.org/xz/xz-${XZ_VER}.tar.gz" \
      -o "xz-${XZ_VER}.tar.gz" && break || {
      echo "Warning: xz download failed attempt $i. Retrying in 3s..." >&2
      sleep 3
    }
  done

  test -f "xz-${XZ_VER}.tar.gz"
  tar xf "xz-${XZ_VER}.tar.gz"
  cd "xz-${XZ_VER}"

  ./configure \
    --host="$HOST_TRIPLE" \
    --prefix="$XZ_PREFIX" \
    --disable-shared \
    --enable-static \
    --disable-xz \
    --disable-xzdec \
    --disable-lzmadec \
    --disable-lzmainfo \
    --disable-scripts \
    --disable-doc \
    --disable-nls \
    --disable-rpath \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    CFLAGS="$CFLAGS -fPIC" \
    CPPFLAGS="-I$ZLIB_PREFIX/include" \
    LDFLAGS="$LDFLAGS -L$ZLIB_PREFIX/lib"

  make -j"$JOBS"
  make install

  cd "$BUILD"
fi

test -f "$XZ_PREFIX/lib/liblzma.a"
test -f "$XZ_PREFIX/include/lzma.h"

echo "===== xz/liblzma artifacts ====="
file "$XZ_PREFIX/lib/liblzma.a" || true
lipo -info "$XZ_PREFIX/lib/liblzma.a" || true
ls -l "$XZ_PREFIX/include/lzma.h"

echo "Info: compression libraries built successfully."
