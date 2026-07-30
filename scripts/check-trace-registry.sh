#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$ROOT/src/core/trace_registry.weave"
EXPECTED="$ROOT/test/trace/expected-actions.txt"
DOC="$ROOT/docs/compilation-trace.md"

fail() {
  printf 'check-trace-registry: %s\n' "$*" >&2
  exit 1
}

[[ -f "$REGISTRY" ]] || fail "missing registry: $REGISTRY"
[[ -f "$EXPECTED" ]] || fail "missing action expectations: $EXPECTED"

declarations_file="$(mktemp)"
wrappers_file="$(mktemp)"
generated_actions="$(mktemp)"
trap 'rm -f "$declarations_file" "$wrappers_file" "$generated_actions"' EXIT

grep '^; trace-action ' "$REGISTRY" > "$declarations_file" || true
declaration_count="$(wc -l < "$declarations_file" | tr -d ' ')"
[[ "$declaration_count" -gt 0 ]] || fail "registry has no trace-action declarations"

while IFS= read -r declaration; do
  read -r marker label wrapper kind pass action shape extra <<<"$declaration"
  [[ "$marker" == ";" && "$label" == "trace-action" && -z "${extra:-}" ]] || \
    fail "invalid declaration: $declaration"
  [[ "$shape" == "node" || "$shape" == "range" ]] || \
    fail "invalid event shape for $wrapper: $shape"
  grep -Fxq "$wrapper" "$wrappers_file" && fail "duplicate wrapper: $wrapper"
  grep -Fxq "$action" "$generated_actions" && fail "duplicate action: $action"
  printf '%s\n' "$wrapper" >> "$wrappers_file"
  printf '%s\n' "$action" >> "$generated_actions"

  starts="$(grep -n -F "  (fn $wrapper" "$REGISTRY" || true)"
  start_count="$(printf '%s\n' "$starts" | awk 'NF { count++ } END { print count + 0 }')"
  [[ "$start_count" -eq 1 ]] || fail "$wrapper must have exactly one function"
  start="${starts%%:*}"
  next_relative="$(tail -n "+$((start + 1))" "$REGISTRY" | \
    grep -n -m1 '^  (fn ' | cut -d: -f1 || true)"
  if [[ -n "$next_relative" ]]; then
    end=$((start + next_relative - 1))
  else
    end="$(wc -l < "$REGISTRY")"
  fi
  block="$(sed -n "${start},${end}p" "$REGISTRY")"

  helper="trace_event_for_node"
  [[ "$shape" == "node" ]] || helper="trace_event_for_range"
  grep -Fq "(call_void $helper" <<<"$block" || \
    fail "$wrapper does not call $helper"
  grep -Fq "(const_string_ptr \"$kind\")" <<<"$block" || \
    fail "$wrapper kind drift: $kind"
  grep -Fq "(const_string_ptr \"$pass\")" <<<"$block" || \
    fail "$wrapper pass drift: $pass"
  grep -Fq "(const_string_ptr \"$action\")" <<<"$block" || \
    fail "$wrapper action drift: $action"

  call_count="$( (grep -R -F "(call_void $wrapper" "$ROOT/src/frontend" || true) | \
    wc -l | tr -d ' ')"
  [[ "$call_count" -gt 0 ]] || fail "$wrapper has no frontend call site"
  if grep -R -Fq "(const_string_ptr \"$action\")" "$ROOT/src/frontend"; then
    fail "raw action metadata bypasses registry: $action"
  fi
  grep -Fq "| \`$action\` |" "$DOC" || fail "action missing from documentation: $action"
done < "$declarations_file"

if grep -R -Eq 'call_void trace_event_for_(node|range)' "$ROOT/src/frontend"; then
  fail "frontend calls generic trace helper directly"
fi

while IFS= read -r wrapper; do
  grep -Fxq "$wrapper" "$wrappers_file" || fail "unregistered frontend wrapper: $wrapper"
done < <(
  grep -RhoE '\(call_void trace_[A-Za-z0-9_]+' "$ROOT/src/frontend" |
    sed 's/(call_void //' | sort -u
)

sort -u "$generated_actions" -o "$generated_actions"
cmp -s "$generated_actions" "$EXPECTED" || {
  diff -u "$EXPECTED" "$generated_actions" >&2 || true
  fail "expected action list differs from registry"
}

grep -Fq 'src/core/trace_registry.weave' "$ROOT/compiler/sources.list" || \
  fail "registry missing from canonical compiler source manifest"

grep -Fq 'scripts/check-trace-registry.sh' "$ROOT/test-all.sh" || \
  fail "registry audit is not part of test-all.sh"
grep -Fq 'expected-actions.txt' "$ROOT/test/trace/test.sh" || \
  fail "trace regression does not load audited action expectations"

printf 'check-trace-registry: %s actions passed\n' "$declaration_count"
