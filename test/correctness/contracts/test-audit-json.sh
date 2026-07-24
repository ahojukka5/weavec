#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WEAVEC2="$ROOT/build/weavec"

log() { printf '[weavec-audit-json-test] %s\n' "$*"; }
fail() { printf '[weavec-audit-json-test] error: %s\n' "$*" >&2; exit 1; }

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
  "$WEAVEC2" --audit-json "$src" >"$actual"
  if ! diff -u "$expected" "$actual"; then
    fail "audit-json output mismatch for $name"
  fi
  log "ok $name"
}

run_case effect-inc \
  "$ROOT/test/correctness/contracts/audit_effect_inc.weave" \
  "$ROOT/test/correctness/contracts/audit_effect_inc.expected.json"

run_case effect-malloc-fail \
  "$ROOT/test/correctness/contracts/audit_effect_malloc_fail.weave" \
  "$ROOT/test/correctness/contracts/audit_effect_malloc_fail.expected.json"

log "ok audit-json golden tests"
