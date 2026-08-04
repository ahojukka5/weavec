#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-module-structs-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

command -v cc >/dev/null 2>&1 || {
  printf 'module-structs: cc is required\n' >&2
  exit 1
}
[[ -x "$WEAVEC" ]] || {
  printf 'module-structs: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/registry.c" <<'C'
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define weave_surface_symbols_reset weave_surface_symbols_reset_storage
#define weave_surface_symbol_begin weave_surface_symbol_begin_storage
#define weave_surface_struct_type_or_declare \
    weave_surface_struct_type_or_declare_storage
#define weave_surface_struct_define weave_surface_struct_define_storage
#define weave_surface_struct_name weave_surface_struct_name_storage
#define weave_surface_module_export_status \
    weave_surface_module_export_status_storage
#define weave_surface_module_import_status \
    weave_surface_module_import_status_storage
#include "runtime/surface_symbols.c"
#undef weave_surface_module_import_status
#undef weave_surface_module_export_status
#undef weave_surface_struct_name
#undef weave_surface_struct_define
#undef weave_surface_struct_type_or_declare
#undef weave_surface_symbol_begin
#undef weave_surface_symbols_reset
#define weave_surface_symbols_reset weave_surface_symbols_reset_symbol_names
#include "runtime/module_wir_names.c"
#undef weave_surface_symbols_reset
#include "runtime/module_struct_names.c"

int main(void) {
    static const char names[] = "alphaRecordvaluebetagamma";

    weave_surface_symbols_reset();
    assert(weave_surface_module_begin(names, 0, 5) == 0);
    int32_t alpha = weave_surface_struct_define(names, 5, 6);
    assert(alpha >= WEAVEC_SURFACE_STRUCT_TYPE_BASE);
    assert(weave_surface_struct_add_field(alpha, names, 11, 5, 2) == 0);
    assert(weave_surface_module_add_export(names, 5, 6) == 0);
    assert(weave_surface_module_export_status(names, 5, 6) == 0);
    assert(strcmp(weave_surface_struct_name(alpha), "Record") == 0);
    assert(strcmp(
        weave_surface_struct_wir_name(alpha),
        "__weave_m_616c706861__t_5265636f7264") == 0);

    assert(weave_surface_module_begin(names, 16, 4) == 1);
    int32_t beta = weave_surface_struct_define(names, 5, 6);
    assert(beta >= WEAVEC_SURFACE_STRUCT_TYPE_BASE);
    assert(beta != alpha);
    assert(weave_surface_struct_add_field(beta, names, 11, 5, 3) == 0);
    assert(strcmp(weave_surface_struct_name(beta), "Record") == 0);
    assert(strcmp(
        weave_surface_struct_wir_name(beta),
        "__weave_m_62657461__t_5265636f7264") == 0);
    assert(weave_surface_struct_field_type(alpha, 0) == 2);
    assert(weave_surface_struct_field_type(beta, 0) == 3);

    assert(weave_surface_module_begin(names, 20, 5) == 2);
    assert(weave_surface_module_add_import(
        names, 0, 5, 5, 6) == 0);
    assert(weave_surface_module_import_status(
        names, 0, 5, 5, 6) == 0);
    assert(weave_surface_module_import_status(
        names, 16, 4, 5, 6) == -3);
    assert(weave_surface_struct_type_or_declare(names, 5, 6) == alpha);

    assert(weave_surface_module_select(names, 0, 5) == 0);
    assert(weave_surface_struct_type_or_declare(names, 5, 6) == alpha);
    assert(weave_surface_module_select(names, 16, 4) == 1);
    assert(weave_surface_struct_type_or_declare(names, 5, 6) == beta);

    weave_surface_symbols_reset();
    assert(weave_surface_module_use_legacy() == 0);
    int32_t legacy = weave_surface_struct_define(names, 5, 6);
    assert(legacy >= WEAVEC_SURFACE_STRUCT_TYPE_BASE);
    assert(strcmp(weave_surface_struct_name(legacy), "Record") == 0);
    assert(strcmp(weave_surface_struct_wir_name(legacy), "Record") == 0);
    weave_surface_symbols_reset();

    puts("module-structs: registry identities passed");
    return 0;
}
C
cc -std=c11 -Wall -Wextra -Werror -I"$ROOT" \
  "$TMP/registry.c" -o "$TMP/registry"
"$TMP/registry"

cat > "$TMP/alpha.weave" <<'WEAVE'
(module alpha
  (export alpha-value)
  (extern malloc (params (size i64)) (returns ptr))
  (struct Record
    (field value i32))
  (fn alpha-value
    (params)
    (returns i32)
    (do
      (let item Record (new Record (value 20)))
      (return (field-get item value)))))
WEAVE

cat > "$TMP/beta.weave" <<'WEAVE'
(module beta
  (export beta-value)
  (struct Record
    (field value i64))
  (fn beta-value
    (params)
    (returns i32)
    (do
      (let item Record (new Record (value 22)))
      (return (cast i32 (field-get item value))))))
WEAVE

cat > "$TMP/main.weave" <<'WEAVE'
(module application
  (import alpha (alpha-value))
  (import beta (beta-value))
  (entry main
    (params)
    (returns i32)
    (do
      (return (op add (call alpha-value) (call beta-value))))))
WEAVE

alpha_base='__weave_m_616c706861__t_5265636f7264'
beta_base='__weave_m_62657461__t_5265636f7264'

check_wir() {
  local path="$1"

  for base in "$alpha_base" "$beta_base"; do
    grep -Fq "(fn ${base}_new " "$path"
    grep -Fq "(fn ${base}_get_value " "$path"
    grep -Fq "(fn ${base}_set_value " "$path"
    grep -Fq "(call_ptr ${base}_new " "$path"
    grep -Fq "${base}_get_value" "$path"
  done
  ! grep -Fq '(fn Record_new ' "$path"
  ! grep -Fq '(call_ptr Record_new ' "$path"
}

"$WEAVEC" --frontend "$TMP/ordered.wir" \
  "$TMP/main.weave" "$TMP/alpha.weave" "$TMP/beta.weave"
"$WEAVEC" --frontend "$TMP/reversed.wir" \
  "$TMP/main.weave" "$TMP/beta.weave" "$TMP/alpha.weave"
check_wir "$TMP/ordered.wir"
check_wir "$TMP/reversed.wir"

for order in ordered reversed; do
  if [[ "$order" == ordered ]]; then
    sources=("$TMP/main.weave" "$TMP/alpha.weave" "$TMP/beta.weave")
  else
    sources=("$TMP/main.weave" "$TMP/beta.weave" "$TMP/alpha.weave")
  fi
  "$WEAVEC" build "${sources[@]}" -o "$TMP/$order"
  set +e
  "$TMP/$order"
  status="$?"
  set -e
  [[ "$status" -eq 42 ]]
done

printf 'module-structs: scoped identities and helpers passed\n'