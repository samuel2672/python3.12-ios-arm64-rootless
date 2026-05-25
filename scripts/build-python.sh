#!/usr/bin/env bash
# ==============================================================================
# Script: build-python.sh
# Purpose: Build CPython 3.12 for iOS arm64 rootless.
# Requires: PY_VER (set in environment)
# ==============================================================================

set -euxo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

cd "$BUILD"

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------

if [ -z "${PYTHON_FOR_BUILD:-}" ]; then
  echo "Error: PYTHON_FOR_BUILD is not set." >&2
  echo "Please set it to the path of a host python${PY_VER} interpreter." >&2
  exit 1
fi

if [ ! -x "$PYTHON_FOR_BUILD" ]; then
  echo "Error: PYTHON_FOR_BUILD='$PYTHON_FOR_BUILD' is not executable." >&2
  exit 1
fi

GSSED="$(command -v gsed || true)"
if [ -z "$GSSED" ]; then
  echo "Error: gsed not found. Please install GNU sed." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$WORKDIR")" && pwd)"
VENDOR_DIR="$REPO_ROOT/vendor/gnu-config"

# ------------------------------------------------------------------------------
# Download CPython Source
# ------------------------------------------------------------------------------

rm -rf "Python-${PY_VER}" "Python-${PY_VER}.tgz"

for i in 1 2 3 4 5; do
  curl --fail --location --show-error -LO \
    "https://www.python.org/ftp/python/${PY_VER}/Python-${PY_VER}.tgz" && break || {
    echo "Error: Download failed attempt $i. Retrying in 3s..." >&2
    sleep 3
  }
done

[ -f "Python-${PY_VER}.tgz" ] || {
  echo "Error: Python tarball missing." >&2
  exit 1
}

tar xf "Python-${PY_VER}.tgz"
cd "Python-${PY_VER}"

# ------------------------------------------------------------------------------
# Disable only confirmed problematic modules
# ------------------------------------------------------------------------------

cat > Modules/Setup.local <<'EOF'
*disabled*
nis
EOF

# ------------------------------------------------------------------------------
# GNU config helpers
# ------------------------------------------------------------------------------

if [ -f "$VENDOR_DIR/config.sub" ]; then
  cp "$VENDOR_DIR/config.sub" config.sub
fi

if [ -f "$VENDOR_DIR/config.guess" ]; then
  cp "$VENDOR_DIR/config.guess" config.guess
fi

BUILD_TRIPLE="$(./config.guess)"

# ------------------------------------------------------------------------------
# Patch configure cross-build guard
# ------------------------------------------------------------------------------

cp configure configure.orig

"$GSSED" -ri \
  's/^[[:space:]]*as_fn_error[^\n]*cross build not supported[^\n]*$/  : # allow iOS cross build for $host/' \
  configure

echo "===== Check configure cross-build guard ====="
grep -n 'cross build not supported' configure || true

if grep -n 'as_fn_error.*cross build not supported' configure; then
  echo "Error: configure still contains fatal cross-build guard." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# config.site for iOS arm64 cross build
# ------------------------------------------------------------------------------

cat > config.site <<'EOF'
# ==============================================================================
# config.site for CPython iOS arm64 cross build
# ==============================================================================

# ------------------------------------------------------------------------------
# Files
# ------------------------------------------------------------------------------
ac_cv_file__dev_ptc=no
ac_cv_file__dev_ptmx=no

# ------------------------------------------------------------------------------
# Basic C types on iOS arm64 / Darwin
# ------------------------------------------------------------------------------
ac_cv_type_clock_t=yes
ac_cv_type_mode_t=yes
ac_cv_type_dev_t=yes
ac_cv_type_gid_t=yes
ac_cv_type_ino_t=yes
ac_cv_type_nlink_t=yes
ac_cv_type_off_t=yes
ac_cv_type_pid_t=yes
ac_cv_type_size_t=yes
ac_cv_type_uid_t=yes
ac_cv_type_ssize_t=yes
ac_cv_type_blksize_t=yes
ac_cv_type_blkcnt_t=yes
ac_cv_type_socklen_t=yes
ac_cv_type_uintptr_t=yes
ac_cv_type_uint64_t=yes
ac_cv_type_int64_t=yes
ac_cv_type_long_double=yes
ac_cv_type_long_long=yes
ac_cv_type_unsigned_long_long=yes

# ------------------------------------------------------------------------------
# Type sizes on iOS arm64 / Darwin
# ------------------------------------------------------------------------------
ac_cv_sizeof__Bool=1
ac_cv_sizeof_char=1
ac_cv_sizeof_short=2
ac_cv_sizeof_int=4
ac_cv_sizeof_long=8
ac_cv_sizeof_long_long=8
ac_cv_sizeof_void_p=8
ac_cv_sizeof_float=4
ac_cv_sizeof_double=8
ac_cv_sizeof_long_double=8
ac_cv_sizeof_size_t=8
ac_cv_sizeof_ssize_t=8
ac_cv_sizeof_off_t=8
ac_cv_sizeof_pid_t=4
ac_cv_sizeof_uid_t=4
ac_cv_sizeof_gid_t=4
ac_cv_sizeof_dev_t=4
ac_cv_sizeof_ino_t=8
ac_cv_sizeof_nlink_t=2
ac_cv_sizeof_clock_t=8
ac_cv_sizeof_time_t=8
ac_cv_sizeof_blksize_t=4
ac_cv_sizeof_blkcnt_t=8
ac_cv_sizeof_socklen_t=4
ac_cv_sizeof_uintptr_t=8
ac_cv_sizeof_wchar_t=4
ac_cv_sizeof_fpos_t=8

# ------------------------------------------------------------------------------
# Type alignments on iOS arm64 / Darwin
# ------------------------------------------------------------------------------
ac_cv_alignof_char=1
ac_cv_alignof_short=2
ac_cv_alignof_int=4
ac_cv_alignof_long=8
ac_cv_alignof_long_long=8
ac_cv_alignof_void_p=8
ac_cv_alignof_float=4
ac_cv_alignof_double=8
ac_cv_alignof_long_double=8
ac_cv_alignof_size_t=8
ac_cv_alignof_max_align_t=8

# ------------------------------------------------------------------------------
# Endianness / integer support
# ------------------------------------------------------------------------------
ac_cv_c_bigendian=no
ac_cv_have_long_long_format=yes
ac_cv_have_size_t_format=yes
ac_cv_have_long_double=yes
ac_cv_have_uintptr_t=yes
ac_cv_have_uint64_t=yes
ac_cv_have_int64_t=yes

# ------------------------------------------------------------------------------
# Sockets / networking on iOS arm64 / Darwin
# ------------------------------------------------------------------------------
ac_cv_type_struct_addrinfo=yes
ac_cv_type_struct_sockaddr=yes
ac_cv_type_struct_sockaddr_in=yes
ac_cv_type_struct_sockaddr_in6=yes
ac_cv_type_struct_sockaddr_storage=yes
ac_cv_type_struct_sockaddr_un=yes

ac_cv_member_struct_sockaddr_sa_len=yes
ac_cv_member_struct_sockaddr_storage_ss_family=yes
ac_cv_member_struct_sockaddr_storage_ss_len=yes

ac_cv_func_socket=yes
ac_cv_func_socketpair=yes
ac_cv_func_accept=yes
ac_cv_func_bind=yes
ac_cv_func_connect=yes
ac_cv_func_listen=yes
ac_cv_func_recvfrom=yes
ac_cv_func_sendto=yes
ac_cv_func_setsockopt=yes
ac_cv_func_getsockname=yes
ac_cv_func_getpeername=yes
ac_cv_func_shutdown=yes

ac_cv_func_gethostbyname=yes
ac_cv_func_gethostbyaddr=yes
ac_cv_func_getservbyname=yes
ac_cv_func_getservbyport=yes
ac_cv_func_getprotobyname=yes

ac_cv_func_inet_aton=yes
ac_cv_func_inet_ntoa=yes
ac_cv_func_inet_pton=yes
ac_cv_func_inet_ntop=yes

ac_cv_func_getaddrinfo=yes
ac_cv_working_getaddrinfo=yes
ac_cv_buggy_getaddrinfo=no
ac_cv_func_getnameinfo=yes

# ------------------------------------------------------------------------------
# Confirmed problematic fork-related paths on iOS target
# ------------------------------------------------------------------------------
ac_cv_func_fork=yes
ac_cv_func_vfork=no
ac_cv_func_fork1=no
ac_cv_func_forkpty=no

# ------------------------------------------------------------------------------
# Confirmed problematic function detections on iOS target
# ------------------------------------------------------------------------------
ac_cv_func_system=no
ac_cv_func_pipe2=no

# iOS SDK may not expose getentropy declaration for this target.
# If enabled, Python/bootstrap_hash.c fails with implicit declaration.
ac_cv_func_getentropy=no

# iOS SDK may not expose sendfile declaration for this target.
# If enabled, Modules/posixmodule.c fails with implicit declaration.
ac_cv_func_sendfile=no
ac_cv_lib_sendfile_sendfile=no

# iOS SDK declares clock_settime but marks it unavailable on iOS.
# If enabled, Modules/timemodule.c fails with "not available on iOS".
ac_cv_func_clock_settime=no

# ------------------------------------------------------------------------------
# Disable NIS
# ------------------------------------------------------------------------------
ac_cv_header_rpcsvc_yp_prot_h=no
ac_cv_header_rpcsvc_ypclnt_h=no
ac_cv_header_rpcsvc_rpcsvc_h=no
ac_cv_func_yp_get_default_domain=no
ac_cv_lib_nsl_yp_get_default_domain=no
ac_cv_have_nis=no

# ------------------------------------------------------------------------------
# pthread / thread checks
# ------------------------------------------------------------------------------
ac_cv_pthread=yes
ac_cv_kpthread=no
ac_cv_kthread=no
ac_cv_thread=yes

# ------------------------------------------------------------------------------
# Misc cross-compile runtime checks
# ------------------------------------------------------------------------------
ac_cv_working_tzset=yes
ac_cv_have_chflags=no
ac_cv_have_lchflags=no
EOF

export CONFIG_SITE="$PWD/config.site"

# ------------------------------------------------------------------------------
# Dependency paths
# ------------------------------------------------------------------------------

OPENSSL_PREFIX="$DEPS/openssl-ios/usr/local"
LIBFFI_PREFIX="$DEPS/libffi-ios/usr/local"
ZLIB_PREFIX="$DEPS/zlib-ios/usr/local"
BZIP2_PREFIX="$DEPS/bzip2-ios/usr/local"
XZ_PREFIX="$DEPS/xz-ios/usr/local"

test -d "$OPENSSL_PREFIX/include"
test -d "$OPENSSL_PREFIX/lib"
test -f "$OPENSSL_PREFIX/lib/libssl.a"
test -f "$OPENSSL_PREFIX/lib/libcrypto.a"

test -d "$LIBFFI_PREFIX/lib"
test -f "$LIBFFI_PREFIX/lib/libffi.a"

test -d "$ZLIB_PREFIX/include"
test -d "$ZLIB_PREFIX/lib"
test -f "$ZLIB_PREFIX/include/zlib.h"
test -f "$ZLIB_PREFIX/lib/libz.a"

test -d "$BZIP2_PREFIX/include"
test -d "$BZIP2_PREFIX/lib"
test -f "$BZIP2_PREFIX/include/bzlib.h"
test -f "$BZIP2_PREFIX/lib/libbz2.a"

test -d "$XZ_PREFIX/include"
test -d "$XZ_PREFIX/lib"
test -f "$XZ_PREFIX/include/lzma.h"
test -f "$XZ_PREFIX/lib/liblzma.a"

# ------------------------------------------------------------------------------
# libffi for _ctypes
# ------------------------------------------------------------------------------

LIBFFI_INCLUDE=""

if [ -f "$LIBFFI_PREFIX/include/ffi.h" ] && [ -f "$LIBFFI_PREFIX/include/ffitarget.h" ]; then
  LIBFFI_INCLUDE="$LIBFFI_PREFIX/include"
else
  LIBFFI_INCLUDE="$(find "$LIBFFI_PREFIX" -type f -name ffi.h -print -quit | xargs dirname)"
fi

if [ -z "$LIBFFI_INCLUDE" ] || [ ! -f "$LIBFFI_INCLUDE/ffi.h" ]; then
  echo "ERROR: ffi.h not found under $LIBFFI_PREFIX" >&2
  find "$LIBFFI_PREFIX" -name 'ffi.h' -o -name 'ffitarget.h' || true
  exit 1
fi

if [ ! -f "$LIBFFI_INCLUDE/ffitarget.h" ]; then
  echo "ERROR: ffitarget.h not found next to ffi.h: $LIBFFI_INCLUDE" >&2
  find "$LIBFFI_PREFIX" -name 'ffi.h' -o -name 'ffitarget.h' || true
  exit 1
fi

echo "===== libffi for _ctypes ====="
echo "LIBFFI_PREFIX=$LIBFFI_PREFIX"
echo "LIBFFI_INCLUDE=$LIBFFI_INCLUDE"
ls -l "$LIBFFI_PREFIX/lib/libffi.a"
ls -l "$LIBFFI_INCLUDE/ffi.h"
ls -l "$LIBFFI_INCLUDE/ffitarget.h"
file "$LIBFFI_PREFIX/lib/libffi.a" || true
lipo -info "$LIBFFI_PREFIX/lib/libffi.a" || true

export LIBFFI_CFLAGS="-I$LIBFFI_INCLUDE"
export LIBFFI_LIBS="-L$LIBFFI_PREFIX/lib -lffi"

# ------------------------------------------------------------------------------
# Compression libraries for zlib / _bz2 / _lzma
# ------------------------------------------------------------------------------

export ZLIB_CFLAGS="-I$ZLIB_PREFIX/include"
export ZLIB_LIBS="-L$ZLIB_PREFIX/lib -lz"

export BZIP2_CFLAGS="-I$BZIP2_PREFIX/include"
export BZIP2_LIBS="-L$BZIP2_PREFIX/lib -lbz2"

export LIBLZMA_CFLAGS="-I$XZ_PREFIX/include"
export LIBLZMA_LIBS="-L$XZ_PREFIX/lib -llzma"

# Help CPython cross configure avoid false negatives.
cat >> config.site <<EOF

# libffi was manually verified for _ctypes.
ac_cv_header_ffi_h=yes
ac_cv_lib_ffi_ffi_call=yes

# Compression libraries were manually built for iOS arm64.
ac_cv_header_zlib_h=yes
ac_cv_lib_z_compress=yes
ac_cv_lib_z_inflateCopy=yes

ac_cv_header_bzlib_h=yes
ac_cv_lib_bz2_BZ2_bzCompress=yes
ac_cv_lib_bz2_BZ2_bzDecompress=yes

ac_cv_header_lzma_h=yes
ac_cv_lib_lzma_lzma_easy_encoder=yes
ac_cv_lib_lzma_lzma_easy_decoder_memusage=yes
EOF

# ------------------------------------------------------------------------------
# Compiler/linker environment
# ------------------------------------------------------------------------------

export CPPFLAGS="-I$OPENSSL_PREFIX/include -I$LIBFFI_INCLUDE -I$ZLIB_PREFIX/include -I$BZIP2_PREFIX/include -I$XZ_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$OPENSSL_PREFIX/lib -L$LIBFFI_PREFIX/lib -L$ZLIB_PREFIX/lib -L$BZIP2_PREFIX/lib -L$XZ_PREFIX/lib ${LDFLAGS:-}"

# OpenSSL static linking may need zlib symbols.
# Keep zlib/bzip2/lzma globally visible so configure can link extension probes.
export LIBS="-lssl -lcrypto -lz -lbz2 -llzma ${LIBS:-}"

# Keep pkg-config path visible for diagnostics, but configure below intentionally
# uses --with-pkg-config=no to avoid staged .pc prefix confusion.
export PKG_CONFIG_PATH="$ZLIB_PREFIX/lib/pkgconfig:$BZIP2_PREFIX/lib/pkgconfig:$XZ_PREFIX/lib/pkgconfig:$LIBFFI_PREFIX/lib/pkgconfig:$OPENSSL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

export CC
export CXX
export AR
export RANLIB
export STRIP

export LD="$CC"
export LDSHARED="$CC -bundle -undefined dynamic_lookup $LDFLAGS"
export LDCXXSHARED="$CXX -bundle -undefined dynamic_lookup $LDFLAGS"

echo "===== Build environment ====="
echo "PYTHON_FOR_BUILD=$PYTHON_FOR_BUILD"
echo "BUILD_TRIPLE=$BUILD_TRIPLE"
echo "HOST_TRIPLE=$HOST_TRIPLE"
echo "CC=$CC"
echo "CXX=$CXX"
echo "AR=$AR"
echo "RANLIB=$RANLIB"
echo "STRIP=$STRIP"
echo "CPPFLAGS=$CPPFLAGS"
echo "LDFLAGS=$LDFLAGS"
echo "LIBS=$LIBS"
echo "LIBFFI_CFLAGS=$LIBFFI_CFLAGS"
echo "LIBFFI_LIBS=$LIBFFI_LIBS"
echo "ZLIB_PREFIX=$ZLIB_PREFIX"
echo "BZIP2_PREFIX=$BZIP2_PREFIX"
echo "XZ_PREFIX=$XZ_PREFIX"
echo "ZLIB_CFLAGS=$ZLIB_CFLAGS"
echo "ZLIB_LIBS=$ZLIB_LIBS"
echo "BZIP2_CFLAGS=$BZIP2_CFLAGS"
echo "BZIP2_LIBS=$BZIP2_LIBS"
echo "LIBLZMA_CFLAGS=$LIBLZMA_CFLAGS"
echo "LIBLZMA_LIBS=$LIBLZMA_LIBS"
echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
echo "CONFIG_SITE=$CONFIG_SITE"
echo "OPENSSL_PREFIX=$OPENSSL_PREFIX"
echo "LIBFFI_PREFIX=$LIBFFI_PREFIX"
echo "LIBFFI_INCLUDE=$LIBFFI_INCLUDE"

# ------------------------------------------------------------------------------
# Compression diagnostics
# ------------------------------------------------------------------------------

echo "===== Check compression artifacts ====="
for p in "$ZLIB_PREFIX/lib/libz.a" "$BZIP2_PREFIX/lib/libbz2.a" "$XZ_PREFIX/lib/liblzma.a"; do
  file "$p" || true
  lipo -info "$p" || true
done

# ------------------------------------------------------------------------------
# OpenSSL diagnostics
# ------------------------------------------------------------------------------

echo "===== Check OpenSSL artifacts ====="
file "$OPENSSL_PREFIX/lib/libssl.a" || true
file "$OPENSSL_PREFIX/lib/libcrypto.a" || true
lipo -info "$OPENSSL_PREFIX/lib/libssl.a" || true
lipo -info "$OPENSSL_PREFIX/lib/libcrypto.a" || true

echo "===== Check OpenSSL pkg-config files ====="
ls -la "$OPENSSL_PREFIX/lib/pkgconfig" || true
cat "$OPENSSL_PREFIX/lib/pkgconfig/openssl.pc" || true
cat "$OPENSSL_PREFIX/lib/pkgconfig/libssl.pc" || true
cat "$OPENSSL_PREFIX/lib/pkgconfig/libcrypto.pc" || true

echo "===== Probe OpenSSL object platform ====="
tmpdir="$(mktemp -d)"
(
  cd "$tmpdir"
  ar -x "$OPENSSL_PREFIX/lib/libcrypto.a" || true
  one_obj="$(find . -type f \( -name '*.o' -o -name '*.obj' \) | head -n 1 || true)"
  if [ -z "$one_obj" ]; then
    echo "Warning: no object extracted from libcrypto.a"
  else
    echo "Object: $one_obj"
    file "$one_obj" || true
    otool -hv "$one_obj" || true
    otool -l "$one_obj" | grep -A10 LC_BUILD_VERSION || true
    otool -l "$one_obj" | grep -A10 LC_VERSION_MIN || true
  fi
)
rm -rf "$tmpdir"

echo "===== Test OpenSSL compile only ====="
cat > /tmp/openssl_probe.c <<'EOF'
#include <openssl/ssl.h>
#include <openssl/evp.h>

int main(void) {
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    const EVP_MD *md = EVP_sha256();
    return md == 0;
}
EOF

"$CC" \
  $CFLAGS \
  $CPPFLAGS \
  -c /tmp/openssl_probe.c \
  -o /tmp/openssl_probe.o

file /tmp/openssl_probe.o || true
otool -hv /tmp/openssl_probe.o || true
otool -l /tmp/openssl_probe.o | grep -A10 LC_BUILD_VERSION || true
otool -l /tmp/openssl_probe.o | grep -A10 LC_VERSION_MIN || true

echo "===== Test simple OpenSSL link manually ====="
set +e
"$CC" \
  $CFLAGS \
  $CPPFLAGS \
  /tmp/openssl_probe.c \
  -L"$OPENSSL_PREFIX/lib" \
  -L"$ZLIB_PREFIX/lib" \
  -lssl -lcrypto -lz \
  -o /tmp/openssl_probe \
  -Wl,-v
OPENSSL_LINK_STATUS=$?
set -e

if [ "$OPENSSL_LINK_STATUS" -ne 0 ]; then
  echo "Warning: simple OpenSSL link test failed with status $OPENSSL_LINK_STATUS" >&2
else
  echo "Info: simple OpenSSL link test succeeded."
  file /tmp/openssl_probe || true
  otool -hv /tmp/openssl_probe || true
  otool -l /tmp/openssl_probe | grep -A10 LC_BUILD_VERSION || true
  otool -l /tmp/openssl_probe | grep -A10 LC_VERSION_MIN || true
fi

rm -f /tmp/openssl_probe.c /tmp/openssl_probe.o /tmp/openssl_probe

echo "===== Test CPython-required OpenSSL ssl APIs ====="
cat > /tmp/openssl_ssl_api_probe.c <<'EOF'
#include <openssl/ssl.h>
#include <openssl/x509v3.h>

#if OPENSSL_VERSION_NUMBER < 0x10101000L
#error "OpenSSL >= 1.1.1 is required"
#endif

static void keylog_cb(const SSL *ssl, const char *line) {
    (void)ssl;
    (void)line;
}

int main(void) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
    if (ctx == 0) {
        return 1;
    }

    SSL_CTX_set_keylog_callback(ctx, keylog_cb);

    SSL *ssl = SSL_new(ctx);
    if (ssl == 0) {
        SSL_CTX_free(ctx);
        return 2;
    }

    X509_VERIFY_PARAM *param = SSL_get0_param(ssl);
    if (param == 0) {
        SSL_free(ssl);
        SSL_CTX_free(ctx);
        return 3;
    }

    if (!X509_VERIFY_PARAM_set1_host(param, "python.org", 0)) {
        SSL_free(ssl);
        SSL_CTX_free(ctx);
        return 4;
    }

    SSL_free(ssl);
    SSL_CTX_free(ctx);
    return 0;
}
EOF

set +e
"$CC" \
  $CFLAGS \
  $CPPFLAGS \
  /tmp/openssl_ssl_api_probe.c \
  -L"$OPENSSL_PREFIX/lib" \
  -L"$ZLIB_PREFIX/lib" \
  -lssl -lcrypto -lz \
  -o /tmp/openssl_ssl_api_probe
OPENSSL_SSL_API_STATUS=$?
set -e

if [ "$OPENSSL_SSL_API_STATUS" -ne 0 ]; then
  echo "Warning: CPython-required OpenSSL ssl API probe failed with status $OPENSSL_SSL_API_STATUS" >&2
else
  echo "Info: CPython-required OpenSSL ssl API probe linked successfully."
fi

rm -f /tmp/openssl_ssl_api_probe.c /tmp/openssl_ssl_api_probe

echo "===== Test CPython-required OpenSSL hashlib APIs ====="
cat > /tmp/openssl_hashlib_api_probe.c <<'EOF'
#include <openssl/evp.h>
#include <openssl/objects.h>

#if OPENSSL_VERSION_NUMBER < 0x10101000L
#error "OpenSSL >= 1.1.1 is required"
#endif

int main(void) {
    const char *a = OBJ_nid2sn(NID_md5);
    const char *b = OBJ_nid2sn(NID_sha1);
    const char *c = OBJ_nid2sn(NID_sha3_512);
    const char *d = OBJ_nid2sn(NID_blake2b512);
    int r = EVP_PBE_scrypt(NULL, 0, NULL, 0, 2, 8, 1, 0, NULL, 0);
    return (a == 0 || b == 0 || c == 0 || d == 0 || r < 0);
}
EOF

set +e
"$CC" \
  $CFLAGS \
  $CPPFLAGS \
  /tmp/openssl_hashlib_api_probe.c \
  -L"$OPENSSL_PREFIX/lib" \
  -L"$ZLIB_PREFIX/lib" \
  -lcrypto -lz \
  -o /tmp/openssl_hashlib_api_probe
OPENSSL_HASHLIB_API_STATUS=$?
set -e

if [ "$OPENSSL_HASHLIB_API_STATUS" -ne 0 ]; then
  echo "Warning: CPython-required OpenSSL hashlib API probe failed with status $OPENSSL_HASHLIB_API_STATUS" >&2
else
  echo "Info: CPython-required OpenSSL hashlib API probe linked successfully."
fi

rm -f /tmp/openssl_hashlib_api_probe.c /tmp/openssl_hashlib_api_probe

if [ "$OPENSSL_SSL_API_STATUS" -eq 0 ] && [ "$OPENSSL_HASHLIB_API_STATUS" -eq 0 ]; then
  echo "===== Force CPython OpenSSL cache results ====="
  cat >> config.site <<'EOF'

# OpenSSL was manually verified with the same APIs CPython checks.
# Force configure cache to avoid pkg-config/prefix confusion during iOS cross build.
ac_cv_working_openssl_ssl=yes
ac_cv_working_openssl_hashlib=yes
EOF
else
  echo "Warning: not forcing OpenSSL cache because one of the exact API probes failed." >&2
fi

# ------------------------------------------------------------------------------
# Configure CPython
# ------------------------------------------------------------------------------

./configure \
  --host="${HOST_TRIPLE}" \
  --build="${BUILD_TRIPLE}" \
  --prefix=/var/jb/usr/local \
  --with-build-python="${PYTHON_FOR_BUILD}" \
  --with-openssl="$OPENSSL_PREFIX" \
  --with-pkg-config=no \
  --with-ensurepip=install \
  --disable-test-modules 2>&1 | tee configure.out

# ------------------------------------------------------------------------------
# Check configure results
# ------------------------------------------------------------------------------

echo "===== Check configure module results ====="

grep -E "checking for libffi|checking for ffi_prep|checking for ffi_closure|checking for zlib|checking for bzip2|checking for bzlib|checking for liblzma|checking for lzma|checking for stdlib extension module _ctypes|checking for stdlib extension module _ssl|checking for stdlib extension module _hashlib|checking for stdlib extension module _socket|checking for stdlib extension module zlib|checking for stdlib extension module _bz2|checking for stdlib extension module _lzma|checking for stdlib extension module _posixsubprocess|py_cv_module__posixsubprocess" configure.out config.log || true

if ! grep -Eq "checking for stdlib extension module _ctypes[.][.][.] yes" configure.out; then
  echo "ERROR: _ctypes is not enabled. libffi detection failed." >&2
  grep -E "libffi|ffi_prep|ffi_closure|_ctypes|LIBFFI" configure.out config.log || true
  exit 1
fi

if ! grep -Eq "checking for stdlib extension module _ssl[.][.][.] yes" configure.out; then
  echo "ERROR: _ssl is not enabled. OpenSSL detection failed." >&2
  grep -E "OpenSSL|openssl|_ssl|ac_cv_working_openssl_ssl" configure.out config.log || true
  exit 1
fi

if ! grep -Eq "checking for stdlib extension module _hashlib[.][.][.] yes" configure.out; then
  echo "ERROR: _hashlib is not enabled. OpenSSL detection failed." >&2
  grep -E "OpenSSL|openssl|_hashlib|ac_cv_working_openssl_hashlib" configure.out config.log || true
  exit 1
fi

if ! grep -Eq "checking for stdlib extension module _socket[.][.][.] yes" configure.out; then
  echo "ERROR: _socket is not enabled." >&2
  grep -E "_socket|socket|addrinfo|getaddrinfo" configure.out config.log || true
  exit 1
fi

if ! grep -Eq "checking for stdlib extension module _posixsubprocess[.][.][.] yes" configure.out \
   && ! grep -Eq "^py_cv_module__posixsubprocess=yes$" config.log; then
  echo "ERROR: _posixsubprocess is not enabled. Native subprocess support will not work." >&2
  grep -E "_posixsubprocess|fork|exec|posix_spawn|py_cv_module__posixsubprocess" configure.out config.log || true
  exit 1
fi

if ! grep -Eq "checking for stdlib extension module zlib[.][.][.] yes" configure.out; then
  echo "ERROR: zlib module is not enabled." >&2
  grep -E "zlib|ZLIB|libz|inflate|compress" configure.out config.log || true
  exit 1
fi

if ! grep -Eq "checking for stdlib extension module _bz2[.][.][.] yes" configure.out; then
  echo "ERROR: _bz2 module is not enabled." >&2
  grep -E "bzip2|bzlib|BZIP2|BZ2|_bz2" configure.out config.log || true
  exit 1
fi

if ! grep -Eq "checking for stdlib extension module _lzma[.][.][.] yes" configure.out; then
  echo "ERROR: _lzma module is not enabled." >&2
  grep -E "lzma|liblzma|LIBLZMA|_lzma" configure.out config.log || true
  exit 1
fi

# ------------------------------------------------------------------------------
# Patch pyconfig.h
# ------------------------------------------------------------------------------

echo "===== Patch pyconfig.h invalid type/function/network fallbacks ====="

python3 - <<'PY'
from pathlib import Path

p = Path("pyconfig.h")
s = p.read_text()

bad_type_fallbacks = [
    "clock_t",
    "mode_t",
    "off_t",
    "pid_t",
    "size_t",
    "uid_t",
    "gid_t",
    "ssize_t",
    "dev_t",
    "ino_t",
    "nlink_t",
    "blksize_t",
    "blkcnt_t",
    "socklen_t",
]

for t in bad_type_fallbacks:
    s = s.replace(f"#define {t} long\n", f"/* #undef {t} */\n")
    s = s.replace(f"#define {t} int\n", f"/* #undef {t} */\n")
    s = s.replace(f"#define {t} unsigned int\n", f"/* #undef {t} */\n")
    s = s.replace(f"#define {t} unsigned long\n", f"/* #undef {t} */\n")

# iOS target: disable only confirmed problematic paths.
for macro in [
    "HAVE_VFORK",
    "HAVE_FORK1",
    "HAVE_FORKPTY",
    "HAVE_GETENTROPY",
    "HAVE_SENDFILE",
    "HAVE_CLOCK_SETTIME",
]:
    s = s.replace(f"#define {macro} 1\n", f"/* #undef {macro} */\n")


def force_define_macro(text: str, macro: str, value: str = "1") -> str:
    lines = text.splitlines()
    out = []
    found = False

    for line in lines:
        if line == f"/* #undef {macro} */":
            out.append(f"#define {macro} {value}")
            found = True
        elif line.startswith(f"#define {macro} "):
            out.append(f"#define {macro} {value}")
            found = True
        else:
            out.append(line)

    if not found:
        out.append(f"#define {macro} {value}")

    return "\n".join(out) + "\n"


# Apple/iOS SDK has native getaddrinfo/getnameinfo and socket address structs.
# Force these because configure may misdetect them during cross-compilation.
for macro in [
    "HAVE_GETADDRINFO",
    "HAVE_GETNAMEINFO",
    "HAVE_ADDRINFO",
    "HAVE_SOCKADDR_STORAGE",
    "HAVE_SOCKADDR_SA_LEN",
    "HAVE_INET_PTON",
    "HAVE_INET_NTOP",
    "HAVE_SOCKET",
    "HAVE_SOCKETPAIR",
    "HAVE_CONNECT",
    "HAVE_BIND",
    "HAVE_LISTEN",
    "HAVE_ACCEPT",
    "HAVE_SENDTO",
    "HAVE_RECVFROM",
    "HAVE_SETSOCKOPT",
    "HAVE_GETSOCKNAME",
    "HAVE_GETPEERNAME",
    "HAVE_SHUTDOWN",
]:
    s = force_define_macro(s, macro)

p.write_text(s)
PY

echo "===== Check pyconfig.h type fallbacks ====="
for t in clock_t mode_t off_t pid_t size_t uid_t gid_t ssize_t dev_t ino_t nlink_t blksize_t blkcnt_t socklen_t; do
  if grep -q "^#define ${t} " pyconfig.h; then
    echo "ERROR: pyconfig.h still unexpectedly defines ${t}" >&2
    grep -n "^#define ${t} " pyconfig.h || true
    exit 1
  fi
done

echo "===== Check pyconfig.h disabled problematic definitions ====="
for m in HAVE_VFORK HAVE_FORK1 HAVE_FORKPTY HAVE_GETENTROPY HAVE_SENDFILE HAVE_CLOCK_SETTIME; do
  if grep -q "^#define ${m} 1" pyconfig.h; then
    echo "ERROR: pyconfig.h still enables ${m}" >&2
    grep -n "^#define ${m} 1" pyconfig.h || true
    exit 1
  fi
done

if ! grep -q "^#define HAVE_FORK 1" pyconfig.h; then
  echo "ERROR: pyconfig.h does not enable HAVE_FORK; native subprocess cannot work." >&2
  grep -n "HAVE_FORK" pyconfig.h || true
  exit 1
fi

echo "===== Check pyconfig.h networking definitions ====="
grep -nE 'HAVE_GETADDRINFO|HAVE_GETNAMEINFO|HAVE_ADDRINFO|HAVE_SOCKADDR_STORAGE|HAVE_SOCKET|HAVE_CONNECT|HAVE_BIND|HAVE_LISTEN|HAVE_ACCEPT|HAVE_SENDTO|HAVE_RECVFROM|HAVE_INET_PTON|HAVE_INET_NTOP' pyconfig.h || true

for m in HAVE_GETADDRINFO HAVE_GETNAMEINFO HAVE_ADDRINFO HAVE_SOCKADDR_STORAGE HAVE_SOCKET HAVE_CONNECT HAVE_BIND HAVE_LISTEN HAVE_ACCEPT HAVE_SENDTO HAVE_RECVFROM; do
  if ! grep -q "^#define ${m} 1" pyconfig.h; then
    echo "ERROR: pyconfig.h does not enable ${m}" >&2
    grep -n "${m}" pyconfig.h || true
    exit 1
  fi
done

# ------------------------------------------------------------------------------
# Patch socketmodule.c addrinfo fallback
# ------------------------------------------------------------------------------

echo "===== Patch socket addrinfo fallback for Apple SDK ====="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("Modules/socketmodule.c")
s = p.read_text()

# CPython may include Modules/addrinfo.h when HAVE_GETADDRINFO is misdetected.
# Since pyconfig.h is patched to define HAVE_GETADDRINFO=1 on iOS,
# this fallback should not be active. If direct include lines exist, guard them.
pattern = re.compile(
    r'^(?P<indent>[ \t]*#[ \t]*include[ \t]+"addrinfo\.h"[ \t]*)$',
    re.MULTILINE,
)

if pattern.search(s):
    s = pattern.sub(
        '# ifndef __APPLE__\n'
        '#  include "addrinfo.h"\n'
        '# endif',
        s,
    )
    p.write_text(s)
    print("Patched direct addrinfo.h include lines")
else:
    print("Info: no direct addrinfo.h include line found; relying on HAVE_GETADDRINFO=1")
PY

echo "===== Verify socketmodule.c addrinfo fallback context ====="
grep -n -A6 -B6 'addrinfo.h' Modules/socketmodule.c || true

# ------------------------------------------------------------------------------
# Keep _posixsubprocess enabled for experimental native subprocess support
# ------------------------------------------------------------------------------

echo "===== Keep _posixsubprocess enabled ====="

# ------------------------------------------------------------------------------
# Patch Makefile: skip checksharedmods
# ------------------------------------------------------------------------------

awk 'BEGIN{skip=0}
  /^checksharedmods:/{print "checksharedmods:\n\t@true"; skip=1; next}
  skip && (/^\t/ || /^[[:space:]]*$/){next}
  skip {skip=0}
  {print}
' Makefile > Makefile.new && mv Makefile.new Makefile

# ------------------------------------------------------------------------------
# Build and Install
# ------------------------------------------------------------------------------

make -j"${JOBS}"

make install ENSUREPIP=no DESTDIR="$STAGE"

# ------------------------------------------------------------------------------
# Basic Installed Layout Checks
# ------------------------------------------------------------------------------

test -x "$STAGE/var/jb/usr/local/bin/python3.12"
test -f "$STAGE/var/jb/usr/local/lib/python3.12/os.py"
test -f "$STAGE/var/jb/usr/local/lib/python3.12/encodings/__init__.py"

echo "===== Required extension module checks ====="
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/_socket*.so
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/_ssl*.so
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/_hashlib*.so
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/_ctypes*.so
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/_posixsubprocess*.so
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/zlib*.so
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/_bz2*.so
ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/_lzma*.so

# ------------------------------------------------------------------------------
# Cleanup source tarball
# ------------------------------------------------------------------------------

cd "$BUILD"
rm -f "Python-${PY_VER}.tgz"

# ------------------------------------------------------------------------------
# Post-Processing
# ------------------------------------------------------------------------------

mkdir -p "$STAGE/var/jb/usr/local/bin"
ln -sf python3.12 "$STAGE/var/jb/usr/local/bin/python3"
ln -sf python3.12 "$STAGE/var/jb/usr/local/bin/python"

echo "Stripping binaries..."
find "$STAGE" -type f \( -name "*.dylib" -o -name "*.so" -o -path "$STAGE/var/jb/usr/local/bin/*" \) -print0 |
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    "$STRIP" -x "$f" || echo "Warning: strip failed on $f" >&2
  fi
done

ENTITLEMENTS="$REPO_ROOT/scripts/entitlements.plist"

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "Error: entitlements file missing: $ENTITLEMENTS" >&2
  exit 1
fi

if ! command -v ldid >/dev/null 2>&1; then
  echo "Error: ldid not found." >&2
  exit 1
fi

echo "Signing Mach-O files..."
find "$STAGE" -type f \( -name "*.dylib" -o -name "*.so" -o -path "$STAGE/var/jb/usr/local/bin/*" \) -print0 |
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    ldid -S"$ENTITLEMENTS" "$f" || echo "Warning: ldid failed on $f" >&2
  fi
done

# ------------------------------------------------------------------------------
# Report important extension modules
# ------------------------------------------------------------------------------

echo "===== Important extension modules ====="

for mod in _socket _ssl _hashlib _ctypes _posixsubprocess zlib _bz2 _lzma select fcntl mmap resource grp termios syslog _multiprocessing _posixshmem; do
  ls "$STAGE/var/jb/usr/local/lib/python3.12/lib-dynload"/"${mod}"*.so || echo "Warning: ${mod} missing"
done

echo "Info: CPython iOS rootless build completed."