#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Qualify #380 module-envelope and ordinary declaration tree lowering: extern,
# fn, entry, and const build as complete WIR subtrees, bodies compose migrated
# statement/expression nodes, and unmigrated children keep the text path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-surface-decl-tree-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'surface-decl-tree: compiler not found: %s\n' "$WEAVEC" >&2
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
    printf 'surface-decl-tree: %s was accepted\n' "$name" >&2
    exit 1
  }
  grep -Fq "$expected" "$TMP/$name.err" || {
    printf 'surface-decl-tree: %s diagnostic changed\n' "$name" >&2
    cat "$TMP/$name.err" >&2
    exit 1
  }
}

if grep -E 'write_cstr|write_byte' "$ROOT/src/frontend/wir_decl.weave" |
  grep -Ev '^;'; then
  printf 'surface-decl-tree: wir_decl.weave still writes textual WIR fragments\n' >&2
  exit 1
fi

"$WEAVEC" build \
  "$ROOT/src/core/extern.weave" \
  "$ROOT/src/parser/tree.weave" \
  "$ROOT/src/wir/tree.weave" \
  "$ROOT/src/wir/invariants.weave" \
  "$ROOT/src/wir/decimal.weave" \
  "$ROOT/src/wir/serialize.weave" \
  "$ROOT/src/frontend/wir_scalar.weave" \
  "$ROOT/src/frontend/wir_scalar_literals.weave" \
  "$ROOT/src/frontend/wir_stmt.weave" \
  "$ROOT/src/frontend/wir_decl.weave" \
  "$ROOT/test/surface-decl-tree/envelope.weave" \
  -o "$TMP/envelope"
set +e
"$TMP/envelope"
envelope_status=$?
set -e
[[ "$envelope_status" -eq 0 ]] || {
  printf 'surface-decl-tree: envelope builder program exited %s\n' \
    "$envelope_status" >&2
  exit 1
}

cat > "$TMP/ordinary.weave" <<'WEAVE'
(program
  (name "surface-decl-tree-ordinary")
  (version "0.1")
  (extern abort
    (params (code i32))
    (returns void))
  (const forty i32 40)
  (fn add2
    (params (n i32))
    (returns i32)
    (do
      (return (add_i32 (param_get n) (const_i32 2)))))
  (entry main
    (params)
    (returns i32)
    (do
      (return (call_i32 add2 (call_i32 forty))))))
WEAVE

"$WEAVEC" --frontend "$TMP/ordinary.wir" "$TMP/ordinary.weave"
got="$(normalize_wir "$TMP/ordinary.wir")"
printf '%s\n' "$got" | grep -Fq '(core-module (core-version 3) (decls' || {
  printf 'surface-decl-tree: module envelope WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(extern abort (params (code i32)) (returns void))' || {
  printf 'surface-decl-tree: extern WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(fn forty (params) (returns i32) (do (return (const_i32 40))))' || {
  printf 'surface-decl-tree: const WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(fn add2 (params (n i32)) (returns i32) (do (return (add_i32 (param_get n) (const_i32 2)))))' || {
  printf 'surface-decl-tree: fn WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(fn main (params) (returns i32) (do (return (call_i32 add2 (call_i32 forty)))))' || {
  printf 'surface-decl-tree: entry WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
if printf '%s\n' "$got" | grep -Fq '(entry '; then
  printf 'surface-decl-tree: entry head was not lowered to fn\n%s\n' "$got" >&2
  exit 1
fi

"$WEAVEC" --backend "$TMP/ordinary.wir" "$TMP/ordinary.ll"

"$WEAVEC" build "$TMP/ordinary.weave" -o "$TMP/ordinary"
set +e
"$TMP/ordinary"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-decl-tree: ordinary program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/compact.weave" <<'WEAVE'
(program
  (name "surface-decl-tree-compact")
  (version "0.1")
  (fn add2 ((n i32)) i32
    (return (+ n 2)))
  (entry main (params) (returns i32)
    (return (add2 40))))
WEAVE

"$WEAVEC" --frontend "$TMP/compact.wir" "$TMP/compact.weave"
got="$(normalize_wir "$TMP/compact.wir")"
printf '%s\n' "$got" | grep -Fq '(fn add2 (params (n i32)) (returns i32) (do' || {
  printf 'surface-decl-tree: compact fn WIR mismatch\n%s\n' "$got" >&2
  exit 1
}
printf '%s\n' "$got" | grep -Fq '(fn main (params) (returns i32) (do' || {
  printf 'surface-decl-tree: compact entry WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/compact.weave" -o "$TMP/compact"
set +e
"$TMP/compact"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-decl-tree: compact program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/control-flow.weave" <<'WEAVE'
(program
  (name "surface-decl-tree-control-flow")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do
      (if
        (condition (eq_i32 (const_i32 1) (const_i32 1)))
        (then (do (return 42)))
        (else (do (return 1)))))))
WEAVE

"$WEAVEC" --frontend "$TMP/control-flow.wir" "$TMP/control-flow.weave"
got="$(normalize_wir "$TMP/control-flow.wir")"
printf '%s\n' "$got" | grep -Fq '(fn main' || {
  printf 'surface-decl-tree: control-flow entry WIR mismatch\n%s\n' "$got" >&2
  exit 1
}

"$WEAVEC" build "$TMP/control-flow.weave" -o "$TMP/control-flow"
set +e
"$TMP/control-flow"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-decl-tree: control-flow program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/helper.weave" <<'WEAVE'
(program
  (name "surface-decl-tree-helper")
  (version "0.1")
  (extern abort
    (params (code i32))
    (returns void))
  (fn helper
    (params)
    (returns i32)
    (do (return 2))))
WEAVE

cat > "$TMP/main.weave" <<'WEAVE'
(program
  (name "surface-decl-tree-main")
  (version "0.1")
  (fn extra
    (params)
    (returns i32)
    (do (return 40)))
  (entry main
    (params)
    (returns i32)
    (do
      (return (add_i32 (call_i32 extra) (call_i32 helper))))))
WEAVE

"$WEAVEC" --frontend "$TMP/ordered.wir" "$TMP/helper.weave" "$TMP/main.weave"
got="$(normalize_wir "$TMP/ordered.wir")"
python3 - "$got" <<'PY'
import sys
got = sys.argv[1]
extern = got.find('(extern abort')
extra = got.find('(fn extra')
main = got.find('(fn main')
helper = got.find('(fn helper')
if min(extern, extra, main, helper) < 0:
    raise SystemExit('surface-decl-tree: multifile decl missing')
if not (extern < extra < main < helper):
    raise SystemExit('surface-decl-tree: multifile ordering changed')
PY

"$WEAVEC" build "$TMP/helper.weave" "$TMP/main.weave" -o "$TMP/ordered"
set +e
"$TMP/ordered"
status=$?
set -e
[[ "$status" -eq 42 ]] || {
  printf 'surface-decl-tree: multifile program exited %s\n' "$status" >&2
  exit 1
}

cat > "$TMP/return-type.weave" <<'WEAVE'
(program
  (name "surface-decl-tree-return-type")
  (version "0.1")
  (entry main
    (params)
    (returns i32)
    (do (return (const_i64 1)))))
WEAVE
expect_frontend_failure return-type 'expected i32, got i64'

printf 'surface-decl-tree: envelope, extern/fn/entry/const, compact, fallback, and ordering passed\n'
