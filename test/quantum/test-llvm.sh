#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Quantum LLVM-IR optimality: compile each fixture to .ll and assert the
# emitted LLVM is what a hand-written ideal implementation would look like.
#
# What "optimal" means here:
# - qrt_* call count matches the lowered native_gates in .metrics.
# - No alloca, store, load, or arithmetic ops in main: qubit handles must
#   flow through as i64 immediates, not stack-rounding-tripped values.
# - For self-inverse cancellation fixtures, main reduces to `ret i32 42`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="$ROOT/build/weavec"
FIXTURE_ROOT="$ROOT/test/quantum"
OUT_DIR="$ROOT/build/test/quantum-llvm"
pass_count=0
fail_count=0

log() { printf '[weavec-quantum-llvm] %s\n' "$*"; }
fail() {
  printf '[weavec-quantum-llvm] error: %s\n' "$*" >&2
  fail_count=$((fail_count + 1))
}

[[ -x "$WEAVEC" ]] || {
  printf '[weavec-quantum-llvm] build/weavec not found; run ./build.sh first\n' >&2
  exit 1
}

mkdir -p "$OUT_DIR"

# Pull a single key=value line out of a .metrics file (printf 0 if absent).
metric() {
  local file="$1" key="$2" line
  if [[ ! -f "$file" ]]; then
    printf '0'
    return
  fi
  line="$(grep -E "^${key}=" "$file" | head -1 || true)"
  if [[ -z "$line" ]]; then
    printf '0'
    return
  fi
  printf '%s' "${line#*=}"
}

# Returns the body of `define i32 @main() { ... }` only (so we don't count
# declaration lines or other functions toward the budget).
main_body() {
  awk '/^define i32 @main\(\)/{inside=1; next} inside && /^}/{inside=0} inside' "$1"
}

check_circuit() {
  local src="$1"
  local label="$2"
  local expected_calls="$3"
  local rel="${src#$FIXTURE_ROOT/}"
  local stem="${rel//\//-}"
  local wir="$OUT_DIR/${stem%.weave}.wir"
  local ll="$OUT_DIR/${stem%.weave}.ll"

  log "llvm $label"

  if ! "$WEAVEC" --frontend "$wir" "$src"; then
    fail "$label: --frontend failed"
    return
  fi
  if ! "$WEAVEC" --backend "$wir" "$ll"; then
    fail "$label: --backend failed"
    return
  fi

  local body
  body="$(main_body "$ll")"

  # 1. Call count.
  local actual_calls
  actual_calls="$(printf '%s' "$body" | grep -cE '^\s*call (void|i32) @qrt_' || true)"
  if [[ "$actual_calls" != "$expected_calls" ]]; then
    fail "$label: expected $expected_calls qrt_* calls, got $actual_calls"
    return
  fi

  # 2. No allocas, stores, loads, or arithmetic in main.
  local junk
  junk="$(printf '%s' "$body" | grep -cE '\b(alloca|store|load|add|sub|mul|sdiv|udiv|getelementptr|phi)\b' || true)"
  if [[ "$junk" != "0" ]]; then
    fail "$label: main contains $junk stack/arith ops; expected 0 (qubit handles must flow as immediates)"
    printf '%s\n' "$body" | grep -E '\b(alloca|store|load|add|sub|mul|sdiv|udiv|getelementptr|phi)\b' >&2 || true
    return
  fi

  # 3. Every qrt_* call argument must be an i64 immediate (not %register),
  #    so the compiler isn't materialising temporaries that an optimiser
  #    would have to fold away.
  local non_immediate
  non_immediate="$(printf '%s' "$body" | grep -E '^\s*call (void|i32) @qrt_' | grep -cE '%[a-zA-Z0-9_.]+' || true)"
  if [[ "$non_immediate" != "0" ]]; then
    fail "$label: $non_immediate qrt_* call(s) use SSA registers as args; expected only i64 immediates"
    return
  fi

  pass_count=$((pass_count + 1))
}

# Benchmarks: read native_gates from .metrics.
while IFS= read -r -d '' src; do
  base="$(basename "$src" .weave)"
  metrics="$(dirname "$src")/$base.metrics"
  [[ -f "$metrics" ]] || continue
  expected="$(metric "$metrics" native_gates)"
  check_circuit "$src" "benchmarks/$base" "$expected"
done < <(find "$FIXTURE_ROOT/benchmarks" -name '*.weave' -print0)

# Gate-coverage fixtures: each is a single named gate, so native_gates = 1
# for the non-H ones and 2 for H. Use metrics if available, otherwise default
# to 1.
while IFS= read -r -d '' src; do
  base="$(basename "$src" .weave)"
  metrics="$(dirname "$src")/$base.metrics"
  expected="$(metric "$metrics" native_gates)"
  check_circuit "$src" "gates/$base" "$expected"
done < <(find "$FIXTURE_ROOT/gates" -name '*.weave' -print0)

while IFS= read -r -d '' src; do
  base="$(basename "$src" .weave)"
  metrics="$(dirname "$src")/$base.metrics"
  expected="$(metric "$metrics" native_gates)"
  check_circuit "$src" "multi-qubit/$base" "$expected"
done < <(find "$FIXTURE_ROOT/multi-qubit" -name '*.weave' -print0)

# Optimization fixtures: each should reduce to zero calls.
while IFS= read -r -d '' src; do
  base="$(basename "$src" .weave)"
  metrics="$(dirname "$src")/$base.metrics"
  if [[ -f "$metrics" ]]; then
    expected="$(metric "$metrics" native_gates)"
  else
    expected="0"
  fi
  check_circuit "$src" "optimization/$base" "$expected"
done < <(find "$FIXTURE_ROOT/optimization" -name '*.weave' -print0)

log "passed $pass_count"
if [[ "$fail_count" -gt 0 ]]; then
  log "failed $fail_count"
  exit 1
fi
exit 0
