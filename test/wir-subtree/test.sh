#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-subtree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-subtree: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/test/wir-subtree/io_stub.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/src/wir/invariants.weave" \
  "$ROOT/src/wir/decimal.weave" \
  "$ROOT/src/wir/serialize.weave" \
  "$ROOT/src/frontend/wir_subtree.weave" \
  "$ROOT/test/wir-subtree/main.weave" \
  -o "$TMP/wir-subtree-test"

"$TMP/wir-subtree-test" > "$TMP/out.txt"
cat > "$TMP/expected.txt" <<'EOF'
(core-module (core-version 3) (decls (fn synthetic (params) (returns i32) (do (return (const_i32 7))))))
before|after
EOF

cmp "$TMP/expected.txt" "$TMP/out.txt" || {
  printf 'wir-subtree: unexpected publication bytes\n' >&2
  diff -u "$TMP/expected.txt" "$TMP/out.txt" >&2 || true
  exit 1
}

printf 'wir-subtree: complete publication and zero-byte failure passed\n'
