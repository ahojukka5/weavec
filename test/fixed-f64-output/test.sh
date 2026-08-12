#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-fixed-f64-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.weave" <<'EOF'
(program
  (name "fixed-f64-output-test")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (call_void write_f64_fixed6 (const_f64 0.0))
      (call_void write_stdout (const_string_ptr "\n"))
      (call_void write_f64_fixed6 (const_f64 1.0))
      (call_void write_stdout (const_string_ptr "\n"))
      (call_void write_f64_fixed6 (const_f64 0.5))
      (call_void write_stdout (const_string_ptr "\n"))
      (call_void write_f64_fixed6 (const_f64 0.8660254))
      (call_void write_stdout (const_string_ptr "\n"))
      (call_void write_f64_fixed6 (const_f64 1.7320508))
      (call_void write_stdout (const_string_ptr "\n"))
      (call_void write_f64_fixed6 (const_f64 -2.25))
      (call_void write_stdout (const_string_ptr "\n"))
      (call_void write_f64_fixed6 (const_f64 1.9999996))
      (call_void write_stdout (const_string_ptr "\n"))
      (return (const_i32 0)))))
EOF

"$WEAVEC" build \
  "$ROOT/stdlib/io.weave" \
  "$TMP/main.weave" \
  -o "$TMP/fixed-f64-output"

"$TMP/fixed-f64-output" > "$TMP/actual.txt"
cat > "$TMP/expected.txt" <<'EOF'
0.000000
1.000000
0.500000
0.866025
1.732051
-2.250000
2.000000
EOF

cmp "$TMP/expected.txt" "$TMP/actual.txt" || {
  printf 'fixed-f64-output: stdout mismatch\n' >&2
  diff -u "$TMP/expected.txt" "$TMP/actual.txt" >&2 || true
  exit 1
}

printf 'fixed-f64-output: passed\n'
