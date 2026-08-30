#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-serialize-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-serialize: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

COMMON=(
  "$ROOT/src/core/extern.weave"
  "$ROOT/src/parser/tokens.weave"
  "$ROOT/src/parser/tree.weave"
  "$ROOT/src/parser/lexer.weave"
  "$ROOT/src/parser/parser.weave"
  "$ROOT/src/core/io.weave"
  "$ROOT/src/core/util.weave"
  "$ROOT/src/wir/tree.weave"
  "$ROOT/src/wir/invariants.weave"
  "$ROOT/src/wir/decimal.weave"
  "$ROOT/src/wir/serialize.weave"
)

"$WEAVEC" build \
  "${COMMON[@]}" \
  "$ROOT/test/wir-serialize/main.weave" \
  -o "$TMP/wir-serialize-test"
"$TMP/wir-serialize-test"

"$WEAVEC" build \
  "${COMMON[@]}" \
  "$ROOT/test/wir-serialize-decimal/main.weave" \
  -o "$TMP/wir-serialize-decimal-test"
"$TMP/wir-serialize-decimal-test"

bash "$ROOT/test/wir-decimal/test.sh"
bash "$ROOT/test/wir-subtree/test.sh"
bash "$ROOT/test/wir-scalar/test.sh"
bash "$ROOT/test/wir-scalar-literals/test.sh"
bash "$ROOT/test/wir-operator/test.sh"

printf 'wir-serialize: canonical, rollback, decimal, subtree, scalar literals, and operator qualifications passed\n'
