#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Circuit IR and compiled local rewrites (#457). Correctness uses the same
# three-rule set on both arms. The timed arms rewrite a frozen 200-gate
# circuit many times so wall time and RSS can decide the stop rule.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-circuit-rewrite-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'circuit-rewrite: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

SRC="$ROOT/test/circuit-rewrite/main.weave"
BIN="$TMP/circuit-rewrite"
WIR="$TMP/circuit-rewrite.wir"
# 20 blocks * 10 gates = 200 gates. Default reps keep special-case work
# off the 1 ms timer floor while remaining acceptable in PR compile.
BLOCKS="${CIRCUIT_REWRITE_BLOCKS:-20}"
REPS="${CIRCUIT_REWRITE_REPS:-4000}"

"$WEAVEC" build \
  "$ROOT/stdlib/memory.weave" \
  "$ROOT/stdlib/option.weave" \
  "$ROOT/stdlib/vec.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/process.weave" \
  "$SRC" \
  -o "$BIN" \
  --emit-wir "$WIR" \
  2>"$TMP/build.stderr" || {
  printf 'circuit-rewrite: build failed\n' >&2
  cat "$TMP/build.stderr" >&2
  exit 1
}

run_bin() {
  local name="$1"
  shift
  set +e
  LC_ALL=C "$BIN" "$@" >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf 'circuit-rewrite: %s exited %s\n' "$name" "$status" >&2
    cat "$TMP/$name.stdout" >&2 || true
    cat "$TMP/$name.stderr" >&2 || true
    exit 1
  fi
  [[ ! -s "$TMP/$name.stderr" ]] || {
    printf 'circuit-rewrite: %s unexpected stderr\n' "$name" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  }
}

run_bin check
printf '%s' $'hh empty\nxx-diff 2\ncnot empty\nh-i-h empty\nrz-fuse 1\nrepeat ok\nbench-block empty\n' \
  > "$TMP/expected.stdout"
cmp "$TMP/expected.stdout" "$TMP/check.stdout" || {
  printf 'circuit-rewrite: stdout mismatch\n' >&2
  diff -u "$TMP/expected.stdout" "$TMP/check.stdout" >&2 || true
  exit 1
}
run_bin check2
cmp "$TMP/check.stdout" "$TMP/check2.stdout"

if grep -Eq '\(q?rewrite\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$SRC"; then
  printf 'circuit-rewrite: witness leaked low-level or rewrite-syntax forms\n' >&2
  exit 1
fi
if grep -n 'fn circ_find_match' -A 40 "$SRC" | grep -Eq 'circ_kind.* 1\)|kind 1'; then
  printf 'circuit-rewrite: generic matcher special-cases H\n' >&2
  exit 1
fi
grep -Fq '(fn rule_cancel_pair' "$SRC"
grep -Fq '(fn rule_drop_identity' "$SRC"
grep -Fq '(fn rule_fuse_rotation' "$SRC"
grep -Fq '(fn circ_special' "$SRC"
grep -Fq '(fn circ_rewrite' "$SRC"
grep -Fq '(core-version 3)' "$WIR"

count_region() {
  local start="$1"
  local stop="$2"
  awk -v start="$start" -v stop="$stop" '
    $0 ~ start {on=1}
    on {n++}
    $0 ~ stop {if (start != stop) {on=0}}
    END {print n+0}
  ' "$SRC"
}
generic_lines=$(count_region 'generic-arm' 'special-arm')
special_lines=$(count_region 'special-arm' 'driver')
printf 'circuit-rewrite: generic-arm-lines %s\n' "$generic_lines"
printf 'circuit-rewrite: special-arm-lines %s\n' "$special_lines"

measure_arm() {
  local arm="$1"
  local name="$2"
  set +e
  python3 - "$BIN" "$arm" "$BLOCKS" "$REPS" "$TMP/$name" <<'PY'
import resource
import subprocess
import sys
import time

binary, arm, blocks, reps, prefix = sys.argv[1:]
start = time.perf_counter()
proc = subprocess.run(
    [binary, arm, blocks, reps],
    check=False,
    stdout=open(prefix + ".stdout", "wb"),
    stderr=open(prefix + ".stderr", "wb"),
)
elapsed = time.perf_counter() - start
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
with open(prefix + ".wall", "w", encoding="utf-8") as fh:
    fh.write("%.4f\n" % elapsed)
with open(prefix + ".rss", "w", encoding="utf-8") as fh:
    fh.write("%d\n" % rss)
sys.exit(proc.returncode)
PY
  local status="$?"
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf 'circuit-rewrite: %s bench exited nonzero\n' "$name" >&2
    cat "$TMP/$name.stdout" >&2 || true
    cat "$TMP/$name.stderr" >&2 || true
    exit 1
  fi
  local wall rss
  wall="$(tr -d ' \n' < "$TMP/$name.wall")"
  rss="$(tr -d ' \n' < "$TMP/$name.rss")"
  printf 'circuit-rewrite: %s-wall-seconds %s\n' "$name" "$wall"
  printf 'circuit-rewrite: %s-max-rss-kib %s\n' "$name" "$rss"
  grep -Fq 'bench ok' "$TMP/$name.stdout"
}

printf 'circuit-rewrite: bench-blocks %s bench-reps %s\n' "$BLOCKS" "$REPS"
measure_arm 1 generic
measure_arm 2 special

printf 'circuit-rewrite: passed\n'
