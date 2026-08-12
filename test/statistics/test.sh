#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-statistics-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'statistics: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/statistics"
WIR="$TMP/statistics.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/examples/statistics/main.weave" \
  -o "$BIN" \
  --emit-wir "$WIR"

run_case() {
  local name="$1"
  local expected_status="$2"
  local expected_stdout="$3"
  local expected_stderr="$4"
  shift 4

  local stdout="$TMP/$name.stdout"
  local stderr="$TMP/$name.stderr"
  local want_stdout="$TMP/$name.expected.stdout"
  local want_stderr="$TMP/$name.expected.stderr"
  printf '%s' "$expected_stdout" > "$want_stdout"
  printf '%s' "$expected_stderr" > "$want_stderr"

  set +e
  LC_ALL=C "$BIN" "$@" >"$stdout" 2>"$stderr"
  local status="$?"
  set -e

  if [[ "$status" -ne "$expected_status" ]]; then
    printf 'statistics: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'statistics: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'statistics: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

run_case documented 0 \
  $'count = 4\nmean = 2.5\nvariance = 1.25\nstddev = 1.118034\n' '' \
  1 2 3 4
run_case single 0 \
  $'count = 1\nmean = 5.0\nvariance = 0.0\nstddev = 0.0\n' '' \
  5
run_case repeated 0 \
  $'count = 4\nmean = 2.0\nvariance = 0.0\nstddev = 0.0\n' '' \
  2 2 2 2
run_case negative 0 \
  $'count = 3\nmean = -2.0\nvariance = 0.666667\nstddev = 0.816497\n' '' \
  -1 -2 -3
run_case decimals 0 \
  $'count = 2\nmean = 2.0\nvariance = 0.25\nstddev = 0.5\n' '' \
  1.5 2.5
run_case mixed-sign 0 \
  $'count = 4\nmean = 0.0\nvariance = 1.25\nstddev = 1.118034\n' '' \
  -1.5 -0.5 0.5 1.5

run_case empty 2 '' $'usage: statistics <value> [value ...]\n'
# The failing argument is named, not merely counted.
run_case malformed 2 '' $'error: not a number: nope\n' 1 nope 3
run_case malformed-first 2 '' $'error: not a number: x\n' x 2 3
run_case malformed-trailing 2 '' $'error: not a number: 4x\n' 1 2 4x

# Application source stays on the ordinary surface with no manual argc/argv.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_|argc|argv' \
    "$ROOT/examples/statistics/main.weave"; then
  printf 'statistics: application source leaked low-level forms\n' >&2
  exit 1
fi
# Standard deviation reuses the square-root module rather than iterating again.
if ! grep -Fq 'sqrt_f64' "$ROOT/examples/statistics/main.weave"; then
  printf 'statistics: example did not reuse the square root module\n' >&2
  exit 1
fi

grep -Fq '(fn program_main' "$WIR"
grep -Fq '(fn sqrt_f64' "$WIR"
grep -Fq '(fn parse_f64' "$WIR"

printf 'statistics: passed\n'
