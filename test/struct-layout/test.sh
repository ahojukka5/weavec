#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-struct-layout-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'struct-layout: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/mixed.weave" <<'WEAVE'
(program
  (name "mixed-struct")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (extern free (params (value ptr)) (returns void))
  (struct Mixed
    (field flag bool)
    (field count i64)
    (field ratio f32)
    (field total f64)
    (field data ptr)
    (field qubit Qubit)
    (field code i32))
  (entry main
    (params)
    (returns i32)
    (do
      (let item ptr
        (call_ptr Mixed_new
          (const_bool true)
          (const_i64 9)
          (const_f32 1)
          (const_f64 2)
          (const_null)
          (const_i64 3)
          (const_i32 7)))
      (if
        (condition (eq_ptr (local_get item) (const_null)))
        (then (do (return (const_i32 1))))
        (else (do)))
      (let flag_value bool (call_bool Mixed_get_flag (local_get item)))
      (if
        (condition (not_bool (local_get flag_value)))
        (then (do
          (call_void free (local_get item))
          (return (const_i32 2))))
        (else (do)))
      (call_void Mixed_set_code (local_get item) (const_i32 42))
      (let result i32 (call_i32 Mixed_get_code (local_get item)))
      (call_void free (local_get item))
      (return (local_get result)))))
WEAVE

"$WEAVEC" --frontend "$TMP/mixed.wir" "$TMP/mixed.weave"

grep -F 'Mixed_new (params (flag bool) (count i64) (ratio f32) (total f64) (data ptr) (qubit i64) (code i32))' \
  "$TMP/mixed.wir" >/dev/null
grep -F '(call_ptr malloc (const_i64 56))' "$TMP/mixed.wir" >/dev/null
grep -F '(ne_i32 (load_u8 (param_get self)) (const_i32 0))' "$TMP/mixed.wir" >/dev/null
grep -F '(store_i8 (local_get self) (const_i32 1))' "$TMP/mixed.wir" >/dev/null
grep -F '(load_i64 (ptr_add (param_get self) (const_i64 8)))' "$TMP/mixed.wir" >/dev/null
grep -F '(load_f32 (ptr_add (param_get self) (const_i64 16)))' "$TMP/mixed.wir" >/dev/null
grep -F '(load_f64 (ptr_add (param_get self) (const_i64 24)))' "$TMP/mixed.wir" >/dev/null
grep -F '(load_ptr (ptr_add (param_get self) (const_i64 32)))' "$TMP/mixed.wir" >/dev/null
grep -F '(load_i64 (ptr_add (param_get self) (const_i64 40)))' "$TMP/mixed.wir" >/dev/null
grep -F '(load_i32 (ptr_add (param_get self) (const_i64 48)))' "$TMP/mixed.wir" >/dev/null
grep -F '(store_f32 (ptr_add (local_get self) (const_i64 16)) (param_get ratio))' \
  "$TMP/mixed.wir" >/dev/null
grep -F '(store_f64 (ptr_add (local_get self) (const_i64 24)) (param_get total))' \
  "$TMP/mixed.wir" >/dev/null

"$WEAVEC" build "$TMP/mixed.weave" -o "$TMP/mixed"
set +e
"$TMP/mixed"
status=$?
set -e
[[ "$status" -eq 42 ]]

cat > "$TMP/unsupported.weave" <<'WEAVE'
(program
  (name "unsupported-struct")
  (version "0.1")
  (struct Broken
    (field child Other))
  (entry main (params) (returns i32) (do (return (const_i32 0)))))
WEAVE

set +e
"$WEAVEC" build "$TMP/unsupported.weave" -o "$TMP/unsupported" \
  --diagnostics-json "$TMP/unsupported.json" 2>"$TMP/unsupported.err"
status=$?
set -e
[[ "$status" -eq 10 ]]
[[ ! -e "$TMP/unsupported" ]]
grep -F 'weavec: surface struct: unsupported field type Other for field child' \
  "$TMP/unsupported.err" >/dev/null

python3 - "$TMP/unsupported.json" "$TMP/unsupported.weave" <<'PY'
import json
import sys
from pathlib import Path

document = json.loads(Path(sys.argv[1]).read_text())
source = Path(sys.argv[2]).read_text()
diagnostics = document["diagnostics"]
assert document["phase"] == "frontend"
assert document["exit_code"] == 10
assert diagnostics
diagnostic = diagnostics[0]
assert diagnostic["code"] == "frontend.struct.unsupported-field-type"
assert diagnostic["span_origin"] == "compiler-semantic"
assert diagnostic["analysis_complete"] is True
assert diagnostic["operand_role"] == "field-type"
span = diagnostic["span"]
assert source[span["start_byte"]:span["end_byte"]] == "Other"
assert diagnostic["repairs"] == []
PY

cat > "$TMP/duplicate.weave" <<'WEAVE'
(program
  (name "duplicate-struct")
  (version "0.1")
  (struct Broken
    (field value i32)
    (field value i64))
  (entry main (params) (returns i32) (do (return (const_i32 0)))))
WEAVE

set +e
"$WEAVEC" --frontend "$TMP/duplicate.wir" "$TMP/duplicate.weave" \
  2>"$TMP/duplicate.err"
status=$?
set -e
[[ "$status" -ne 0 ]]
[[ ! -e "$TMP/duplicate.wir" ]]
grep -F 'weavec: surface struct: duplicate field value' \
  "$TMP/duplicate.err" >/dev/null

cat > "$TMP/malformed.weave" <<'WEAVE'
(program
  (name "malformed-struct")
  (version "0.1")
  (struct Broken
    (member value i32))
  (entry main (params) (returns i32) (do (return (const_i32 0)))))
WEAVE

set +e
"$WEAVEC" --frontend "$TMP/malformed.wir" "$TMP/malformed.weave" \
  2>"$TMP/malformed.err"
status=$?
set -e
[[ "$status" -ne 0 ]]
[[ ! -e "$TMP/malformed.wir" ]]
grep -F 'weavec: surface struct: fields must use (field NAME TYPE)' \
  "$TMP/malformed.err" >/dev/null

printf 'struct-layout: all checks passed\n'
