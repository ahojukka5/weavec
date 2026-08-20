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

run_fixture() {
  local stem="$1"
  local expected_exit="$2"
  local fixture="$ROOT/test/correctness/surface/$stem.weave"
  local expected="$ROOT/test/correctness/surface/$stem.expected.wir"
  "$WEAVEC" --frontend "$TMP/$stem.wir" "$fixture"
  [[ "$(normalize_wir "$TMP/$stem.wir")" == "$(normalize_wir "$expected")" ]]
  "$WEAVEC" build "$fixture" -o "$TMP/$stem"
  set +e
  "$TMP/$stem"
  local status=$?
  set -e
  [[ "$status" -eq "$expected_exit" ]]
}

run_fixture 75_canonical_typed_call 42
run_fixture 76_canonical_ops_and_casts 42
run_fixture 77_contract_canonical_result 42
run_fixture 78_lisp_head_call 42

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
    (do (return (forty_two)))))
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

cat > "$TMP/reserved.weave" <<'WEAVE'
(program
  (name "reserved-call-name")
  (version "0.1")
  (fn if
    (params (value i32))
    (returns i32)
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do (return 0))))
WEAVE
set +e
"$WEAVEC" --frontend "$TMP/reserved.wir" "$TMP/reserved.weave" \
  2>"$TMP/reserved.stderr"
status=$?
set -e
[[ "$status" -ne 0 ]]
grep -Fq 'function name collides with reserved syntax if' \
  "$TMP/reserved.stderr"

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

cat > "$TMP/bool-integer.weave" <<'WEAVE'
(program
  (name "bool-integer")
  (version "0.1")
  (fn consume (params (value bool)) (returns i32) (do (return 42)))
  (entry main (params) (returns i32)
    (do (return (call consume 1)))))
WEAVE
expect_frontend_failure bool-integer 'argument type mismatch for consume: expected bool, got i32'

cat > "$TMP/mixed-op.weave" <<'WEAVE'
(program
  (name "mixed-op")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (let wide i64 (cast i64 2))
      (return (op add (const_i32 40) wide)))))
WEAVE
expect_frontend_failure mixed-op 'operand type mismatch for add'

cat > "$TMP/unsupported-cast.weave" <<'WEAVE'
(program
  (name "unsupported-cast")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (cast ptr 1)))))
WEAVE
expect_frontend_failure unsupported-cast 'unsupported cast from i32 to ptr'

cat > "$TMP/operator-arity.weave" <<'WEAVE'
(program
  (name "operator-arity")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (op add 1)))))
WEAVE
expect_frontend_failure operator-arity 'wrong arity for add: expected 2, got 1'

cat > "$TMP/contract-result-type.weave" <<'WEAVE'
(program
  (name "contract-result-type")
  (version "0.1")
  (fn accepts_i32
    (params (value i32))
    (returns bool)
    (do (return true)))
  (fn checked
    (params (value i64))
    (returns i64)
    (ensures (call accepts_i32 result))
    (do (return value)))
  (entry main
    (params)
    (returns i32)
    (do (return (cast i32 (call checked 42))))))
WEAVE
expect_frontend_failure contract-result-type \
  'argument type mismatch for accepts_i32: expected i32, got i64'

printf 'surface-elaboration: all checks passed\n'
