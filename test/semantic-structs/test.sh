#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-semantic-structs-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'semantic-structs: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/registry.c" <<'C'
#include <assert.h>
#include <stdint.h>
#include <string.h>
#include "runtime/surface_symbols.c"

int main(void) {
    const char source[] = "ForwardRecordcode";
    weave_surface_symbols_reset();
    int32_t provisional = weave_surface_struct_type_or_declare(source, 0, 13);
    assert(provisional >= WEAVEC_SURFACE_STRUCT_TYPE_BASE);
    assert(weave_surface_struct_is_type(provisional));
    assert(!weave_surface_struct_is_defined(provisional));
    int32_t defined = weave_surface_struct_define(source, 0, 13);
    assert(defined == provisional);
    assert(weave_surface_struct_is_defined(defined));
    assert(weave_surface_struct_add_field(defined, source, 13, 4, 2) == 0);
    assert(weave_surface_struct_add_field(defined, source, 13, 4, 3) == -2);
    assert(weave_surface_struct_field_count(defined) == 1);
    assert(weave_surface_struct_field_type(defined, 0) == 2);
    assert(strcmp(weave_surface_struct_field_name(defined, 0), "code") == 0);
    assert(weave_surface_struct_find_field(defined, source, 13, 4) == 0);
    assert(weave_surface_struct_field_type(defined, 1) == 0);
    assert(weave_surface_struct_field_name(defined, 1) == NULL);
    assert(weave_surface_struct_define(source, 0, 13) == -2);
    int32_t second = weave_surface_struct_type_or_declare(source, 7, 6);
    assert(second != defined);
    assert(weave_surface_struct_is_type(second));
    assert(!weave_surface_struct_is_defined(second));
    weave_surface_symbols_reset();
    return 0;
}
C
cc -std=c11 -Wall -Wextra -Werror -I"$ROOT" "$TMP/registry.c" -o "$TMP/registry"
"$TMP/registry"

cat > "$TMP/valid.weave" <<'WEAVE'
(program
  (name "semantic-structs-valid")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (extern free (params (value ptr)) (returns void))
  (struct Record
    (field count i64)
    (field flag bool)
    (field total f64))
  (fn identity
    (params (value Record))
    (returns Record)
    (do
      (return value)))
  (entry main
    (params)
    (returns i32)
    (do
      (let item Record
        (new Record
          (total 2)
          (flag true)
          (count 40)))
      (let copy Record (call identity item))
      (if
        (condition (op equal copy null))
        (then (do (return 2)))
        (else (do)))
      (field-set copy count
        (op add (field-get copy count) 2))
      (if
        (condition (field-get copy flag))
        (then (do))
        (else (do (return 1))))
      (let result i32 (cast i32 (field-get copy count)))
      (call free copy)
      (return result))))
WEAVE

"$WEAVEC" --frontend "$TMP/valid.wir" "$TMP/valid.weave"

grep -F 'identity (params (value ptr)) (returns ptr)' "$TMP/valid.wir" >/dev/null
grep -F '(let item ptr (call_ptr Record_new (const_i64 40) (const_bool true) (const_f64 2)))' \
  "$TMP/valid.wir" >/dev/null
grep -F '(let copy ptr (call_ptr identity item))' "$TMP/valid.wir" >/dev/null
grep -F '(eq_ptr copy (const_null))' "$TMP/valid.wir" >/dev/null
grep -F '(call_void Record_set_count copy (add_i64 (call_i64 Record_get_count copy) (const_i64 2)))' \
  "$TMP/valid.wir" >/dev/null
grep -F '(call_bool Record_get_flag copy)' "$TMP/valid.wir" >/dev/null
grep -F '(call_i64 Record_get_count copy)' "$TMP/valid.wir" >/dev/null

"$WEAVEC" build "$TMP/valid.weave" -o "$TMP/valid"
set +e
"$TMP/valid"
status=$?
set -e
[[ "$status" -eq 42 ]]

cat > "$TMP/use.weave" <<'WEAVE'
(program
  (name "semantic-struct-use")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (fn read
    (params (value Later))
    (returns i32)
    (do
      (return (field-get value code))))
  (entry main
    (params)
    (returns i32)
    (do
      (let value Later (new Later (code 42)))
      (return (call read value)))))
WEAVE

cat > "$TMP/type.weave" <<'WEAVE'
(program
  (name "semantic-struct-type")
  (version "0.1")
  (struct Later
    (field code i32)))
WEAVE

"$WEAVEC" --frontend "$TMP/cross-file.wir" "$TMP/use.weave" "$TMP/type.weave"
grep -F 'read (params (value ptr)) (returns i32)' "$TMP/cross-file.wir" >/dev/null
grep -F '(let value ptr (call_ptr Later_new (const_i32 42)))' "$TMP/cross-file.wir" >/dev/null
"$WEAVEC" build "$TMP/use.weave" "$TMP/type.weave" -o "$TMP/cross-file"
set +e
"$TMP/cross-file"
status=$?
set -e
[[ "$status" -eq 42 ]]

check_failure() {
  local name="$1"
  local code="$2"
  local role="$3"
  local span_text="$4"
  local stderr_text="$5"

  set +e
  "$WEAVEC" build "$TMP/$name.weave" -o "$TMP/$name" \
    --diagnostics-json "$TMP/$name.json" 2>"$TMP/$name.err"
  local status=$?
  set -e
  [[ "$status" -eq 10 ]]
  [[ ! -e "$TMP/$name" ]]
  grep -F "$stderr_text" "$TMP/$name.err" >/dev/null

  python3 - "$TMP/$name.json" "$TMP/$name.weave" "$code" "$role" "$span_text" <<'PY'
import json
import sys
from pathlib import Path

document = json.loads(Path(sys.argv[1]).read_text())
source = Path(sys.argv[2]).read_text()
code, role, span_text = sys.argv[3:]
matches = [item for item in document["diagnostics"] if item["code"] == code]
assert matches, (code, document["diagnostics"])
diagnostic = matches[0]
assert diagnostic["span_origin"] == "compiler-semantic"
assert diagnostic["analysis_complete"] is True
assert diagnostic["operand_role"] == role
span = diagnostic["span"]
assert source[span["start_byte"]:span["end_byte"]] == span_text
assert diagnostic["repairs"] == []
PY
}

cat > "$TMP/malformed-constructor.weave" <<'WEAVE'
(program
  (name "malformed-constructor")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point (field x i32))
  (entry main (params) (returns i32)
    (do
      (let point Point (new Point ((op add 1 1) 2)))
      (return 0))))
WEAVE
check_failure \
  malformed-constructor \
  frontend.struct.constructor.malformed \
  constructor-field \
  '(op add 1 1)' \
  'weavec: surface struct constructor: field name must be an identifier'

cat > "$TMP/unknown-field.weave" <<'WEAVE'
(program
  (name "unknown-field")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point (field x i32))
  (entry main (params) (returns i32)
    (do
      (let point Point (new Point (y 1)))
      (return 0))))
WEAVE
check_failure \
  unknown-field \
  frontend.struct.constructor.unknown-field \
  constructor-field \
  y \
  'weavec: surface struct constructor: unknown field y for Point'

cat > "$TMP/duplicate-field.weave" <<'WEAVE'
(program
  (name "duplicate-constructor-field")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point (field x i32))
  (entry main (params) (returns i32)
    (do
      (let point Point (new Point (x 1) (x 2)))
      (return 0))))
WEAVE
check_failure \
  duplicate-field \
  frontend.struct.constructor.duplicate-field \
  constructor-field \
  x \
  'weavec: surface struct constructor: duplicate field x'

cat > "$TMP/missing-field.weave" <<'WEAVE'
(program
  (name "missing-constructor-field")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point (field x i32) (field y i32))
  (entry main (params) (returns i32)
    (do
      (let point Point (new Point (x 1)))
      (return 0))))
WEAVE
check_failure \
  missing-field \
  frontend.struct.constructor.missing-field \
  constructor \
  '(new Point (x 1))' \
  'weavec: surface struct constructor: missing field y for Point'

cat > "$TMP/value-type.weave" <<'WEAVE'
(program
  (name "constructor-value-type")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point (field x i32))
  (entry main (params) (returns i32)
    (do
      (let point Point (new Point (x true)))
      (return 0))))
WEAVE
check_failure \
  value-type \
  frontend.struct.field-type-mismatch \
  field-value \
  true \
  'weavec: surface struct constructor: field x expects i32, got bool'

cat > "$TMP/receiver-type.weave" <<'WEAVE'
(program
  (name "receiver-type")
  (version "0.1")
  (entry main (params) (returns i32)
    (do
      (let value i32 1)
      (return (field-get value x)))))
WEAVE
check_failure \
  receiver-type \
  frontend.struct.receiver-type \
  receiver \
  value \
  'weavec: surface struct field: receiver is not a known struct value'

cat > "$TMP/access-field.weave" <<'WEAVE'
(program
  (name "access-field")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point (field x i32))
  (entry main (params) (returns i32)
    (do
      (let point Point (new Point (x 1)))
      (return (field-get point y)))))
WEAVE
check_failure \
  access-field \
  frontend.struct.field.unknown \
  field \
  y \
  'weavec: surface struct field: unknown field y for Point'

cat > "$TMP/set-type.weave" <<'WEAVE'
(program
  (name "set-type")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Point (field x i32))
  (entry main (params) (returns i32)
    (do
      (let point Point (new Point (x 1)))
      (field-set point x false)
      (return 0))))
WEAVE
check_failure \
  set-type \
  frontend.struct.field-type-mismatch \
  field-value \
  false \
  'weavec: surface struct field: field x expects i32, got bool'

cat > "$TMP/undefined-type.weave" <<'WEAVE'
(program
  (name "undefined-type")
  (version "0.1")
  (fn consume (params (value Missing)) (returns i32) (do (return 0)))
  (entry main (params) (returns i32) (do (return 0))))
WEAVE
check_failure \
  undefined-type \
  frontend.struct.undefined-type \
  struct-type \
  Missing \
  'weavec: surface struct type: undefined struct type Missing'

cat > "$TMP/nominal-call.weave" <<'WEAVE'
(program
  (name "nominal-call")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Left (field value i32))
  (struct Right (field value i32))
  (fn consume (params (value Left)) (returns i32) (do (return 0)))
  (entry main (params) (returns i32)
    (do
      (let value Right (new Right (value 1)))
      (return (call consume value)))))
WEAVE
check_failure \
  nominal-call \
  frontend.call.argument-type-mismatch \
  argument \
  value \
  'weavec: surface call: argument type mismatch for consume: expected Left, got Right'

cat > "$TMP/reserved-type.weave" <<'WEAVE'
(program
  (name "reserved-type")
  (version "0.1")
  (struct i32 (field value i32))
  (entry main (params) (returns i32) (do (return 0))))
WEAVE
check_failure \
  reserved-type \
  frontend.struct.reserved-type \
  struct-type \
  i32 \
  'weavec: surface struct declaration: reserved struct name i32'

cat > "$TMP/nominal-equality.weave" <<'WEAVE'
(program
  (name "nominal-equality")
  (version "0.1")
  (extern malloc (params (size i64)) (returns ptr))
  (struct Left (field value i32))
  (struct Right (field value i32))
  (entry main (params) (returns i32)
    (do
      (let left Left (new Left (value 1)))
      (let right Right (new Right (value 1)))
      (if (condition (op equal left right))
        (then (do (return 1)))
        (else (do (return 0)))))))
WEAVE
check_failure \
  nominal-equality \
  frontend.operator.operand-type-mismatch \
  right \
  right \
  'weavec: surface operator: operand type mismatch for equal'

printf 'semantic-structs: all checks passed\n'
