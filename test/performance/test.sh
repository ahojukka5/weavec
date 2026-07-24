#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="$ROOT/build/weavec"
FIXTURE_DIR="$ROOT/test/performance/wir"
EXPECTED_DIR="$ROOT/test/performance/expected-llvm"
BUILD_DIR="$ROOT/build/test/performance"
GENERATED_DIR="$BUILD_DIR/generated"
BC_DIR="$BUILD_DIR/bc"

pass_count=0
fail_count=0

log() {
  printf '[weavec-performance] %s\n' "$*"
}

fail() {
  printf '[weavec-performance] error: %s\n' "$*" >&2
  fail_count=$((fail_count + 1))
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '[weavec-performance] missing required tool: %s\n' "$1" >&2
    exit 1
  }
}

[[ -x "$WEAVEC" ]] || {
  printf '[weavec-performance] build/weavec not found; run ./build.sh first\n' >&2
  exit 1
}

require_tool llvm-as

mkdir -p "$GENERATED_DIR" "$BC_DIR"

for src in "$FIXTURE_DIR"/*.wir; do
  name="$(basename "$src" .wir)"
  rel_src="test/performance/wir/$name.wir"
  expected="$EXPECTED_DIR/$name.ll"
  generated="$GENERATED_DIR/$name.ll"
  bc="$BC_DIR/$name.bc"

  log "llvm $name"

  if [[ ! -f "$expected" ]]; then
    fail "$name: missing expected LLVM $expected"
    continue
  fi

  if ! (cd "$ROOT" && "$WEAVEC" --backend "$rel_src" "$generated"); then
    fail "$name: weavec failed"
    continue
  fi

  if ! diff -u "$expected" "$generated"; then
    fail "$name: LLVM golden mismatch"
    continue
  fi

  if ! llvm-as "$generated" -o "$bc"; then
    fail "$name: llvm-as failed"
    continue
  fi

  if command -v opt >/dev/null 2>&1; then
    opt_bc="$BC_DIR/$name-mem2reg.bc"
    if ! opt -passes=mem2reg -disable-output "$bc" -o "$opt_bc" 2>/dev/null; then
      fail "$name: opt -mem2reg failed"
      continue
    fi
  fi

  log "ok $name"
  pass_count=$((pass_count + 1))
done

log "$pass_count passed, $fail_count failed"

if [[ "$fail_count" -ne 0 ]]; then
  exit 1
fi
