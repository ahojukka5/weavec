#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-decimal-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-decimal: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/src/wir/invariants.weave" \
  "$ROOT/src/wir/decimal.weave" \
  "$ROOT/test/wir-decimal/main.weave" \
  -o "$TMP/wir-decimal-test"

"$TMP/wir-decimal-test"

printf 'wir-decimal: owned lexeme validation passed\n'
