#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-io-stderr-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.weave" <<'EOF'
(program
  (name "io-stderr-test")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (call write_stderr "error text\n")
      (return 0))))
EOF

"$WEAVEC" build \
  "$ROOT/stdlib/io.weave" \
  "$TMP/main.weave" \
  -o "$TMP/io-stderr"

"$TMP/io-stderr" >"$TMP/stdout" 2>"$TMP/stderr"
printf 'error text\n' > "$TMP/expected.stderr"
[[ ! -s "$TMP/stdout" ]]
cmp "$TMP/expected.stderr" "$TMP/stderr"
printf 'io-stderr: passed\n'
