#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Qualify #412 ordinary/typed call tree lowering: zero/one/multi-argument
# calls must match canonical WIR, typed heads stay exact, specialization
# names stay deterministic, and unresolved/arity/type diagnostics stay on
# stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-call-tree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'surface-call-tree: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'surface-call-tree: %s was accepted\n' "$name" >&2
    exit 1
  }
  grep -Fq "$expected" "$TMP/$name.err" || {
    printf 'surface-call-tree: %s diagnostic changed\n' "$name" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  }
}

cat > "$TMP/zero.weave" <<'WEAVE'
(program
  (name "surface-call-tree-zero")
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

"$WEAVEC" --frontend "$TMP/zero.wir" "$TMP/zero.weave"
got="$(normalize_wir "$TMP/zero.wir")"
printf '%s\n' "$got" | grep -Fq '(add_i32 (call_i32 forty) (const_i32 2))' || {
  printf 'surface-call-tree: zero-arg call WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/zero.weave" -o "$TMP/zero"
set +e
"$TMP/zero"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-call-tree: zero-arg program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/multi.weave" <<'WEAVE'
(program
  (name "surface-call-tree-multi")
  (version "0.1")
  (fn add2
    (params (left i32) (right i32))
    (returns i32)
    (do (return (+ left right))))
  (entry main
    (params)
    (returns i32)
    (do
      (return (add2 40 2)))))
WEAVE

"$WEAVEC" --frontend "$TMP/multi.wir" "$TMP/multi.weave"
got="$(normalize_wir "$TMP/multi.wir")"
printf '%s\n' "$got" | grep -Fq '(call_i32 add2 (const_i32 40) (const_i32 2))' || {
  printf 'surface-call-tree: multi-arg call WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/multi.weave" -o "$TMP/multi"
set +e
"$TMP/multi"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-call-tree: multi-arg program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/typed.weave" <<'WEAVE'
(program
  (name "surface-call-tree-typed")
  (version "0.1")
  (fn answer64
    (params)
    (returns i64)
    (do (return (const_i64 42))))
  (entry main
    (params)
    (returns i32)
    (do
      (return (cast i32 (answer64))))))
WEAVE

"$WEAVEC" --frontend "$TMP/typed.wir" "$TMP/typed.weave"
got="$(normalize_wir "$TMP/typed.wir")"
printf '%s\n' "$got" | grep -Fq '(cast_i64_to_i32 (call_i64 answer64))' || {
  printf 'surface-call-tree: typed call head mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/typed.weave" -o "$TMP/typed"
set +e
"$TMP/typed"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-call-tree: typed program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/spec.weave" <<'WEAVE'
(program
  (name "surface-call-tree-spec")
  (version "0.1")
  (fn id
    (type-params T)
    (params (value T))
    (returns T)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do
      (return (id (type-args i32) 42)))))
WEAVE

"$WEAVEC" --frontend "$TMP/spec.wir" "$TMP/spec.weave"
got="$(normalize_wir "$TMP/spec.wir")"
printf '%s\n' "$got" | grep -Fq '(call_i32 id__s__i32 (const_i32 42))' || {
  printf 'surface-call-tree: specialization name mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/spec.weave" -o "$TMP/spec"
set +e
"$TMP/spec"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-call-tree: specialization program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/unresolved.weave" <<'WEAVE'
(program
  (name "surface-call-tree-unresolved")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (missing)))))
WEAVE
expect_frontend_failure unresolved 'unresolved function missing'

cat > "$TMP/arity.weave" <<'WEAVE'
(program
  (name "surface-call-tree-arity")
  (version "0.1")
  (fn add2
    (params (left i32) (right i32))
    (returns i32)
    (do (return (+ left right))))
  (entry main
    (params)
    (returns i32)
    (do (return (add2 1)))))
WEAVE
expect_frontend_failure arity 'wrong arity for add2: expected 2, got 1'

cat > "$TMP/type.weave" <<'WEAVE'
(program
  (name "surface-call-tree-type")
  (version "0.1")
  (fn consume
    (params (value i64))
    (returns i32)
    (do (return 42)))
  (entry main
    (params)
    (returns i32)
    (do (return (consume (const_i32 1))))))
WEAVE
expect_frontend_failure type 'argument type mismatch for consume: expected i64, got i32'

printf 'surface-call-tree: arity shapes, typed heads, specs, and diagnostics passed\n'
