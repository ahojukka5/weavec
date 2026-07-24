#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="$ROOT/build/weavec"
BUILD_DIR="$ROOT/build/test/public-build"
RUNTIME_SOURCE="$ROOT/runtime/program_runtime.c"
SURFACE_DIR="$ROOT/test/correctness/surface"

fail() {
  printf '[weavec-build-test] error: %s\n' "$*" >&2
  exit 1
}

[[ -x "$WEAVEC" ]] || fail "compiler missing: $WEAVEC"
[[ -f "$RUNTIME_SOURCE" ]] || fail "development runtime missing: $RUNTIME_SOURCE"
command -v clang >/dev/null 2>&1 || fail "clang not found"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

export WEAVEC_RUNTIME="$RUNTIME_SOURCE"
export WEAVEC_CC="${WEAVEC_CC:-clang}"

return42="$BUILD_DIR/return-42"
"$WEAVEC" build "$SURFACE_DIR/01_return_42.weave" -o "$return42"
[[ -x "$return42" ]] || fail "build produced no executable"
set +e
"$return42"
status="$?"
set -e
[[ "$status" -eq 42 ]] || fail "expected exit 42, got $status"

contract_bin="$BUILD_DIR/contract-fail"
"$WEAVEC" build "$SURFACE_DIR/62_contract_requires_fail.weave" -o "$contract_bin"
set +e
"$contract_bin" 2>"$BUILD_DIR/contract.stderr"
status="$?"
set -e
[[ "$status" -eq 1 ]] || fail "contract executable expected exit 1, got $status"
grep -F "contract failed:" "$BUILD_DIR/contract.stderr" >/dev/null || \
  fail "private runtime contract diagnostic missing"

invalid_source="$BUILD_DIR/invalid.weave"
invalid_output="$BUILD_DIR/atomic-output"
printf '(program\n' > "$invalid_source"
printf 'sentinel\n' > "$invalid_output"
set +e
"$WEAVEC" build "$invalid_source" -o "$invalid_output" \
  >"$BUILD_DIR/invalid.stdout" 2>"$BUILD_DIR/invalid.stderr"
status="$?"
set -e
[[ "$status" -ne 0 ]] || fail "invalid source unexpectedly built"
[[ "$(cat "$invalid_output")" == "sentinel" ]] || \
  fail "failed build replaced the existing output"

if find "$BUILD_DIR" -maxdepth 1 -type d -name '*.weavec-build-*' | grep -q .; then
  fail "temporary build directory leaked"
fi

printf '[weavec-build-test] public build command passed\n'
