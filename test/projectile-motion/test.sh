#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-projectile-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'projectile-motion: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

BIN="$TMP/projectile-motion"
WIR="$TMP/projectile-motion.wir"

"$WEAVEC" build \
  "$ROOT/stdlib/process.weave" \
  "$ROOT/stdlib/parse.weave" \
  "$ROOT/stdlib/math.weave" \
  "$ROOT/stdlib/io.weave" \
  "$ROOT/examples/projectile-motion/main.weave" \
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
    printf 'projectile-motion: %s exited %s, expected %s\n' \
      "$name" "$status" "$expected_status" >&2
    cat "$stdout" >&2 || true
    cat "$stderr" >&2 || true
    exit 1
  fi
  cmp "$want_stdout" "$stdout" || {
    printf 'projectile-motion: %s stdout mismatch\n' "$name" >&2
    diff -u "$want_stdout" "$stdout" >&2 || true
    exit 1
  }
  cmp "$want_stderr" "$stderr" || {
    printf 'projectile-motion: %s stderr mismatch\n' "$name" >&2
    diff -u "$want_stderr" "$stderr" >&2 || true
    exit 1
  }
}

# The documented case from the issue.
run_case documented 0 \
  $'flight-time = 2.883208\nmax-height = 10.193680\nrange = 40.774720\n' '' \
  20 45
# Low speed.
run_case low 0 \
  $'flight-time = 0.509684\nmax-height = 0.318552\nrange = 2.206996\n' '' \
  5 30
# Medium speed at a steeper angle.
run_case medium 0 \
  $'flight-time = 3.531194\nmax-height = 15.290520\nrange = 35.311943\n' '' \
  20 60
run_case steep 0 \
  $'flight-time = 5.907803\nmax-height = 42.798748\nrange = 45.871560\n' '' \
  30 75
# Vertical launch: all the speed is vertical, so the range rounds to zero.
run_case vertical 0 \
  $'flight-time = 4.077472\nmax-height = 20.387360\nrange = 0.000000\n' '' \
  20 90
# Flat launch: no vertical speed, so the projectile never leaves the ground.
run_case horizontal 0 \
  $'flight-time = 0.000000\nmax-height = 0.000000\nrange = 0.000000\n' '' \
  15 0
run_case zero-speed 0 \
  $'flight-time = 0.000000\nmax-height = 0.000000\nrange = 0.000000\n' '' \
  0 45
# Fractional speed and angle.
run_case fractional 0 \
  $'flight-time = 1.399141\nmax-height = 2.400501\nrange = 14.617651\n' '' \
  12.5 33.3

run_case angle-too-large 2 '' \
  $'error: angle must be between 0 and 90 degrees\n' 20 95
run_case angle-negative 2 '' \
  $'error: angle must be between 0 and 90 degrees\n' 20 -5
run_case speed-negative 2 '' \
  $'error: speed must not be negative\n' -5 45
run_case arity 2 '' $'usage: projectile-motion <speed> <angle>\n' 20
run_case malformed 2 '' $'error: not a number: x\n' 20 x

# Independent check of the printed range against the closed form
# v^2 * sin(2*theta) / g, computed outside the program. At 45 degrees
# sin(2*theta) is 1, so the range is exactly v^2/g.
awk -v v=20 -v g=9.81 'BEGIN {
  expected = (v * v) / g
  printf "range = %.6f\n", expected
}' > "$TMP/closed-form.txt"
grep -F 'range = ' "$TMP/documented.stdout" > "$TMP/actual-range.txt"
cmp "$TMP/closed-form.txt" "$TMP/actual-range.txt" || {
  printf 'projectile-motion: range disagrees with the closed form\n' >&2
  diff -u "$TMP/closed-form.txt" "$TMP/actual-range.txt" >&2 || true
  exit 1
}

# Application source stays on the ordinary surface and adds no trigonometry.
if grep -Eq '\bptr\b|\bextern\b|call_(i32|i64|f32|f64|ptr|void)|const_[a-z0-9_]+|ptr_add|load_|store_|weave_rt_' \
    "$ROOT/examples/projectile-motion/main.weave"; then
  printf 'projectile-motion: application source leaked low-level forms\n' >&2
  exit 1
fi
if grep -Eq '\(fn (sin|cos|tan)_|Taylor|3\.14159' \
    "$ROOT/examples/projectile-motion/main.weave"; then
  printf 'projectile-motion: example reimplemented trigonometry or pi\n' >&2
  exit 1
fi
# The gravity constant is declared once, not repeated as a literal.
if [[ "$(grep -c '9\.81' "$ROOT/examples/projectile-motion/main.weave")" -ne 1 ]]; then
  printf 'projectile-motion: gravity is not a single named constant\n' >&2
  exit 1
fi

grep -Fq '(fn sin_f64' "$WIR"
grep -Fq '(fn cos_f64' "$WIR"
grep -Fq '(fn degrees_to_radians' "$WIR"

printf 'projectile-motion: passed\n'
