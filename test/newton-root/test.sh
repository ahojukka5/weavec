#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-newton-root-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'newton-root: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/newton-root"
WIR="$TMP/newton-root.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/examples/newton-root/main.weave" \
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
    printf 'newton-root: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'newton-root: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'newton-root: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

# The documented case from the issue.
run_case documented 0 $'root = 1.414214\niterations = 5\n' '' 2
# Above one, including an exact square and a large value.
run_case exact-square 0 $'root = 2.000000\niterations = 6\n' '' 4
run_case exact-square-nine 0 $'root = 3.000000\niterations = 7\n' '' 9
run_case large 0 $'root = 1000.000000\niterations = 15\n' '' 1000000
# Below one, including an exact square.
run_case below-one 0 $'root = 0.500000\niterations = 6\n' '' 0.25
run_case below-one-half 0 $'root = 0.707107\niterations = 5\n' '' 0.5
# One is its own root, reached in a single pass.
run_case unity 0 $'root = 1.000000\niterations = 1\n' '' 1
# Zero is exact and needs no iteration; it is also the input that would divide
# by the first guess.
run_case zero 0 $'root = 0.000000\niterations = 0\n' '' 0
run_case fractional-square 0 $'root = 1.500000\niterations = 5\n' '' 2.25

run_case negative 2 '' \
  $'error: cannot take the square root of a negative value\n' -4
run_case malformed 2 '' $'error: not a number: x\n' x
run_case arity 2 '' $'usage: newton-root <value>\n' 1 2

# The hand-rolled iteration is checked against an independent square root
# computed outside the program.
awk 'BEGIN { printf "root = %.6f\n", sqrt(2) }' > "$TMP/independent.txt"
grep -F 'root = ' "$TMP/documented.stdout" > "$TMP/actual-root.txt"
cmp "$TMP/independent.txt" "$TMP/actual-root.txt" || {
  printf 'newton-root: root disagrees with an independent square root\n' >&2
  diff -u "$TMP/independent.txt" "$TMP/actual-root.txt" >&2 || true
  exit 1
}

# The point of this example is the loop, so it must not delegate to the
# reusable square-root module.
if grep -Fq 'sqrt_f64' "$ROOT/examples/newton-root/main.weave"; then
  printf 'newton-root: example called the reusable square root\n' >&2
  exit 1
fi
# std.math is still built, for f64_abs, so sqrt_f64 is present as a definition.
# What matters is that the elaborated program never calls it.
if grep -Eq 'call_[a-z0-9]+ sqrt_f64' "$WIR"; then
  printf 'newton-root: elaborated program calls the reusable square root\n' >&2
  exit 1
fi
# Application source stays on the ordinary surface.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/newton-root/main.weave"; then
  printf 'newton-root: application source leaked low-level forms\n' >&2
  exit 1
fi
# The tolerance and the iteration limit are named constants, not inline magic.
if ! grep -Fq '(const TOLERANCE_F64' "$ROOT/examples/newton-root/main.weave"; then
  printf 'newton-root: tolerance is not a named constant\n' >&2
  exit 1
fi
if ! grep -Fq '(const ITERATION_LIMIT_I32' "$ROOT/examples/newton-root/main.weave"; then
  printf 'newton-root: iteration limit is not a named constant\n' >&2
  exit 1
fi

grep -Fq '(fn program_main' "$WIR"
grep -Fq '(fn f64_abs' "$WIR"

printf 'newton-root: passed\n'
