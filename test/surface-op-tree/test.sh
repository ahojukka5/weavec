#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Qualify #411 operator/cast tree lowering: leaf-only forms must match the
# canonical compact WIR, nested ops/casts must compose, call operands still
# lower, and arity diagnostics stay on stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-op-tree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'surface-op-tree: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

normalize_wir() {
  tr '\n\t\r' ' ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

cat > "$TMP/leaves.weave" <<'WEAVE'
(program
  (name "surface-op-tree-leaves")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (return (+ (cast i32 (cast i64 40)) 2)))))
WEAVE

"$WEAVEC" --frontend "$TMP/leaves.wir" "$TMP/leaves.weave"
got="$(normalize_wir "$TMP/leaves.wir")"
printf '%s\n' "$got" | grep -Fq '(add_i32 (cast_i64_to_i32 (cast_i32_to_i64 (const_i32 40))) (const_i32 2))' || {
  printf 'surface-op-tree: leaf operator/cast WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/leaves.weave" -o "$TMP/leaves"
set +e
"$TMP/leaves"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-op-tree: leaf program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/nested.weave" <<'WEAVE'
(program
  (name "surface-op-tree-nested")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (if
        (condition (not (or (not true) false)))
        (then (do (return (+ 40 2))))
        (else (do (return 0)))))))
WEAVE

"$WEAVEC" --frontend "$TMP/nested.wir" "$TMP/nested.weave"
got="$(normalize_wir "$TMP/nested.wir")"
printf '%s\n' "$got" | grep -Fq '(not_bool (or_bool (not_bool (const_bool true)) (const_bool false)))' || {
  printf 'surface-op-tree: nested bool operator WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/nested.weave" -o "$TMP/nested"
set +e
"$TMP/nested"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-op-tree: nested program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/call-operand.weave" <<'WEAVE'
(program
  (name "surface-op-tree-call-operand")
  (version "0.1")
  (fn forty
    (params)
    (returns i32)
    (do (return 40)))
  (entry main
    (params)
    (returns i32)
    (do
      (return (+ (forty) 2)))))
WEAVE

"$WEAVEC" --frontend "$TMP/call.wir" "$TMP/call-operand.weave"
got="$(normalize_wir "$TMP/call.wir")"
printf '%s\n' "$got" | grep -Fq '(add_i32 (call_i32 forty) (const_i32 2))' || {
  printf 'surface-op-tree: call-operand operator WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/call-operand.weave" -o "$TMP/call-operand"
set +e
"$TMP/call-operand"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-op-tree: call-operand program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/arity.weave" <<'WEAVE'
(program
  (name "surface-op-tree-arity")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (+ 1)))))
WEAVE

set +e
"$WEAVEC" --frontend "$TMP/arity.wir" "$TMP/arity.weave" 2>"$TMP/arity.err"
status=$?
set -e
[[ "$status" -ne 0 ]] || {
  printf 'surface-op-tree: wrong-arity operator was accepted\n' >&2
  exit 1
}
grep -Fq 'wrong arity for +: expected 2, got 1' "$TMP/arity.err" || {
  printf 'surface-op-tree: arity diagnostic changed\n' >&2
  cat "$TMP/arity.err" >&2
  exit 1
}

printf 'surface-op-tree: leaf, nested, call-operand, and arity paths passed\n'
