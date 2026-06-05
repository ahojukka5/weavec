#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Quantum surface tests: WIR goldens, metrics, validation rejects.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC2="$ROOT/build/weavec2"
FIXTURE_ROOT="$ROOT/test/quantum"
OUT_DIR="$ROOT/build/test/quantum"
pass_count=0
fail_count=0

log() {
  printf '[weavec2-quantum] %s\n' "$*"
}

fail() {
  printf '[weavec2-quantum] error: %s\n' "$*" >&2
  fail_count=$((fail_count + 1))
}

normalize_wir() {
  tr '\n\t\r' ' ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

compare_metrics() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  # exit_code/trace_count are e2e-only; --dump-quantum-stats doesn't emit them.
  if ! diff -u <(grep -vE '^(exit_code|trace_count)=' "$expected") "$actual"; then
    fail "$label: metrics mismatch"
    return 1
  fi
  return 0
}

run_wir_golden_dir() {
  local subdir="$1"
  while IFS= read -r -d '' src; do
    local dir base rel expected wir
    dir="$(dirname "$src")"
    base="$(basename "$src" .weave)"
    rel="${dir#$FIXTURE_ROOT/}"
    expected="$dir/$base.expected.wir"
    wir="$OUT_DIR/${rel//\//-}-$base.wir"

    log "golden $rel/$base"

    if [[ ! -f "$expected" ]]; then
      fail "$rel/$base: missing $expected"
      continue
    fi

    if ! "$WEAVEC2" --frontend "$wir" "$src"; then
      fail "$rel/$base: frontend failed"
      continue
    fi

    if ! diff -u <(normalize_wir "$expected") <(normalize_wir "$wir"); then
      fail "$rel/$base: WIR golden mismatch"
      continue
    fi

    local metrics="$dir/$base.metrics"
    if [[ -f "$metrics" ]]; then
      local got="$OUT_DIR/${rel//\//-}-$base.metrics"
      if ! "$WEAVEC2" --dump-quantum-stats "$got" "$src"; then
        fail "$rel/$base: --dump-quantum-stats failed"
        continue
      fi
      if ! compare_metrics "$metrics" "$got" "$rel/$base"; then
        continue
      fi
    fi

    pass_count=$((pass_count + 1))
  done < <(find "$FIXTURE_ROOT/$subdir" -name '*.weave' -print0)
}

[[ -x "$WEAVEC2" ]] || {
  printf '[weavec2-quantum] build/weavec2 not found; run ./build.sh first\n' >&2
  exit 1
}

mkdir -p "$OUT_DIR"

run_wir_golden_dir nativization
run_wir_golden_dir gates
run_wir_golden_dir multi-qubit
run_wir_golden_dir benchmarks
run_wir_golden_dir algorithms
run_wir_golden_dir optimization

# Validation fixtures must fail the frontend before WIR is written.
while IFS= read -r -d '' src; do
  dir="$(dirname "$src")"
  base="$(basename "$src" .weave)"
  rel="${dir#$FIXTURE_ROOT/}"
  wir="$OUT_DIR/${rel//\//-}-$base-should-fail.wir"

  log "reject $rel/$base"

  if "$WEAVEC2" --frontend "$wir" "$src"; then
    fail "$rel/$base: expected frontend failure, got success"
    continue
  fi

  pass_count=$((pass_count + 1))
done < <(find "$FIXTURE_ROOT/validation" -name '*.weave' -print0)

log "passed $pass_count"
if [[ "$fail_count" -gt 0 ]]; then
  log "failed $fail_count"
  exit 1
fi
exit 0
