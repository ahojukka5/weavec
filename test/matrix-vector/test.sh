#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-matrix-vector-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'matrix-vector: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/matrix-vector"
WIR="$TMP/matrix-vector.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/stdlib/vector.weave" \
  "$ROOT/stdlib/matrix.weave" \
  "$ROOT/examples/matrix-vector/main.weave" \
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
    printf 'matrix-vector: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'matrix-vector: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'matrix-vector: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

# The documented built-in demonstration, with no arguments.
run_case demonstration 0 $'result = [14.0, 32.0, 50.0]\n' ''

run_case identity 0 $'result = [1.0, 2.0, 3.0]\n' '' \
  1 0 0  0 1 0  0 0 1  1 2 3
run_case diagonal 0 $'result = [2.0, 6.0, 12.0]\n' '' \
  2 0 0  0 3 0  0 0 4  1 2 3
run_case zero 0 $'result = [0.0, 0.0, 0.0]\n' '' \
  0 0 0  0 0 0  0 0 0  1 2 3
run_case dense 0 $'result = [14.0, 32.0, 50.0]\n' '' \
  1 2 3  4 5 6  7 8 9  1 2 3
run_case fractional 0 $'result = [0.5, 1.5, 2.5]\n' '' \
  0.5 0 0  0 0.5 0  0 0 0.5  1 3 5
run_case negative 0 $'result = [-14.0, -32.0, -50.0]\n' '' \
  -1 -2 -3  -4 -5 -6  -7 -8 -9  1 2 3
# A non-symmetric matrix distinguishes row-major from column-major application.
run_case row-order 0 $'result = [3.0, 1.0, 2.0]\n' '' \
  0 0 1  1 0 0  0 1 0  1 2 3

run_case arity 2 '' $'usage: matrix-vector [m00..m22 vx vy vz]\n' 1 2 3
run_case malformed 2 '' $'error: components must be numbers\n' \
  1 0 0  0 1 0  0 0 1  1 2 oops

# Application source stays on the ordinary surface: no raw allocation, pointer
# arithmetic, or generated struct helper calls.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/matrix-vector/main.weave"; then
  printf 'matrix-vector: application source leaked low-level forms\n' >&2
  exit 1
fi
if grep -Eq 'malloc|free|Mat3_new|Vec3_new|_get_m[0-9]|_set_m[0-9]' \
    "$ROOT/examples/matrix-vector/main.weave"; then
  printf 'matrix-vector: application source called allocation or helpers\n' >&2
  exit 1
fi

grep -Fq '(fn mat3_apply' "$WIR"
grep -Fq '(fn vec3_dot' "$WIR"
grep -Fq '(fn write_f64_trimmed' "$WIR"

printf 'matrix-vector: passed\n'
