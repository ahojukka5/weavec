#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WEAVEC2="$ROOT/build/weavec"

log() { printf '[weavec-audit-test] %s\n' "$*"; }
fail() { printf '[weavec-audit-test] error: %s\n' "$*" >&2; exit 1; }

[[ -x "$WEAVEC2" ]] || fail "weavec not found: $WEAVEC2 (run ./build.sh)"

run_case() {
  local name="$1"
  local src="$2"
  local expected="$3"
  local actual
  actual="$(mktemp)"
  trap 'rm -f "$actual"' RETURN
  [[ -f "$src" ]] || fail "missing source: $src"
  [[ -f "$expected" ]] || fail "missing expected: $expected"
  "$WEAVEC2" --audit "$src" >"$actual"
  if ! diff -u "$expected" "$actual"; then
    fail "audit output mismatch for $name"
  fi
  log "ok $name"
}

run_case clamp \
  "$ROOT/test/correctness/surface/64_contract_ensures_multi_return.weave" \
  "$ROOT/test/correctness/contracts/audit_clamp.expected.txt"

run_case malloc-while \
  "$ROOT/test/correctness/contracts/explain_audit_malloc_while.weave" \
  "$ROOT/test/correctness/contracts/audit_malloc_while.expected.txt"

run_case effect-inc \
  "$ROOT/test/correctness/contracts/audit_effect_inc.weave" \
  "$ROOT/test/correctness/contracts/audit_effect_inc.expected.txt"

run_case effect-puts-fail \
  "$ROOT/test/correctness/contracts/audit_effect_puts_fail.weave" \
  "$ROOT/test/correctness/contracts/audit_effect_puts_fail.expected.txt"

run_case effect-malloc-fail \
  "$ROOT/test/correctness/contracts/audit_effect_malloc_fail.weave" \
  "$ROOT/test/correctness/contracts/audit_effect_malloc_fail.expected.txt"

run_case effect-unknown \
  "$ROOT/test/correctness/contracts/audit_effect_unknown.weave" \
  "$ROOT/test/correctness/contracts/audit_effect_unknown.expected.txt"

log "ok audit golden tests"
