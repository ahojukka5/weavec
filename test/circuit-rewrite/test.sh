#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Circuit IR and compiled local rewrites (#457). Builds the ordinary-Weave
# engine, checks the frozen corpus, and reports peephole vs generic size.
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

"$WEAVEC" build \
  "$ROOT/stdlib/memory.weave" \
  "$ROOT/stdlib/option.weave" \
  "$ROOT/stdlib/vec.weave" \
  "$ROOT/stdlib/io.weave" \
  "$SRC" \
  -o "$BIN" \
  --emit-wir "$WIR" \
  2>"$TMP/build.stderr" || {
  printf 'circuit-rewrite: build failed\n' >&2
  cat "$TMP/build.stderr" >&2
  exit 1
}

stdout="$TMP/run.stdout"
stderr="$TMP/run.stderr"
set +e
LC_ALL=C "$BIN" >"$stdout" 2>"$stderr"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  printf 'circuit-rewrite: program exited %s\n' "$status" >&2
  cat "$stdout" >&2 || true
  cat "$stderr" >&2 || true
  exit 1
fi

printf '%s' $'hh empty\nxx-diff 2\ncnot empty\nh-i-h generic-empty peephole-3\nrz-fuse generic-1 peephole-2\nrepeat ok\n' \
  > "$TMP/expected.stdout"
cmp "$TMP/expected.stdout" "$stdout" || {
  printf 'circuit-rewrite: stdout mismatch\n' >&2
  diff -u "$TMP/expected.stdout" "$stdout" >&2 || true
  exit 1
}
[[ ! -s "$stderr" ]] || {
  printf 'circuit-rewrite: unexpected stderr\n' >&2
  cat "$stderr" >&2
  exit 1
}

# Run twice more: the selected circuit must be identical across repeats.
LC_ALL=C "$BIN" >"$TMP/run2.stdout" 2>"$TMP/run2.stderr"
cmp "$stdout" "$TMP/run2.stdout"
[[ ! -s "$TMP/run2.stderr" ]]

# The witness stays on the ordinary surface.
if grep -Eq '\(q?rewrite\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$SRC"; then
  printf 'circuit-rewrite: witness leaked low-level or rewrite-syntax forms\n' >&2
  exit 1
fi
# H·H cancellation must go through the self-inverse table, not a matcher
# branch on the H kind.
if grep -n 'fn circ_find_match' -A 40 "$SRC" | grep -Eq 'circ_kind.* 1\)|kind 1'; then
  printf 'circuit-rewrite: generic matcher special-cases H\n' >&2
  exit 1
fi
grep -Fq '(fn rule_cancel_pair' "$SRC"
grep -Fq '(fn rule_drop_identity' "$SRC"
grep -Fq '(fn rule_fuse_rotation' "$SRC"
grep -Fq '(fn circ_peephole' "$SRC"
grep -Fq '(core-version 3)' "$WIR"

# Source-size comparison used by the M1 measurement note.
generic_lines=$(wc -l < "$SRC")
peephole_lines=$(wc -l < "$ROOT/src/frontend/quantum_optimize.weave")
printf 'circuit-rewrite: generic-source-lines %s\n' "$generic_lines"
printf 'circuit-rewrite: handwritten-predicate-lines %s\n' "$peephole_lines"

# Wall time of one process. Tiny corpus: this is a smoke figure, not a
# quality claim.
TIMEFORMAT='circuit-rewrite: wall-seconds %R'
time LC_ALL=C "$BIN" >/dev/null

if /usr/bin/time -f '%M' true >/dev/null 2>&1; then
  /usr/bin/time -f 'circuit-rewrite: max-rss-kb %M' "$BIN" >/dev/null
fi

printf 'circuit-rewrite: passed\n'
