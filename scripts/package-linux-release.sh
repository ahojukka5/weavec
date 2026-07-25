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
BUILD_DIAGNOSTICS="$RELEASE_BUILD/build-smoke.diagnostics.json"
FRONTEND_FAILURE_SOURCE="$RELEASE_BUILD/frontend-failure.weave"
FRONTEND_FAILURE_BIN="$RELEASE_BUILD/frontend-failure"
FRONTEND_FAILURE_DIAGNOSTICS="$RELEASE_BUILD/frontend-failure.diagnostics.json"
BACKEND_FAILURE_SOURCE="$RELEASE_BUILD/backend-failure.weave"
BACKEND_FAILURE_BIN="$RELEASE_BUILD/backend-failure"
BACKEND_FAILURE_DIAGNOSTICS="$RELEASE_BUILD/backend-failure.diagnostics.json"
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
require_tool python3
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
# selection or a linker command to the caller. It must also produce the stable
# manifest and diagnostics protocols from the exact packaged compiler.
rm -f "$BUILD_BIN" "$BUILD_MANIFEST" "$BUILD_DIAGNOSTICS"
"$COMPILER" build \
  "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$BUILD_BIN" \
  --manifest-json "$BUILD_MANIFEST" \
  --diagnostics-json "$BUILD_DIAGNOSTICS"
[[ -x "$BUILD_BIN" && -s "$BUILD_MANIFEST" && -s "$BUILD_DIAGNOSTICS" ]] || {
  printf 'weavec build did not produce its executable, manifest, and diagnostics\n' >&2
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

cat > "$FRONTEND_FAILURE_SOURCE" <<'EOF'
(program
  (name "release-frontend-failure")
EOF
rm -f "$FRONTEND_FAILURE_BIN" "$FRONTEND_FAILURE_DIAGNOSTICS"
set +e
"$COMPILER" build "$FRONTEND_FAILURE_SOURCE" \
  -o "$FRONTEND_FAILURE_BIN" \
  --diagnostics-json "$FRONTEND_FAILURE_DIAGNOSTICS" \
  >/dev/null 2>&1
frontend_failure_status="$?"
set -e
if [[ "$frontend_failure_status" -ne 10 || -e "$FRONTEND_FAILURE_BIN" ]]; then
  printf 'frontend failure contract was not preserved (status=%s)\n' \
    "$frontend_failure_status" >&2
  exit 1
fi

cat > "$BACKEND_FAILURE_SOURCE" <<'EOF'
(program
  (name "release-backend-failure")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (unknown_form 0)))))
EOF
rm -f "$BACKEND_FAILURE_BIN" "$BACKEND_FAILURE_DIAGNOSTICS"
set +e
"$COMPILER" build "$BACKEND_FAILURE_SOURCE" \
  -o "$BACKEND_FAILURE_BIN" \
  --diagnostics-json "$BACKEND_FAILURE_DIAGNOSTICS" \
  >/dev/null 2>&1
backend_failure_status="$?"
set -e
if [[ "$backend_failure_status" -ne 11 || -e "$BACKEND_FAILURE_BIN" ]]; then
  printf 'backend failure contract was not preserved (status=%s)\n' \
    "$backend_failure_status" >&2
  exit 1
fi

python3 - \
  "$BUILD_DIAGNOSTICS" \
  "$FRONTEND_FAILURE_SOURCE" "$FRONTEND_FAILURE_DIAGNOSTICS" \
  "$BACKEND_FAILURE_SOURCE" "$BACKEND_FAILURE_DIAGNOSTICS" <<'PY'
import json
import pathlib
import sys

(
    success_path,
    frontend_source_path,
    frontend_diagnostics_path,
    backend_source_path,
    backend_diagnostics_path,
) = map(pathlib.Path, sys.argv[1:])

success = json.loads(success_path.read_text(encoding="utf-8"))
assert success == {
    "format": "weavec-diagnostics-v1",
    "status": "succeeded",
    "phase": "complete",
    "exit_code": 0,
    "raw_exit_code": 0,
    "diagnostics": [],
}

frontend = json.loads(frontend_diagnostics_path.read_text(encoding="utf-8"))
assert frontend["format"] == "weavec-diagnostics-v1"
assert frontend["status"] == "failed"
assert frontend["phase"] == "frontend"
assert frontend["exit_code"] == 10
frontend_entry = frontend["diagnostics"][0]
assert frontend_entry["code"] == "frontend.parse.unclosed-list"
assert frontend_entry["span_origin"] == "compiler-preflight"
assert frontend_entry["span"]["start_byte"] == 0
assert frontend_entry["span"]["end_byte"] == 1
assert frontend_source_path.read_bytes()[0:1] == b"("

backend = json.loads(backend_diagnostics_path.read_text(encoding="utf-8"))
assert backend["format"] == "weavec-diagnostics-v1"
assert backend["status"] == "failed"
assert backend["phase"] == "backend"
assert backend["exit_code"] == 11
backend_entry = backend["diagnostics"][0]
assert backend_entry["code"] == "backend.unknown-expression-operator"
assert backend_entry["message"] == "unknown expression operator: unknown_form"
assert backend_entry["span_origin"] == "inferred-unique-token"
span = backend_entry["span"]
assert span is not None
source = backend_source_path.read_bytes()
assert source[span["start_byte"] : span["end_byte"]] == b"unknown_form"
PY

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
build_manifest_format=weavec-build-manifest-v1
diagnostics_format=weavec-diagnostics-v1
EOF

printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"
cp "$ROOT/README.md" "$PACKAGE_DIR/"
[[ -f "$ROOT/LICENSE" ]] && cp "$ROOT/LICENSE" "$PACKAGE_DIR/"
[[ -f "$ROOT/NOTICE" ]] && cp "$ROOT/NOTICE" "$PACKAGE_DIR/"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$COMPILER"
fi

# Re-run low-level and public commands after stripping so the compiler and its
# relative runtime discovery are tested exactly as archived.
"$COMPILER" --backend "$FRONTEND_WIR" "$BACKEND_LL"
llvm-as "$BACKEND_LL" -o "$BACKEND_BC"
rm -f "$BUILD_BIN" "$BUILD_DIAGNOSTICS"
"$COMPILER" build \
  "$ROOT/test/correctness/surface/01_return_42.weave" \
  -o "$BUILD_BIN" \
  --diagnostics-json "$BUILD_DIAGNOSTICS"
set +e
"$BUILD_BIN"
build_status="$?"
set -e
[[ "$build_status" -eq 42 ]] || {
  printf 'stripped package build smoke returned %s instead of 42\n' "$build_status" >&2
  exit 1
}
python3 - "$BUILD_DIAGNOSTICS" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-diagnostics-v1"
assert document["status"] == "succeeded"
assert document["exit_code"] == 0
assert document["diagnostics"] == []
PY

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"
printf '%s\n' "$ARCHIVE"
