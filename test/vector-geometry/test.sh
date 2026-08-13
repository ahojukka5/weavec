#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-vector-geometry-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'vector-geometry: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/vector-geometry"
WIR="$TMP/vector-geometry.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/stdlib/memory.weave" \
  "$ROOT/stdlib/vector.weave" \
  "$ROOT/examples/vector-geometry/main.weave" \
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
    printf 'vector-geometry: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'vector-geometry: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'vector-geometry: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

run_case orthogonal 0 \
  $'length-a = 1.0\nlength-b = 1.0\nangle-degrees = 90.0\n' '' \
  1 0 0 0 1 0
run_case parallel 0 \
  $'length-a = 3.741657\nlength-b = 7.483315\nangle-degrees = 0.0\n' '' \
  1 2 3 2 4 6
run_case opposite 0 \
  $'length-a = 3.741657\nlength-b = 3.741657\nangle-degrees = 180.0\n' '' \
  1 2 3 -1 -2 -3
run_case fractional 0 \
  $'length-a = 1.414214\nlength-b = 1.0\nangle-degrees = 45.0\n' '' \
  1 1 0 1 0 0
run_case obtuse 0 \
  $'length-a = 1.0\nlength-b = 1.414214\nangle-degrees = 135.0\n' '' \
  1 0 0 -1 1 0
run_case pythagorean 0 \
  $'length-a = 5.0\nlength-b = 5.0\nangle-degrees = 90.0\n' '' \
  3 4 0 0 0 5
run_case zero-first 2 '' \
  $'error: the angle of a zero-length vector is undefined\n' 0 0 0 1 2 3
run_case zero-second 2 '' \
  $'error: the angle of a zero-length vector is undefined\n' 1 2 3 0 0 0
run_case arity 2 '' \
  $'usage: vector-geometry <ax> <ay> <az> <bx> <by> <bz>\n' 1 2 3
run_case malformed 2 '' \
  $'error: components must be numbers\n' 1 0 0 0 1 nope

# Application source stays on the ordinary surface, and the example adds no
# second magnitude, inverse-cosine, or degree-conversion implementation.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/vector-geometry/main.weave"; then
  printf 'vector-geometry: application source leaked low-level forms\n' >&2
  exit 1
fi
if grep -Eq '\b(asin|atan)' "$ROOT/examples/vector-geometry/main.weave"; then
  printf 'vector-geometry: example added a second inverse trigonometry\n' >&2
  exit 1
fi
if grep -Fq '180.0' "$ROOT/examples/vector-geometry/main.weave"; then
  printf 'vector-geometry: example open-coded degree conversion\n' >&2
  exit 1
fi

grep -Fq '(fn acos_f64' "$WIR"
grep -Fq '(fn radians_to_degrees' "$WIR"
grep -Fq '(fn vec3_dot' "$WIR"
grep -Fq '(fn sqrt_f64' "$WIR"

printf 'vector-geometry: passed\n'
