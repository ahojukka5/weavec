#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WEAVEC="$ROOT/build/weavec"
SRC="$ROOT/test/correctness/surface/64_contract_ensures_multi_return.weave"
EXPECTED="$ROOT/test/correctness/contracts/64_explain.expected.txt"

log() { printf '[weavec-explain-test] %s\n' "$*"; }
fail() { printf '[weavec-explain-test] error: %s\n' "$*" >&2; exit 1; }

[[ -x "$WEAVEC" ]] || fail "build/weavec not found; run ./build.sh first"

actual="$(mktemp)"
trap 'rm -f "$actual"' EXIT

"$WEAVEC" --explain "$SRC" >"$actual"

if ! diff -u "$EXPECTED" "$actual"; then
  fail "explain output mismatch"
fi

log "ok explain output"
exit 0
