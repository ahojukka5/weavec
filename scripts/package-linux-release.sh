#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/package-linux-release.sh <glibc|musl> <version> [output-dir]

Package an already-built weavec compiler and its private program runtime as a
static Linux x86-64 release. Run ./build.sh and ./test-all.sh first with matching
SDK libc selections.
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
  glibc|musl) ;;
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
PROGRAM_RUNTIME_OBJ="$RELEASE_BUILD/program_runtime.o"
COMPILER="$PACKAGE_DIR/bin/weavec"
RUNTIME_DIR="$PACKAGE_DIR/lib/weavec"
RUNTIME_ARCHIVE="$RUNTIME_DIR/libweave-runtime.a"
FRONTEND_WIR="$RELEASE_BUILD/frontend-smoke.wir"
BACKEND_LL="$RELEASE_BUILD/backend-smoke.ll"
BACKEND_BC="$RELEASE_BUILD/backend-smoke.bc"
BUILD_SMOKE="$RELEASE_BUILD/build-smoke"
LEGACY_LL="$RELEASE_BUILD/legacy-implicit-backend.ll"
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
case "$LIBC" in
  glibc)
    clang -O2 -DWEAVEC_DEFAULT_CC='"clang"' \
      -c "$ROOT/runtime/portable.c" -o "$PORTABLE_OBJ"
    clang -O2 -ffunction-sections -fdata-sections \
      -c "$ROOT/runtime/program_runtime.c" -o "$PROGRAM_RUNTIME_OBJ"
    clang -static "$COMPILER_OBJ" "$PORTABLE_OBJ" \
      -Wl,-z,stack-size="$STACK_SIZE" \
      -o "$COMPILER"
    ;;
  musl)
    musl-gcc -O2 -DWEAVEC_DEFAULT_CC='"musl-gcc"' \
      -c "$ROOT/runtime/portable.c" -o "$PORTABLE_OBJ"
    musl-gcc -O2 -ffunction-sections -fdata-sections \
      -c "$ROOT/runtime/program_runtime.c" -o "$PROGRAM_RUNTIME_OBJ"
    musl-gcc -static "$COMPILER_OBJ" "$PORTABLE_OBJ" \
      -Wl,-z,stack-size="$STACK_SIZE" \
      -o "$COMPILER"
    ;;
esac
ar rcs "$RUNTIME_ARCHIVE" "$PROGRAM_RUNTIME_OBJ"
chmod 0755 "$COMPILER"
chmod 0644 "$RUNTIME_ARCHIVE"

if readelf -l "$COMPILER" | grep -q 'INTERP'; then
  printf 'compiler is dynamically linked: %s\n' "$COMPILER" >&2
  readelf -l "$COMPILER" >&2
  exit 1
fi

file "$COMPILER"
file "$RUNTIME_ARCHIVE"

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

rm -f "$BUILD_SMOKE"
"$COMPILER" build "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$BUILD_SMOKE"
[[ -x "$BUILD_SMOKE" ]] || {
  printf 'build command produced no executable\n' >&2
  exit 1
}
set +e
"$BUILD_SMOKE"
build_status="$?"
set -e
if [[ "$build_status" -ne 42 ]]; then
  printf 'build smoke expected exit 42, got %s\n' "$build_status" >&2
  exit 1
fi

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
compiler=bin/weavec
runtime=lib/weavec/libweave-runtime.a
runtime_visibility=private
build_command=weavec build INPUT -o OUTPUT
weavec1_version=${WEAVEC1_VERSION:-v0.2.0}
weavec_bootstrap_version=${WEAVEC_BOOTSTRAP_VERSION:-v0.2.0}
source_commit=${GITHUB_SHA:-unknown}
linkage=static
EOF

printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"
cp "$ROOT/README.md" "$PACKAGE_DIR/"
[[ -f "$ROOT/LICENSE" ]] && cp "$ROOT/LICENSE" "$PACKAGE_DIR/"
[[ -f "$ROOT/NOTICE" ]] && cp "$ROOT/NOTICE" "$PACKAGE_DIR/"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$COMPILER"
  strip --strip-unneeded "$PROGRAM_RUNTIME_OBJ" 2>/dev/null || true
  ar rcs "$RUNTIME_ARCHIVE" "$PROGRAM_RUNTIME_OBJ"
fi

# Re-run the public command after stripping so archived artifacts are tested.
rm -f "$BUILD_SMOKE"
"$COMPILER" build "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$BUILD_SMOKE"
set +e
"$BUILD_SMOKE"
build_status="$?"
set -e
[[ "$build_status" -eq 42 ]] || {
  printf 'stripped build smoke expected exit 42, got %s\n' "$build_status" >&2
  exit 1
}

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
