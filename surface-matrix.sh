#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEAVEC="$ROOT/build/weavec"
SURFACE_DIR="$ROOT/test/correctness/surface"
BUILD_DIR="$ROOT/build/test/surface-matrix"
WIR_DIR="$BUILD_DIR/wir"
LL_DIR="$BUILD_DIR/ll"
BC_DIR="$BUILD_DIR/bc"
BIN_DIR="$BUILD_DIR/bin"

frontend_ok=0
backend_ok=0
llvm_ok=0
clang_ok=0
run_ok=0
total=0

log() {
  printf '[weavec-surface] %s\n' "$*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[weavec-surface] missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

expected_exit() {
  case "$1" in
    02_return_constant) echo 0 ;;
    05_one_arg_function) echo 43 ;;
    24_mod_i32) echo 2 ;;
    52_integration_nested_control_flow) echo 75 ;;
    53_integration_multi_function_chain) echo 35 ;;
    54_integration_memory_flow) echo 100 ;;
    55_new_operators) echo 40 ;;
    *) echo 42 ;;
  esac
}

report() {
  local name="$1"
  local phase="$2"
  printf '%-36s %s\n' "$name" "$phase"
}

[[ -x "$WEAVEC" ]] || {
  printf '[weavec-surface] build/weavec not found; run ./build.sh first\n' >&2
  exit 1
}

require_tool llvm-as
require_tool clang

chmod -R u+rw "$BUILD_DIR" 2>/dev/null || true
mkdir -p "$WIR_DIR" "$LL_DIR" "$BC_DIR" "$BIN_DIR"

log "surface fixture compatibility matrix"

for src in "$SURFACE_DIR"/[0-9][0-9]_*.weave; do
  name="$(basename "$src" .weave)"
  wir="$WIR_DIR/$name.wir"
  ll="$LL_DIR/$name.ll"
  bc="$BC_DIR/$name.bc"
  bin="$BIN_DIR/$name"
  expected="$(expected_exit "$name")"
  total=$((total + 1))

  if ! "$WEAVEC" --frontend "$wir" "$src" >/dev/null 2>&1; then
    report "$name" "frontend-fail"
    continue
  fi
  frontend_ok=$((frontend_ok + 1))

  if ! "$WEAVEC" --backend "$wir" "$ll" >/dev/null 2>&1; then
    report "$name" "backend-fail"
    continue
  fi
  backend_ok=$((backend_ok + 1))

  if ! llvm-as "$ll" -o "$bc" >/dev/null 2>&1; then
    report "$name" "llvm-as-fail"
    continue
  fi
  llvm_ok=$((llvm_ok + 1))

  if ! clang "$ll" -o "$bin" >/dev/null 2>&1; then
    report "$name" "clang-fail"
    continue
  fi
  clang_ok=$((clang_ok + 1))

  set +e
  "$bin" >/dev/null 2>&1
  actual="$?"
  set -e

  if [[ "$actual" != "$expected" ]]; then
    report "$name" "run-fail expected=$expected actual=$actual"
    continue
  fi
  run_ok=$((run_ok + 1))
  report "$name" "ok"
done

log "frontend: $frontend_ok/$total"
log "backend:  $backend_ok/$total"
log "llvm-as:  $llvm_ok/$total"
log "clang:    $clang_ok/$total"
log "run:      $run_ok/$total"
