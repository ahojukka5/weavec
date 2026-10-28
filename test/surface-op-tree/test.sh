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

cat > "$TMP/identifiers.weave" <<'WEAVE'
(program
  (name "surface-op-tree-identifiers")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let alpha bool true)
      (let beta bool false)
      (if
        (condition (and alpha (or beta (not beta))))
        (then (do (return 42)))
        (else (do (return 0)))))))
WEAVE

"$WEAVEC" --frontend "$TMP/identifiers.wir" "$TMP/identifiers.weave"
got="$(normalize_wir "$TMP/identifiers.wir")"
printf '%s\n' "$got" | grep -Fq '(and_bool alpha (or_bool beta (not_bool beta)))' || {
  printf 'surface-op-tree: bare-identifier and/or WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/identifiers.weave" -o "$TMP/identifiers"
set +e
"$TMP/identifiers"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-op-tree: bare-identifier program exited %s\n' "$status" >&2
  exit 1
}

# The end-to-end WIR is the same whether the tree path or the text renderer
# wrote it, so call the tree path directly: it must own leaf and nested
# operators and must decline (code 0, no bytes) an unmigrated if operand.
# Link the compiler's frontend sources (not src/main.weave) with the host
# runtime, as build.sh does for the compiler. Relative paths keep the
# command line within the driver's argument limits.
harness_sources=()
while IFS= read -r line; do
  case "$line" in
    ''|'#'*|'!'*|src/main.weave) continue ;;
  esac
  harness_sources+=("$line")
done < "$ROOT/compiler/sources.list"
(cd "$ROOT" && "$WEAVEC" build "${harness_sources[@]}" \
  test/surface-op-tree/main.weave --runtime runtime/portable.c \
  -o "$TMP/op-tree-direct")
"$TMP/op-tree-direct" > "$TMP/direct.txt"
cat > "$TMP/direct.expected" <<'EXPECTED'
(not_bool (const_bool true))|1
(and_bool alpha beta)|1
(or_bool (not_bool (const_bool true)) (const_bool false))|1
|0
|0
EXPECTED
cmp "$TMP/direct.expected" "$TMP/direct.txt" || {
  printf 'surface-op-tree: direct tree-path result changed\n' >&2
  diff -u "$TMP/direct.expected" "$TMP/direct.txt" >&2 || true
  exit 1
}

# The direct call above cannot notice if the emitter stopped calling the tree
# path (the text renderer would produce the same WIR), so the emitter must keep
# its one unary and two binary publish call sites.
calls="$(grep -Ec 'call_i32 sot_try_publish_(unary|binary)' \
  "$ROOT/src/frontend/surface_op_emit.weave")"
[[ "$calls" -eq 3 ]] || {
  printf 'surface-op-tree: emitter tree-path call sites changed (%s, want 3)\n' "$calls" >&2
  exit 1
}

printf 'surface-op-tree: leaf, nested, call-operand, identifier, arity and direct tree paths passed\n'
