#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEAVEC="${WEAVEC:-$ROOT/build/weavec}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/weavec-module-symbols-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

command -v cc >/dev/null 2>&1 || {
  printf 'module-symbols: cc is required\n' >&2
  exit 1
}
[[ -x "$WEAVEC" ]] || {
  printf 'module-symbols: compiler not found: %s\n' "$WEAVEC" >&2
  exit 1
}

cat > "$TMP/registry.c" <<'C'
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define weave_surface_symbols_reset weave_surface_symbols_reset_storage
#define weave_surface_symbol_begin weave_surface_symbol_begin_storage
#include "runtime/surface_symbols.c"
#undef weave_surface_symbol_begin
#undef weave_surface_symbols_reset
#include "runtime/module_wir_names.c"

static int32_t begin_module(const char *name) {
    return weave_surface_module_begin(name, 0, (int64_t)strlen(name));
}

int main(void) {
    static const char helper[] = "helper";
    static const char public_name[] = "public-name";
    static const char external_name[] = "external-name";

    weave_surface_symbols_reset();
    assert(begin_module("alpha") == 0);
    assert(weave_surface_symbol_begin(helper, 0, 6, 2) == 0);
    assert(strcmp(weave_surface_symbol_wir_name(helper, 0, 6), "helper") == 0);

    assert(begin_module("beta") == 1);
    assert(weave_surface_symbol_begin(helper, 0, 6, 2) == 1);
    assert(strcmp(
        weave_surface_symbol_wir_name(helper, 0, 6),
        "__weave_m_62657461__s_68656c706572") == 0);
    assert(weave_surface_module_select("alpha", 0, 5) == 0);
    assert(strcmp(
        weave_surface_symbol_wir_name(helper, 0, 6),
        "__weave_m_616c706861__s_68656c706572") == 0);

    weave_surface_symbols_reset();
    assert(begin_module("alpha") == 0);
    assert(weave_surface_module_add_export(public_name, 0, 11) == 0);
    assert(weave_surface_symbol_begin(public_name, 0, 11, 2) == 0);
    assert(begin_module("beta") == 1);
    assert(weave_surface_module_add_export(public_name, 0, 11) == 0);
    assert(weave_surface_symbol_begin(public_name, 0, 11, 2) == -2);

    weave_surface_symbols_reset();
    assert(begin_module("alpha") == 0);
    assert(weave_surface_symbol_begin(external_name, 0, 13, 2) == 0);
    assert(weave_surface_symbol_mark_external(external_name, 0, 13) == 0);
    assert(begin_module("beta") == 1);
    assert(weave_surface_symbol_begin(external_name, 0, 13, 2) == -2);

    weave_surface_symbols_reset();
    puts("module-symbols: registry naming passed");
    return 0;
}
C
cc -std=c11 -Wall -Wextra -Werror -I"$ROOT" \
  "$TMP/registry.c" -o "$TMP/registry"
"$TMP/registry"

cat > "$TMP/alpha.weave" <<'WEAVE'
(module alpha
  (export alpha-value)
  (const offset i32 20)
  (fn helper
    (params)
    (returns i32)
    (requires (const_bool true))
    (do (return (call_i32 offset))))
  (fn alpha-value
    (params)
    (returns i32)
    (do (return (call_i32 helper)))))
WEAVE

cat > "$TMP/beta.weave" <<'WEAVE'
(module beta
  (export beta-value)
  (const offset i32 22)
  (fn helper
    (params)
    (returns i32)
    (requires (const_bool true))
    (do (return (call_i32 offset))))
  (fn beta-value
    (params)
    (returns i32)
    (do (return (call_i32 helper)))))
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

"$WEAVEC" --frontend "$TMP/module-symbols.wir" \
  "$TMP/main.weave" "$TMP/alpha.weave" "$TMP/beta.weave"

alpha_helper='__weave_m_616c706861__s_68656c706572'
beta_helper='__weave_m_62657461__s_68656c706572'
alpha_offset='__weave_m_616c706861__s_6f6666736574'
beta_offset='__weave_m_62657461__s_6f6666736574'

for symbol in "$alpha_helper" "$beta_helper" "$alpha_offset" "$beta_offset"; do
  grep -Fq "(fn $symbol" "$TMP/module-symbols.wir"
  grep -Fq "(call_i32 $symbol" "$TMP/module-symbols.wir"
done
! grep -Fq '(fn helper ' "$TMP/module-symbols.wir"
grep -Fq '(fn alpha-value ' "$TMP/module-symbols.wir"
grep -Fq '(fn beta-value ' "$TMP/module-symbols.wir"
grep -Fq '(fn main ' "$TMP/module-symbols.wir"

"$WEAVEC" build "$TMP/main.weave" "$TMP/alpha.weave" "$TMP/beta.weave" \
  -o "$TMP/module-symbols-program"
set +e
"$TMP/module-symbols-program"
status="$?"
set -e
[[ "$status" -eq 42 ]]

printf 'module-symbols: deterministic private names passed\n'
