#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Regenerate one or all performance LLVM goldens from weavec output.
#
# Usage:
#   ./test/performance/regen-golden.sh              # all fixtures
#   ./test/performance/regen-golden.sh 0073_factorial_iter_i32
#   ./test/performance/regen-golden.sh 0008_while 0073_factorial_iter_i32

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="$ROOT/build/weavec"
WIR_DIR="$ROOT/test/performance/wir"
EXPECTED_DIR="$ROOT/test/performance/expected-llvm"
GEN_DIR="$ROOT/build/test/performance/regen"

log() { printf '[regen-golden] %s\n' "$*"; }
fail() { printf '[regen-golden] error: %s\n' "$*" >&2; exit 1; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

[[ -x "$WEAVEC" ]] || fail "build/weavec not found; run ./build.sh from weave/weavec"
require_tool llvm-as

mkdir -p "$GEN_DIR"

regen_one() {
  local name="$1"
  local src="$WIR_DIR/${name}.wir"
  local out="$GEN_DIR/${name}.ll"
  local golden="$EXPECTED_DIR/${name}.ll"

  [[ -f "$src" ]] || fail "missing WIR fixture: $src"

  log "$name"
  (cd "$ROOT" && "$WEAVEC" --backend "test/performance/wir/${name}.wir" "$out") || fail "weavec failed: $name"
  llvm-as "$out" -o /dev/null || fail "llvm-as failed: $name"
  cp "$out" "$golden"
  log "ok $name -> $golden"
}

if [[ "$#" -eq 0 ]]; then
  for src in "$WIR_DIR"/*.wir; do
    regen_one "$(basename "$src" .wir)"
  done
else
  for name in "$@"; do
    regen_one "$name"
  done
fi

log "done"
