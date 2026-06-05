#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Build weavec2 with weavec2 itself.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED="$ROOT/build/weavec2"
BUILD_DIR="$ROOT/build/selfhost"

log() { printf '[weavec2-selfhost] %s\n' "$*"; }
fail() { printf '[weavec2-selfhost] error: %s\n' "$*" >&2; exit 1; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

[[ -x "$SEED" ]] || fail "seed compiler not found at $SEED; run ./build.sh first"
require_tool llvm-link
require_tool llvm-as
require_tool clang

chmod -R u+rw "$BUILD_DIR" 2>/dev/null || true

# Keep in sync with SOURCES in build.sh (same order, $ROOT-prefixed paths).
SOURCES=(
  "$ROOT/src/core/extern.weave"
  "$ROOT/src/core/io.weave"
  "$ROOT/src/core/util.weave"
  "$ROOT/src/frontend/quantum_optimize.weave"
  "$ROOT/src/frontend/quantum_nativize.weave"
  "$ROOT/src/frontend/quantum_stats.weave"
  "$ROOT/src/frontend/emit.weave"
  "$ROOT/src/frontend/contract-lower.weave"
  "$ROOT/src/frontend/struct.weave"
  "$ROOT/src/frontend/lower.weave"
  "$ROOT/src/frontend/driver.weave"
  "$ROOT/src/frontend/explain-audit.weave"
  "$ROOT/src/frontend/contract-effects.weave"
  "$ROOT/src/frontend/audit-report.weave"
  "$ROOT/src/llvm/ctx.weave"
  "$ROOT/src/llvm/types.weave"
  "$ROOT/src/llvm/locals.weave"
  "$ROOT/src/llvm/strings.weave"
  "$ROOT/src/llvm/expr.weave"
  "$ROOT/src/llvm/loop-phi.weave"
  "$ROOT/src/llvm/stmt.weave"
  "$ROOT/src/llvm/fn.weave"
  "$ROOT/src/llvm/module.weave"
  "$ROOT/src/main.weave"
)

RUNTIME_MODULES=(
  sexpr_tokens
  sexpr_tree
  sexpr_lexer
  sexpr_parser
)

# Link bc+runtime; reject broken executables (clang output for the large
# self-host module is not always safe to run). Retry until smoke --frontend works.
link_stage_binary() {
  local bc="$1"
  local out_bin="$2"
  local stack_size="0x1000000"
  local tmp_bin smoke_wir attempt

  log "clang $out_bin"
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    tmp_bin="$(mktemp /tmp/weavec2-stage.XXXXXX)"
    smoke_wir="$(mktemp /tmp/weavec2-smoke.XXXXXX.wir)"
    rm -f "$out_bin"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      clang "$bc" "$ROOT/runtime/portable.c" -o "$tmp_bin" \
        -Wl,-stack_size,"$stack_size"
    else
      clang "$bc" "$ROOT/runtime/portable.c" -o "$tmp_bin" \
        -Wl,-z,stack-size="$stack_size"
    fi
    if "$tmp_bin" --frontend "$smoke_wir" \
      "$ROOT/src/core/extern.weave" \
      "$ROOT/src/main.weave" \
      "$ROOT/src/frontend/driver.weave" \
      "$ROOT/src/frontend/lower.weave" >/dev/null 2>&1; then
      mv "$tmp_bin" "$out_bin"
      rm -f "$smoke_wir"
      return 0
    fi
    rm -f "$tmp_bin" "$smoke_wir"
  done
  fail "link produced an unusable compiler binary after 10 attempts (rebuild seed: ./build.sh)"
}

build_stage() {
  local compiler="$1"
  local out_dir="$2"
  local out_bin="$out_dir/weavec2"

  mkdir -p "$out_dir"

  log "frontend $out_dir/weavec2.wir"
  "$compiler" --frontend "$out_dir/weavec2.wir" "${SOURCES[@]}"

  log "backend $out_dir/weavec2.ll"
  "$compiler" --backend "$out_dir/weavec2.wir" "$out_dir/weavec2.ll"

  local runtime_ll=()
  local mod
  for mod in "${RUNTIME_MODULES[@]}"; do
    log "runtime $mod"
    "$compiler" --backend \
      "$ROOT/src/runtime-wir/$mod.wir" \
      "$out_dir/$mod.ll"
    runtime_ll+=("$out_dir/$mod.ll")
  done

  log "link $out_dir/weavec2.bc"
  llvm-link "$out_dir/weavec2.ll" "${runtime_ll[@]}" -o "$out_dir/weavec2.bc"

  link_stage_binary "$out_dir/weavec2.bc" "$out_bin"
}

build_stage "$SEED" "$BUILD_DIR/stage1"
build_stage "$BUILD_DIR/stage1/weavec2" "$BUILD_DIR/stage2"

normalize_wir() {
  tr '\n\t\r' ' ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

run_stage2_fixture() {
  local name="$1"
  local expected_exit="$2"
  local stage2="$BUILD_DIR/stage2/weavec2"
  local out_dir="$BUILD_DIR/stage2-fixtures"
  local src="$ROOT/test/correctness/surface/$name.weave"
  local expected_wir="$ROOT/test/correctness/surface/$name.expected.wir"
  local wir="$out_dir/$name.wir"
  local ll="$out_dir/$name.ll"
  local bc="$out_dir/$name.bc"
  local bin="$out_dir/$name"

  mkdir -p "$out_dir"

  log "stage2 frontend fixture $name"
  "$stage2" --frontend "$wir" "$src"

  if ! diff -u <(normalize_wir "$expected_wir") <(normalize_wir "$wir"); then
    fail "stage2 frontend WIR mismatch for $name"
  fi

  log "stage2 backend fixture $name"
  "$stage2" --backend "$wir" "$ll"
  llvm-as "$ll" -o "$bc"
  clang "$ll" -o "$bin"

  set +e
  "$bin"
  local actual_exit="$?"
  set -e

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    fail "stage2 fixture $name expected exit $expected_exit, got $actual_exit"
  fi
}

run_stage2_fixture 01_return_42 42
run_stage2_fixture 59_bare_identifier_operands 42
run_stage2_fixture 60_let_literal_sugar 42

log "complete: $BUILD_DIR/stage2/weavec2"
