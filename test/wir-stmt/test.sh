#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-stmt-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-stmt: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

# Ratchet migrated scalar builder modules off textual WIR fragments.
for module in wir_scalar wir_scalar_literals wir_scalar_expr wir_operator \
  wir_call wir_stmt; do
  if grep -E 'write_cstr|write_byte' "$ROOT/src/frontend/${module}.weave" |
    grep -Ev '^;'; then
    printf 'wir-stmt: %s still writes textual WIR fragments\n' "$module" >&2
    exit 1
  fi
done

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/src/parser/tree.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/src/wir/invariants.weave" \
  "$ROOT/src/wir/decimal.weave" \
  "$ROOT/src/wir/serialize.weave" \
  "$ROOT/src/frontend/wir_scalar.weave" \
  "$ROOT/src/frontend/wir_operator.weave" \
  "$ROOT/src/frontend/wir_call.weave" \
  "$ROOT/src/frontend/wir_stmt.weave" \
  "$ROOT/test/wir-stmt/main.weave" \
  -o "$TMP/wir-stmt-test"

"$TMP/wir-stmt-test"
printf 'wir-stmt: let/set/return/return_void builders and ownership passed\n'
