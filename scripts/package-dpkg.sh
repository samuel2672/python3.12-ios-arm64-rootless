#!/usr/bin/env bash
# ==============================================================================
# Script: package-dpkg.sh
# Purpose: Package staged CPython rootless iOS files into a .deb.
# ==============================================================================

set -euxo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

PKG_NAME="com.samuel2672.python3-rootless"
PKG_VERSION="${PY_VER}-1"
PKG_ARCH="iphoneos-arm64"

PKGROOT="$WORKDIR/pkgroot"
DEB_OUT="$WORKDIR/python3.12-rootless_${PKG_VERSION}_${PKG_ARCH}.deb"

REPO_ROOT="$(cd "$(dirname "$WORKDIR")" && pwd)"

rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/DEBIAN"

# ------------------------------------------------------------------------------
# Validate staged CPython layout
# ------------------------------------------------------------------------------

if [ ! -d "$STAGE/var/jb/usr/local" ]; then
  echo "ERROR: staged rootless Python tree not found: $STAGE/var/jb/usr/local" >&2
  exit 1
fi

test -x "$STAGE/var/jb/usr/local/bin/python3.12"
test -f "$STAGE/var/jb/usr/local/lib/python3.12/os.py"
test -f "$STAGE/var/jb/usr/local/lib/python3.12/encodings/__init__.py"

# ------------------------------------------------------------------------------
# Copy staged files into package root
# ------------------------------------------------------------------------------

mkdir -p "$PKGROOT/var/jb"
cp -a "$STAGE/var/jb/usr" "$PKGROOT/var/jb/"

# ------------------------------------------------------------------------------
# Debian documentation
# ------------------------------------------------------------------------------

DOC_DIR="$PKGROOT/var/jb/usr/share/doc/$PKG_NAME"
mkdir -p "$DOC_DIR"

CHANGELOG_FILE="$REPO_ROOT/debian/changelog"
COPYRIGHT_FILE="$REPO_ROOT/debian/copyright"

if [ -f "$CHANGELOG_FILE" ]; then
  gzip -9 -n -c "$CHANGELOG_FILE" > "$DOC_DIR/changelog.gz"
fi

if [ -f "$COPYRIGHT_FILE" ]; then
  cp "$COPYRIGHT_FILE" "$DOC_DIR/copyright"
fi

# ------------------------------------------------------------------------------
# Rootless profile.d
# ------------------------------------------------------------------------------

mkdir -p "$PKGROOT/var/jb/etc/profile.d"

cat > "$PKGROOT/var/jb/etc/profile.d/python3.sh" <<'EOF'
# Python 3.12 rootless iOS environment
export PATH="/var/jb/usr/local/bin:$PATH"
export SSL_CERT_FILE="/var/jb/usr/local/etc/ssl/cert.pem"
export REQUESTS_CA_BUNDLE="/var/jb/usr/local/etc/ssl/cert.pem"
EOF

chmod 0644 "$PKGROOT/var/jb/etc/profile.d/python3.sh"

# ------------------------------------------------------------------------------
# Helper: portable sed -i
# ------------------------------------------------------------------------------

sed_inplace() {
  local expr="$1"
  local file="$2"

  if command -v gsed >/dev/null 2>&1; then
    gsed -i "$expr" "$file"
  else
    sed -i '' "$expr" "$file"
  fi
}

# ------------------------------------------------------------------------------
# Fix script shebangs
# ------------------------------------------------------------------------------

if [ -d "$PKGROOT/var/jb/usr/local/bin" ]; then
  for f in \
    "$PKGROOT"/var/jb/usr/local/bin/pip* \
    "$PKGROOT"/var/jb/usr/local/bin/pydoc* \
    "$PKGROOT"/var/jb/usr/local/bin/idle* \
    "$PKGROOT"/var/jb/usr/local/bin/2to3*
  do
    if [ ! -f "$f" ]; then
      continue
    fi

    sed_inplace '1s|^#!.*python.*|#!/var/jb/usr/local/bin/python3.12|' "$f" || true
    chmod 0755 "$f"
  done
fi

# ------------------------------------------------------------------------------
# Optional CA certificate placeholder
# ------------------------------------------------------------------------------

mkdir -p "$PKGROOT/var/jb/usr/local/etc/ssl"

if [ ! -f "$PKGROOT/var/jb/usr/local/etc/ssl/cert.pem" ]; then
  if [ -f "/etc/ssl/cert.pem" ]; then
    cp "/etc/ssl/cert.pem" "$PKGROOT/var/jb/usr/local/etc/ssl/cert.pem"
  elif [ -f "/usr/local/etc/openssl@3/cert.pem" ]; then
    cp "/usr/local/etc/openssl@3/cert.pem" "$PKGROOT/var/jb/usr/local/etc/ssl/cert.pem"
  elif [ -f "/opt/homebrew/etc/openssl@3/cert.pem" ]; then
    cp "/opt/homebrew/etc/openssl@3/cert.pem" "$PKGROOT/var/jb/usr/local/etc/ssl/cert.pem"
  else
    touch "$PKGROOT/var/jb/usr/local/etc/ssl/cert.pem"
  fi
fi

chmod 0644 "$PKGROOT/var/jb/usr/local/etc/ssl/cert.pem"

# ------------------------------------------------------------------------------
# Remove known unwanted build cache files
# ------------------------------------------------------------------------------

find "$PKGROOT" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "$PKGROOT" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete

# ------------------------------------------------------------------------------
# Rootless path sanity checks
# ------------------------------------------------------------------------------

echo "===== Check rootless package layout ====="

test -x "$PKGROOT/var/jb/usr/local/bin/python3.12"
test -f "$PKGROOT/var/jb/usr/local/lib/python3.12/os.py"
test -f "$PKGROOT/var/jb/usr/local/lib/python3.12/encodings/__init__.py"
test -f "$PKGROOT/var/jb/etc/profile.d/python3.sh"

if [ -e "$PKGROOT/usr" ]; then
  echo "ERROR: rootful /usr exists in package root: $PKGROOT/usr" >&2
  exit 1
fi

if [ -e "$PKGROOT/etc" ]; then
  echo "ERROR: rootful /etc exists in package root: $PKGROOT/etc" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Mach-O dependency path check
# Important:
#   otool -L prints the checked file path on the first line.
#   That first line naturally contains /Users/runner during GitHub Actions.
#   Therefore we MUST skip the first line before grepping dependencies.
# ------------------------------------------------------------------------------

echo "===== Check Mach-O dependency paths ====="

BAD=0

while IFS= read -r f; do
  if ! file -b "$f" | grep -q "Mach-O"; then
    continue
  fi

  if otool -L "$f" | tail -n +2 | grep -E '/Users/runner|/opt/homebrew|/usr/local/Cellar|/usr/local/opt|/usr/local/lib'; then
    echo "BAD dependency path in $f" >&2
    otool -L "$f" >&2 || true
    BAD=1
  fi
done < <(find "$PKGROOT" -type f)

if [ "$BAD" = "1" ]; then
  echo "ERROR: bad Mach-O dependency path found" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Optional Mach-O signing
# Build step should already sign files, but signing again is safe for packaging.
# ------------------------------------------------------------------------------

ENTITLEMENTS="$REPO_ROOT/scripts/entitlements.plist"

if command -v ldid >/dev/null 2>&1 && [ -f "$ENTITLEMENTS" ]; then
  echo "===== Re-sign Mach-O files in package root ====="

  while IFS= read -r f; do
    if file -b "$f" | grep -q "Mach-O"; then
      ldid -S"$ENTITLEMENTS" "$f" || echo "Warning: ldid failed on $f" >&2
    fi
  done < <(find "$PKGROOT" -type f)
else
  echo "Warning: ldid or entitlements.plist missing; skipping package-time signing" >&2
fi

# ------------------------------------------------------------------------------
# Debian control file
# ------------------------------------------------------------------------------

INSTALLED_SIZE="$(du -sk "$PKGROOT" | awk '{print $1}')"
CONTROL_IN="$REPO_ROOT/debian/control.in"

if [ -f "$CONTROL_IN" ]; then
  python3 - "$CONTROL_IN" "$PKGROOT/DEBIAN/control" "$PKG_VERSION" "$INSTALLED_SIZE" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
version = sys.argv[3]
installed_size = sys.argv[4]

s = src.read_text()
s = s.replace("${PY_VER}-1", version)
s = s.replace("${PY_VER}", version.rsplit("-", 1)[0])
s = s.replace("${INSTALLED_SIZE}", installed_size)

# Debian control files do not allow whitespace-only blank continuation lines
# inside multiline fields such as Description. Also ensure exactly one final newline.
lines = [line.rstrip() for line in s.splitlines()]
while lines and lines[-1].strip() == "":
    lines.pop()
s = "\n".join(lines) + "\n"

dst.write_text(s)
PY
else
  cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: $PKG_NAME
Name: Python 3.12 Rootless
Version: $PKG_VERSION
Section: Development
Priority: optional
Architecture: $PKG_ARCH
Maintainer: samuel2672
Installed-Size: $INSTALLED_SIZE
Depends: firmware (>= $MIN_IOS)
Description: Python 3.12 interpreter for rootless iOS jailbreaks.
 This package provides a Python 3.12 environment installed under /var/jb/usr/local.
 .
 Included:
 * Python 3.12 interpreter
 * Standard library
 * SSL support when _ssl is built
 * ctypes support when _ctypes is built
EOF
fi

chmod 0644 "$PKGROOT/DEBIAN/control"

echo "===== DEBIAN/control ====="
cat "$PKGROOT/DEBIAN/control"

# ------------------------------------------------------------------------------
# Build .deb
# ------------------------------------------------------------------------------

rm -f "$DEB_OUT"

if command -v fakeroot >/dev/null 2>&1; then
  fakeroot dpkg-deb --build --root-owner-group "$PKGROOT" "$DEB_OUT"
else
  dpkg-deb --build --root-owner-group "$PKGROOT" "$DEB_OUT"
fi

test -f "$DEB_OUT"

echo "===== Built package ====="
ls -lh "$DEB_OUT"

echo "===== Package content sanity check ====="
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/bin/python3.12'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/lib/python3.12/os.py'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/lib/python3.12/encodings/__init__.py'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/etc/profile.d/python3.sh'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/lib/python3.12/lib-dynload/_ctypes.'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/lib/python3.12/lib-dynload/_posixsubprocess.'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/lib/python3.12/lib-dynload/zlib.'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/lib/python3.12/lib-dynload/_bz2.'
dpkg-deb -c "$DEB_OUT" | grep -F './var/jb/usr/local/lib/python3.12/lib-dynload/_lzma.'

if dpkg-deb -c "$DEB_OUT" | grep -E '^\./usr/|^\./etc/'; then
  echo "ERROR: rootful path found in deb" >&2
  exit 1
fi

echo "Info: package completed successfully: $DEB_OUT"