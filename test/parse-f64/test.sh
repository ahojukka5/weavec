#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-parse-f64-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.weave" <<'EOF'
(program
  (name "parse-f64-test")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (if
        (condition (op not (call parse_f64_valid "3")))
        (then (do (return 1)))
        (else (do)))
      (if
        (condition (op not (call parse_f64_valid "-2.25")))
        (then (do (return 2)))
        (else (do)))
      (if
        (condition (call parse_f64_valid "1."))
        (then (do (return 3)))
        (else (do)))
      (if
        (condition (call parse_f64_valid ".5"))
        (then (do (return 4)))
        (else (do)))
      (if
        (condition (call parse_f64_valid "4x"))
        (then (do (return 5)))
        (else (do)))
      (let integer f64 (call parse_f64 "3"))
      (if
        (condition (op not-equal integer 3.0))
        (then (do (return 6)))
        (else (do)))
      (let decimal f64 (call parse_f64 "1.5"))
      (if
        (condition (op not-equal decimal 1.5))
        (then (do (return 7)))
        (else (do)))
      (let negative f64 (call parse_f64 "-2.25"))
      (if
        (condition (op not-equal negative -2.25))
        (then (do (return 8)))
        (else (do)))
      (return 0))))
EOF

"$WEAVEC" build \
  "$ROOT/stdlib/parse.weave" \
  "$TMP/main.weave" \
  -o "$TMP/parse-f64"

"$TMP/parse-f64"
printf 'parse-f64: passed\n'
