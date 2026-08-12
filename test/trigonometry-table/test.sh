#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-trig-table-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/trigonometry-table"
OUT="$TMP/stdout.txt"
ERR="$TMP/stderr.txt"
EXPECTED="$TMP/expected.txt"

"$WEAVEC" build \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/examples/trigonometry-table/main.weave" \
  -o "$BIN"

set +e
LC_ALL=C "$BIN" >"$OUT" 2>"$ERR"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  printf 'trigonometry-table: executable returned %s\n' "$status" >&2
  cat "$OUT" >&2 || true
  cat "$ERR" >&2 || true
  exit 1
fi
if [[ -s "$ERR" ]]; then
  printf 'trigonometry-table: unexpected stderr\n' >&2
  cat "$ERR" >&2
  exit 1
fi

cat > "$EXPECTED" <<'EOF'
angle  sin       cos       tan
0      0.000000  1.000000  0.000000
30     0.500000  0.866025  0.577350
45     0.707107  0.707107  1.000000
60     0.866025  0.500000  1.732051
EOF

cmp "$EXPECTED" "$OUT" || {
  printf 'trigonometry-table: stdout mismatch\n' >&2
  diff -u "$EXPECTED" "$OUT" >&2 || true
  exit 1
}

if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/trigonometry-table/main.weave"; then
  printf 'trigonometry-table: application source leaked low-level forms\n' >&2
  exit 1
fi

printf 'trigonometry-table: passed\n'
