#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-linux-release.sh <glibc|musl> <version> [output-dir]

Package an already-built weavec compiler as a static Linux x86-64 toolchain.
The archive exposes one public compiler command and carries its target runtime
as a private resource discovered automatically by `weavec build`.
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

LIBC="$1"
VERSION="$2"
OUTPUT_DIR="${3:-dist}"

case "$LIBC" in
  glibc)
    TARGET="x86_64-unknown-linux-gnu"
    LINKER="clang"
    RUNTIME_CC="clang"
    ;;
  musl)
    TARGET="x86_64-unknown-linux-musl"
    LINKER="musl-gcc"
    RUNTIME_CC="musl-gcc"
    ;;
  *)
    printf 'unsupported libc: %s\n' "$LIBC" >&2
    usage >&2
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_NAME="weavec-${VERSION}-linux-x86_64-${LIBC}"
RELEASE_BUILD="$ROOT/build/release/$LIBC"
PACKAGE_DIR="$RELEASE_BUILD/$PACKAGE_NAME"
ARCHIVE_DIR="$ROOT/$OUTPUT_DIR"
ARCHIVE="$ARCHIVE_DIR/$PACKAGE_NAME.tar.gz"

COMPILER_BC="$ROOT/build/weavec.bc"
COMPILER_OBJ="$RELEASE_BUILD/weavec.o"
PORTABLE_OBJ="$RELEASE_BUILD/portable.o"
RUNTIME_OBJ="$RELEASE_BUILD/program-runtime.o"
COMPILER="$PACKAGE_DIR/bin/weavec"
RUNTIME_DIR="$PACKAGE_DIR/lib/weavec/$TARGET"
RUNTIME_ARCHIVE="$RUNTIME_DIR/libweave-runtime.a"
FRONTEND_WIR="$RELEASE_BUILD/frontend-smoke.wir"
BACKEND_LL="$RELEASE_BUILD/backend-smoke.ll"
BACKEND_BC="$RELEASE_BUILD/backend-smoke.bc"
LEGACY_LL="$RELEASE_BUILD/legacy-implicit-backend.ll"
BUILD_BIN="$RELEASE_BUILD/build-smoke"
BUILD_MANIFEST="$RELEASE_BUILD/build-smoke.json"
STACK_SIZE="0x1000000"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'required tool not found: %s\n' "$1" >&2
    exit 1
  }
}

require_tool ar
require_tool clang
require_tool file
require_tool llvm-as
require_tool readelf
require_tool tar
if [[ "$LIBC" == musl ]]; then
  require_tool musl-gcc
fi

[[ -s "$COMPILER_BC" ]] || {
  printf 'missing compiler bitcode: %s\n' "$COMPILER_BC" >&2
  printf 'run ./build.sh first\n' >&2
  exit 1
}

rm -rf "$RELEASE_BUILD"
mkdir -p "$PACKAGE_DIR/bin" "$RUNTIME_DIR" "$ARCHIVE_DIR"

clang -Wno-override-module -O2 -c "$COMPILER_BC" -o "$COMPILER_OBJ"
"$RUNTIME_CC" -O2 -ffunction-sections -fdata-sections \
  -c "$ROOT/runtime/program.c" -o "$RUNTIME_OBJ"
ar rcs "$RUNTIME_ARCHIVE" "$RUNTIME_OBJ"

COMMON_DEFINES=(
  "-DWEAVEC_DEFAULT_TARGET=\"$TARGET\""
  "-DWEAVEC_DEFAULT_LINKER=\"$LINKER\""
)

case "$LIBC" in
  glibc)
    clang -O2 "${COMMON_DEFINES[@]}" \
      -c "$ROOT/runtime/portable.c" -o "$PORTABLE_OBJ"
    clang -static "$COMPILER_OBJ" "$PORTABLE_OBJ" \
      -Wl,-z,stack-size="$STACK_SIZE" \
      -o "$COMPILER"
    ;;
  musl)
    musl-gcc -O2 "${COMMON_DEFINES[@]}" \
      -c "$ROOT/runtime/portable.c" -o "$PORTABLE_OBJ"
    musl-gcc -static "$COMPILER_OBJ" "$PORTABLE_OBJ" \
      -Wl,-z,stack-size="$STACK_SIZE" \
      -o "$COMPILER"
    ;;
esac
chmod 0755 "$COMPILER"

if readelf -l "$COMPILER" | grep -q 'INTERP'; then
  printf 'compiler is dynamically linked: %s\n' "$COMPILER" >&2
  readelf -l "$COMPILER" >&2
  exit 1
fi

file "$COMPILER"
[[ -s "$RUNTIME_ARCHIVE" ]] || {
  printf 'private runtime archive is missing: %s\n' "$RUNTIME_ARCHIVE" >&2
  exit 1
}

# Low-level compiler interfaces remain available for bootstrap and debugging.
"$COMPILER" --frontend "$FRONTEND_WIR" \
  "$ROOT/test/correctness/surface/01_return_42.weave"
[[ -s "$FRONTEND_WIR" ]] || {
  printf 'frontend smoke produced no WIR\n' >&2
  exit 1
}

"$COMPILER" --backend "$FRONTEND_WIR" "$BACKEND_LL"
[[ -s "$BACKEND_LL" ]] || {
  printf 'backend smoke produced no LLVM IR\n' >&2
  exit 1
}
llvm-as "$BACKEND_LL" -o "$BACKEND_BC"

# The public contract must produce a native executable without exposing runtime
# selection or a linker command to the caller.
rm -f "$BUILD_BIN" "$BUILD_MANIFEST"
"$COMPILER" build \
  "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$BUILD_BIN" \
  --manifest-json "$BUILD_MANIFEST"
[[ -x "$BUILD_BIN" && -s "$BUILD_MANIFEST" ]] || {
  printf 'weavec build did not produce its executable and manifest\n' >&2
  exit 1
}
set +e
"$BUILD_BIN"
build_status="$?"
set -e
if [[ "$build_status" -ne 42 ]]; then
  printf 'built program returned %s instead of 42\n' "$build_status" >&2
  exit 1
fi
grep -F '"status": "succeeded"' "$BUILD_MANIFEST" >/dev/null
grep -F "\"target\": \"$TARGET\"" "$BUILD_MANIFEST" >/dev/null

rm -f "$LEGACY_LL"
set +e
"$COMPILER" "$FRONTEND_WIR" "$LEGACY_LL" >/dev/null 2>&1
legacy_status="$?"
set -e
if [[ "$legacy_status" -eq 0 || -e "$LEGACY_LL" ]]; then
  printf 'implicit backend compatibility syntax is still accepted\n' >&2
  exit 1
fi

cat > "$PACKAGE_DIR/BUILD-MANIFEST" <<EOF
name=weavec
version=$VERSION
platform=linux-x86_64
libc=$LIBC
target=$TARGET
compiler=bin/weavec
runtime=lib/weavec/$TARGET/libweave-runtime.a
weavec1_version=${WEAVEC1_VERSION:-v0.2.0}
weavec_bootstrap_version=${WEAVEC_BOOTSTRAP_VERSION:-v0.2.0}
source_commit=${GITHUB_SHA:-unknown}
compiler_linkage=static
runtime_visibility=private
EOF

printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"
cp "$ROOT/README.md" "$PACKAGE_DIR/"
[[ -f "$ROOT/LICENSE" ]] && cp "$ROOT/LICENSE" "$PACKAGE_DIR/"
[[ -f "$ROOT/NOTICE" ]] && cp "$ROOT/NOTICE" "$PACKAGE_DIR/"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$COMPILER"
fi

# Re-run both low-level and public commands after stripping so the archived
# compiler and its relative runtime discovery are tested exactly as shipped.
"$COMPILER" --backend "$FRONTEND_WIR" "$BACKEND_LL"
llvm-as "$BACKEND_LL" -o "$BACKEND_BC"
rm -f "$BUILD_BIN"
"$COMPILER" build \
  "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$BUILD_BIN"
set +e
"$BUILD_BIN"
build_status="$?"
set -e
[[ "$build_status" -eq 42 ]] || {
  printf 'stripped package build smoke returned %s instead of 42\n' "$build_status" >&2
  exit 1
}

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
