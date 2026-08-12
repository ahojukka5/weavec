#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-quadratic-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'quadratic: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/quadratic"
WIR="$TMP/quadratic.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/examples/quadratic/main.weave" \
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
    printf 'quadratic: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'quadratic: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'quadratic: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

# Positive discriminant: two distinct real roots.
run_case documented 0 $'roots = 1.0, 2.0\n' '' 1 -3 2
run_case spread 0 $'roots = -1.0, 3.0\n' '' 2 -4 -6
run_case decimals 0 $'roots = 1.0, 2.0\n' '' 0.5 -1.5 1
# A negative leading coefficient swaps which formula gives the smaller root, so
# ascending order must be chosen rather than assumed.
run_case negative-leading 0 $'roots = 1.0, 2.0\n' '' -1 3 -2
run_case irrational 0 $'roots = -1.618034, 0.618034\n' '' 1 1 -1

# Zero discriminant: one root of multiplicity two, printed as a single value.
run_case repeated 0 $'root = -1.0\n' '' 1 2 1
run_case repeated-positive 0 $'root = 3.0\n' '' 1 -6 9

# Negative discriminant: no real roots is a result, not a usage error.
run_case no-real-roots 0 $'no real roots\n' '' 1 0 1
run_case no-real-roots-shifted 0 $'no real roots\n' '' 2 2 3

run_case zero-leading 2 '' $'error: the coefficient a must not be zero\n' 0 2 4
run_case arity 2 '' $'usage: quadratic <a> <b> <c>\n' 1 2
run_case malformed 2 '' $'error: not a number: x\n' 1 x 3

# Application source stays on the ordinary surface.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/quadratic/main.weave"; then
  printf 'quadratic: application source leaked low-level forms\n' >&2
  exit 1
fi
if ! grep -Fq 'sqrt_f64' "$ROOT/examples/quadratic/main.weave"; then
  printf 'quadratic: example did not reuse the square root module\n' >&2
  exit 1
fi

grep -Fq '(fn program_main' "$WIR"
grep -Fq '(fn sqrt_f64' "$WIR"

printf 'quadratic: passed\n'
