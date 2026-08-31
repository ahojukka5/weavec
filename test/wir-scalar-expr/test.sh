#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-scalar-expr-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-scalar-expr: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/src/parser/tokens.weave" \
  "$ROOT/src/parser/tree.weave" \
  "$ROOT/src/parser/lexer.weave" \
  "$ROOT/src/parser/parser.weave" \
  "$ROOT/src/core/io.weave" \
  "$ROOT/src/core/util.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/src/wir/invariants.weave" \
  "$ROOT/src/wir/decimal.weave" \
  "$ROOT/src/wir/serialize.weave" \
  "$ROOT/src/frontend/wir_scalar.weave" \
  "$ROOT/src/frontend/wir_scalar_literals.weave" \
  "$ROOT/src/frontend/wir_scalar_expr.weave" \
  "$ROOT/test/wir-scalar-expr/main.weave" \
  -o "$TMP/wir-scalar-expr-test"

"$TMP/wir-scalar-expr-test"
printf 'wir-scalar-expr: leaf-only structural adapter and ownership passed\n'
