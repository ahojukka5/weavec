#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-elaboration-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'surface-elaboration: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

normalize_wir() {
  tr '\n\t\r' ' ' < "$1" |
    sed -E 's/[[:space:]]+/ /g; s/\( /(/g; s/ \)/)/g; s/^ //; s/ $//'
}

FIXTURE="$ROOT/test/correctness/surface/75_canonical_typed_call.weave"
EXPECTED="$ROOT/test/correctness/surface/75_canonical_typed_call.expected.wir"
"$WEAVEC" --frontend "$TMP/canonical.wir" "$FIXTURE"
[[ "$(normalize_wir "$TMP/canonical.wir")" == "$(normalize_wir "$EXPECTED")" ]]
"$WEAVEC" build "$FIXTURE" -o "$TMP/canonical"
set +e
"$TMP/canonical"
status=$?
set -e
[[ "$status" -eq 42 ]]

cat > "$TMP/library.weave" <<'WEAVE'
(program
  (name "library")
  (version "0.1")
  (fn forty_two
    (params)
    (returns i32)
    (do (return 42))))
WEAVE

cat > "$TMP/main.weave" <<'WEAVE'
(program
  (name "main")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (call forty_two)))))
WEAVE

# Put the caller first to prove that pass-zero registration resolves forward
# declarations across separately parsed source files.
"$WEAVEC" --frontend "$TMP/multi.wir" "$TMP/main.weave" "$TMP/library.weave"
grep -F '(call_i32 forty_two)' "$TMP/multi.wir" >/dev/null
"$WEAVEC" build "$TMP/main.weave" "$TMP/library.weave" -o "$TMP/multi"
set +e
"$TMP/multi"
status=$?
set -e
[[ "$status" -eq 42 ]]

cat > "$TMP/contract.weave" <<'WEAVE'
(program
  (name "contract-call")
  (version "0.1")
  (fn identity
    (params (value i32))
    (returns i32)
    (do (return value)))
  (fn checked
    (params (value i32))
    (returns i32)
    (requires (ge_i32 value (const_i32 0)))
    (do (return (call identity value))))
  (entry main
    (params)
    (returns i32)
    (do (return (call checked 42)))))
WEAVE
"$WEAVEC" --frontend "$TMP/contract.wir" "$TMP/contract.weave"
grep -F '(call_i32 identity value)' "$TMP/contract.wir" >/dev/null
"$WEAVEC" build "$TMP/contract.weave" -o "$TMP/contract"
set +e
"$TMP/contract"
status=$?
set -e
[[ "$status" -eq 42 ]]

expect_frontend_failure() {
  local name="$1"
  local expected="$2"
  set +e
  "$WEAVEC" --frontend "$TMP/$name.wir" "$TMP/$name.weave" 2>"$TMP/$name.err"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]]
  grep -F "$expected" "$TMP/$name.err" >/dev/null
}

cat > "$TMP/unresolved.weave" <<'WEAVE'
(program
  (name "unresolved")
  (version "0.1")
  (entry main (params) (returns i32) (do (return (call missing)))))
WEAVE
expect_frontend_failure unresolved 'unresolved function missing'

cat > "$TMP/arity.weave" <<'WEAVE'
(program
  (name "arity")
  (version "0.1")
  (fn add (params (left i32) (right i32)) (returns i32)
    (do (return (add_i32 left right))))
  (entry main (params) (returns i32) (do (return (call add 1)))))
WEAVE
expect_frontend_failure arity 'wrong arity for add: expected 2, got 1'

cat > "$TMP/type.weave" <<'WEAVE'
(program
  (name "type")
  (version "0.1")
  (fn consume (params (value i64)) (returns i32) (do (return 42)))
  (entry main (params) (returns i32)
    (do (return (call consume (const_i32 1))))))
WEAVE
expect_frontend_failure type 'argument type mismatch for consume: expected i64, got i32'

printf 'surface-elaboration: all checks passed\n'
