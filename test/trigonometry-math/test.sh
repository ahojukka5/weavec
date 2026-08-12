#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-trig-math-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

run_case() {
  local name="$1"
  local expression="$2"
  local low="$3"
  local high="$4"
  local source="$TMP/$name.weave"
  local binary="$TMP/$name"

  cat > "$source" <<EOF
(program
  (name "trigonometry-$name")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let value f64 $expression)
      (if
        (condition (and_bool
          (ge_f64 (local_get value) (const_f64 $low))
          (le_f64 (local_get value) (const_f64 $high))))
        (then (do (return (const_i32 0))))
        (else (do (return (const_i32 1))))))))
EOF

  "$WEAVEC" build \
    "$ROOT/stdlib/math.weave" \
    "$source" \
    -o "$binary"

  set +e
  "$binary"
  local status="$?"
  set -e
  if [[ "$status" -ne 0 ]]; then
    printf 'trigonometry-math: %s returned %s\n' "$name" "$status" >&2
    exit 1
  fi
}

run_case pi \
  '(call_f64 PI_F64)' \
  3.1415926 3.1415927
run_case radians-180 \
  '(call_f64 degrees_to_radians (const_f64 180.0))' \
  3.1415926 3.1415927
run_case sine-30 \
  '(call_f64 sin_f64 (call_f64 degrees_to_radians (const_f64 30.0)))' \
  0.4999999 0.5000001
run_case cosine-60 \
  '(call_f64 cos_f64 (call_f64 degrees_to_radians (const_f64 60.0)))' \
  0.4999999 0.5000001
run_case sine-45 \
  '(call_f64 sin_f64 (call_f64 degrees_to_radians (const_f64 45.0)))' \
  0.7071067 0.7071069
run_case tangent-45 \
  '(call_f64 tan_f64 (call_f64 degrees_to_radians (const_f64 45.0)))' \
  0.9999999 1.0000001
run_case tangent-60 \
  '(call_f64 tan_f64 (call_f64 degrees_to_radians (const_f64 60.0)))' \
  1.7320507 1.7320510
run_case sine-390 \
  '(call_f64 sin_f64 (call_f64 degrees_to_radians (const_f64 390.0)))' \
  0.4999999 0.5000001

printf 'trigonometry-math: passed\n'
