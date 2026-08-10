#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-sqrt-f64-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.weave" <<'EOF'
(program
  (name "sqrt-f64-test")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let exact f64 (call sqrt_f64 9.0))
      (if
        (condition (op not-equal exact 3.0))
        (then (do (return 1)))
        (else (do)))
      (let fractional f64 (call sqrt_f64 6.25))
      (if
        (condition (op not-equal fractional 2.5))
        (then (do (return 2)))
        (else (do)))
      (let irrational f64 (call sqrt_f64 2.0))
      (if
        (condition (op less-than irrational 1.4142))
        (then (do (return 3)))
        (else (do)))
      (if
        (condition (op greater-than irrational 1.4143))
        (then (do (return 4)))
        (else (do)))
      (if
        (condition (op not-equal (call sqrt_f64 0.0) 0.0))
        (then (do (return 5)))
        (else (do)))
      (return 0))))
EOF

"$WEAVEC" build \
  "$ROOT/stdlib/math.weave" \
  "$TMP/main.weave" \
  -o "$TMP/sqrt-f64"

"$TMP/sqrt-f64"
printf 'sqrt-f64: passed\n'
