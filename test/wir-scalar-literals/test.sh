#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-scalar-literals-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-scalar-literals: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/src/parser/tree.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/src/wir/invariants.weave" \
  "$ROOT/src/wir/decimal.weave" \
  "$ROOT/src/wir/serialize.weave" \
  "$ROOT/src/frontend/wir_scalar.weave" \
  "$ROOT/src/frontend/wir_scalar_literals.weave" \
  "$ROOT/test/wir-scalar-literals/main.weave" \
  -o "$TMP/wir-scalar-literals-test"

"$TMP/wir-scalar-literals-test"
printf 'wir-scalar-literals: float, bool, null, and ownership passed\n'
