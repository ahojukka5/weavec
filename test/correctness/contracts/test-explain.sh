#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WEAVEC2="$ROOT/build/weavec2"
SRC="$ROOT/test/correctness/surface/64_contract_ensures_multi_return.weave"
EXPECTED="$ROOT/test/correctness/contracts/64_explain.expected.txt"

log() { printf '[weavec2-explain-test] %s\n' "$*"; }
fail() { printf '[weavec2-explain-test] error: %s\n' "$*" >&2; exit 1; }

[[ -x "$WEAVEC2" ]] || fail "build/weavec2 not found; run ./build.sh first"

actual="$(mktemp)"
trap 'rm -f "$actual"' EXIT

"$WEAVEC2" --explain "$SRC" >"$actual"

if ! diff -u "$EXPECTED" "$actual"; then
  fail "explain output mismatch"
fi

log "ok explain output"
exit 0
