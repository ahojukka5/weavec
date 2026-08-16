#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# WIR declares a struct without a layout. The backend derives the layout,
# because layout is a property of the target and the backend is the component
# that knows the target. See docs/wir-next-struct-fields.md.
#
# The offsets asserted here are the `Mixed` table in docs/struct-layout.md. That
# table was the frontend's layout before this moved; reproducing it exactly is
# what makes the move a relocation rather than a rewrite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-struct-forms-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[[ -x "$WEAVEC" ]] || {
  printf 'struct-forms: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

expect_ir() {
  local label="$1"
  local pattern="$2"
  if ! grep -Eq "$pattern" "$TMP/mixed.ll"; then
    printf 'struct-forms: %s not found\n' "$label" >&2
    printf 'expected to match: %s\n' "$pattern" >&2
    exit 1
  fi
}

cat > "$TMP/mixed.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Mixed
      (field flag bool)
      (field count i64)
      (field ratio f32)
      (field total f64)
      (field data ptr)
      (field qubit i64)
      (field code i32))
    (fn size_of (params) (returns i64)
      (do (return (struct_size Mixed))))
    (fn addr_code (params (m ptr)) (returns ptr)
      (do (return (field_addr Mixed code (param_get m)))))
    (fn read_total (params (m ptr)) (returns f64)
      (do (return (field_get_f64 Mixed total (param_get m)))))
    (fn read_flag (params (m ptr)) (returns bool)
      (do (return (field_get_bool Mixed flag (param_get m)))))
    (fn write_count (params (m ptr) (v i64)) (returns void)
      (do (field_set_i64 Mixed count (param_get m) (param_get v)) (return_void)))
    (fn write_flag (params (m ptr) (v bool)) (returns void)
      (do (field_set_bool Mixed flag (param_get m) (param_get v)) (return_void)))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF

"$WEAVEC" --backend "$TMP/mixed.wir" "$TMP/mixed.ll" 2>"$TMP/mixed.stderr" || {
  printf 'struct-forms: backend rejected the module\n' >&2
  cat "$TMP/mixed.stderr" >&2
  exit 1
}

# No byte offset appears in WIR; every one of these was derived here.
expect_ir 'total allocation size'  '= add i64 0, 56'
expect_ir 'offset of code (48)'    'getelementptr i8, ptr %m, i64 48'
expect_ir 'offset of total (24)'   'getelementptr i8, ptr %m, i64 24'
expect_ir 'offset of count (8)'    'getelementptr i8, ptr %m, i64 8'
expect_ir 'offset of flag (0)'     'getelementptr i8, ptr %m, i64 0'
expect_ir 'typed field load'       '= load double, ptr %t[0-9]+'
expect_ir 'typed field store'      'store i64 %v, ptr %t[0-9]+'
# A bool field occupies one byte and narrows on read, widens on write.
expect_ir 'bool field load'        '= load i8, ptr %t[0-9]+'
expect_ir 'bool narrowing'         '= icmp ne i8 %t[0-9]+, 0'
expect_ir 'bool widening'          '= zext i1 %v to i8'
expect_ir 'bool field store'       'store i8 %t[0-9]+, ptr %t[0-9]+'

# The layout must not leak back into WIR.
if grep -Eq 'ptr_add|const_i64 (8|24|48|56)' "$TMP/mixed.wir"; then
  printf 'struct-forms: the fixture WIR contains a layout number\n' >&2
  exit 1
fi

if ! command -v llvm-as >/dev/null 2>&1; then
  printf 'struct-forms: llvm-as unavailable; skipping IR verification\n' >&2
else
  llvm-as "$TMP/mixed.ll" -o "$TMP/mixed.bc" || {
    printf 'struct-forms: generated IR does not verify\n' >&2
    exit 1
  }
fi

expect_rejected() {
  local name="$1"
  local needle="$2"

  set +e
  "$WEAVEC" --backend "$TMP/$name.wir" "$TMP/$name.ll" \
    >"$TMP/$name.stdout" 2>"$TMP/$name.stderr"
  local status="$?"
  set -e

  if [[ "$status" -eq 0 ]]; then
    printf 'struct-forms: %s was accepted\n' "$name" >&2
    exit 1
  fi
  if [[ -e "$TMP/$name.ll" ]]; then
    printf 'struct-forms: %s left partial output\n' "$name" >&2
    exit 1
  fi
  if ! grep -Fq "$needle" "$TMP/$name.stderr"; then
    printf 'struct-forms: %s missing expected diagnostic\n' "$name" >&2
    printf 'expected to contain: %s\n' "$needle" >&2
    cat "$TMP/$name.stderr" >&2
    exit 1
  fi
}

cat > "$TMP/unknown-struct.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Point (field x f64) (field y f64))
    (fn read (params (p ptr)) (returns f64)
      (do (return (field_get_f64 Missing x (param_get p)))))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected unknown-struct 'unknown struct: Missing'

# A field type the layout rules cannot resolve must be refused, not defaulted.
# Silently treating an unrecognised type as i32 would take i32's size and
# alignment and move every field after it, so this must fail loudly.
#
# A type naming a declared struct is resolvable and laid out inline; the case
# below names nothing at all.
cat > "$TMP/unsupported-field-type.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Outer (field tag i32) (field inner Absent) (field n i64))
    (fn read (params (o ptr)) (returns i64)
      (do (return (field_get_i64 Outer n (param_get o)))))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected unsupported-field-type \
  'struct Outer field inner has unsupported type Absent'

# The declaration is checked even when nothing accesses it, so a struct that is
# declared and never used cannot carry an unresolvable layout.
cat > "$TMP/unused-bad-struct.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Unused (field thing Whatever))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected unused-bad-struct \
  'struct Unused field thing has unsupported type Whatever'

cat > "$TMP/unknown-field.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Point (field x f64) (field y f64))
    (fn read (params (p ptr)) (returns f64)
      (do (return (field_get_f64 Point z (param_get p)))))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected unknown-field 'struct Point has no field named z'

# A field operation whose suffix disagrees with the declared type would emit a
# four-byte load from an eight-byte field and read half a double as an integer.
cat > "$TMP/suffix-mismatch.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Point (field x f64) (field y f64))
    (fn wrong (params (p ptr)) (returns i32)
      (do (return (field_get_i32 Point x (param_get p)))))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected suffix-mismatch \
  'field Point.x is declared f64, so it cannot be accessed as i32'

# ---------------------------------------------------------------------------
# Nested structs are laid out inline: a struct-typed field occupies the nested
# struct's bytes directly rather than a pointer to them.
# ---------------------------------------------------------------------------

cat > "$TMP/nested.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Inner (field a f64) (field b f64))
    (struct Outer (field tag i32) (field inner Inner) (field n i64))
    (fn size_inner (params) (returns i64) (do (return (struct_size Inner))))
    (fn size_outer (params) (returns i64) (do (return (struct_size Outer))))
    (fn addr_inner (params (o ptr)) (returns ptr)
      (do (return (field_addr Outer inner (param_get o)))))
    (fn addr_n (params (o ptr)) (returns ptr)
      (do (return (field_addr Outer n (param_get o)))))
    (fn read_inner_b (params (o ptr)) (returns f64)
      (do (return (field_get_f64 Inner b (field_addr Outer inner (param_get o))))))
    (fn write_inner_a (params (o ptr) (v f64)) (returns void)
      (do (field_set_f64 Inner a (field_addr Outer inner (param_get o)) (param_get v))
          (return_void)))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF

"$WEAVEC" --backend "$TMP/nested.wir" "$TMP/nested.ll" 2>"$TMP/nested.stderr" || {
  printf 'struct-forms: the backend rejected the nested module\n' >&2
  cat "$TMP/nested.stderr" >&2
  exit 1
}

expect_nested() {
  local label="$1"
  local pattern="$2"
  if ! grep -Eq "$pattern" "$TMP/nested.ll"; then
    printf 'struct-forms: %s not found\n' "$label" >&2
    printf 'expected to match: %s\n' "$pattern" >&2
    exit 1
  fi
}

# Inner is two f64: 16 bytes. Outer is tag at 0, inner aligned to 8 so it spans
# 8..24, n at 24: 32 bytes. A pointer-to-Inner layout would make Outer 24.
expect_nested 'Inner size'            '= add i64 0, 16'
expect_nested 'Outer size'            '= add i64 0, 32'
expect_nested 'offset of inner (8)'   'getelementptr i8, ptr %o, i64 8'
expect_nested 'offset of n (24)'      'getelementptr i8, ptr %o, i64 24'

# The composition claim the representation was designed around: a nested field
# is reached by chaining field_addr, with no path form and no grammar change.
expect_nested 'composed nested read'  'getelementptr i8, ptr %t[0-9]+, i64 8'
expect_nested 'composed nested write' 'store double %v, ptr %t[0-9]+'

if command -v llvm-as >/dev/null 2>&1; then
  llvm-as "$TMP/nested.ll" -o "$TMP/nested.bc" || {
    printf 'struct-forms: nested IR does not verify\n' >&2
    exit 1
  }
fi

# A struct-typed field has no scalar type, so no field_get_T suffix fits it.
cat > "$TMP/struct-as-scalar.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Inner (field a f64))
    (struct Outer (field inner Inner))
    (fn bad (params (o ptr)) (returns i64)
      (do (return (field_get_i64 Outer inner (param_get o)))))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected struct-as-scalar \
  'field Outer.inner is declared a struct, so it cannot be accessed as i64'

# A struct containing itself has no finite layout, directly or indirectly.
cat > "$TMP/direct-cycle.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct Node (field next Node) (field v i64))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected direct-cycle \
  'struct Node contains itself through field next, so it has no finite layout'

cat > "$TMP/indirect-cycle.wir" <<'EOF'
(core-module
  (core-version 3)
  (decls
    (struct A (field b B))
    (struct B (field a A))
    (fn main (params) (returns i32) (do (return (const_i32 0))))))
EOF
expect_rejected indirect-cycle \
  'struct A contains itself through field b, so it has no finite layout'

printf 'struct-forms: passed\n'
