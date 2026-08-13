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
FORMATTER_OBJ="$RELEASE_BUILD/formatter_driver.o"
RUNTIME_OBJ="$RELEASE_BUILD/program-runtime.o"
COMPILER="$PACKAGE_DIR/bin/weavec"
RUNTIME_DIR="$PACKAGE_DIR/lib/weavec/$TARGET"
RUNTIME_ARCHIVE="$RUNTIME_DIR/libweave-runtime.a"
FRONTEND_WIR="$RELEASE_BUILD/frontend-smoke.wir"
BACKEND_LL="$RELEASE_BUILD/backend-smoke.ll"
BACKEND_BC="$RELEASE_BUILD/backend-smoke.bc"
LEGACY_LL="$RELEASE_BUILD/legacy-implicit-backend.ll"
BUILD_SOURCE="$RELEASE_BUILD/build-smoke.weave"
BUILD_BIN="$RELEASE_BUILD/build-smoke"
BUILD_MANIFEST="$RELEASE_BUILD/build-smoke.json"
BUILD_DIAGNOSTICS="$RELEASE_BUILD/build-smoke.diagnostics.json"
BUILD_TRACE="$RELEASE_BUILD/build-smoke.trace.json"
BUILD_RAW_LL="$RELEASE_BUILD/build-smoke.raw.ll"
BUILD_OPT_LL="$RELEASE_BUILD/build-smoke.optimized.ll"
BUILD_ASSEMBLY="$RELEASE_BUILD/build-smoke.s"
BUILD_DISASSEMBLY="$RELEASE_BUILD/build-smoke.disasm"
BUILD_OPT_RECORD="$RELEASE_BUILD/build-smoke.opt.yaml"
PROVENANCE_BIN="$RELEASE_BUILD/provenance-smoke"
PROVENANCE_STDERR="$RELEASE_BUILD/provenance-smoke.stderr"
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
require_tool llc
require_tool llvm-objdump
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

# Public Weave source libraries and runnable examples are part of the toolchain
# package. Keeping their repository-relative layout makes documented build
# commands work unchanged from the extracted package root.
cp -R "$ROOT/stdlib" "$PACKAGE_DIR/stdlib"
cp -R "$ROOT/examples" "$PACKAGE_DIR/examples"

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
    clang -O2 -c "$ROOT/runtime/formatter_driver.c" -o "$FORMATTER_OBJ"
    clang -static "$COMPILER_OBJ" "$PORTABLE_OBJ" "$FORMATTER_OBJ" \
      -Wl,-z,stack-size="$STACK_SIZE" \
      -o "$COMPILER"
    ;;
  musl)
    musl-gcc -O2 "${COMMON_DEFINES[@]}" \
      -c "$ROOT/runtime/portable.c" -o "$PORTABLE_OBJ"
    musl-gcc -O2 -c "$ROOT/runtime/formatter_driver.c" -o "$FORMATTER_OBJ"
    musl-gcc -static "$COMPILER_OBJ" "$PORTABLE_OBJ" "$FORMATTER_OBJ" \
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
# manifest, diagnostics, and compilation-trace protocols from the exact
# packaged compiler. The typed integer sugar guarantees one trace event.
cat > "$BUILD_SOURCE" <<'EOF'
(program
  (name "release-build-smoke")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let answer i32 42)
      (return (local_get answer)))))
EOF
rm -f "$BUILD_BIN" "$BUILD_MANIFEST" "$BUILD_DIAGNOSTICS" "$BUILD_TRACE" \
  "$BUILD_RAW_LL" "$BUILD_OPT_LL" "$BUILD_ASSEMBLY" \
  "$BUILD_DISASSEMBLY" "$BUILD_OPT_RECORD"
"$COMPILER" build \
  "$BUILD_SOURCE" \
  -o "$BUILD_BIN" \
  --manifest-json "$BUILD_MANIFEST" \
  --diagnostics-json "$BUILD_DIAGNOSTICS" \
  --trace-json "$BUILD_TRACE" \
  --emit-llvm "$BUILD_RAW_LL" \
  --emit-optimized-llvm "$BUILD_OPT_LL" \
  --emit-assembly "$BUILD_ASSEMBLY" \
  --emit-disassembly "$BUILD_DISASSEMBLY" \
  --optimization-record "$BUILD_OPT_RECORD"
[[ -x "$BUILD_BIN" && -s "$BUILD_MANIFEST" && -s "$BUILD_DIAGNOSTICS" && \
   -s "$BUILD_TRACE" && -s "$BUILD_RAW_LL" && -s "$BUILD_OPT_LL" && \
   -s "$BUILD_ASSEMBLY" && -s "$BUILD_DISASSEMBLY" && \
   -s "$BUILD_OPT_RECORD" ]] || {
  printf 'weavec build did not produce all requested automation outputs\n' >&2
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
python3 - "$BUILD_MANIFEST" "$TARGET" <<'PY_MANIFEST'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["format"] == "weavec-build-manifest-v1"
assert manifest["status"] == "succeeded"
assert manifest["phase"] == "complete"
assert manifest["target"] == sys.argv[2]
assert manifest["optimization"] == {
    "level": "O2",
    "cpu": None,
    "tune_cpu": None,
}
PY_MANIFEST
llvm-as "$BUILD_RAW_LL" -o "$RELEASE_BUILD/build-smoke.raw.bc"
llvm-as "$BUILD_OPT_LL" -o "$RELEASE_BUILD/build-smoke.optimized.bc"
grep -Eq '<_?main>:' "$BUILD_DISASSEMBLY"

rm -f "$PROVENANCE_BIN" "$PROVENANCE_STDERR"
"$COMPILER" build "$BUILD_SOURCE" -o "$PROVENANCE_BIN" \
  --llvm-provenance 2>"$PROVENANCE_STDERR"
PROVENANCE_DIR="$(sed -n \
  's/^weavec: kept temporary build directory: //p' \
  "$PROVENANCE_STDERR" | tail -1)"
[[ -n "$PROVENANCE_DIR" && -s "$PROVENANCE_DIR/program.ll" ]] || {
  printf 'packaged compiler did not retain provenance LLVM\n' >&2
  exit 1
}
grep -q '^; weave.source kind=function index=0 ' "$PROVENANCE_DIR/program.ll"
grep -q '^; weave.source kind=statement index=0 ' "$PROVENANCE_DIR/program.ll"
llvm-as "$PROVENANCE_DIR/program.ll" -o "$RELEASE_BUILD/provenance-smoke.bc"
rm -rf "$PROVENANCE_DIR"

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
  "$BUILD_DIAGNOSTICS" "$BUILD_SOURCE" "$BUILD_TRACE" \
  "$FRONTEND_FAILURE_SOURCE" "$FRONTEND_FAILURE_DIAGNOSTICS" \
  "$BACKEND_FAILURE_SOURCE" "$BACKEND_FAILURE_DIAGNOSTICS" <<'PY'
import json
import pathlib
import sys

(
    success_path,
    build_source_path,
    build_trace_path,
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

trace = json.loads(build_trace_path.read_text(encoding="utf-8"))
assert trace["format"] == "weavec-compilation-trace-v1"
assert trace["status"] == "succeeded"
assert trace["phase"] == "complete"
assert trace["sources"] == [str(build_source_path)]
events = [
    event for event in trace["events"]
    if event["action"] == "wrap-typed-integer"
]
assert len(events) == 1
assert events[0]["surface"] == "42"
assert events[0]["detail"] == "i32"

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
assert backend_entry["span_origin"] == "propagated-wir-location"
assert pathlib.Path(backend_entry["source"]) == backend_source_path
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
stdlib=stdlib
examples=examples
weavec1_version=${WEAVEC1_VERSION:-v0.3.2}
weavec_bootstrap_version=${WEAVEC_BOOTSTRAP_VERSION:-v0.3.1}
source_commit=${GITHUB_SHA:-unknown}
compiler_linkage=static
runtime_visibility=private
build_manifest_format=weavec-build-manifest-v1
diagnostics_format=weavec-diagnostics-v1
compilation_trace_format=weavec-compilation-trace-v1
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
rm -f "$BUILD_BIN" "$BUILD_DIAGNOSTICS" "$BUILD_TRACE"
"$COMPILER" build \
  "$BUILD_SOURCE" \
  -o "$BUILD_BIN" \
  --diagnostics-json "$BUILD_DIAGNOSTICS" \
  --trace-json "$BUILD_TRACE"
set +e
"$BUILD_BIN"
build_status="$?"
set -e
[[ "$build_status" -eq 42 ]] || {
  printf 'stripped package build smoke returned %s instead of 42\n' "$build_status" >&2
  exit 1
}
python3 - "$BUILD_DIAGNOSTICS" "$BUILD_TRACE" <<'PY'
import json
import pathlib
import sys

document = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert document["format"] == "weavec-diagnostics-v1"
assert document["status"] == "succeeded"
assert document["exit_code"] == 0
assert document["diagnostics"] == []

trace = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert trace["format"] == "weavec-compilation-trace-v1"
assert trace["status"] == "succeeded"
assert any(event["action"] == "wrap-typed-integer" for event in trace["events"])
PY

rm -f "$PROVENANCE_BIN" "$PROVENANCE_STDERR"
"$COMPILER" build "$BUILD_SOURCE" -o "$PROVENANCE_BIN" \
  --llvm-provenance 2>"$PROVENANCE_STDERR"
PROVENANCE_DIR="$(sed -n \
  's/^weavec: kept temporary build directory: //p' \
  "$PROVENANCE_STDERR" | tail -1)"
[[ -n "$PROVENANCE_DIR" && -s "$PROVENANCE_DIR/program.ll" ]]
grep -q '^; weave.source kind=function index=0 ' "$PROVENANCE_DIR/program.ll"
llvm-as "$PROVENANCE_DIR/program.ll" -o "$RELEASE_BUILD/provenance-stripped.bc"
rm -rf "$PROVENANCE_DIR"

rm -f "$ARCHIVE"
tar -C "$RELEASE_BUILD" -czf "$ARCHIVE" "$PACKAGE_NAME"

# Exercise a real user-facing program from a freshly extracted copy of the
# archive. This catches packages that contain the compiler/runtime but omit
# public Weave source dependencies such as stdlib modules.
EXTRACTED_SMOKE="$RELEASE_BUILD/extracted-package-smoke"
EXTRACTED_PACKAGE="$EXTRACTED_SMOKE/$PACKAGE_NAME"
EXTRACTED_FLOAT_BIN="$EXTRACTED_SMOKE/float-arithmetic"
EXTRACTED_FLOAT_OUT="$EXTRACTED_SMOKE/float-arithmetic.stdout"
EXTRACTED_FLOAT_ERR="$EXTRACTED_SMOKE/float-arithmetic.stderr"
EXTRACTED_FLOAT_EXPECTED="$EXTRACTED_SMOKE/float-arithmetic.expected"
rm -rf "$EXTRACTED_SMOKE"
mkdir -p "$EXTRACTED_SMOKE"
tar -C "$EXTRACTED_SMOKE" -xzf "$ARCHIVE"
[[ -x "$EXTRACTED_PACKAGE/bin/weavec" ]]
[[ -s "$EXTRACTED_PACKAGE/stdlib/io.weave" ]]
[[ -s "$EXTRACTED_PACKAGE/examples/float-arithmetic/main.weave" ]]
cat > "$EXTRACTED_FLOAT_EXPECTED" <<'EOF_FLOAT'
1.5 + 2.25 = 3.75
7.0 / 2.0 = 3.5
2.5 * 4.0 - 1.0 = 9.0
EOF_FLOAT
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/examples/float-arithmetic/main.weave" \
  -o "$EXTRACTED_FLOAT_BIN"
set +e
LC_ALL=C "$EXTRACTED_FLOAT_BIN" >"$EXTRACTED_FLOAT_OUT" 2>"$EXTRACTED_FLOAT_ERR"
extracted_float_status="$?"
set -e
if [[ "$extracted_float_status" -ne 0 || -s "$EXTRACTED_FLOAT_ERR" ]]; then
  printf 'extracted float example failed (status=%s)\n' \
    "$extracted_float_status" >&2
  cat "$EXTRACTED_FLOAT_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_FLOAT_EXPECTED" "$EXTRACTED_FLOAT_OUT" || {
  printf 'extracted float example stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_PYTHAGORAS_BIN="$EXTRACTED_SMOKE/pythagoras"
EXTRACTED_PYTHAGORAS_OUT="$EXTRACTED_SMOKE/pythagoras.stdout"
EXTRACTED_PYTHAGORAS_ERR="$EXTRACTED_SMOKE/pythagoras.stderr"
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/process.weave" \
  "$EXTRACTED_PACKAGE/stdlib/parse.weave" \
  "$EXTRACTED_PACKAGE/stdlib/math.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/examples/pythagoras/main.weave" \
  -o "$EXTRACTED_PYTHAGORAS_BIN"
set +e
LC_ALL=C "$EXTRACTED_PYTHAGORAS_BIN" 3 4 \
  >"$EXTRACTED_PYTHAGORAS_OUT" 2>"$EXTRACTED_PYTHAGORAS_ERR"
extracted_pythagoras_status="$?"
set -e
if [[ "$extracted_pythagoras_status" -ne 0 || -s "$EXTRACTED_PYTHAGORAS_ERR" ]]; then
  printf 'extracted Pythagoras example failed (status=%s)\n' \
    "$extracted_pythagoras_status" >&2
  cat "$EXTRACTED_PYTHAGORAS_ERR" >&2
  exit 1
fi
printf '5.0\n' > "$EXTRACTED_SMOKE/pythagoras.expected"
cmp "$EXTRACTED_SMOKE/pythagoras.expected" "$EXTRACTED_PYTHAGORAS_OUT" || {
  printf 'extracted Pythagoras example stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_TRIG_BIN="$EXTRACTED_SMOKE/trigonometry-table"
EXTRACTED_TRIG_OUT="$EXTRACTED_SMOKE/trigonometry-table.stdout"
EXTRACTED_TRIG_ERR="$EXTRACTED_SMOKE/trigonometry-table.stderr"
EXTRACTED_TRIG_EXPECTED="$EXTRACTED_SMOKE/trigonometry-table.expected"
cat > "$EXTRACTED_TRIG_EXPECTED" <<'EOF_TRIG'
angle  sin       cos       tan
0      0.000000  1.000000  0.000000
30     0.500000  0.866025  0.577350
45     0.707107  0.707107  1.000000
60     0.866025  0.500000  1.732051
EOF_TRIG
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/math.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/examples/trigonometry-table/main.weave" \
  -o "$EXTRACTED_TRIG_BIN"
set +e
LC_ALL=C "$EXTRACTED_TRIG_BIN" >"$EXTRACTED_TRIG_OUT" 2>"$EXTRACTED_TRIG_ERR"
extracted_trig_status="$?"
set -e
if [[ "$extracted_trig_status" -ne 0 || -s "$EXTRACTED_TRIG_ERR" ]]; then
  printf 'extracted trigonometry table failed (status=%s)\n' \
    "$extracted_trig_status" >&2
  cat "$EXTRACTED_TRIG_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_TRIG_EXPECTED" "$EXTRACTED_TRIG_OUT" || {
  printf 'extracted trigonometry table stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_DOT_BIN="$EXTRACTED_SMOKE/vector-dot"
EXTRACTED_DOT_OUT="$EXTRACTED_SMOKE/vector-dot.stdout"
EXTRACTED_DOT_ERR="$EXTRACTED_SMOKE/vector-dot.stderr"
EXTRACTED_DOT_EXPECTED="$EXTRACTED_SMOKE/vector-dot.expected"
printf '32.0\n' > "$EXTRACTED_DOT_EXPECTED"
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/process.weave" \
  "$EXTRACTED_PACKAGE/stdlib/parse.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/stdlib/vector.weave" \
  "$EXTRACTED_PACKAGE/examples/vector-dot/main.weave" \
  -o "$EXTRACTED_DOT_BIN"
set +e
LC_ALL=C "$EXTRACTED_DOT_BIN" 1 2 3 4 5 6 \
  >"$EXTRACTED_DOT_OUT" 2>"$EXTRACTED_DOT_ERR"
extracted_dot_status="$?"
set -e
if [[ "$extracted_dot_status" -ne 0 || -s "$EXTRACTED_DOT_ERR" ]]; then
  printf 'extracted vector dot product failed (status=%s)\n' \
    "$extracted_dot_status" >&2
  cat "$EXTRACTED_DOT_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_DOT_EXPECTED" "$EXTRACTED_DOT_OUT" || {
  printf 'extracted vector dot product stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_GEOMETRY_BIN="$EXTRACTED_SMOKE/vector-geometry"
EXTRACTED_GEOMETRY_OUT="$EXTRACTED_SMOKE/vector-geometry.stdout"
EXTRACTED_GEOMETRY_ERR="$EXTRACTED_SMOKE/vector-geometry.stderr"
EXTRACTED_GEOMETRY_EXPECTED="$EXTRACTED_SMOKE/vector-geometry.expected"
cat > "$EXTRACTED_GEOMETRY_EXPECTED" <<'EOF_GEOMETRY'
length-a = 1.0
length-b = 1.0
angle-degrees = 90.0
EOF_GEOMETRY
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/process.weave" \
  "$EXTRACTED_PACKAGE/stdlib/parse.weave" \
  "$EXTRACTED_PACKAGE/stdlib/math.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/stdlib/vector.weave" \
  "$EXTRACTED_PACKAGE/examples/vector-geometry/main.weave" \
  -o "$EXTRACTED_GEOMETRY_BIN"
set +e
LC_ALL=C "$EXTRACTED_GEOMETRY_BIN" 1 0 0 0 1 0 \
  >"$EXTRACTED_GEOMETRY_OUT" 2>"$EXTRACTED_GEOMETRY_ERR"
extracted_geometry_status="$?"
set -e
if [[ "$extracted_geometry_status" -ne 0 || -s "$EXTRACTED_GEOMETRY_ERR" ]]; then
  printf 'extracted vector geometry failed (status=%s)\n' \
    "$extracted_geometry_status" >&2
  cat "$EXTRACTED_GEOMETRY_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_GEOMETRY_EXPECTED" "$EXTRACTED_GEOMETRY_OUT" || {
  printf 'extracted vector geometry stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_MATRIX_BIN="$EXTRACTED_SMOKE/matrix-vector"
EXTRACTED_MATRIX_OUT="$EXTRACTED_SMOKE/matrix-vector.stdout"
EXTRACTED_MATRIX_ERR="$EXTRACTED_SMOKE/matrix-vector.stderr"
EXTRACTED_MATRIX_EXPECTED="$EXTRACTED_SMOKE/matrix-vector.expected"
printf 'result = [14.0, 32.0, 50.0]\n' > "$EXTRACTED_MATRIX_EXPECTED"
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/process.weave" \
  "$EXTRACTED_PACKAGE/stdlib/parse.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/stdlib/vector.weave" \
  "$EXTRACTED_PACKAGE/stdlib/matrix.weave" \
  "$EXTRACTED_PACKAGE/examples/matrix-vector/main.weave" \
  -o "$EXTRACTED_MATRIX_BIN"
set +e
LC_ALL=C "$EXTRACTED_MATRIX_BIN" \
  >"$EXTRACTED_MATRIX_OUT" 2>"$EXTRACTED_MATRIX_ERR"
extracted_matrix_status="$?"
set -e
if [[ "$extracted_matrix_status" -ne 0 || -s "$EXTRACTED_MATRIX_ERR" ]]; then
  printf 'extracted matrix-vector failed (status=%s)\n' \
    "$extracted_matrix_status" >&2
  cat "$EXTRACTED_MATRIX_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_MATRIX_EXPECTED" "$EXTRACTED_MATRIX_OUT" || {
  printf 'extracted matrix-vector stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_STATS_BIN="$EXTRACTED_SMOKE/statistics"
EXTRACTED_STATS_OUT="$EXTRACTED_SMOKE/statistics.stdout"
EXTRACTED_STATS_ERR="$EXTRACTED_SMOKE/statistics.stderr"
EXTRACTED_STATS_EXPECTED="$EXTRACTED_SMOKE/statistics.expected"
cat > "$EXTRACTED_STATS_EXPECTED" <<'EOF_STATS'
count = 4
mean = 2.5
variance = 1.25
stddev = 1.118034
EOF_STATS
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/process.weave" \
  "$EXTRACTED_PACKAGE/stdlib/parse.weave" \
  "$EXTRACTED_PACKAGE/stdlib/math.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/examples/statistics/main.weave" \
  -o "$EXTRACTED_STATS_BIN"
set +e
LC_ALL=C "$EXTRACTED_STATS_BIN" 1 2 3 4 \
  >"$EXTRACTED_STATS_OUT" 2>"$EXTRACTED_STATS_ERR"
extracted_stats_status="$?"
set -e
if [[ "$extracted_stats_status" -ne 0 || -s "$EXTRACTED_STATS_ERR" ]]; then
  printf 'extracted statistics failed (status=%s)\n' \
    "$extracted_stats_status" >&2
  cat "$EXTRACTED_STATS_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_STATS_EXPECTED" "$EXTRACTED_STATS_OUT" || {
  printf 'extracted statistics stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_QUADRATIC_BIN="$EXTRACTED_SMOKE/quadratic"
EXTRACTED_QUADRATIC_OUT="$EXTRACTED_SMOKE/quadratic.stdout"
EXTRACTED_QUADRATIC_ERR="$EXTRACTED_SMOKE/quadratic.stderr"
EXTRACTED_QUADRATIC_EXPECTED="$EXTRACTED_SMOKE/quadratic.expected"
printf 'roots = 1.0, 2.0\n' > "$EXTRACTED_QUADRATIC_EXPECTED"
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/process.weave" \
  "$EXTRACTED_PACKAGE/stdlib/parse.weave" \
  "$EXTRACTED_PACKAGE/stdlib/math.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/examples/quadratic/main.weave" \
  -o "$EXTRACTED_QUADRATIC_BIN"
set +e
LC_ALL=C "$EXTRACTED_QUADRATIC_BIN" 1 -3 2 \
  >"$EXTRACTED_QUADRATIC_OUT" 2>"$EXTRACTED_QUADRATIC_ERR"
extracted_quadratic_status="$?"
set -e
if [[ "$extracted_quadratic_status" -ne 0 || -s "$EXTRACTED_QUADRATIC_ERR" ]]; then
  printf 'extracted quadratic failed (status=%s)\n' \
    "$extracted_quadratic_status" >&2
  cat "$EXTRACTED_QUADRATIC_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_QUADRATIC_EXPECTED" "$EXTRACTED_QUADRATIC_OUT" || {
  printf 'extracted quadratic stdout mismatch\n' >&2
  exit 1
}

EXTRACTED_PROJECTILE_BIN="$EXTRACTED_SMOKE/projectile-motion"
EXTRACTED_PROJECTILE_OUT="$EXTRACTED_SMOKE/projectile-motion.stdout"
EXTRACTED_PROJECTILE_ERR="$EXTRACTED_SMOKE/projectile-motion.stderr"
EXTRACTED_PROJECTILE_EXPECTED="$EXTRACTED_SMOKE/projectile-motion.expected"
cat > "$EXTRACTED_PROJECTILE_EXPECTED" <<'EOF_PROJECTILE'
flight-time = 2.883208
max-height = 10.193680
range = 40.774720
EOF_PROJECTILE
"$EXTRACTED_PACKAGE/bin/weavec" build \
  "$EXTRACTED_PACKAGE/stdlib/process.weave" \
  "$EXTRACTED_PACKAGE/stdlib/parse.weave" \
  "$EXTRACTED_PACKAGE/stdlib/math.weave" \
  "$EXTRACTED_PACKAGE/stdlib/io.weave" \
  "$EXTRACTED_PACKAGE/examples/projectile-motion/main.weave" \
  -o "$EXTRACTED_PROJECTILE_BIN"
set +e
LC_ALL=C "$EXTRACTED_PROJECTILE_BIN" 20 45 \
  >"$EXTRACTED_PROJECTILE_OUT" 2>"$EXTRACTED_PROJECTILE_ERR"
extracted_projectile_status="$?"
set -e
if [[ "$extracted_projectile_status" -ne 0 || -s "$EXTRACTED_PROJECTILE_ERR" ]]; then
  printf 'extracted projectile motion failed (status=%s)\n' \
    "$extracted_projectile_status" >&2
  cat "$EXTRACTED_PROJECTILE_ERR" >&2
  exit 1
fi
cmp "$EXTRACTED_PROJECTILE_EXPECTED" "$EXTRACTED_PROJECTILE_OUT" || {
  printf 'extracted projectile motion stdout mismatch\n' >&2
  exit 1
}
rm -rf "$EXTRACTED_SMOKE"

printf '%s\n' "$ARCHIVE"
