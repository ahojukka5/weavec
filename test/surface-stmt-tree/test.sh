#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Qualify #413 let/set/return tree lowering: ordinary statements compose
# tree-built children, bare return is return_void, and inference/type
# diagnostics stay on stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-stmt-tree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'surface-stmt-tree: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

normalize_wir() {
  tr '\n\t\r' ' ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

expect_frontend_failure() {
  local name="$1"
  local expected="$2"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" 2>"$TMP/$name.err"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || {
    printf 'surface-stmt-tree: %s was accepted\n' "$name" >&2
    exit 1
  }
  grep -Fq "$expected" "$TMP/$name.err" || {
    printf 'surface-stmt-tree: %s diagnostic changed\n' "$name" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  }
}

cat > "$TMP/let-set-return.weave" <<'WEAVE'
(program
  (name "surface-stmt-tree-let-set-return")
  (version "0.1")
  (fn forty
    (params)
    (returns i32)
    (do (return 40)))
  (entry main
    (params)
    (returns i32)
    (do
      (let n i32 (forty))
      (set n (+ n 2))
      (return n))))
WEAVE

"$WEAVEC" --frontend "$TMP/let-set-return.wir" "$TMP/let-set-return.weave"
got="$(normalize_wir "$TMP/let-set-return.wir")"
printf '%s\n' "$got" | grep -Fq '(let n i32 (call_i32 forty))' || {
  printf 'surface-stmt-tree: typed let WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(set n (add_i32 (local_get n) (const_i32 2)))' || {
  printf 'surface-stmt-tree: set WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(return (local_get n))' || {
  printf 'surface-stmt-tree: return WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/let-set-return.weave" -o "$TMP/let-set-return"
set +e
"$TMP/let-set-return"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-stmt-tree: let/set/return program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/inferred.weave" <<'WEAVE'
(program
  (name "surface-stmt-tree-inferred")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n 40)
      (return (+ n 2)))))
WEAVE

"$WEAVEC" --frontend "$TMP/inferred.wir" "$TMP/inferred.weave"
got="$(normalize_wir "$TMP/inferred.wir")"
printf '%s\n' "$got" | grep -Fq '(let n i32 (const_i32 40))' || {
  printf 'surface-stmt-tree: inferred let WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/inferred.weave" -o "$TMP/inferred"
set +e
"$TMP/inferred"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-stmt-tree: inferred program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/void-return.weave" <<'WEAVE'
(program
  (name "surface-stmt-tree-void-return")
  (version "0.1")
  (fn mark
    (params)
    (returns void)
    (do (return)))
  (entry main
    (params)
    (returns i32)
    (do
      (call_void mark)
      (return 42))))
WEAVE

"$WEAVEC" --frontend "$TMP/void-return.wir" "$TMP/void-return.weave"
got="$(normalize_wir "$TMP/void-return.wir")"
printf '%s\n' "$got" | grep -Fq '(return_void)' || {
  printf 'surface-stmt-tree: bare return WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/void-return.weave" -o "$TMP/void-return"
set +e
"$TMP/void-return"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-stmt-tree: void-return program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/untyped.weave" <<'WEAVE'
(program
  (name "surface-stmt-tree-untyped")
  (version "0.1")
  (fn nope
    (params)
    (returns void)
    (do (return)))
  (entry main
    (params)
    (returns i32)
    (do
      (let n (call nope))
      (return 0))))
WEAVE
expect_frontend_failure untyped 'let needs a type annotation'

cat > "$TMP/return-type.weave" <<'WEAVE'
(program
  (name "surface-stmt-tree-return-type")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (const_i64 1)))))
WEAVE
expect_frontend_failure return-type 'expected i32, got i64'

cat > "$TMP/set-type.weave" <<'WEAVE'
(program
  (name "surface-stmt-tree-set-type")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let n i32 1)
      (set n (const_i64 2))
      (return n))))
WEAVE
expect_frontend_failure set-type 'expected i32, got i64'

printf 'surface-stmt-tree: let/set/return, inferred, void, and diagnostics passed\n'
