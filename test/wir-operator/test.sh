#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-operator-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-operator: compiler not found: %s\n' "$WEAVEC" >&2
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
  "$ROOT/src/frontend/wir_operator.weave" \
  "$ROOT/test/wir-operator/main.weave" \
  -o "$TMP/wir-operator-test"

"$TMP/wir-operator-test"
printf 'wir-operator: typed heads, binary/unary operators, and casts passed\n'
