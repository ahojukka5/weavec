#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WEAVEC2="$ROOT/build/weavec"
SRC="$ROOT/test/correctness/contracts/explain_audit_malloc_while.weave"
EXPECTED_TXT="$ROOT/test/correctness/contracts/explain_audit_malloc_while.expected.txt"
EXPECTED_JSON="$ROOT/test/correctness/contracts/explain_audit_malloc_while.expected.json"

log() { printf '[weavec-explain-audit-test] %s\n' "$*"; }
fail() { printf '[weavec-explain-audit-test] error: %s\n' "$*" >&2; exit 1; }

[[ -x "$WEAVEC2" ]] || fail "weavec not found: $WEAVEC2 (run ./build.sh)"
[[ -f "$SRC" ]] || fail "missing source: $SRC"
[[ -f "$EXPECTED_TXT" ]] || fail "missing expected text: $EXPECTED_TXT"
[[ -f "$EXPECTED_JSON" ]] || fail "missing expected json: $EXPECTED_JSON"

actual_txt="$(mktemp)"
actual_json="$(mktemp)"
trap 'rm -f "$actual_txt" "$actual_json"' EXIT

"$WEAVEC2" --explain "$SRC" >"$actual_txt"
if ! diff -u "$EXPECTED_TXT" "$actual_txt"; then
  fail "explain text output mismatch"
fi
log "ok explain text output"

"$WEAVEC2" --explain-json "$SRC" >"$actual_json"
if ! diff -u "$EXPECTED_JSON" "$actual_json"; then
  fail "explain json output mismatch"
fi
log "ok explain json output"
