#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-tree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-tree: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/test/wir-tree/main.weave" \
  -o "$TMP/wir-tree-test"

"$TMP/wir-tree-test"

printf 'wir-tree: owned arena and builder passed\n'
