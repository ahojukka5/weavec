#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="$ROOT/build/weavec"
WIR="$ROOT/build/weavec.wir"
OUT_LL="$ROOT/build/test/selfhost/weavec.ll"
OUT_BC="$ROOT/build/test/selfhost/weavec.bc"

log() {
  printf '[weavec-selfhost] %s\n' "$*"
}

fail() {
  printf '[weavec-selfhost] error: %s\n' "$*" >&2
  exit 1
}

command -v llvm-as >/dev/null 2>&1 || fail 'missing llvm-as'

[[ -x "$WEAVEC" ]] || fail 'build/weavec not found; run ./build.sh first'
[[ -f "$WIR" ]] || fail 'build/weavec.wir not found; run ./build.sh first'

mkdir -p "$(dirname "$OUT_LL")"

log "compile $WIR"
"$WEAVEC" "$WIR" "$OUT_LL" || fail 'weavec failed on self-host WIR'

log "llvm-as"
llvm-as "$OUT_LL" -o "$OUT_BC" || fail 'llvm-as failed on self-host LLVM'

if command -v opt >/dev/null 2>&1; then
  OPT_BC="$ROOT/build/test/selfhost/weavec-mem2reg.bc"
  log "opt -passes=mem2reg"
  opt -passes=mem2reg -disable-output "$OUT_BC" -o "$OPT_BC" || fail 'opt -mem2reg failed'
fi

log 'ok self-host LLVM verifies'
