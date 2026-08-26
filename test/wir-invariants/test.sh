#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-wir-invariants-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'wir-invariants: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/src/wir/invariants.weave" \
  "$ROOT/test/wir-invariants/main.weave" \
  -o "$TMP/wir-invariants-test"

"$TMP/wir-invariants-test"

printf 'wir-invariants: allocation and cycle guards passed\n'
