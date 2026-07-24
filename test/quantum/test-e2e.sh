#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Quantum end-to-end: surface .weave -> WIR -> LLVM -> clang + quantum_runtime.c -> run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="$ROOT/build/weavec"
RUNTIME="$ROOT/runtime/quantum_runtime.c"
FIXTURE_ROOT="$ROOT/test/quantum"
OUT_DIR="$ROOT/build/test/quantum-e2e"
E2E_DIRS=("e2e" "algorithms")
pass_count=0
fail_count=0

log() {
  printf '[weavec-quantum-e2e] %s\n' "$*"
}

fail() {
  printf '[weavec-quantum-e2e] error: %s\n' "$*" >&2
  fail_count=$((fail_count + 1))
}

read_metrics_field() {
  local file="$1"
  local key="$2"
  local line
  line="$(grep -E "^${key}=" "$file" | head -1 || true)"
  if [[ -z "$line" ]]; then
    printf ''
    return 1
  fi
  printf '%s' "${line#*=}"
}

[[ -x "$WEAVEC" ]] || {
  printf '[weavec-quantum-e2e] build/weavec not found; run ./build.sh first\n' >&2
  exit 1
}
[[ -f "$RUNTIME" ]] || {
  printf '[weavec-quantum-e2e] missing %s\n' "$RUNTIME" >&2
  exit 1
}

mkdir -p "$OUT_DIR"

find_paths=()
for d in "${E2E_DIRS[@]}"; do
  if [[ -d "$FIXTURE_ROOT/$d" ]]; then
    find_paths+=("$FIXTURE_ROOT/$d")
  fi
done

while IFS= read -r -d '' src; do
  base="$(basename "$src" .weave)"
  wir="$OUT_DIR/$base.wir"
  ll="$OUT_DIR/$base.ll"
  exe="$OUT_DIR/$base"
  metrics="$(dirname "$src")/$base.metrics"

  log "e2e $base"

  if ! "$WEAVEC" --frontend "$wir" "$src"; then
    fail "$base: frontend failed"
    continue
  fi
  if ! "$WEAVEC" --backend "$wir" "$ll"; then
    fail "$base: backend failed"
    continue
  fi
  if ! clang -Wno-override-module "$ll" "$RUNTIME" -lm -o "$exe"; then
    fail "$base: clang link failed"
    continue
  fi
  set +e
  "$exe"
  status=$?
  set -e

  if [[ -f "$metrics" ]]; then
    expected_exit="$(read_metrics_field "$metrics" exit_code || true)"
    if [[ -z "$expected_exit" ]]; then
      expected_exit=42
    fi
    if [[ "$status" != "$expected_exit" ]]; then
      fail "$base: expected exit $expected_exit, got $status"
      continue
    fi
    expected_trace="$(read_metrics_field "$metrics" trace_count || true)"
    if [[ -n "$expected_trace" && "$status" != "$expected_trace" ]]; then
      fail "$base: expected trace_count $expected_trace, got $status"
      continue
    fi
  else
    if [[ "$status" != "42" ]]; then
      fail "$base: expected exit 42, got $status"
      continue
    fi
  fi

  pass_count=$((pass_count + 1))
done < <(find "${find_paths[@]}" -name '*.weave' -print0)

log "passed $pass_count"
if [[ "$fail_count" -gt 0 ]]; then
  log "failed $fail_count"
  exit 1
fi
exit 0
